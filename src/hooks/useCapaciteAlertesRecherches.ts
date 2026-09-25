import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';

/** Le frontend peut arriver avant SQL/Edge : une RPC absente ferme l'activation. */
export function useCapaciteAlertesRecherches(audience: string) {
  const { user } = useAuth();
  const [revision, setRevision] = useState(0);
  const [verification, setVerification] = useState<{ userId: string; disponible: boolean } | null>(null);
  const estEtab = audience === 'ETAB_RECHERCHE_SOIGNANTS';
  useEffect(() => {
    if (!estEtab || !user?.id) return;
    let actif = true;
    setVerification(null);
    void (async () => {
      try {
        const { data, error } = await supabase.rpc('fn_capacite_alertes_recherches' as any);
        if (actif) setVerification({ userId: user.id, disponible: !error && data === true });
      } catch {
        if (actif) setVerification({ userId: user.id, disponible: false });
      }
    })();
    return () => { actif = false; };
  }, [estEtab, user?.id, revision]);
  return {
    disponible: !estEtab || !!(verification?.userId === user?.id && verification?.disponible),
    verificationEnCours: estEtab && !!user?.id && verification === null,
    reessayer: () => setRevision(r => r + 1),
  };
}
