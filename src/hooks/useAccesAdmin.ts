import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { AdminAccessGroup } from '@/lib/adminAccess';

interface AccesAdmin {
  accesTotal: boolean;
  groupes: string[];
  loading: boolean;
  aAcces: (groupe: AdminAccessGroup) => boolean;
}

export function useAccesAdmin(): AccesAdmin {
  // Fail closed : aucun menu sensible n'est disponible avant la reponse
  // serveur, ni lorsque la verification des droits echoue.
  const [accesTotal, setAccesTotal] = useState(false);
  const [groupes, setGroupes] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function charger() {
      const { data, error } = await supabase.rpc('fn_admin_mes_acces' as any);
      if (cancelled) return;
      if (error || !data) {
        setAccesTotal(false);
        setGroupes([]);
        setLoading(false);
        return;
      }
      const d = data as any;
      if (d.acces_total) {
        setAccesTotal(true);
        setGroupes([]);
      } else {
        setAccesTotal(false);
        setGroupes(Array.isArray(d.groupes) ? d.groupes : []);
      }
      setLoading(false);
    }
    void charger();
    return () => { cancelled = true; };
  }, []);

  const aAcces = useCallback(
    (groupe: AdminAccessGroup) => accesTotal || groupes.includes(groupe),
    [accesTotal, groupes],
  );

  return { accesTotal, groupes, loading, aAcces };
}
