import type { DocumentUploadJournal, PendingDocumentUpload } from '../ui/documents/adapters';
import type { SecureKeyValueStore } from '../session/secureSessionStorage';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PREFIX = 'jolene.native.documents.staging.';
const INVALID = 'Le suivi du dernier envoi ne peut pas être vérifié. Aucun nouvel envoi ne sera lancé.';

function keyFor(userId: string): string {
  if (!UUID.test(userId)) throw new Error(INVALID);
  return `${PREFIX}${userId.toLowerCase()}`;
}

function validateReceipt(userId: string, pending: PendingDocumentUpload): PendingDocumentUpload {
  const path = pending?.storageKey;
  if (typeof path !== 'string' || path.length > 512) throw new Error(INVALID);
  const parts = path.split('/');
  if (parts.length !== 4 || parts[0] !== userId || parts[1] !== 'documents'
    || !/^[A-Z][A-Z0-9_]{1,79}$/.test(parts[2] ?? '')
    || !/^[A-Za-z0-9._-]+$/.test(parts[3] ?? '') || path.includes('..')) throw new Error(INVALID);
  return { storageKey: path };
}

/**
 * One runtime-owned journal, encrypted by native SecureStore. Persist a bounded
 * receipt before Storage starts; keep it across screen changes and logout.
 * It contains no token, signed URL, document bytes or provider response.
 * Unreadable/corrupt state throws: it must not silently unlock a second upload.
 */
export function createDocumentUploadJournal(store: SecureKeyValueStore): DocumentUploadJournal {
  const pending = new Map<string, Promise<unknown>>();
  const serialize = <T>(userId: string, operation: (key: string) => Promise<T>): Promise<T> => {
    const key = keyFor(userId);
    const previous = pending.get(key) ?? Promise.resolve();
    const next = previous.catch(() => undefined).then(() => operation(key));
    pending.set(key, next);
    void next.finally(() => { if (pending.get(key) === next) pending.delete(key); }).catch(() => undefined);
    return next;
  };
  const read = async (userId: string, key: string): Promise<PendingDocumentUpload | null> => {
    const raw = await store.getItem(key);
    if (raw === null) return null;
    if (raw.length > 1024) throw new Error(INVALID);
    let decoded: unknown;
    try { decoded = JSON.parse(raw); } catch { throw new Error(INVALID); }
    if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) throw new Error(INVALID);
    const value = decoded as Record<string, unknown>;
    if (value.version !== 1 || value.userId !== userId || typeof value.storageKey !== 'string'
      || Object.keys(value).some(key => !['version', 'userId', 'storageKey'].includes(key))) throw new Error(INVALID);
    return validateReceipt(userId, { storageKey: value.storageKey });
  };
  return {
    read(userId) { return serialize(userId, key => read(userId, key)); },
    write(userId, receipt) {
      // Snapshot before any await: the caller cannot replace the receipt in flight.
      const frozen = validateReceipt(userId, receipt);
      return serialize(userId, async key => {
        const previous = await read(userId, key);
        if (previous && previous.storageKey !== frozen.storageKey) throw new Error(INVALID);
        await store.setItem(key, JSON.stringify({ version: 1, userId, storageKey: frozen.storageKey }));
        const saved = await read(userId, key);
        if (saved?.storageKey !== frozen.storageKey) throw new Error(INVALID);
      });
    },
    clear(userId, expectedStorageKey) {
      const expected = validateReceipt(userId, { storageKey: expectedStorageKey });
      return serialize(userId, async key => {
        const previous = await read(userId, key);
        if (!previous) return;
        if (previous.storageKey !== expected.storageKey) throw new Error(INVALID);
        await store.removeItem(key);
        if (await store.getItem(key) !== null) throw new Error(INVALID);
      });
    },
  };
}
