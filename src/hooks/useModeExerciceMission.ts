import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import {
  paramsModeExerciceMission,
  type ModeExerciceMission,
} from '@/lib/modeExerciceMission';

export function useModeExerciceMission(
  professionRequise: string,
  typeEtablissement: string | null,
  estSecteurPublic: boolean,
) {
  const [mode, setMode] = useState<ModeExerciceMission | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!professionRequise || !typeEtablissement) {
      setMode(null);
      setError(null);
      setLoading(false);
      return;
    }

    let actif = true;
    setMode(null);
    setError(null);
    setLoading(true);

    supabase
      .rpc(
        'fn_mode_exercice' as any,
        paramsModeExerciceMission(professionRequise, typeEtablissement, estSecteurPublic) as any,
      )
      .then(({ data, error: rpcError }: any) => {
        if (!actif) return;
        if (rpcError || !data?.niveau) {
          setError(rpcError?.message || 'Matrice des modes d’exercice indisponible.');
          setMode(null);
        } else {
          setMode(data as ModeExerciceMission);
        }
        setLoading(false);
      });

    return () => {
      actif = false;
    };
  }, [professionRequise, typeEtablissement, estSecteurPublic]);

  return { mode, loading, error };
}
