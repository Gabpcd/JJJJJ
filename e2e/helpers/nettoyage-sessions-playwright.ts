import type { SupabaseClient } from '@supabase/supabase-js';

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
