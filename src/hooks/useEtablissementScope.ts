import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';

export function useEtablissementScope() {
  const { user } = useAuth();
  const { etablissement_id, loading } = useRole();

  return {
    user,
    loading,
    etablissementId: etablissement_id ?? user?.id ?? null,
  };
}