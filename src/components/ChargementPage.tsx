export function ChargementPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <div className="flex flex-col items-center gap-4">
        <div className="relative">
          <div className="h-12 w-12 rounded-full border-4 border-primary/20 border-t-primary animate-spin" />
        </div>
        <p className="text-sm text-muted-foreground">Chargement…</p>
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
