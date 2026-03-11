import { Trophy } from 'lucide-react';

interface BadgePalierProps {
  palierNom: string;
  taux: number;
}

export function BadgePalier({ palierNom, taux }: BadgePalierProps) {
  return (
    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-accent/20 text-accent-foreground text-xs font-semibold">
      <Trophy className="h-3 w-3" />
      {palierNom} ({taux}%)
    </span>
  );
}
