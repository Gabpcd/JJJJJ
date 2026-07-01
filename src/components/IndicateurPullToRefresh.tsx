import { Loader2, ArrowDown } from 'lucide-react';

/**
 * Indicateur visuel du pull-to-refresh (cf. usePullToRefresh).
 * Rendu en haut du contenu de page : hauteur nulle au repos, s'étire pendant
 * le tirage, spinner pendant le refetch.
 */
export function IndicateurPullToRefresh({ distance, refreshing }: { distance: number; refreshing: boolean }) {
  const hauteur = refreshing ? 48 : distance;
  if (hauteur <= 0) return null;
  const pret = distance >= 70;
  return (
    <div
      className="flex items-center justify-center overflow-hidden text-muted-foreground transition-[height] duration-100"
      style={{ height: hauteur }}
      aria-hidden="true"
    >
      {refreshing ? (
        <Loader2 className="h-5 w-5 animate-spin text-primary" />
      ) : (
        <span className="inline-flex items-center gap-1.5 text-xs font-medium">
          <ArrowDown className={`h-4 w-4 transition-transform ${pret ? 'rotate-180 text-primary' : ''}`} />
          {pret ? 'Relâche pour actualiser' : 'Tire pour actualiser'}
        </span>
      )}
    </div>
  );
}
