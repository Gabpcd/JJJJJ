import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * Lecture générique d'un flag booléen système via `fn_param_bool` (miroir de
 * `parametres_systeme.valeur`, 0 = false). Flippable à chaud sans redeploy.
 *
 * Défaut renvoyé tant que le flag n'est pas confirmé (chargement / erreur) :
 * on ne promet jamais un service/avantage indisponible par défaut.
 *
 * (`useAffacturageActif` reste séparé pour son intention métier explicite ; ce
 * hook couvre les autres flags ponctuels — ex. récompenses 3200h.)
 */
export function useParamBool(cle: string, defaut = false): boolean {
  const { data } = useQuery({
    queryKey: ['feature-flag', cle],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_param_bool' as any, {
        p_cle: cle,
        p_defaut: defaut,
      });
      if (error) return defaut;
      return !!data;
    },
    staleTime: 5 * 60_000,
  });
  return data ?? defaut;
}
