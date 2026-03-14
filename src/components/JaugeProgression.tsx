interface JaugeProgressionProps {
  valeur: number;
  max: number;
  marqueurs?: number[];
  couleurBarre?: string;
  couleurFond?: string;
  afficherPourcentage?: boolean;
}

export function JaugeProgression({
  valeur,
  max,
  marqueurs = [],
  couleurBarre = 'bg-primary',
  couleurFond = 'bg-primary/10',
  afficherPourcentage = false,
}: JaugeProgressionProps) {
  const pourcentage = Math.min(Math.round((valeur / max) * 100), 100);

  return (
    <div className="w-full">
      <div className={`relative h-3 rounded-full ${couleurFond} overflow-hidden`}>
        <div
          className={`absolute inset-y-0 left-0 rounded-full ${couleurBarre} transition-all duration-700 ease-out`}
          style={{ width: `${pourcentage}%` }}
        />
        {/* Marqueurs */}
        {marqueurs.map((m) => {
          const pos = (m / max) * 100;
          const atteint = valeur >= m;
          return (
            <div
              key={m}
              className="absolute top-1/2 -translate-y-1/2 -translate-x-1/2"
              style={{ left: `${pos}%` }}
            >
              <div className={`h-4 w-4 rounded-full border-2 ${
                atteint
                  ? 'bg-primary border-primary'
                  : 'bg-card border-muted-foreground/30'
              }`} />
            </div>
          );
        })}
      </div>
      {afficherPourcentage && (
        <p className="text-xs text-muted-foreground mt-1 text-right">{pourcentage}%</p>
      )}
    </div>
  );
}
