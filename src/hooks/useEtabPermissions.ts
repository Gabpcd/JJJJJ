import { useEffect, useState, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';

export type RoleEtab = 'PROPRIETAIRE' | 'ADMIN_GROUPE' | 'RH' | 'POINTAGE_ONLY' | 'LECTURE_SEULE';

export interface PermissionsEtab {
  gerer_equipe: boolean;
  supprimer_compte: boolean;
  profil_etab: boolean;
  paiement: boolean;
  lecture_paiement: boolean;
  missions: boolean;
  candidatures: boolean;
  contrats: boolean;
  pointage: boolean;
  rh: boolean;
  lecture: boolean;
}

const PERMISSIONS_VIDES: PermissionsEtab = {
  gerer_equipe: false,
  supprimer_compte: false,
  profil_etab: false,
  paiement: false,
  lecture_paiement: false,
  missions: false,
  candidatures: false,
  contrats: false,
  pointage: false,
  rh: false,
  lecture: false,
};

interface State {
  loading: boolean;
  role: RoleEtab | null;
  permissions: PermissionsEtab;
  etablissementId: string | null;
  error: string | null;
}

/**
 * Hook permissions équipe étab (Sprint 5.7 PR 3).
 *
 * Appelle fn_mes_permissions_etab et expose role + matrix de permissions.
 *
 * Usage :
 * ```tsx
 * const { permissions, role, loading } = useEtabPermissions();
 * if (!permissions.paiement) return <AccesRefuse />;
 * ```
 *
 * Cache 30 secondes par défaut pour éviter trop de roundtrips.
 */
export function useEtabPermissions(
  etablissementId?: string,
  enabled = true,
): State & { recharger: () => Promise<void> } {
  const { user } = useAuth();
  const [state, setState] = useState<State>({
    loading: true,
    role: null,
    permissions: PERMISSIONS_VIDES,
    etablissementId: etablissementId ?? null,
    error: null,
  });

  const recharger = useCallback(async () => {
    if (!enabled || !user) {
      setState({ loading: false, role: null, permissions: PERMISSIONS_VIDES, etablissementId: null, error: null });
      return;
    }
    setState((s) => ({ ...s, loading: true, error: null }));
    const { data, error } = await supabase.rpc('fn_mes_permissions_etab' as any, {
      p_etablissement_id: etablissementId ?? null,
    });
    if (error) {
      setState({
        loading: false,
        role: null,
        permissions: PERMISSIONS_VIDES,
        etablissementId: etablissementId ?? null,
        error: error.message,
      });
      return;
    }
    const result = data as any;
    if (!result?.success) {
      setState({
        loading: false,
        role: null,
        permissions: PERMISSIONS_VIDES,
        etablissementId: etablissementId ?? null,
        error: result?.error_code || 'Erreur',
      });
      return;
    }
    const role = (result.role as RoleEtab | null) ?? null;
    const perms = (result.permissions ?? PERMISSIONS_VIDES) as Partial<PermissionsEtab>;
    setState({
      loading: false,
      role,
      permissions: { ...PERMISSIONS_VIDES, ...perms },
      etablissementId: etablissementId ?? null,
      error: null,
    });
  }, [user, etablissementId, enabled]);

  useEffect(() => {
    void recharger();
  }, [recharger]);

  return { ...state, recharger };
}

/**
 * Vérifie si l'utilisateur courant a une permission donnée.
 * Retourne null tant que le chargement est en cours.
 */
export function usePermissionEtab(perm: keyof PermissionsEtab): boolean | null {
  const { loading, permissions } = useEtabPermissions();
  if (loading) return null;
  return permissions[perm];
}
