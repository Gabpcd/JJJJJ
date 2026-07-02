import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';

/**
 * 6c.4 — Boucle quotidienne : badge « X nouvelles missions » sur l'onglet
 * Explorer, depuis la dernière visite (timestamp localStorage).
 *
 * Première visite (aucun timestamp) : pas de badge — « tout est nouveau »
 * n'informe pas. La visite d'Explorer remet le compteur à zéro
 * (marquerExplorerVisite dans RechercheMissions).
 */
const CLE_DERNIERE_VISITE = 'jolene_explorer_derniere_visite';

export function marquerExplorerVisite() {
  try { localStorage.setItem(CLE_DERNIERE_VISITE, new Date().toISOString()); } catch { /* ignore */ }
}

export function useNouvellesMissionsExplorer(actif: boolean): number {
  const { user } = useAuth();
  const { data } = useQuery({
    queryKey: ['nouvelles-missions-explorer', user?.id],
    queryFn: async () => {
      let depuis: string | null = null;
      try { depuis = localStorage.getItem(CLE_DERNIERE_VISITE); } catch { /* ignore */ }
      if (!depuis) return 0;
      const { count } = await supabase
        .from('missions')
        .select('id', { count: 'exact', head: true })
        .eq('statut', 'OUVERTE')
        .gt('cree_le', depuis);
      return count ?? 0;
    },
    enabled: actif && !!user,
    staleTime: 120_000,
    refetchInterval: 300_000,
  });
  return data ?? 0;
}

export default useNouvellesMissionsExplorer;
