import { BADGES_STATUT } from '@/lib/constantes';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';

interface BadgeStatutProps {
  statut: string;
}

// Mapping statut métier mission → variant Y2K (Sprint 12-G).
// Lot 11 : Ouverte ≠ Expirée — une mission ouverte (recrutement actif) n'est
// pas un avertissement ; l'orange est réservé aux états qui demandent
// attention (expirée sans candidat, litige).
const STATUT_VARIANT: Record<string, 'success' | 'warning' | 'error' | 'info' | 'premium'> = {
  OUVERTE: 'info',
  ASSIGNEE: 'success',
  EN_COURS: 'success',
  TERMINEE: 'success',
  EXPIREE: 'warning',
  ANNULEE_PAR_ETABLISSEMENT: 'info',
  ANNULEE_PAR_SOIGNANT: 'error',
  ABSENCE: 'error',
  LITIGE: 'warning',
};

export function BadgeStatut({ statut }: BadgeStatutProps) {
  const config = BADGES_STATUT[statut] || { label: statut, classes: '' };
  const variant = STATUT_VARIANT[statut] ?? 'info';
  return (
    <BadgeY2K variant={variant} size="md">
      {config.label}
    </BadgeY2K>
  );
}
