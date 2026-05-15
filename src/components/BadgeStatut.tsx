import { BADGES_STATUT } from '@/lib/constantes';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';

interface BadgeStatutProps {
  statut: string;
}

// Mapping statut métier mission → variant Y2K (Sprint 12-G).
// Cohérence avec autres usages Sprint 12-E (OUVERTE warning, etc.).
const STATUT_VARIANT: Record<string, 'success' | 'warning' | 'error' | 'info' | 'premium'> = {
  OUVERTE: 'warning',
  ASSIGNEE: 'info',
  EN_COURS: 'info',
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
