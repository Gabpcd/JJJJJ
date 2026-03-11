import React, { useState, useMemo } from 'react';
import { format, addDays, getISOWeek, startOfWeek } from 'date-fns';
import { fr } from 'date-fns/locale';
import { CheckCircle2, XCircle, AlertTriangle } from 'lucide-react';
import { ARTICLES_CODE_TRAVAIL } from '@/constantes/loi';

const JOURS_SEMAINE = [
  { iso: 1, label: 'Lun' },
  { iso: 2, label: 'Mar' },
  { iso: 3, label: 'Mer' },
  { iso: 4, label: 'Jeu' },
  { iso: 5, label: 'Ven' },
  { iso: 6, label: 'Sam' },
  { iso: 7, label: 'Dim' },
];

export interface Creneau {
  debut: string;
  fin: string;
  jourISO: number;
}

export interface RecurrenceConfig {
  dateDebut: string;
  dateFin: string;
  joursCochés: number[];
  heureDebut: string;
  heureFin: string;
}

export interface RecurrenceValidation {
  reposOk: boolean;
  reposHeures: number;
  plafond48hOk: boolean;
  maxHebdo: number;
  semaineProbleme?: string;
  dureeCreneauOk: boolean;
  dureeCreneau: number;
}

interface FormulaireRecurrenceProps {
  onChange: (config: RecurrenceConfig, creneaux: Creneau[], validation: RecurrenceValidation) => void;
}

export function genererCreneaux(
  dateDebut: string, dateFin: string,
  joursCochés: number[], heureDebut: string, heureFin: string
): Creneau[] {
  if (!dateDebut || !dateFin || !heureDebut || !heureFin || joursCochés.length === 0) return [];
  const creneaux: Creneau[] = [];
  const debut = new Date(dateDebut);
  const fin = new Date(dateFin);

  for (let d = new Date(debut); d <= fin; d.setDate(d.getDate() + 1)) {
    const jourISO = d.getDay() === 0 ? 7 : d.getDay();
    if (joursCochés.includes(jourISO)) {
      const dateStr = d.toISOString().split('T')[0];
      creneaux.push({
        debut: `${dateStr}T${heureDebut}:00`,
        fin: `${dateStr}T${heureFin}:00`,
        jourISO,
      });
    }
  }
  return creneaux;
}

function validerCreneaux(creneaux: Creneau[], heureDebut: string, heureFin: string): RecurrenceValidation {
  const dureeCreneau = (() => {
    const d = new Date(`2000-01-01T${heureDebut}`);
    const f = new Date(`2000-01-01T${heureFin}`);
    let diff = (f.getTime() - d.getTime()) / 3600000;
    if (diff <= 0) diff += 24;
    return diff;
  })();

  const reposHeures = 24 - dureeCreneau;

  // Heures par semaine ISO
  const heuresParSemaine = new Map<string, { heures: number; dateLabel: string }>();
  creneaux.forEach(c => {
    const d = new Date(c.debut);
    const w = startOfWeek(d, { weekStartsOn: 1 });
    const key = w.toISOString().split('T')[0];
    const existing = heuresParSemaine.get(key);
    heuresParSemaine.set(key, {
      heures: (existing?.heures || 0) + dureeCreneau,
      dateLabel: format(w, 'd MMM', { locale: fr }),
    });
  });
  const maxHebdoEntry = [...heuresParSemaine.entries()].reduce(
    (max, [k, v]) => (v.heures > max.heures ? { ...v, key: k } : max),
    { heures: 0, dateLabel: '', key: '' }
  );

  return {
    reposOk: reposHeures >= 11,
    reposHeures: Math.round(reposHeures * 10) / 10,
    plafond48hOk: maxHebdoEntry.heures <= 48,
    maxHebdo: Math.round(maxHebdoEntry.heures * 10) / 10,
    semaineProbleme: maxHebdoEntry.heures > 48 ? `Semaine du ${maxHebdoEntry.dateLabel}` : undefined,
    dureeCreneauOk: dureeCreneau <= 12,
    dureeCreneau: Math.round(dureeCreneau * 10) / 10,
  };
}

