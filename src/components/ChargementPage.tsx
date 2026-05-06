import { HeartPulse } from 'lucide-react';

export function ChargementPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-background" role="status" aria-label="Chargement en cours">
      <div className="flex flex-col items-center gap-3">
        <HeartPulse className="h-10 w-10 text-rose animate-pulse" aria-hidden="true" />
        <span className="text-lg font-bold text-rose">Jolene</span>
      </div>
    </div>
  );
}

export function SkeletonCard() {
  return (
    <div className="card-base space-y-3">
      <div className="h-4 w-3/4 rounded-lg animate-shimmer" />
      <div className="h-3 w-1/2 rounded-lg animate-shimmer" />
      <div className="h-3 w-2/3 rounded-lg animate-shimmer" />
    </div>
  );
}
