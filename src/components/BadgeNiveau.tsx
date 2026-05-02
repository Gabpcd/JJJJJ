interface BadgeNiveauProps {
  score: number | null | undefined;
  totalMissionsTerminees?: number | null;
  compact?: boolean;
}

function getNiveau(score: number) {
  if (score >= 90) return { label: '💎 Diamant', classes: 'bg-gradient-to-r from-emerald-100 to-teal-100 text-emerald-800 border-emerald-300 animate-shimmer' };
  if (score >= 70) return { label: '🔵 Platine', classes: 'bg-primary/10 text-primary border-primary/30' };
  if (score >= 50) return { label: '🟡 Or', classes: 'bg-yellow-100 text-yellow-700 border-yellow-300' };
  if (score >= 30) return { label: '🟠 Argent', classes: 'bg-amber-100 text-amber-700 border-amber-300' };
  return { label: '🔴 Bronze', classes: 'bg-destructive/10 text-destructive border-destructive/30' };
}

export function BadgeNiveau({ score, totalMissionsTerminees, compact }: BadgeNiveauProps) {
  // J5.F : "Non noté" si <3 missions terminées
  const masque = score == null || (totalMissionsTerminees != null && totalMissionsTerminees < 3);

  if (masque) {
    return (
      <span
        className={`inline-flex items-center border rounded-full font-semibold bg-muted text-muted-foreground border-border ${compact ? 'px-2 py-0.5 text-[10px]' : 'px-3 py-1 text-xs'}`}
        title="Score disponible après 3 missions terminées"
      >
        Non noté
      </span>
    );
  }

  const { label, classes } = getNiveau(Number(score));
  return (
    <span className={`inline-flex items-center border rounded-full font-semibold ${compact ? 'px-2 py-0.5 text-[10px]' : 'px-3 py-1 text-xs'} ${classes}`}>
      {label}
    </span>
  );
}
