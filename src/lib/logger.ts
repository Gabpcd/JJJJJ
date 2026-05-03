import * as Sentry from '@sentry/react';

const isDev = import.meta.env.DEV;

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
