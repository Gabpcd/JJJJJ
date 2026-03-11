import React, { useState, useEffect } from 'react';
import { MapPin, Flag, Loader2, RotateCcw } from 'lucide-react';

interface BoutonPointageProps {
  type: 'arrivee' | 'depart';
  onPointage: () => Promise<void>;
  disabled?: boolean;
}

type EtatGPS = 'idle' | 'recherche' | 'acquisition' | 'signal_faible' | 'erreur';

export function BoutonPointage({ type, onPointage, disabled }: BoutonPointageProps) {
  const [etatGPS, setEtatGPS] = useState<EtatGPS>('idle');

  const handleClick = async () => {
    if (etatGPS !== 'idle' && etatGPS !== 'erreur') return;
    if (disabled) return;

    setEtatGPS('recherche');

    const timerAcquisition = setTimeout(() => setEtatGPS('acquisition'), 3000);
    const timerSignalFaible = setTimeout(() => setEtatGPS('signal_faible'), 8000);

    try {
      await onPointage();
    } catch {
      // error handled by parent
    } finally {
      clearTimeout(timerAcquisition);
      clearTimeout(timerSignalFaible);
      setEtatGPS('idle');
    }
  };

  const handleRetry = () => {
    setEtatGPS('idle');
    setTimeout(() => handleClick(), 50);
  };

  const enCours = etatGPS === 'recherche' || etatGPS === 'acquisition' || etatGPS === 'signal_faible';
  const isArrivee = type === 'arrivee';

  return (
    <div>
      {etatGPS === 'erreur' ? (
        <button
          onClick={handleRetry}
          className="w-full py-5 rounded-2xl text-lg font-bold shadow-lg transition-all active:scale-95 flex items-center justify-center gap-3 bg-destructive text-destructive-foreground hover:bg-destructive/90"
        >
          <RotateCcw className="h-5 w-5" /> Réessayer
        </button>
      ) : (
        <button
          onClick={handleClick}
          disabled={enCours || disabled}
          className={`w-full py-5 rounded-2xl text-lg font-bold shadow-lg transition-all active:scale-95 disabled:opacity-70 disabled:cursor-not-allowed flex items-center justify-center gap-3 ${
            isArrivee
              ? 'bg-primary text-primary-foreground hover:bg-primary/90'
              : 'bg-foreground/80 text-background hover:bg-foreground/70'
          }`}
        >
          {enCours ? (
            <><Loader2 className="h-5 w-5 animate-spin" /> 🛰️ Recherche du signal satellite...</>
          ) : isArrivee ? (
            <><MapPin className="h-5 w-5" /> POINTER MON ARRIVÉE</>
          ) : (
            <><Flag className="h-5 w-5" /> POINTER MON DÉPART</>
          )}
        </button>
      )}

      {/* Messages GPS progressifs */}
      {etatGPS === 'acquisition' && (
        <p className="text-sm text-primary animate-pulse text-center mt-2">
          🛰️ Acquisition GPS en cours... restez immobile quelques secondes
        </p>
      )}
      {etatGPS === 'signal_faible' && (
        <p className="text-sm text-warning text-center mt-2">
          📡 Signal faible — tentative en cours...
        </p>
      )}
      {etatGPS === 'erreur' && (
        <p className="text-sm text-destructive text-center mt-2">
          Impossible d'obtenir votre position. Cliquez sur Réessayer.
        </p>
      )}

      {etatGPS === 'idle' && (
        <p className="text-[11px] text-muted-foreground/60 italic text-center mt-2">
          📍 Votre position est relevée uniquement lors du clic (respect RGPD & vie privée).
        </p>
      )}
    </div>
  );
}
