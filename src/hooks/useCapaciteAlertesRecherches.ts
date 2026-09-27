import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';

/** Découverte via une API préexistante : ne pas appeler une RPC pas encore livrée. */
export function useCapaciteAlertesRecherches(audience: string) {
  const { user } = useAuth();
  const [revision, setRevision] = useState(0);
  const [verification, setVerification] = useState<{ userId: string; disponible: boolean; erreur: string | null } | null>(null);
  const estEtab = audience === 'ETAB_RECHERCHE_SOIGNANTS';
  useEffect(() => {
    if (!estEtab || !user?.id) return;
    let actif = true;
    setVerification(null);
    void (async () => {
      try {
        const annonce = await supabase.rpc('fn_param_bool' as any, { p_cle: 'api_alertes_recherches_v1', p_defaut: false });
        if (!actif) return;
        if (annonce.error || typeof annonce.data !== 'boolean') {
          setVerification({ userId: user.id, disponible: false, erreur: 'Impossible de vérifier la disponibilité des alertes. Réessayez.' });
          return;
        }
        if (!annonce.data) {
          setVerification({ userId: user.id, disponible: false, erreur: null });
          return;
        }
        const { data, error } = await supabase.rpc('fn_capacite_alertes_recherches' as any);
        if (actif) setVerification({ userId: user.id, disponible: !error && data === true,
          erreur: error || typeof data !== 'boolean' ? 'Le service d’alertes annoncé est momentanément indisponible. Réessayez.' : null });
      } catch {
        if (actif) setVerification({ userId: user.id, disponible: false, erreur: 'Impossible de vérifier la disponibilité des alertes. Réessayez.' });
      }
    })();
    return () => { actif = false; };
  }, [estEtab, user?.id, revision]);
  return {
    disponible: !estEtab || !!(verification?.userId === user?.id && verification?.disponible),
    erreur: estEtab && verification?.userId === user?.id ? verification?.erreur ?? null : null,
    verificationEnCours: estEtab && !!user?.id && verification?.userId !== user.id,
    reessayer: () => setRevision(r => r + 1),
  };
}
