import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';

export function useTypesExerciceAutorises(profession: string) {
  const [typesAutorises, setTypesAutorises] = useState<string[] | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!profession) {
      setTypesAutorises(null);
      return;
    }
    setLoading(true);
    supabase.rpc('fn_types_exercice_autorises' as any, { p_profession: profession })
      .then(({ data, error }: any) => {
        if (error || !Array.isArray(data)) {
          setTypesAutorises(null);
        } else {
          setTypesAutorises(data);
        }
        setLoading(false);
      });
  }, [profession]);

  const uniqueType = typesAutorises && typesAutorises.length === 1 ? typesAutorises[0] : null;

  return { typesAutorises, uniqueType, loading };
}
