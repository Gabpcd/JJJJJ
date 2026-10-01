import { AsyncLocalStorage } from 'node:async_hooks';

// Le hook Playwright conserve sa borne de 30 s. Le transport doit cesser
// avant cette borne, afin qu'afterAll ne relance pas un nettoyage encore actif.
export const CLEANUP_DEADLINE_MS = 25_000;

interface CleanupScope {
  controller: AbortController;
  label: string;
  lastRequest: string;
  expired?: Error;
  removeAbortListeners: Array<() => void>;
}

const cleanupScope = new AsyncLocalStorage<CleanupScope>();

/** Borne le nettoyage entier ; une erreur ou expiration reste un échec. */
export async function executerNettoyageBorne<T>(
  label: string,
  cleanup: () => Promise<T>,
): Promise<T> {
  // Une sous-opération ne reçoit jamais un délai supplémentaire.
  if (cleanupScope.getStore()) return cleanup();
  const scope: CleanupScope = {
    controller: new AbortController(), label, lastRequest: 'aucune requête', removeAbortListeners: [],
  };
  const timeout = setTimeout(() => {
    scope.expired = new Error(
      `[cleanup] ${label}: délai ${CLEANUP_DEADLINE_MS} ms atteint ; dernière requête ${scope.lastRequest}`,
    );
    scope.controller.abort(scope.expired);
  }, CLEANUP_DEADLINE_MS);
  try {
    const result = await cleanupScope.run(scope, cleanup);
    // Même un callback qui collecte/absorbe les erreurs réseau doit échouer.
    if (scope.expired) throw scope.expired;
    return result;
  } catch (error) {
    throw scope.expired ?? error;
  } finally {
    clearTimeout(timeout);
    for (const remove of scope.removeAbortListeners) remove();
  }
}

function decrireRequete(input: RequestInfo | URL, init?: RequestInit): string {
  const request = input instanceof Request ? input : undefined;
  const url = new URL(request?.url ?? String(input));
  // Aucun filtre, UUID, corps ou secret : seulement méthode et table/RPC.
  const rest = url.pathname.match(/^\/rest\/v1\/(?:rpc\/)?[a-zA-Z0-9_]+/);
  const route = rest?.[0] ?? (url.pathname.startsWith('/auth/v1/') ? '/auth/v1/[route]' : '[route]');
  return `${init?.method ?? request?.method ?? 'GET'} ${route}`;
}

/** Fetch habituel hors nettoyage ; pendant celui-ci, propage sa cancellation. */
export const fetchAvecBorneNettoyage: typeof fetch = async (input, init) => {
  const scope = cleanupScope.getStore();
  if (!scope) return fetch(input, init);
  if (scope.expired) throw scope.expired;
  scope.lastRequest = decrireRequete(input, init);
  const requestSignal = init?.signal ?? (input instanceof Request ? input.signal : undefined);
  const signals = [scope.controller.signal, requestSignal].filter(
    (signal): signal is AbortSignal => Boolean(signal),
  );
  const controller = new AbortController();
  for (const signal of signals) {
    const abort = () => controller.abort(signal.reason);
    if (signal.aborted) abort();
    else signal.addEventListener('abort', abort, { once: true });
    scope.removeAbortListeners.push(() => signal.removeEventListener('abort', abort));
  }
  // Le signal reste lié après réception
  // des en-têtes : une lecture JSON de réponse bloquée doit aussi s'annuler.
  return fetch(input, { ...init, signal: controller.signal });
};
