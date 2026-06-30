import React from 'react';
import { AlertTriangle, Flag } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface BandeauOubliDepartProps {
  mission: any;
  onPointer: () => void;
}

export function BandeauOubliDepart({ mission, onPointer }: BandeauOubliDepartProps) {
  const finPrevue = format(new Date(mission.fin_le), "HH:mm", { locale: fr });

  return (
    <div className="bg-warning/10 border-l-4 border-warning p-4 rounded-r-xl mb-4 animate-pulse [animation-duration:3s] [animation-iteration-count:3]">
      <div className="flex items-start gap-3">
        <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
        <div className="flex-1">
          <p className="text-sm font-semibold text-foreground">⚠️ Oubli de pointage ?</p>
          <p className="text-sm text-muted-foreground mt-1">
            Ta mission « {mission.intitule} » devait se terminer à {finPrevue}.
            N'oublie pas de valider ton départ.
          </p>
          <button
            onClick={onPointer}
            className="mt-2 inline-flex items-center gap-2 bg-foreground/80 text-background text-sm font-semibold px-4 py-2 rounded-xl hover:bg-foreground/70 transition-colors"
          >
            <Flag className="h-4 w-4" /> Pointer mon départ maintenant
          </button>
        </div>
      </div>
    </div>
  );
}
