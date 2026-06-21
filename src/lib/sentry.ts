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
  // Normalisation : Sentry affiche "Object captured as exception with keys:
  // code, details, hint, message" quand on lui passe un objet d'erreur Supabase
  // brut (non-Error). On le transforme en vraie Error avec un message lisible et
  // on conserve l'objet d'origine en extra pour le débogage.
  let normalise: Error;
  let erreurBrute: unknown;
  if (error instanceof Error) {
    normalise = error;
  } else if (error && typeof error === 'object') {
    const o = error as Record<string, unknown>;
    const msg = (o.message ?? o.error_description ?? o.error ?? o.code ?? 'Erreur inconnue') as string;
    normalise = new Error(`${composant}/${action}: ${msg}`);
    if (typeof o.code === 'string') normalise.name = `SupabaseError(${o.code})`;
    erreurBrute = error;
  } else {
    normalise = new Error(`${composant}/${action}: ${String(error)}`);
  }
  Sentry.captureException(normalise, {
    tags: { composant, action },
    extra: erreurBrute !== undefined ? { ...extra, erreur_brute: erreurBrute } : extra,
  });
}