export function FormulaireRecurrence({ onChange }: FormulaireRecurrenceProps) {
  const [dateDebut, setDateDebut] = useState('');
  const [dateFin, setDateFin] = useState('');
  const [joursCochés, setJoursCochés] = useState<number[]>([1, 2, 3, 4, 5]);
  const [heureDebut, setHeureDebut] = useState('07:00');
  const [heureFin, setHeureFin] = useState('19:00');

  const creneaux = useMemo(() =>
    genererCreneaux(dateDebut, dateFin, joursCochés, heureDebut, heureFin),
    [dateDebut, dateFin, joursCochés, heureDebut, heureFin]
  );

  const validation = useMemo(() =>
    validerCreneaux(creneaux, heureDebut, heureFin),
    [creneaux, heureDebut, heureFin]
  );

  const totalHeures = creneaux.length * validation.dureeCreneau;
  const nbSemaines = new Set(creneaux.map(c => {
    const d = new Date(c.debut);
    return startOfWeek(d, { weekStartsOn: 1 }).toISOString().split('T')[0];
  })).size;

  // Notify parent
  React.useEffect(() => {
    onChange({ dateDebut, dateFin, joursCochés, heureDebut, heureFin }, creneaux, validation);
  }, [dateDebut, dateFin, joursCochés, heureDebut, heureFin]);

  const toggleJour = (iso: number) => {
    setJoursCochés(prev =>
      prev.includes(iso) ? prev.filter(j => j !== iso) : [...prev, iso].sort()
    );
  };

  return (
    <div className="space-y-4">
      {/* Période */}
      <div className="bg-primary/5 border border-primary/20 rounded-2xl p-5 space-y-4">
        <p className="text-sm font-semibold text-foreground">📅 Période du remplacement</p>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div>
            <label className="text-xs text-muted-foreground mb-1 block">Du *</label>
            <input type="date" value={dateDebut} onChange={e => setDateDebut(e.target.value)} className="input-base" required />
          </div>
          <div>
            <label className="text-xs text-muted-foreground mb-1 block">Au *</label>
            <input type="date" value={dateFin} onChange={e => setDateFin(e.target.value)} className="input-base" required />
          </div>
        </div>

        <div>
          <label className="text-xs text-muted-foreground mb-2 block">Jours travaillés</label>
          <div className="flex flex-wrap gap-2">
            {JOURS_SEMAINE.map(j => (
              <button
                key={j.iso}
                type="button"
                onClick={() => toggleJour(j.iso)}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${
                  joursCochés.includes(j.iso)
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-muted text-muted-foreground hover:bg-muted/80'
                }`}
              >
                {joursCochés.includes(j.iso) ? '☑️' : '☐'} {j.label}
              </button>
            ))}
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs text-muted-foreground mb-1 block">Début créneau *</label>
            <input type="time" value={heureDebut} onChange={e => setHeureDebut(e.target.value)} className="input-base" required />
          </div>
          <div>
            <label className="text-xs text-muted-foreground mb-1 block">Fin créneau *</label>
            <input type="time" value={heureFin} onChange={e => setHeureFin(e.target.value)} className="input-base" required />
          </div>
        </div>
      </div>

      {/* Prévisualisation */}
      {creneaux.length > 0 && (
        <div className="card-base">
          <p className="text-sm font-bold text-foreground mb-3">
            📋 Prévisualisation : {creneaux.length} créneau{creneaux.length > 1 ? 'x' : ''} sera{creneaux.length > 1 ? 'ont' : ''} créé{creneaux.length > 1 ? 's' : ''}
          </p>

          <div className="max-h-48 overflow-y-auto space-y-1">
            {creneaux.map((c, i) => (
              <div key={i} className="flex items-center gap-2 text-xs text-foreground">
                <span className="text-success">✅</span>
                <span className="font-medium w-28">
                  {format(new Date(c.debut), 'EEE d MMM', { locale: fr })}
                </span>
                <span className="text-muted-foreground">
                  {heureDebut} → {heureFin} ({validation.dureeCreneau}h)
                </span>
                {i < creneaux.length - 1 && (
                  <span className={`text-[10px] ml-auto ${validation.reposOk ? 'text-success' : 'text-destructive font-bold'}`}>
                    ↕️ {validation.reposHeures}h repos {validation.reposOk ? '✅' : '❌'}
                  </span>
                )}
              </div>
            ))}
          </div>

          <div className="border-t border-border mt-3 pt-3 space-y-1 text-xs text-muted-foreground">
            <p>Total : <strong className="text-foreground">{totalHeures.toFixed(0)}h</strong> sur {nbSemaines} semaine{nbSemaines > 1 ? 's' : ''}</p>
          </div>
        </div>
      )}

      {/* Validations */}
      {creneaux.length > 0 && (
        <div className="space-y-2">
          {/* Repos 11h */}
          <div className={`flex items-center gap-2 text-xs font-medium ${validation.reposOk ? 'text-success' : 'text-destructive'}`}>
            {validation.reposOk ? <CheckCircle2 className="h-4 w-4" /> : <XCircle className="h-4 w-4" />}
            Repos inter-créneaux : {validation.reposHeures}h — {validation.reposOk ? 'conforme' : 'NON CONFORME (min. 11h)'}
          </div>
          {!validation.reposOk && (
            <p className="text-[10px] text-destructive ml-6">
              📖 Art. L3131-1 — {ARTICLES_CODE_TRAVAIL['L3131-1']?.explicationSimple}
            </p>
          )}

          {/* Plafond 48h */}
          <div className={`flex items-center gap-2 text-xs font-medium ${validation.plafond48hOk ? 'text-success' : 'text-destructive'}`}>
            {validation.plafond48hOk ? <CheckCircle2 className="h-4 w-4" /> : <XCircle className="h-4 w-4" />}
            Heures max/semaine : {validation.maxHebdo}h — {validation.plafond48hOk ? 'conforme (max 48h)' : `DÉPASSEMENT (max 48h)`}
          </div>
          {!validation.plafond48hOk && validation.semaineProbleme && (
            <p className="text-[10px] text-destructive ml-6">
              📖 Art. L3121-20 — {validation.semaineProbleme} totaliserait {validation.maxHebdo}h.
            </p>
          )}

          {/* Durée créneau */}
          {!validation.dureeCreneauOk && (
            <div className="flex items-center gap-2 text-xs font-medium text-warning">
              <AlertTriangle className="h-4 w-4" />
              Créneau de {validation.dureeCreneau}h — recommandation : max 12h pour la sécurité des patients
            </div>
          )}
        </div>
      )}
    </div>
  );
}
