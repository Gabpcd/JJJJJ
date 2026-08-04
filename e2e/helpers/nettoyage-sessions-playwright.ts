import type { SupabaseClient } from '@supabase/supabase-js';

const EMAIL_SOIGNANT_PLAYWRIGHT = 'playwright-soignant@jolene.app';

/**
 * Un run interrompu pendant le test de suspension admin peut laisser le compte
 * soignant banni. Restaure exclusivement ce compte technique et l'état de son
 * profil avant toute authentification du run suivant.
 */
export async function reactiverSoignantPlaywright(admin: SupabaseClient): Promise<void> {
  const { data: userIdBrut, error: userIdError } = await admin.rpc(
    'fn_admin_get_user_id_by_email',
    { p_email: EMAIL_SOIGNANT_PLAYWRIGHT },
  );
  const userId = typeof userIdBrut === 'string' ? userIdBrut : null;
  if (userIdError || !userId) {
    throw new Error(
      `[sessions-playwright] compte soignant introuvable : ${userIdError?.message || 'aucun identifiant'}`,
    );
  }

  const { data: suspension, error: suspensionError } = await admin
    .from('suspensions_profils_admin')
    .select('supprime_le_avant')
    .eq('type_ressource', 'soignants')
    .eq('id_ressource', userId)
    .maybeSingle();
  if (suspensionError) {
    throw new Error(`[sessions-playwright] lecture suspension impossible : ${suspensionError.message}`);
  }

  // Cas normal : le test de suspension s'est terminé et sa RPC de cleanup a
  // déjà restauré auth.users + le profil dans la même transaction SQL. Ne pas
  // appeler GoTrue Admin sans nécessité : cette requête distante a provoqué
  // des 500/504 de teardown alors qu'aucun compte n'était encore suspendu.
  if (!suspension) return;

  const { error: authError } = await admin.auth.admin.updateUserById(userId, {
    ban_duration: 'none',
  });
  if (authError) {
    const diagnostic = JSON.stringify({
      message: authError.message,
      status: (authError as { status?: number }).status,
      code: (authError as { code?: string }).code,
    });
    throw new Error(`[sessions-playwright] réactivation Auth impossible : ${diagnostic}`);
  }

  const { error: profilError } = await admin
    .from('soignants')
    .update({ supprime_le: suspension?.supprime_le_avant ?? null })
    .eq('id', userId);
  if (profilError) {
    throw new Error(`[sessions-playwright] réactivation profil impossible : ${profilError.message}`);
  }

  for (const table of ['suspensions_auth_admin', 'suspensions_profils_admin'] as const) {
    const { error } = await admin
      .from(table)
      .delete()
      .eq('type_ressource', 'soignants')
      .eq('id_ressource', userId);
    if (error) {
      throw new Error(`[sessions-playwright] purge ${table} impossible : ${error.message}`);
    }
  }
}

/**
 * Purge les sessions des deux comptes CI via une RPC réservée au service_role.
 * La migration peut ne pas encore être déployée pendant la validation de la PR :
 * dans ce cas le run continue avec un avertissement et le prochain setup réessaie.
 */
export async function nettoyerSessionsPlaywright(
  admin: SupabaseClient,
  anciennete: string,
): Promise<void> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20_000);
  let data: unknown;
  let error: { message: string } | null;

  try {
    const resultat = await admin
      .rpc('fn_test_nettoyer_sessions_playwright', { p_anciennete: anciennete })
      .abortSignal(controller.signal);
    data = resultat.data;
    error = resultat.error;
  } catch (cause) {
    console.warn(
      `[sessions-playwright] purge différée : ${cause instanceof Error ? cause.message : String(cause)}`,
    );
    return;
  } finally {
    clearTimeout(timeout);
  }

  if (error) {
    console.warn(`[sessions-playwright] purge différée : ${error.message}`);
    return;
  }

  console.log(`[sessions-playwright] purge terminée : ${JSON.stringify(data)}`);
}
