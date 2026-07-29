import { LogoJolene } from '@/components/LogoJolene';

export function ChargementPage() {
  return (
    <div className="min-h-[100dvh] flex items-center justify-center bg-background" role="status" aria-label="Chargement en cours">
      <div className="flex flex-col items-center gap-3">
        <LogoJolene
          decoratif
          className="flex-col gap-3"
          imageClassName="h-10 w-10 animate-pulse"
          nomClassName="text-lg text-rose"
        />
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
