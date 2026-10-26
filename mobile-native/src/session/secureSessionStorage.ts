/** All session bytes stay in the platform keychain/keystore, never AsyncStorage. */
export interface SecureKeyValueStore {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

type Manifest = { version: 1; slot: 'a' | 'b'; count: number; digest: string };
const CHUNK_CODEPOINTS = 480; // At most 1920 UTF-8 bytes, including non-BMP text.
const MAX_CHUNKS = 128;
const TOMBSTONE = JSON.stringify({ version: 1, deleted: true });

function parseManifest(raw: string | null): Manifest | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as Partial<Manifest>;
    if (value.version === 1 && (value.slot === 'a' || value.slot === 'b')
      && Number.isInteger(value.count) && value.count! > 0 && value.count! <= MAX_CHUNKS
      && typeof value.digest === 'string' && /^[a-f0-9]{64}$/.test(value.digest)) {
      return value as Manifest;
    }
  } catch { /* Corrupt storage is treated as a missing session. */ }
  return null;
}

/**
 * Two bounded slots and an atomic pointer prevent partially written refresh tokens
 * from replacing the previous complete session. Hashing detects missing/mixed chunks;
 * encryption is provided entirely by SecureStore. Operations are serialized per key.
 */
export function createSecureSessionStorage(
  secure: SecureKeyValueStore,
  digest: (value: string) => Promise<string>,
): SecureKeyValueStore {
  const pending = new Map<string, Promise<unknown>>();
  const denied = new Set<string>();
  const keyPrefix = (key: string) => {
    if (!/^[\w.-]{1,160}$/.test(key)) throw new Error('Clé de session invalide.');
    return `jolene.native.${key}`;
  };
  const serialized = <T>(key: string, action: () => Promise<T>): Promise<T> => {
    const previous = pending.get(key) ?? Promise.resolve();
    const next = previous.catch(() => undefined).then(action);
    pending.set(key, next);
    void next.finally(() => { if (pending.get(key) === next) pending.delete(key); }).catch(() => undefined);
    return next;
  };
  const eraseSlot = async (prefix: string, slot: 'a' | 'b', count = MAX_CHUNKS) => {
    await Promise.all(Array.from({ length: count }, (_, index) => secure.removeItem(`${prefix}.${slot}.${index}`)));
  };
  return {
    getItem(key) {
      return serialized(key, async () => {
        if (denied.has(key)) return null;
        const prefix = keyPrefix(key);
        const raw = await secure.getItem(`${prefix}.head`);
        const manifest = parseManifest(raw);
        if (!manifest) return null;
        const chunks = await Promise.all(Array.from({ length: manifest.count }, (_, index) =>
          secure.getItem(`${prefix}.${manifest.slot}.${index}`)));
        const value = chunks.every((chunk) => chunk !== null) ? chunks.join('') : null;
        if (value === null || await digest(value) !== manifest.digest) {
          // Invalidate first; a damaged token is never offered to Supabase.
          denied.add(key);
          await secure.setItem(`${prefix}.head`, TOMBSTONE);
          await eraseSlot(prefix, manifest.slot, manifest.count);
          return null;
        }
        return value;
      });
    },
    setItem(key, value) {
      return serialized(key, async () => {
        const prefix = keyPrefix(key);
        const codepoints = Array.from(value);
        const count = Math.max(1, Math.ceil(codepoints.length / CHUNK_CODEPOINTS));
        if (count > MAX_CHUNKS) throw new Error('Session trop volumineuse pour le stockage sécurisé.');
        const previous = parseManifest(await secure.getItem(`${prefix}.head`));
        const slot = previous?.slot === 'a' ? 'b' : 'a';
        const manifest: Manifest = { version: 1, slot, count, digest: await digest(value) };
        for (let index = 0; index < count; index += 1) {
          await secure.setItem(`${prefix}.${slot}.${index}`, codepoints.slice(index * CHUNK_CODEPOINTS, (index + 1) * CHUNK_CODEPOINTS).join(''));
        }
        // Commit last. If any preceding write fails, the old pointer stays valid.
        await secure.setItem(`${prefix}.head`, JSON.stringify(manifest));
        denied.delete(key);
        if (previous) await eraseSlot(prefix, previous.slot, previous.count).catch(() => undefined);
      });
    },
    removeItem(key) {
      // Hide locally immediately, even while a preceding token write finishes.
      denied.add(key);
      return serialized(key, async () => {
        const prefix = keyPrefix(key);
        // Persist deletion before removing chunks. A failed cleanup cannot restore login.
        await secure.setItem(`${prefix}.head`, TOMBSTONE);
        await Promise.all([eraseSlot(prefix, 'a'), eraseSlot(prefix, 'b')]);
      });
    },
  };
}
