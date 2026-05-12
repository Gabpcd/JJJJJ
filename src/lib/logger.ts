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
    // [BUG 3 fix] String(plainObject) retournait "[object Object]" dans
    // Sentry. On sérialise désormais avec safeStringify qui :
    //   - garde error.message pour les Error
    //   - JSON.stringify pour les objets plats (incluant { code, message }
    //     remontés depuis les edge functions)
    //   - String() pour les primitives (string, number, etc.)
    const msg = safeStringify(error);

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
      // Pour les objets non-Error (typiquement un payload { code, message }
      // remonté depuis une edge function), capture en captureMessage avec
      // les attributs extras structurés pour faciliter le filtrage Sentry.
      const isPlainObject = typeof error === 'object' && error !== null;
      const code = isPlainObject ? (error as any).code : undefined;
      Sentry.captureMessage(`${message}: ${msg}`, {
        level: 'error',
        tags: { source: 'logger', ...(code ? { code: String(code) } : {}) },
        extra: isPlainObject ? { payload: error as any } : { value: msg },
      });
    } else {
      Sentry.captureMessage(message, { level: 'error', tags: { source: 'logger' } });
    }
  },
};

function safeStringify(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (value instanceof Error) {
    return value.message || value.toString();
  }
  if (typeof value === 'string') return value;
  if (typeof value === 'object') {
    try {
      const json = JSON.stringify(value);
      // Si l'objet est vide ({}), tomber sur la représentation native qui
      // peut révéler le constructeur (utile pour les erreurs DOM/réseau).
      if (json === '{}') return String(value);
      return json;
    } catch {
      return String(value);
    }
  }
  return String(value);
}
