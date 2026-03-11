import { BADGES_STATUT } from '@/lib/constantes';

interface BadgeStatutProps {
  statut: string;
}

export function BadgeStatut({ statut }: BadgeStatutProps) {
  const config = BADGES_STATUT[statut] || { label: statut, classes: 'bg-muted text-muted-foreground' };
  return (
    <span className={`badge-base ${config.classes}`}>
      {config.label}
    </span>
  );
}
