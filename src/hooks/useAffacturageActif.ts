import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * Feature flag « affacturage_actif » (paiement rapide Defacto), lu depuis le
 * paramètre système `affacturage_actif` via `fn_param_bool` — flippable à chaud
 * sans redeploy.
 *
 * Défaut **false** (y compris pendant le chargement) : tant que le flag n'est pas
 * confirmé actif, on N'AFFICHE PAS l'affacturage (onglet Avances, opt-in Defacto,
 * cession de créance) — il promet sinon un service indisponible.
 */
export function useAffacturageActif(): boolean {
  const { data } = useQuery({
    queryKey: ['feature-flag', 'affacturage_actif'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_param_bool' as any, {
        p_cle: 'affacturage_actif',
        p_defaut: false,
      });
      if (error) return false;
      return !!data;
    },
    staleTime: 5 * 60_000,
  });
  return data ?? false;
}
