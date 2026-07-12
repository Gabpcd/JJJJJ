import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';

interface AccesAdmin {
  accesTotal: boolean;
  groupes: string[];
  loading: boolean;
  aAcces: (groupe: string) => boolean;
}

export function useAccesAdmin(): AccesAdmin {
  // Fail closed : aucun menu sensible n'est disponible avant la reponse
  // serveur, ni lorsque la verification des droits echoue.
  const [accesTotal, setAccesTotal] = useState(false);
  const [groupes, setGroupes] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function charger() {
      const { data, error } = await supabase.rpc('fn_admin_mes_acces' as any);
      if (error || !data) {
        setAccesTotal(false);
        setGroupes([]);
        setLoading(false);
        return;
      }
      const d = data as any;
      if (d.acces_total) {
        setAccesTotal(true);
      } else {
        setAccesTotal(false);
        setGroupes(d.groupes || []);
      }
      setLoading(false);
    }
    charger();
  }, []);

  const aAcces = useCallback(
    (groupe: string) => accesTotal || groupes.includes(groupe),
    [accesTotal, groupes],
  );

  return { accesTotal, groupes, loading, aAcces };
}
