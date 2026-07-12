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

import { createClient } from 'npm:@supabase/supabase-js@2.99.2';

export type AdminAuthResult =
  | { ok: true; isServiceRole: boolean; userId: string | null; userEmail: string | null }
  | { ok: false; status: number; error: string };

export type UserOrServiceAuthResult =
  | {
      ok: true;
      isServiceRole: boolean;
      userId: string | null;
      userEmail: string | null;
      role: string | null;
      aal: string | null;
    }
  | { ok: false; status: number; error: string };

const ADMIN_ROLES = new Set(['ADMIN', 'ADMIN_PLATEFORME']);

// Cache mémoire du secret vault (sb_secret_*) lu via RPC fn_lire_secret_cron.
// Pg_cron envoie ce secret comme Bearer ; il n'est pas auto-injecté en env var.
let _cachedVaultSecret: { value: string; expiresAt: number } | null = null;
async function fetchVaultCronSecret(supabaseUrl: string, serviceRoleKey: string): Promise<string> {
  if (_cachedVaultSecret && _cachedVaultSecret.expiresAt > Date.now()) {
    return _cachedVaultSecret.value;
  }
  _cachedVaultSecret = null;
  if (!supabaseUrl || !serviceRoleKey) return '';
  try {
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const { data } = await admin.rpc('fn_lire_secret_cron');
    if (data && typeof data === 'string') {
      // Une rotation/revocation Vault doit prendre effet sur une instance Edge
      // chaude; ne jamais conserver le secret pour toute sa duree de vie.
      _cachedVaultSecret = { value: data, expiresAt: Date.now() + 5 * 60_000 };
      return data;
    }
  } catch { /* ignore */ }
  return '';
}

/**
 * Verifie un JWT utilisateur aupres de Supabase Auth, ou un secret interne par
 * egalite stricte avec une valeur configuree cote serveur.
 *
 * Important : le contenu d'un JWT n'est jamais decode pour prendre une decision
 * d'autorisation. En particulier, un payload forge `{ role: "service_role" }`
 * ne peut pas activer le bypass server-to-server.
 */
export async function verifyUserOrServiceRole(req: Request): Promise<UserOrServiceAuthResult> {
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
    return { ok: true, isServiceRole: true, userId: null, userEmail: null, role: 'service_role', aal: 'aal2' };
  }

  // Fallback vault : pg_cron envoie le sb_secret_* stocké dans vault.decrypted_secrets
  // (name='service_role_key'). Quand SUPABASE_SECRET_KEY n'est pas configuré dans les
  // Edge Functions Secrets, on lit le secret via fn_lire_secret_cron pour valider.
  if (bearer.startsWith('sb_secret_')) {
    const vaultSecret = await fetchVaultCronSecret(supabaseUrl, serviceRoleKey);
    if (vaultSecret && bearer === vaultSecret) {
      return { ok: true, isServiceRole: true, userId: null, userEmail: null, role: 'service_role', aal: 'aal2' };
    }
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

  const deletedAt = (userData.user as typeof userData.user & { deleted_at?: string | null }).deleted_at;
  if (deletedAt) {
    return { ok: false, status: 403, error: 'Compte desactive' };
  }
  const bannedUntilRaw = userData.user.banned_until;
  const bannedUntil = bannedUntilRaw ? new Date(bannedUntilRaw).getTime() : 0;
  if (bannedUntilRaw && (!Number.isFinite(bannedUntil) || bannedUntil > Date.now())) {
    return { ok: false, status: 403, error: 'Compte desactive' };
  }

  // getUser() a deja valide le token cote Auth. getClaims() fournit ensuite
  // le niveau AAL cryptographiquement verifie, sans decoder un payload non
  // fiable dans le code applicatif.
  const { data: claimsData, error: claimsError } = await supabaseAuth.auth.getClaims(bearer);
  if (claimsError || !claimsData?.claims) {
    return { ok: false, status: 401, error: 'Claims du token invalides' };
  }

  return {
    ok: true,
    isServiceRole: false,
    userId: userData.user.id,
    userEmail: userData.user.email || null,
    // app_metadata vient de la reponse Auth serveur. Ne jamais utiliser
    // user_metadata pour une autorisation.
    role: (userData.user.app_metadata?.role as string | undefined) || null,
    aal: typeof claimsData.claims.aal === 'string' ? claimsData.claims.aal : null,
  };
}

/** Verifie que la requete provient d'un admin actif ou d'un appel interne. */
export async function verifyAdminOrServiceRole(req: Request): Promise<AdminAuthResult> {
  const auth = await verifyUserOrServiceRole(req);
  if (!auth.ok) return auth;
  if (auth.isServiceRole) {
    return { ok: true, isServiceRole: true, userId: null, userEmail: null };
  }

  const role = auth.role || '';

  if (!role || !ADMIN_ROLES.has(role)) {
    return { ok: false, status: 403, error: 'Accès réservé aux administrateurs Jolene' };
  }
  if (auth.aal !== 'aal2') {
    return { ok: false, status: 403, error: 'Authentification forte AAL2 requise' };
  }

  // Un admin present dans equipe_admin mais marque inactif doit rester bloque,
  // meme si son ancien JWT contient toujours ADMIN_PLATEFORME. Une erreur de
  // lecture est elle aussi bloquante (fail closed).
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!serviceRoleKey) {
    return { ok: false, status: 500, error: 'Configuration serveur incomplète' };
  }
  const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
  const { data: equipe, error: equipeError } = await adminClient
    .from('equipe_admin')
    .select('actif')
    .eq('user_id', auth.userId!)
    .maybeSingle();
  if (equipeError) {
    console.error('[admin-auth] verification equipe_admin impossible', equipeError.message);
    return { ok: false, status: 503, error: 'Verification des acces admin indisponible' };
  }
  if (equipe && equipe.actif !== true) {
    return { ok: false, status: 403, error: 'Compte administrateur desactive' };
  }

  return {
    ok: true,
    isServiceRole: false,
    userId: auth.userId,
    userEmail: auth.userEmail,
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
