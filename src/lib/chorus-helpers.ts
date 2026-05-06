export type ChorusStatut =
  | 'pending_credentials'
  | 'pending'
  | 'submitting'
  | 'submitted'
  | 'accepted'
  | 'rejected'
  | 'error';

export interface ChorusBadgeConfig {
  label: string;
  classes: string;
}

export const CHORUS_STATUT_CONFIG: Record<ChorusStatut | 'unknown', ChorusBadgeConfig> = {
  pending_credentials: { label: 'Credentials manquants', classes: 'bg-muted text-muted-foreground' },
  pending: { label: 'En attente', classes: 'bg-warning/10 text-warning' },
  submitting: { label: 'En cours', classes: 'bg-warning/10 text-warning' },
  submitted: { label: 'Déposée', classes: 'bg-info/10 text-info' },
  accepted: { label: 'Acceptée', classes: 'bg-success/10 text-success' },
  rejected: { label: 'Rejetée', classes: 'bg-destructive/10 text-destructive' },
  error: { label: 'Erreur', classes: 'bg-destructive/10 text-destructive' },
  unknown: { label: '—', classes: 'bg-muted text-muted-foreground' },
};

export function getChorusStatutBadge(status: string | null | undefined): ChorusBadgeConfig {
  if (!status) return CHORUS_STATUT_CONFIG.unknown;
  return CHORUS_STATUT_CONFIG[status as ChorusStatut] ?? CHORUS_STATUT_CONFIG.unknown;
}
