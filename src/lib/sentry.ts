import * as Sentry from '@sentry/react';

/**
 * Capture une exception Supabase/applicative dans Sentry avec contexte.
 * À utiliser dans les catch des appels critiques (RPC, paiements, contrats…).
 */
export function capturerErreurSentry(
  error: unknown,
  composant: string,
  action: string,
  extra?: Record<string, unknown>,
) {
  Sentry.captureException(error, {
    tags: { composant, action },
    extra,
  });
}
