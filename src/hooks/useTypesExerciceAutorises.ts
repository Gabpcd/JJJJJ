import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';

type EtatTypesExercice = {
  profession: string;
  typesAutorises: string[] | null;
  statut: 'inactif' | 'chargement' | 'disponible' | 'indisponible';
};

export function useTypesExerciceAutorises(profession: string) {
  const [etat, setEtat] = useState<EtatTypesExercice>({
    profession: '',
    typesAutorises: null,
    statut: 'inactif',
  });

  useEffect(() => {
    if (!profession) {
      setEtat({ profession: '', typesAutorises: null, statut: 'inactif' });
      return;
    }

    let actif = true;
    setEtat({ profession, typesAutorises: null, statut: 'chargement' });

    void (async () => {
      try {
        const { data, error } = await supabase.rpc('fn_types_exercice_autorises' as any, { p_profession: profession });
        if (!actif) return;
        if (error || !Array.isArray(data)) {
          setEtat({ profession, typesAutorises: null, statut: 'indisponible' });
          return;
        }
        setEtat({ profession, typesAutorises: data, statut: 'disponible' });
      } catch {
        if (actif) {
          setEtat({ profession, typesAutorises: null, statut: 'indisponible' });
        }
      }
    })();

    return () => {
      actif = false;
    };
  }, [profession]);

  // Ne jamais exposer la réponse de la profession précédente pendant le
  // changement : une règle IDE ne doit pas être appliquée à un profil AS.
  const correspondProfession = !!profession && etat.profession === profession;
  const typesAutorises = correspondProfession && etat.statut === 'disponible'
    ? etat.typesAutorises
    : null;
  const loading = !!profession && (!correspondProfession || etat.statut === 'chargement');
  const indisponible = correspondProfession && etat.statut === 'indisponible';
  const uniqueType = typesAutorises && typesAutorises.length === 1 ? typesAutorises[0] : null;

  return { typesAutorises, uniqueType, loading, indisponible };
}
