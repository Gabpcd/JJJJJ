import * as Sentry from '@sentry/react';

/** Configuration locale seulement : aucun de ces états ne prouve une réception. */
export function etatDiagnosticSentry() {
  if (!import.meta.env.VITE_SENTRY_DSN?.trim()) {
    return { disponible: false, detail: 'Sentry non configuré pour cette version.' };
  }
  if (!Sentry.getClient() || !Sentry.isEnabled()) {
    return { disponible: false, detail: 'Sentry configuré, mais le client est indisponible ou désactivé.' };
  }
  return { disponible: true, detail: 'Client Sentry configuré. Réception des événements non vérifiée.' };
}
