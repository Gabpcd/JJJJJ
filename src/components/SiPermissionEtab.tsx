import { ReactNode } from 'react';
import { useEtabPermissions, type PermissionsEtab } from '@/hooks/useEtabPermissions';

interface Props {
  /** Permission requise (clé de PermissionsEtab) */
  permission: keyof PermissionsEtab;
  /** Plusieurs permissions : toutes requises (AND) */
  permissions?: Array<keyof PermissionsEtab>;
  /** Mode : 'all' (toutes requises) ou 'any' (au moins une) */
  mode?: 'all' | 'any';
  /** Composant affiché si autorisé */
  children: ReactNode;
  /** Composant affiché si refusé (par défaut : rien) */
  fallback?: ReactNode;
}

/**
 * Wrapper composant pour afficher conditionnellement selon permissions étab (Sprint 5.7 PR 3).
 *
 * Usage :
 * ```tsx
 * <SiPermissionEtab permission="paiement">
 *   <BoutonPayer />
 * </SiPermissionEtab>
 *
 * <SiPermissionEtab permissions={['paiement', 'profil_etab']} mode="all">
 *   <FormulaireSensible />
 * </SiPermissionEtab>
 *
 * <SiPermissionEtab permission="profil_etab" fallback={<MessageRefus />}>
 *   <EditeurProfil />
 * </SiPermissionEtab>
 * ```
 *
 * Notes :
 * - Pendant le chargement initial : rien n'est affiché (évite flash UI).
 * - Si pas de session étab (role null) : rien n'est affiché.
 * - Vérification côté backend reste source de vérité (RPC sécurisées).
 */
export function SiPermissionEtab({ permission, permissions, mode = 'all', children, fallback = null }: Props) {
  const { loading, permissions: perms } = useEtabPermissions();
  if (loading) return null;

  const liste = permissions ?? [permission];
  const autorise = mode === 'all'
    ? liste.every((p) => perms[p])
    : liste.some((p) => perms[p]);

  return <>{autorise ? children : fallback}</>;
}
