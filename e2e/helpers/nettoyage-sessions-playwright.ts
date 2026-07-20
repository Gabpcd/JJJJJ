import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Purge les sessions des deux comptes CI via une RPC réservée au service_role.
 * La migration peut ne pas encore être déployée pendant la validation de la PR :
 * dans ce cas le cron de secours prendra le relais après le merge.
 */
export async function nettoyerSessionsPlaywright(
  admin: SupabaseClient,
  anciennete: string,
): Promise<void> {
  const { data, error } = await admin.rpc('fn_test_nettoyer_sessions_playwright', {
    p_anciennete: anciennete,
  });

  if (error) {
    console.warn(`[sessions-playwright] purge différée : ${error.message}`);
    return;
  }

  console.log(`[sessions-playwright] purge terminée : ${JSON.stringify(data)}`);
}
