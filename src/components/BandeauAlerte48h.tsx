import React from 'react';
import { format, addDays, startOfWeek } from 'date-fns';
import { fr } from 'date-fns/locale';

interface BandeauAlerte48hProps {
  heuresSemaine: number;
}

export function BandeauAlerte48h({ heuresSemaine }: BandeauAlerte48hProps) {
  if (heuresSemaine < 44) return null;

  const lundiProchain = addDays(startOfWeek(new Date(), { weekStartsOn: 1 }), 7);
  const restant = Math.max(0, 48 - heuresSemaine);

  if (heuresSemaine >= 48) {
    return (
      <div className="bg-destructive/5 border-l-4 border-destructive p-4 rounded-r-xl mb-4">
        <p className="text-sm text-destructive font-medium">
          🛑 Plafond de 48h atteint cette semaine. Vous ne pouvez plus accepter de missions
          avant la semaine prochaine (lundi {format(lundiProchain, 'd MMMM', { locale: fr })}).
        </p>
      </div>
    );
  }

  return (
    <div className="bg-warning/5 border-l-4 border-warning p-4 rounded-r-xl mb-4">
      <p className="text-sm text-warning font-medium">
        🚨 Attention : vous approchez du plafond de 48h cette semaine ({heuresSemaine.toFixed(0)}h planifiées).
        Vous ne pourrez plus accepter que {restant.toFixed(0)}h de missions.
      </p>
    </div>
  );
}
