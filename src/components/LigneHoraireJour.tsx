import React from 'react';
import { Trash2 } from 'lucide-react';
import {
  dateFinCreneau,
  libelleDateCourte,
  materialiserCreneau,
  type CreneauPlanningDate,
} from '@/lib/planning-derive';

interface LigneHoraireJourProps {
  date: string;
  creneau: CreneauPlanningDate;
  index: number;
  onChange: (creneau: CreneauPlanningDate) => void;
  onRemove: () => void;
  enErreur: boolean;
}

export function LigneHoraireJour({
  date,
  creneau,
  index,
  onChange,
  onRemove,
  enErreur,
}: LigneHoraireJourProps) {
  const resultat = materialiserCreneau(date, creneau);
  const duree = resultat.valeur?.dureeHeures ?? null;
  const dateFin = dateFinCreneau(date, creneau);
  const dureeColor = duree == null
    ? 'text-destructive'
    : duree <= 10
      ? 'text-teal-600'
      : duree <= 12
        ? 'text-amber-600'
        : 'text-destructive font-bold';

  return (
    <div
      className={`rounded-xl border p-3 ${
        enErreur ? 'border-destructive/40 bg-destructive/5' : 'border-border bg-card'
      }`}
      data-testid={`creneau-${date}-${index}`}
    >
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_auto_1fr_1.35fr_auto] sm:items-end">
        <label className="text-xs text-muted-foreground">
          Début
          <input
            aria-label={`Début du créneau ${index + 1} du ${date}`}
            type="time"
            value={creneau.heureDebut}
            onChange={(event) => onChange({ ...creneau, heureDebut: event.target.value })}
            className="input-base mt-1 w-full text-center"
          />
        </label>

        <span className="hidden pb-2 text-sm text-muted-foreground sm:block">→</span>

        <label className="text-xs text-muted-foreground">
          Fin
          <input
            aria-label={`Fin du créneau ${index + 1} du ${date}`}
            type="time"
            value={creneau.heureFin}
            onChange={(event) => onChange({ ...creneau, heureFin: event.target.value })}
            className="input-base mt-1 w-full text-center"
          />
        </label>

        <label className="text-xs text-muted-foreground">
          Date de fin
          <select
            aria-label={`Date de fin du créneau ${index + 1} du ${date}`}
            value={creneau.finJourSuivant ? 'LENDEMAIN' : 'MEME_JOUR'}
            onChange={(event) => onChange({
              ...creneau,
              finJourSuivant: event.target.value === 'LENDEMAIN',
            })}
            className="input-base mt-1 w-full"
          >
            <option value="MEME_JOUR">Même jour · {libelleDateCourte(date)}</option>
            <option value="LENDEMAIN">Lendemain · {libelleDateCourte(dateFinCreneau(date, { finJourSuivant: true }))}</option>
          </select>
        </label>

        <button
          type="button"
          onClick={onRemove}
          className="mb-1 inline-flex min-h-10 items-center justify-center rounded-lg px-2 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
          aria-label={`Supprimer le créneau ${index + 1} du ${date}`}
        >
          <Trash2 className="h-4 w-4" />
        </button>
      </div>

      <p className={`mt-2 text-xs ${dureeColor}`}>
        {duree == null
          ? resultat.erreur
          : `${libelleDateCourte(date)} ${creneau.heureDebut} → ${libelleDateCourte(dateFin)} ${creneau.heureFin} · ${duree.toLocaleString('fr-FR', { maximumFractionDigits: 2 })} h`}
      </p>
    </div>
  );
}
