import { Tag } from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';

interface BadgePalierProps {
  /** Conservé pour compatibilité d'appel — plus affiché (paliers abandonnés). */
  palierNom?: string;
  taux: number;
}

/** Badge du taux de commission (modèle par paliers abandonné — 12/06/2026). */
export function BadgePalier({ taux }: BadgePalierProps) {
  const formatTaux = (valeur: number) => new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 2 }).format(valeur);
  return (
    <BadgeY2K variant="info" size="md" icone={<Tag className="h-3 w-3" />}>
      Commission {formatTaux(taux)} % HT · {formatTaux(taux * 1.2)} % TTC
    </BadgeY2K>
  );
}
