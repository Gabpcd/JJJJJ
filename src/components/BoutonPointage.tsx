import React, { useState } from 'react';
import { MapPin, Flag, Loader2 } from 'lucide-react';

interface BoutonPointageProps {
  type: 'arrivee' | 'depart';
  onPointage: () => Promise<void>;
  disabled?: boolean;
}

export function BoutonPointage({ type, onPointage, disabled }: BoutonPointageProps) {
  const [enCours, setEnCours] = useState(false);

  const handleClick = async () => {
    if (enCours || disabled) return;
    setEnCours(true);
    try {
      await onPointage();
    } finally {
      setEnCours(false);
    }
  };

  const isArrivee = type === 'arrivee';

  return (
    <div>
      <button
        onClick={handleClick}
        disabled={enCours || disabled}
        className={`w-full py-5 rounded-2xl text-lg font-bold shadow-lg transition-all active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-3 ${
          isArrivee
            ? 'bg-primary text-primary-foreground hover:bg-primary/90'
            : 'bg-foreground/80 text-background hover:bg-foreground/70'
        }`}
      >
        {enCours ? (
          <><Loader2 className="h-5 w-5 animate-spin" /> Géolocalisation en cours...</>
        ) : isArrivee ? (
          <><MapPin className="h-5 w-5" /> POINTER MON ARRIVÉE</>
        ) : (
          <><Flag className="h-5 w-5" /> POINTER MON DÉPART</>
        )}
      </button>
      <p className="text-[11px] text-muted-foreground/60 italic text-center mt-2">
        📍 Votre position est relevée uniquement lors du clic (respect RGPD & vie privée).
      </p>
    </div>
  );
}
