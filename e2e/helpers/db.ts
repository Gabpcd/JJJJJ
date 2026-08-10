/**
 * Helpers DB pour les tests E2E — utilise SUPABASE_SERVICE_ROLE_KEY
 * pour bypass RLS et seed/cleanup les données test.
 *
 * IMPORTANT : ce helper n'est utilisé QUE en environnement test
 * (CI ou local avec .env.local). Le service role key ne doit JAMAIS
 * être committée ni utilisée côté browser.
 */

import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PLAYWRIGHT_SUPABASE_URL || '';
const SERVICE_ROLE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.PLAYWRIGHT_SERVICE_ROLE_KEY || '';
const PUBLISHABLE_KEY =
  process.env.SUPABASE_PUBLISHABLE_KEY ||
  process.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  process.env.SUPABASE_ANON_KEY ||
  '';

let _admin: SupabaseClient | null = null;
const _userClients = new Map<string, Promise<SupabaseClient>>();

/** Client Supabase admin (service_role) — bypass RLS. À utiliser dans les tests E2E uniquement. */
export function adminClient(): SupabaseClient {
  if (!_admin) {
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
      throw new Error(
        '[playwright/db] SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY manquant. ' +
          'Définir dans .env.local (local) ou secrets GitHub Actions (CI). ' +
          'Voir docs/tests-playwright.md.',
      );
    }
    _admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }
  return _admin;
}

/**
 * Crée un client Supabase signé en tant qu'utilisateur test donné.
 * Utilise la publishable key (anon) + signInWithPassword → RLS appliquée.
 * Permet de tester les RPCs dépendantes de auth.uid().
 */
export async function userClient(email: string, password: string): Promise<SupabaseClient> {
  if (!SUPABASE_URL || !PUBLISHABLE_KEY) {
    throw new Error(
      '[playwright/db] SUPABASE_URL ou SUPABASE_PUBLISHABLE_KEY manquant pour userClient. ' +
        'Définir SUPABASE_PUBLISHABLE_KEY (= VITE_SUPABASE_PUBLISHABLE_KEY) dans le workflow CI.',
    );
  }
  // Une suite E2E appelle plusieurs fois les mêmes comptes canoniques. Chaque
  // appel créait auparavant une nouvelle session GoTrue, jusqu'à provoquer des
  // latences et timeouts aléatoires sans rapport avec les RPCs testées. Le
  // cache reste local au processus Playwright (donc isolé par worker) et par
  // couple email/mot de passe. Une authentification échouée est retirée pour
  // permettre une tentative ultérieure saine.
  const cacheKey = `${email}\u0000${password}`;
  const cached = _userClients.get(cacheKey);
  if (cached) return cached;

  const authenticatedClient = (async () => {
    const client = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error } = await client.auth.signInWithPassword({ email, password });
    if (error) {
      throw new Error(`[playwright/db] userClient signInWithPassword("${email}") failed: ${error.message}`);
    }
    return client;
  })();

  _userClients.set(cacheKey, authenticatedClient);
  try {
    return await authenticatedClient;
  } catch (error) {
    _userClients.delete(cacheKey);
    throw error;
  }
}

/** Reset un compte test au state initial (purge missions, candidatures, notations, etc.). */
export async function resetTestAccount(role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT'): Promise<void> {
  const { error } = await adminClient().rpc('fn_admin_reset_test_account' as any, { p_role: role });
  if (error) throw new Error(`[playwright/db] resetTestAccount failed: ${error.message}`);
}

/** Cleanup tous les comptes créés avec le préfixe playwright-test-. */
export async function cleanupTestAccounts(): Promise<{ deleted: number }> {
  const { data, error } = await adminClient().rpc('fn_admin_cleanup_test_accounts' as any);
  if (error) throw new Error(`[playwright/db] cleanupTestAccounts failed: ${error.message}`);
  return (data as any) || { deleted: 0 };
}

/**
 * Vérifie qu'un email apparaît bien dans la table emails_envoyes pour un user.
 * Ex. après inscription, vérifier qu'un BIENVENUE_SOIGNANT a été envoyé.
 */
export async function emailFutEnvoye(
  userId: string,
  type: string,
  windowSeconds = 60,
): Promise<boolean> {
  const since = new Date(Date.now() - windowSeconds * 1000).toISOString();
  const { data, error } = await adminClient()
    .from('emails_envoyes' as any)
    .select('id')
    .eq('destinataire_id', userId)
    .eq('type', type)
    .gte('envoye_le', since)
    .limit(1);
  if (error) throw new Error(`[playwright/db] emailFutEnvoye: ${error.message}`);
  return Array.isArray(data) && data.length > 0;
}

/**
 * Récupère l'ID auth d'un compte test (pour cleanup ciblé).
 *
 * Utilise la RPC `fn_admin_get_user_id_by_email` (migration
 * 20260503060000) plutôt que `auth.admin.listUsers()` qui échoue
 * silencieusement en CI (pagination 50/page, rate limit, timeout).
 */
export async function userIdByEmail(email: string): Promise<string | null> {
  const { data, error } = await adminClient().rpc(
    'fn_admin_get_user_id_by_email' as any,
    { p_email: email },
  );
  if (error) {
    console.error(`[playwright/db] userIdByEmail("${email}") RPC error:`, error.message);
    return null;
  }
  return (data as string | null) || null;
}
