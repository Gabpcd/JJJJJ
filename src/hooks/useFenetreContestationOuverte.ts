import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

/**
 * Fenêtre de contestation d'une présence validée, décidée par le serveur
 * (`fn_fenetre_contestation_ouverte('DESACCORD_HEURES_POINTAGE', mission)`, même
 * prédicat que le refus de `fn_ouvrir_litige_rate_limited`). Aucune constante de
 * délai côté client : la durée est le paramètre `parametres_litiges
 * .delai_contestation_pointage_h` (DECISIONS_LOT2 D12, HARD STOP n°4 ; CLAUDE.md
 * « État dérivé »).
 *
 * Fail-closed : fermée tant que la réponse n'est pas là, sur erreur, ou sur toute
 * réponse autre que `true`. Une présence non validée n'est jamais contestable
 * (le serveur répondrait vrai faute de présence validée : la précondition reste
 * côté client, comme le natif).
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
        if (actif) setOuverte(!error && data === true);
      } catch {
        if (actif) setOuverte(false);
      }
    })();
    return () => { actif = false; };
  }, [missionId, presenceValideeLe]);

  return ouverte;
}
