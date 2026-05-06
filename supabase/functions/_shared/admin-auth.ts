/**
 * admin-auth.ts — Helper d'authentification admin partagé.
 *
 * Pattern recommandé pour les edge functions exposées au frontend admin :
 *   1. Le frontend envoie le JWT user normal via Authorization: Bearer
 *      (supabase.functions.invoke() le fait automatiquement)
 *   2. La fonction vérifie le JWT avec supabase.auth.getUser()
 *   3. La fonction vérifie que l'utilisateur a app_metadata.role = ADMIN_PLATEFORME
 *      (alias acceptés : ADMIN, ADMIN_PLATEFORME)
 *   4. Si admin OK, la fonction crée son propre client service_role en interne
 *      pour les opérations sensibles. La service_role NE SORT JAMAIS de l'edge.
 *
 * Bypass service_role (interne) : si le caller est lui-même une edge function
 * (admin-invoke, generate-invoice → submit-to-chorus, cron pg_cron), le bearer
 * peut être directement la service_role key. Ce bypass est limité aux appels
 * server-to-server.
 *
 * Usage type :
 *   import { verifyAdminOrServiceRole } from '../_shared/admin-auth.ts';
 *   const auth = await verifyAdminOrServiceRole(req);
 *   if (!auth.ok) return new Response(JSON.stringify({ error: auth.error }),
 *     { status: auth.status, headers: corsHeaders(req) });
 *   // auth.userId / auth.isServiceRole disponibles si besoin
 */

import { createClient } from 'npm:@supabase/supabase-js@2';

export type AdminAuthResult =
  | { ok: true; isServiceRole: boolean; userId: string | null; userEmail: string | null }
  | { ok: false; status: number; error: string };

const ADMIN_ROLES = new Set(['ADMIN', 'ADMIN_PLATEFORME']);

/** Vérifie que la requête provient d'un admin authentifié OU d'un appel
 *  server-to-server avec la service_role. Retourne un objet stable. */
export async function verifyAdminOrServiceRole(req: Request): Promise<AdminAuthResult> {
  const authHeader = req.headers.get('Authorization') || '';
  const bearer = authHeader.replace(/^Bearer\s+/i, '').trim();

  if (!bearer) {
    return { ok: false, status: 401, error: 'Authorization Bearer manquant' };
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  // Nouveau format asymétrique sb_secret_... (vault / cron secret)
  const newSecretKey = Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SB_SECRET_KEY') || '';

  // ── Bypass service_role (server-to-server) ──
  // Match strict pour éviter la fuite par préfixe.
  if ((serviceRoleKey && bearer === serviceRoleKey) ||
      (newSecretKey && bearer === newSecretKey)) {
    return { ok: true, isServiceRole: true, userId: null, userEmail: null };
  }

  // Détection JWT service_role classique (legacy Supabase Auth tokens)
  const parts = bearer.split('.');
  if (parts.length === 3) {
    try {
      const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const padded = b64 + '='.repeat((4 - b64.length % 4) % 4);
      const payload = JSON.parse(atob(padded));
      if (payload?.role === 'service_role') {
        return { ok: true, isServiceRole: true, userId: null, userEmail: null };
      }
    } catch { /* invalid JWT, fallthrough to user check */ }
  }

  // ── JWT user + check rôle admin ──
  if (!supabaseUrl || !anonKey) {
    return { ok: false, status: 500, error: 'Configuration serveur incomplète (SUPABASE_URL/ANON_KEY)' };
  }

  const supabaseAuth = createClient(supabaseUrl, anonKey, { auth: { persistSession: false } });
  const { data: userData, error: userErr } = await supabaseAuth.auth.getUser(bearer);
  if (userErr || !userData?.user) {
    return { ok: false, status: 401, error: 'Token invalide ou expiré' };
  }

  // Vérification du rôle admin via app_metadata (la source de vérité côté serveur,
  // jamais user_metadata qui est modifiable par l'utilisateur).
  let role = userData.user.app_metadata?.role as string | undefined;

  // Fallback : si app_metadata.role absent, lookup via service_role pour
  // gérer les anciens comptes qui n'ont pas eu app_metadata renseigné.
  if (!role && serviceRoleKey) {
    try {
      const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
      const { data: full } = await adminClient.auth.admin.getUserById(userData.user.id);
      role = full?.user?.app_metadata?.role as string | undefined;
    } catch { /* ignore */ }
  }

  if (!role || !ADMIN_ROLES.has(role)) {
    return { ok: false, status: 403, error: 'Accès réservé aux administrateurs Jolene' };
  }

  return {
    ok: true,
    isServiceRole: false,
    userId: userData.user.id,
    userEmail: userData.user.email || null,
  };
}

/** Récupère le client Supabase service_role pour les opérations sensibles
 *  internes après authentification admin réussie. Ne JAMAIS exposer ce
 *  client au caller — il a tous les droits. */
export function getServiceRoleClient() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  return createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
}
