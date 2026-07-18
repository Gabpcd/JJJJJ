import { supabase } from '@/integrations/supabase/client';
import { extraireErreurEdgeFn } from '@/lib/erreurs';

export type PayMissionOutcome = {
  result: any | null;
  error: any | null;
  payload: Record<string, any> | null;
  code: string | undefined;
  message: string | undefined;
  factureGenereeAuto: boolean;
};

/**
 * FIX 3 Option B — Wrapper "pay mission Stripe Connect" avec génération
 * automatique de la facture honoraires si absente.
 *
 * Flow :
 *  1. invoke stripe-connect-pay-mission
 *  2. Si erreur FACTURE_NON_GENEREE : invoke generate-invoice
 *     - Si la génération échoue : retourne l'erreur générée pour toast
 *     - Sinon : retry stripe-connect-pay-mission
 *  3. Retourne toutes les infos pour que le caller gère les toasts + UI.
 *
 * L'appelant reste responsable de :
 *   - Vérifier la session user AVANT l'appel (accessToken requis)
 *   - Afficher les toasts selon le code retourné
 *   - Gérer les states local (loading, client_secret, decomposition, etc.)
 */
export async function payerMissionStripeConnectAvecGenerationAuto(
  missionId: string,
  accessToken: string,
  onProgressMessage?: (msg: string) => void,
  factureHonoraireId?: string,
): Promise<PayMissionOutcome> {
  const authHeaders = { Authorization: `Bearer ${accessToken}` };

  let { data: result, error } = await supabase.functions.invoke('stripe-connect-pay-mission', {
    body: {
      mission_id: missionId,
      ...(factureHonoraireId ? { facture_honoraire_id: factureHonoraireId } : {}),
    },
    headers: authHeaders,
  });
  let payload = await extraireErreurEdgeFn(result, error);
  let code = payload?.error as string | undefined;
  let message = payload?.message as string | undefined;
  let factureGenereeAuto = false;

  if (code === 'FACTURE_NON_GENEREE' && !factureHonoraireId) {
    onProgressMessage?.('Génération de la facture honoraires…');
    const genResp = await supabase.functions.invoke('generate-invoice', {
      body: { mission_id: missionId },
      headers: authHeaders,
    });
    const genPayload = await extraireErreurEdgeFn(genResp.data, genResp.error);
    if (genResp.error || genPayload?.error) {
      return {
        result: null,
        error: genResp.error ?? null,
        payload: genPayload,
        code: (genPayload?.error as string | undefined) ?? 'GENERATE_INVOICE_FAILED',
        message: (genPayload?.message as string | undefined) ?? genResp.error?.message ?? 'Impossible de générer la facture honoraires',
        factureGenereeAuto: false,
      };
    }
    factureGenereeAuto = true;

    const retry = await supabase.functions.invoke('stripe-connect-pay-mission', {
      body: { mission_id: missionId },
      headers: authHeaders,
    });
    result = retry.data;
    error = retry.error;
    payload = await extraireErreurEdgeFn(result, error);
    code = payload?.error as string | undefined;
    message = payload?.message as string | undefined;
  }

  return { result, error, payload, code, message, factureGenereeAuto };
}
