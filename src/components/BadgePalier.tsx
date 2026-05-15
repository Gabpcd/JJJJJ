import { Trophy } from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';

interface BadgePalierProps {
  palierNom: string;
  taux: number;
}

export function BadgePalier({ palierNom, taux }: BadgePalierProps) {
  return (
    <BadgeY2K variant="premium" size="md" icone={<Trophy className="h-3 w-3" />}>
      {palierNom} ({taux}%)
    </BadgeY2K>
  );
}
