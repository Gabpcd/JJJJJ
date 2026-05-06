import * as Sentry from '@sentry/react';

const isDev = import.meta.env.DEV;

// Erreurs attendues qu'on ne veut PAS remonter à Sentry (bruit connu) :
// - "Lock was stolen by another request" : Supabase Auth multi-tabs, le SDK
//   utilise le navigator.locks API pour le refresh token et un autre onglet
//   peut "voler" le verrou — comportement normal, pas un bug applicatif.
// - AbortError : navigation, signal annulé, etc.
function isExpectedNoiseError(error: unknown): boolean {
  if (!error) return false;
  const name = (error as any)?.name || '';
  const message = error instanceof Error ? error.message : String(error);
  if (name === 'AbortError') return true;
  if (/Lock was stolen by another request/i.test(message)) return true;
  if (/AbortError|aborted/i.test(message) && /Lock|navigator|signal/i.test(message)) return true;
  return false;
}

export const logger = {
  debug: (...args: unknown[]) => {
    if (isDev) console.log('[DEBUG]', ...args);
  },
  info: (...args: unknown[]) => {
    if (isDev) console.info('[INFO]', ...args);
  },
  warn: (...args: unknown[]) => {
    console.warn('[WARN]', ...args);
    // Breadcrumb pour contexte (pas un event Sentry plein)
    Sentry.addBreadcrumb({ level: 'warning', category: 'logger', message: args.map(String).join(' ') });
  },
  error: (message: string, error?: unknown) => {
    const msg = error instanceof Error ? error.message : String(error ?? '');

    // Bruit attendu : on log en debug et on n'envoie pas à Sentry
    if (isExpectedNoiseError(error)) {
      if (isDev) console.debug('[noise]', message, msg);
      return;
    }

    console.error('[ERROR]', message, msg);
    // Pousse vers Sentry pour visibilité prod (déduplication automatique côté Sentry)
    if (error instanceof Error) {
      Sentry.captureException(error, { tags: { source: 'logger' }, extra: { message } });
    } else if (error !== undefined && error !== null) {
      Sentry.captureMessage(`${message}: ${msg}`, { level: 'error', tags: { source: 'logger' } });
    } else {
      Sentry.captureMessage(message, { level: 'error', tags: { source: 'logger' } });
    }
  },
};
