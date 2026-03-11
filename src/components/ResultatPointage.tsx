import React from 'react';
import { MapPin, Radio, AlertTriangle } from 'lucide-react';

interface ResultatPointageProps {
  type: 'arrivee' | 'depart';
  heure: string;
  distanceM: number | null;
  perimetreOk: boolean | null;
  precisionM: number | null;
  alerteTeleportation?: boolean;
}

export function ResultatPointage({ type, heure, distanceM, perimetreOk, precisionM, alerteTeleportation }: ResultatPointageProps) {
  const heureFormatee = new Date(heure).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  const label = type === 'arrivee' ? 'Arrivée' : 'Départ';

  return (
    <div className="space-y-1">
      <div className="flex items-center gap-2 text-sm">
        <span className="text-success font-medium">✅ {label} pointé{type === 'arrivee' ? 'e' : ''} à {heureFormatee}</span>
      </div>
      <div className="flex flex-wrap gap-3 text-xs">
        {distanceM !== null && (
          <span className={`flex items-center gap-1 ${perimetreOk ? 'text-success' : 'text-warning'}`}>
            <MapPin className="h-3.5 w-3.5" />
            à {Math.round(distanceM)}m
            {perimetreOk ? ' · Périmètre OK' : ` · Hors périmètre (>${500}m)`}
          </span>
        )}
        {precisionM !== null && (
          <span className={`flex items-center gap-1 ${precisionM > 100 ? 'text-warning' : 'text-muted-foreground'}`}>
            <Radio className="h-3.5 w-3.5" />
            Précision {precisionM > 100 ? 'faible' : ''} : {Math.round(precisionM)}m
          </span>
        )}
      </div>
      {alerteTeleportation && (
        <div className="flex items-center gap-1 text-xs text-destructive font-medium">
          <AlertTriangle className="h-3.5 w-3.5" />
          🚨 Alerte téléportation détectée
        </div>
      )}
    </div>
  );
}
