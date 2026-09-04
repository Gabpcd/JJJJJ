import { LoaderCircle } from 'lucide-react';

export function ChargementPage() {
  return (
    <div
      className="flex min-h-[50dvh] items-center justify-center bg-background py-12"
      role="status"
      aria-label="Chargement en cours"
    >
      <LoaderCircle className="h-6 w-6 animate-spin text-primary" aria-hidden="true" />
      <span className="sr-only">Chargement en cours</span>
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
