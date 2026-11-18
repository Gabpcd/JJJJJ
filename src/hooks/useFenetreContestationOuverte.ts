import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { capturerErreurSentry } from '@/lib/sentry';

/**
 * Fenêtre de contestation d'une présence validée, décidée par le serveur
 * (`fn_fenetre_contestation_ouverte('DESACCORD_HEURES_POINTAGE', mission)`, même
 * prédicat que le refus de `fn_ouvrir_litige_rate_limited`). Aucune constante de
 * délai côté client : la durée est le paramètre `parametres_litiges
 * .delai_contestation_pointage_h` (DECISIONS_LOT2 D12, HARD STOP n°4 ; CLAUDE.md
 * « État dérivé »).
 *
 * Fail-closed : fermée tant que la réponse n'est pas là, sur erreur, ou sur toute
 * réponse autre que `true`. Une erreur, un rejet ou une réponse non booléenne
 * sont remontés à Sentry : un fail-closed muet (grant retiré, 42501) retirerait le
 * canal de contestation à tous sans alerte. Une présence non validée n'est jamais
 * contestable (le serveur répondrait vrai faute de présence validée : la
 * précondition reste côté client, comme le natif).
 */
export function useFenetreContestationOuverte(
  missionId: string,
  presenceValideeLe: string | null,
): boolean {
  const [ouverte, setOuverte] = useState(false);

  useEffect(() => {
    setOuverte(false);
    if (!presenceValideeLe || !missionId) return;
    let actif = true;
    (async () => {
      try {
        // p_facture_id omis : DEFAULT NULL (sans objet pour une présence).
        const { data, error } = await supabase.rpc('fn_fenetre_contestation_ouverte', {
          p_type_litige: 'DESACCORD_HEURES_POINTAGE',
          p_mission_id: missionId,
        });
        if (!actif) return;
        if (error) {
          capturerErreurSentry(error, 'useFenetreContestationOuverte', 'fenetre_contestation');
        } else if (typeof data !== 'boolean') {
          capturerErreurSentry(
            new Error(`réponse non booléenne : ${JSON.stringify(data)}`),
            'useFenetreContestationOuverte',
            'fenetre_contestation',
          );
        }
        setOuverte(!error && data === true);
      } catch (err) {
        if (!actif) return;
        capturerErreurSentry(err, 'useFenetreContestationOuverte', 'fenetre_contestation');
        setOuverte(false);
      }
    })();
    return () => { actif = false; };
  }, [missionId, presenceValideeLe]);

  return ouverte;
}
