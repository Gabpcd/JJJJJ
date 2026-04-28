// Helper partagé de rate-limiting en mémoire (par IP).
//
// Important : la mémoire est limitée à l'instance courante de l'edge function.
// Pour un rate-limit cross-instance robuste il faudrait Redis/Upstash, mais
// pour les volumes Jolene actuels et les fenêtres courtes, la map mémoire
// suffit largement à bloquer les abus naïfs.
//
// Utilisation typique :
//
//   import { applyRateLimit } from "../_shared/rate-limit.ts";
//   const limited = applyRateLimit('send-email', clientIp, { max: 5, windowMs: 60_000 });
//   if (limited) return new Response(JSON.stringify({ error: 'Trop de requêtes' }),
//     { status: 429, headers: ... });

interface Bucket { count: number; resetAt: number }

// Une map par scope (nom de fonction) pour éviter les collisions entre endpoints.
const buckets = new Map<string, Map<string, Bucket>>();

export interface RateLimitOptions {
  /** Nombre de requêtes max dans la fenêtre. */
  max: number;
  /** Largeur de la fenêtre glissante en millisecondes. */
  windowMs: number;
}

/**
 * Retourne `true` si la requête doit être bloquée (limite dépassée).
 * Retourne `false` si la requête est autorisée et incrémente le compteur.
 */
export function applyRateLimit(scope: string, ip: string, opts: RateLimitOptions): boolean {
  if (!ip || ip === 'unknown') return false;
  const now = Date.now();
  let scopeMap = buckets.get(scope);
  if (!scopeMap) {
    scopeMap = new Map();
    buckets.set(scope, scopeMap);
  }
  const entry = scopeMap.get(ip);
  if (!entry || now > entry.resetAt) {
    scopeMap.set(ip, { count: 1, resetAt: now + opts.windowMs });
    return false;
  }
  entry.count++;
  return entry.count > opts.max;
}

export function getClientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
}
