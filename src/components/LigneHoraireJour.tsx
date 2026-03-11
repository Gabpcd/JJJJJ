import React from 'react';
import { Wand2 } from 'lucide-react';

export interface HorairesJour {
  jourISO: number;
  label: string;
  heureDebut: string;
  heureFin: string;
  dureeHeures: number;
  actif: boolean;
}

interface LigneHoraireJourProps {
  jour: HorairesJour;
  onChange: (heureDebut: string, heureFin: string) => void;
  estPremierJour: boolean;
  onAppliquerATous?: () => void;
  enErreur: boolean;
  messageErreur?: string;
}

export function parseHeure(heure: string): number {
  const [h, m] = heure.split(':').map(Number);
  return h + m / 60;
}

export function calculerDuree(heureDebut: string, heureFin: string): number {
  let diff = parseHeure(heureFin) - parseHeure(heureDebut);
  if (diff <= 0) diff += 24;
  return Math.round(diff * 10) / 10;
}

export function LigneHoraireJour({ jour, onChange, estPremierJour, onAppliquerATous, enErreur }: LigneHoraireJourProps) {
  const dureeColor = jour.dureeHeures <= 10
    ? 'text-teal-600'
    : jour.dureeHeures <= 12
      ? 'text-amber-600'
      : 'text-destructive font-bold';

  return (
    <div className={`flex flex-col sm:flex-row sm:items-center gap-2 p-3 rounded-xl transition-colors ${
      enErreur ? 'bg-destructive/5 border border-destructive/20' : 'bg-card'
    }`}>
      <span className="font-semibold text-foreground w-24 shrink-0">{jour.label}</span>

      <div className="flex items-center gap-2 flex-1">
        <input
          type="time"
          value={jour.heureDebut}
          onChange={e => onChange(e.target.value, jour.heureFin)}
          className="input-base w-[7rem] text-center"
        />
        <span className="text-muted-foreground text-sm">→</span>
        <input
          type="time"
          value={jour.heureFin}
          onChange={e => onChange(jour.heureDebut, e.target.value)}
          className="input-base w-[7rem] text-center"
        />
        <span className={`text-sm font-medium min-w-[3rem] ${dureeColor}`}>
          ({jour.dureeHeures}h)
        </span>
      </div>

      {estPremierJour && onAppliquerATous && (
        <button
          type="button"
          onClick={onAppliquerATous}
          className="text-sm text-primary hover:text-primary/80 font-medium flex items-center gap-1 shrink-0"
        >
          <Wand2 className="h-3.5 w-3.5" />
          <span className="hidden sm:inline">Appliquer à tous</span>
          <span className="sm:hidden">À tous</span>
        </button>
      )}
    </div>
  );
}
