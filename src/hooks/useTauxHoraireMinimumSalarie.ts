import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { normaliserTauxMinimumSalarie, TAUX_HORAIRE_MINIMUM_SALARIE_REPLI } from '@/lib/tauxHoraireMinimumSalarie';

/**
 * Taux horaire minimal d'une mission salariée, lu au serveur (`fn_taux_horaire_minimum_salarie`). Repli sur
 * `TAUX_HORAIRE_MINIMUM_SALARIE_REPLI` pendant le chargement, en cas d'erreur ou de paramètre absent. Le refus
 * qui fait foi reste celui du serveur, à l'enregistrement de la mission.
 *
 * Annonce d'abord par `fn_param_bool` (déjà servie partout, comme `useCapaciteAlertesRecherches`) : tant que la
 * migration 20261125120000 n'est pas déployée, la clé est absente, le site garde le repli et n'appelle pas une RPC
 * inexistante (aucune 404 en console sur une base qui ne la porte pas encore).
 */
export function useTauxHoraireMinimumSalarie(): number {
  const [minimum, setMinimum] = useState(TAUX_HORAIRE_MINIMUM_SALARIE_REPLI);
  useEffect(() => {
    let actif = true;
    (async () => {
      try {
        const annonce = await supabase.rpc('fn_param_bool' as any, { p_cle: 'taux_horaire_minimum_salarie', p_defaut: false });
        if (!actif || annonce.error || annonce.data !== true) return;
        const { data, error } = await supabase.rpc('fn_taux_horaire_minimum_salarie' as any);
        if (actif && !error) setMinimum(normaliserTauxMinimumSalarie(data));
      } catch {
        // Repli conservé : le serveur refusera de toute façon un taux insuffisant.
      }
    })();
    return () => { actif = false; };
  }, []);
  return minimum;
}
