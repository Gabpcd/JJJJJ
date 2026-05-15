import { BadgeY2K } from '@/components/y2k/BadgeY2K';

interface BadgeNiveauProps {
  score: number | null | undefined;
  totalMissionsTerminees?: number | null;
  compact?: boolean;
}

function getNiveau(score: number): {
  label: string;
  variant: 'success' | 'warning' | 'error' | 'info' | 'premium';
} {
  if (score >= 90) return { label: '💎 Diamant', variant: 'premium' };
  if (score >= 70) return { label: '🔵 Platine', variant: 'premium' };
  if (score >= 50) return { label: '🟡 Or', variant: 'warning' };
  if (score >= 30) return { label: '🟠 Argent', variant: 'warning' };
  return { label: '🔴 Bronze', variant: 'error' };
}

export function BadgeNiveau({ score, totalMissionsTerminees, compact }: BadgeNiveauProps) {
  // J5.F : "Non noté" si <3 missions terminées
  const masque = score == null || (totalMissionsTerminees != null && totalMissionsTerminees < 3);

  if (masque) {
    return (
      <BadgeY2K variant="info" size={compact ? 'sm' : 'md'} title="Score disponible après 3 missions terminées">
        Non noté
      </BadgeY2K>
    );
  }

  const { label, variant } = getNiveau(Number(score));
  return (
    <BadgeY2K variant={variant} size={compact ? 'sm' : 'md'}>
      {label}
    </BadgeY2K>
  );
}
