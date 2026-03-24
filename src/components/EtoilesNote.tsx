import { Star } from 'lucide-react';

interface Props {
  note: number;
  total: number;
  taille?: 'sm' | 'md';
}

export function EtoilesNote({ note, total, taille = 'sm' }: Props) {
  const iconSize = taille === 'sm' ? 'h-3.5 w-3.5' : 'h-4 w-4';
  const textSize = taille === 'sm' ? 'text-xs' : 'text-sm';

  if (total === 0) {
    return <span className={`${textSize} text-muted-foreground`}>Pas encore d'évaluation</span>;
  }

  return (
    <span className={`inline-flex items-center gap-1 ${textSize}`}>
      {[1, 2, 3, 4, 5].map(v => (
        <Star
          key={v}
          className={`${iconSize} ${v <= Math.round(note) ? 'fill-amber-400 text-amber-400' : 'text-muted-foreground/30'}`}
        />
      ))}
      <span className="text-foreground font-medium ml-0.5">{note.toFixed(1)}</span>
      <span className="text-muted-foreground">({total} avis)</span>
    </span>
  );
}
