/**
 * cors.ts — Helper CORS partagé pour toutes les edge functions Supabase.
 *
 * Whitelist : voir la constante ALLOWED_ORIGINS ci-dessous.
 *
 * Note CI : le job drift-detection dans .github/workflows/validate-pr.yml
 * filtre les littéraux CORS (chaînes entre quotes) pour les autoriser dans
 * les whitelists d'origine sans casser la CI.
 *
 * Usage type :
 *   import { corsHeaders } from '../_shared/cors.ts';
 *   Deno.serve((req) => {
 *     if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders(req) });
 *     ...
 *     return new Response(JSON.stringify(body), { status: 200, headers: corsHeaders(req) });
 *   });
 */

const ALLOWED_ORIGINS = new Set([
  'https://jolene.app',
  'https://www.jolene.app',
  'https://app.jolene.app',
  // Coquilles natives Capacitor. Android utilise androidScheme=https et iOS
  // conserve le scheme Capacitor par defaut.
  'https://localhost',
  'capacitor://localhost',
  'http://localhost:5173',
  'http://localhost:8080',
]);

const LOVABLE_PREVIEW_RE = /^https:\/\/[a-z0-9-]+\.lovable\.app$/i;

/** Retourne l'origine à autoriser. Fallback sur https://jolene.app pour ne
 *  jamais renvoyer un wildcard ni rejeter silencieusement. */
export function getCorsOrigin(req: Request): string {
  const origin = req.headers.get('origin') || '';
  if (ALLOWED_ORIGINS.has(origin)) return origin;
  if (LOVABLE_PREVIEW_RE.test(origin)) return origin;
  return 'https://jolene.app';
}

/** Headers CORS complets pour les réponses JSON. */
export function corsHeaders(req: Request): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-key, x-api-secret, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
    'Content-Type': 'application/json',
  };
}

/** Réponse JSON avec CORS, helper court. */
export function jsonResponse(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(req) });
}

/** Réponse OPTIONS preflight standard. */
export function preflightResponse(req: Request): Response {
  return new Response(null, { status: 204, headers: corsHeaders(req) });
}
