import { HeartPulse } from 'lucide-react';

export function ChargementPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <div className="flex flex-col items-center gap-3 animate-pulse">
        <HeartPulse className="h-10 w-10 text-primary" />
        <span className="text-lg font-bold text-primary">Soin Direct</span>
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
