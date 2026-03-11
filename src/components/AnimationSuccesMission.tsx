import { useEffect } from 'react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface AnimationSuccesMissionProps {
  mission: any;
  onTermine: () => void;
}

export function AnimationSuccesMission({ mission, onTermine }: AnimationSuccesMissionProps) {
  useEffect(() => {
    const timer = setTimeout(onTermine, 3000);
    return () => clearTimeout(timer);
  }, [onTermine]);

  return (
    <div className="fixed inset-0 z-[300] flex items-center justify-center bg-card/95">
      {/* Confetti CSS */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        {Array.from({ length: 24 }).map((_, i) => (
          <div
            key={i}
            className="confetti-piece"
            style={{
              left: `${Math.random() * 100}%`,
              animationDelay: `${Math.random() * 1.5}s`,
              animationDuration: `${2 + Math.random() * 2}s`,
              backgroundColor: ['hsl(var(--primary))', 'hsl(var(--success))', 'hsl(var(--warning))', '#8b5cf6'][i % 4],
            }}
          />
        ))}
      </div>

      <div className="text-center z-10 animate-bounce-in">
        <div className="text-6xl mb-4">🎉</div>
        <h2 className="text-2xl font-bold text-foreground mb-3">Mission acceptée !</h2>
        <p className="text-muted-foreground mb-1">
          Rendez-vous le {format(new Date(mission.debut_le), 'EEEE d MMMM yyyy', { locale: fr })}
        </p>
        <p className="text-muted-foreground mb-4">
          de {format(new Date(mission.debut_le), "HH'h'mm", { locale: fr })} à {format(new Date(mission.fin_le), "HH'h'mm", { locale: fr })}
        </p>
        <p className="text-sm text-primary font-semibold">
          🏥 {mission.etablissements?.nom} — {mission.etablissements?.adresse_ville}
        </p>
      </div>
    </div>
  );
}
