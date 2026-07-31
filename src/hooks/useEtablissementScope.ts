import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';

export function useEtablissementScope() {
  const { user } = useAuth();
  const { role, etablissement_id, loading, resolved, error, retry } = useRole();

  // Les anciens comptes mono-établissement utilisaient leur user.id comme
  // établissement et un rôle signé ETABLISSEMENT, sans métadonnée de scope.
  // On garde ce repli strictement borné à cet ancien alias signé.
  const legacyEtablissementId = resolved
    && !error
    && role === 'ADMIN_ETABLISSEMENT'
    && user?.app_metadata?.role === 'ETABLISSEMENT'
    ? user.id
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
