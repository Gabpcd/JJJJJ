declare const __APP_VERSION__: string;

const CHUNK_RECOVERY_STORAGE_KEY = 'jolene:chunk-recovery';
const CHUNK_RECOVERY_COOLDOWN_MS = 60_000;

type StorageMinimal = Pick<Storage, 'getItem' | 'setItem'>;

interface ChunkRecoveryOptions {
  release?: string;
  storage?: StorageMinimal;
  now?: number;
  reload?: () => void;
  beforeReload?: () => void;
}

interface ChunkRecoveryMarker {
  release: string;
  at: number;
}

export const APP_RELEASE =
  typeof __APP_VERSION__ !== 'undefined' ? __APP_VERSION__ : 'dev-unknown';

export function isChunkLoadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error ?? '');
  const normalized = message.toLowerCase();

  return (
    normalized.includes('importing a module script failed') ||
    normalized.includes('failed to fetch dynamically imported module') ||
    normalized.includes('error loading dynamically imported module') ||
    normalized.includes('loading chunk') ||
    normalized.includes('loading css chunk') ||
    normalized.includes('modulepreload')
  );
}

function readMarker(storage: StorageMinimal): ChunkRecoveryMarker | null {
  try {
    const raw = storage.getItem(CHUNK_RECOVERY_STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<ChunkRecoveryMarker>;
    if (typeof parsed.release !== 'string' || typeof parsed.at !== 'number') return null;
    return { release: parsed.release, at: parsed.at };
  } catch {
    return null;
  }
}

/**
 * Recharge une seule fois le document courant lorsqu'un chunk haché n'existe
 * plus après un déploiement. Le verrou est lié à la release et expire : une
 * panne persistante remonte donc bien à l'ErrorBoundary sans boucle de reload,
 * tandis qu'un déploiement ultérieur peut à nouveau être récupéré.
 */
export function recoverFromChunkLoadError(
  error: unknown,
  options: ChunkRecoveryOptions = {},
): boolean {
  if (!isChunkLoadError(error)) return false;

  const release = options.release ?? APP_RELEASE;
  const storage = options.storage ?? window.sessionStorage;
  const now = options.now ?? Date.now();
  const marker = readMarker(storage);

  if (
    marker?.release === release &&
    now - marker.at < CHUNK_RECOVERY_COOLDOWN_MS
  ) {
    return false;
  }

  try {
    storage.setItem(
      CHUNK_RECOVERY_STORAGE_KEY,
      JSON.stringify({ release, at: now } satisfies ChunkRecoveryMarker),
    );
  } catch {
    // Sans stockage fiable, ne pas risquer une boucle de rechargement Safari.
    return false;
  }

  options.beforeReload?.();
  (options.reload ?? (() => window.location.reload()))();
  return true;
}

/**
 * Vite émet cet événement avant que l'échec de modulepreload n'atteigne
 * React.lazy. Il faut donc l'écouter avant l'initialisation de Sentry.
 */
export function installVitePreloadRecovery(release = APP_RELEASE): () => void {
  const handler = (event: Event) => {
    const preloadEvent = event as Event & { payload?: unknown };
    recoverFromChunkLoadError(
      preloadEvent.payload ?? new Error('modulepreload failed'),
      {
        release,
        beforeReload: () => event.preventDefault(),
      },
    );
  };

  window.addEventListener('vite:preloadError', handler);
  return () => window.removeEventListener('vite:preloadError', handler);
}
