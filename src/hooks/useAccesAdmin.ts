import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';

interface AccesAdmin {
  accesTotal: boolean;
  groupes: string[];
  loading: boolean;
  aAcces: (groupe: string) => boolean;
}

export function useAccesAdmin(): AccesAdmin {
  const [accesTotal, setAccesTotal] = useState(true);
  const [groupes, setGroupes] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function charger() {
      const { data, error } = await supabase.rpc('fn_admin_mes_acces' as any);
      if (error || !data) {
        setAccesTotal(true);
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
