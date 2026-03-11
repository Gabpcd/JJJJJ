import { MapPin } from 'lucide-react';
import { formaterDistance } from '@/lib/geo';

interface BadgeDistanceProps {
  distanceKm: number | null;
}

export function BadgeDistance({ distanceKm }: BadgeDistanceProps) {
  if (distanceKm === null) {
    return (
      <span className="flex items-center gap-1 text-xs text-muted-foreground/50">
        <MapPin className="h-3.5 w-3.5" /> Distance non disponible
      </span>
    );
  }

  let couleur = 'text-muted-foreground';
  let label = '';
  if (distanceKm < 5) {
    couleur = 'text-success font-semibold';
    label = ' · Tout près !';
  } else if (distanceKm <= 15) {
    couleur = 'text-primary';
  } else if (distanceKm <= 30) {
    couleur = 'text-warning';
  } else {
    couleur = 'text-muted-foreground';
  }

  return (
    <span className={`flex items-center gap-1 text-xs ${couleur}`}>
      <MapPin className="h-3.5 w-3.5" /> à {formaterDistance(distanceKm)}{label}
    </span>
  );
}
