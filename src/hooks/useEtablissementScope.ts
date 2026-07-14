import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';

export function useEtablissementScope() {
  const { user } = useAuth();
  const { role, etablissement_id, loading, resolved, error, retry } = useRole();

  // La RPC actuelle fournit toujours etablissement_id pour les comptes et
  // membres ADMIN_ETABLISSEMENT. Le seul fallback toléré couvre l'ancien rôle
  // ETABLISSEMENT, après une résolution serveur explicitement réussie.
  const legacyEtablissementId = resolved && !error && role === 'ETABLISSEMENT'
    ? user?.id ?? null
    : null;
  const etablissementId = resolved && !error
    ? etablissement_id ?? legacyEtablissementId
    : null;

  return {
    user,
    loading,
    resolved,
    error,
    retry,
    etablissementId,
  };
}
