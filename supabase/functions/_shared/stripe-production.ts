const PRODUCTION_PROJECT_REF = 'flripxtsyegjshnhzjkz';

export function isProductionRuntime(): boolean {
  // Le project ref est l'ancre de confiance : une variable SUPABASE_ENV mal
  // renseignée ne doit jamais pouvoir réautoriser une clé de test sur prod.
  if ((Deno.env.get('SUPABASE_URL') || '').includes(PRODUCTION_PROJECT_REF)) return true;
  const explicit = (Deno.env.get('SUPABASE_ENV') || '').trim().toLowerCase();
  if (explicit === 'production' || explicit === 'prod') return true;
  if (explicit === 'development' || explicit === 'dev' || explicit === 'staging' || explicit === 'test') return false;
  return false;
}

/** Empêche toute opération financière prod avec une clé Stripe de test. */
export function assertStripeSecretMode(secret: string): void {
  if (!secret) throw new Error('STRIPE_SECRET_KEY manquante');
  if (isProductionRuntime() && !secret.startsWith('sk_live_')) {
    throw new Error('Configuration Stripe production invalide');
  }
}
