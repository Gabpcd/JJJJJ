import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AlertTriangle, CheckCircle2, Copy, Plus, XCircle } from 'lucide-react';
import { ARTICLES_CODE_TRAVAIL } from '@/constantes/loi';
import { LigneHoraireJour } from '@/components/LigneHoraireJour';
import { cleJourParis, cleSemaineParis, formatParis, instantJolene } from '@/lib/date-heure-paris';
import {
  datesDansPlage,
  jourSemaineISO,
  libelleDate,
  materialiserPlanning,
  validerPlanningDates,
  type CreneauPlanningDate,
  type JourPlanningDate,
  type ValidationPlanning,
} from '@/lib/planning-derive';

export interface CreneauFlex {
  id?: string;
  clientId: string;
  debut: string;
  fin: string;
  jourLabel: string;
  dureeHeures: number;
}

export interface PlanningInitialCreneau {
  id?: string;
  debut: string;
  fin: string;
}

export interface RecurrenceFlexConfig {
  dateDebut: string;
  dateFin: string;
  jours: JourPlanningDate[];
}

export type ErreurValidation = ValidationPlanning['erreurs'][number];
export type ValidationFlexResult = ValidationPlanning;

interface FormulaireRecurrenceProps {
  onChange: (
    config: RecurrenceFlexConfig,
    creneaux: CreneauFlex[],
    validation: ValidationFlexResult,
  ) => void;
  initialCreneaux?: PlanningInitialCreneau[];
  initialDateDebut?: string;
  initialDateFin?: string;
}

let compteurCreneaux = 0;

function nouvelIdClient(): string {
  compteurCreneaux += 1;
  return `planning-${compteurCreneaux}`;
}

function creneauDefaut(): CreneauPlanningDate {
  return {
    clientId: nouvelIdClient(),
    heureDebut: '07:00',
    heureFin: '19:00',
    finJourSuivant: false,
  };
}

function heureParis(value: string): string {
  return formatParis(value, 'HH:mm');
}

function instantValide(value: string): number {
  try {
    return instantJolene(value).getTime();
  } catch {
    return Number.NaN;
  }
}

function initialiserDepuisCreneaux(initialCreneaux: PlanningInitialCreneau[]): {
  dateDebut: string;
  dateFin: string;
  jours: JourPlanningDate[];
} | null {
  const valides = initialCreneaux
    .filter((creneau) => Number.isFinite(instantValide(creneau.debut)) && Number.isFinite(instantValide(creneau.fin)))
    .sort((a, b) => instantValide(a.debut) - instantValide(b.debut));
  if (valides.length === 0) return null;

  const parDate = new Map<string, CreneauPlanningDate[]>();
  for (const creneau of valides) {
    const date = cleJourParis(creneau.debut);
    const dateFin = cleJourParis(creneau.fin);
    const liste = parDate.get(date) ?? [];
    liste.push({
      id: creneau.id,
      clientId: creneau.id ? `persisted-${creneau.id}` : nouvelIdClient(),
      heureDebut: heureParis(creneau.debut),
      heureFin: heureParis(creneau.fin),
      finJourSuivant: dateFin !== date,
      debutInitial: creneau.debut,
      finInitial: creneau.fin,
    });
    parDate.set(date, liste);
  }

  const dates = [...parDate.keys()].sort();
  const dateDebut = dates[0];
  const dateFin = dates[dates.length - 1];
  return {
    dateDebut,
    dateFin,
    jours: datesDansPlage(dateDebut, dateFin).map((date) => ({
      date,
      actif: parDate.has(date),
      creneaux: parDate.get(date) ?? [],
    })),
  };
}

function formatDuree(heures: number): string {
  const totalMinutes = Math.round(heures * 60);
  return `${Math.floor(totalMinutes / 60)} h ${String(totalMinutes % 60).padStart(2, '0')}`;
}

export function FormulaireRecurrence({
  onChange,
  initialCreneaux = [],
  initialDateDebut = '',
  initialDateFin = '',
}: FormulaireRecurrenceProps) {
  const [initial] = useState(() => initialiserDepuisCreneaux(initialCreneaux));
  const [dateDebut, setDateDebut] = useState(initial?.dateDebut ?? initialDateDebut);
  const [dateFin, setDateFin] = useState(initial?.dateFin ?? initialDateFin);
  const [jours, setJours] = useState<JourPlanningDate[]>(initial?.jours ?? []);
  const [datesModifiees, setDatesModifiees] = useState(
    Boolean(initial || initialDateDebut || initialDateFin),
  );
  const onChangeRef = useRef(onChange);

  useEffect(() => {
    onChangeRef.current = onChange;
  }, [onChange]);

  useEffect(() => {
    const dates = datesDansPlage(dateDebut, dateFin);
    if (dates.length === 0 || dates.length > 366) {
      setJours([]);
      return;
    }
    setJours((precedents) => {
      const parDate = new Map(precedents.map((jour) => [jour.date, jour]));
      return dates.map((date) => parDate.get(date) ?? {
        date,
        actif: false,
        creneaux: [creneauDefaut()],
      });
    });
  }, [dateDebut, dateFin]);

  const validation = useMemo<ValidationFlexResult>(() => {
    if (!dateDebut || !dateFin || dateFin < dateDebut) {
      return {
        valide: false,
        erreurs: [{
          type: 'PLAGE_INVALIDE',
          gravite: 'bloquant',
          message: 'Choisissez une période valide.',
        }],
        totalHebdo: 0,
        semaines: [],
      };
    }
    if (datesDansPlage(dateDebut, dateFin).length > 366) {
      return {
        valide: false,
        erreurs: [{
          type: 'PLAGE_INVALIDE',
          gravite: 'bloquant',
          message: 'Une mission ne peut pas couvrir plus de 366 dates.',
        }],
        totalHebdo: 0,
        semaines: [],
      };
    }
    if (!jours.some((jour) => jour.actif)) {
      return {
        valide: false,
        erreurs: [{
          type: 'CRENEAU_MANQUANT',
          gravite: 'bloquant',
          message: 'Sélectionnez au moins une date travaillée.',
        }],
        totalHebdo: 0,
        semaines: [],
      };
    }
    return validerPlanningDates(jours);
  }, [dateDebut, dateFin, jours]);

  const creneaux = useMemo<CreneauFlex[]>(() => materialiserPlanning(jours).map((creneau) => ({
    id: creneau.id,
    clientId: creneau.clientId,
    debut: creneau.debut,
    fin: creneau.fin,
    jourLabel: libelleDate(creneau.date),
    dureeHeures: creneau.dureeHeures,
  })), [jours]);

  useEffect(() => {
    onChangeRef.current({ dateDebut, dateFin, jours }, creneaux, validation);
  }, [dateDebut, dateFin, jours, creneaux, validation]);

  const modifierJour = useCallback((date: string, transform: (jour: JourPlanningDate) => JourPlanningDate) => {
    setJours((precedents) => precedents.map((jour) => (jour.date === date ? transform(jour) : jour)));
  }, []);

  const toggleDate = useCallback((date: string) => {
    modifierJour(date, (jour) => ({
      ...jour,
      actif: !jour.actif,
      creneaux: !jour.actif && jour.creneaux.length === 0 ? [creneauDefaut()] : jour.creneaux,
    }));
  }, [modifierJour]);

  const ajouterCreneau = useCallback((date: string) => {
    modifierJour(date, (jour) => ({ ...jour, actif: true, creneaux: [...jour.creneaux, creneauDefaut()] }));
  }, [modifierJour]);

  const appliquerSelection = useCallback((predicate: (jour: JourPlanningDate, index: number) => boolean) => {
    setJours((precedents) => precedents.map((jour, index) => {
      const actif = predicate(jour, index);
      return {
        ...jour,
        actif,
        creneaux: actif && jour.creneaux.length === 0 ? [creneauDefaut()] : jour.creneaux,
      };
    }));
  }, []);

  const appliquerPremierCreneauATous = useCallback(() => {
    const modele = jours.find((jour) => jour.actif)?.creneaux[0];
    if (!modele) return;
    setJours((precedents) => precedents.map((jour) => (
      jour.actif
        ? {
          ...jour,
          creneaux: [{
            ...modele,
            id: undefined,
            clientId: nouvelIdClient(),
          }],
        }
        : jour
    )));
  }, [jours]);

  const appliquerUneSemaineSurDeux = useCallback(() => {
    const semaines = [...new Set(jours.map((jour) => cleSemaineParis(`${jour.date}T12:00`)))];
    appliquerSelection((jour) => semaines.indexOf(cleSemaineParis(`${jour.date}T12:00`)) % 2 === 0);
  }, [appliquerSelection, jours]);

  const creneauxEnErreur = useMemo(() => new Set(
    validation.erreurs.flatMap((erreur) => erreur.creneauxAffectes ?? []),
  ), [validation.erreurs]);
  const totalHeures = creneaux.reduce((somme, creneau) => somme + creneau.dureeHeures, 0);

  return (
    <div className="space-y-4">
      <div className="rounded-2xl border border-primary/20 bg-primary/5 p-5 space-y-4">
        <div>
          <p className="text-sm font-semibold text-foreground">📅 Dates et horaires réels</p>
          <p className="mt-1 text-xs text-muted-foreground">
            Chaque date est indépendante. Vous pouvez prévoir des jours non travaillés, plusieurs créneaux et des gardes de nuit.
          </p>
        </div>

        <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
          <label className="text-xs text-muted-foreground">
            Première date affichée *
            <input
              type="date"
              value={dateDebut}
              onChange={(event) => { setDatesModifiees(true); setDateDebut(event.target.value); }}
              className="input-base mt-1"
              required
            />
          </label>
          <label className="text-xs text-muted-foreground">
            Dernière date affichée *
            <input
              type="date"
              value={dateFin}
              min={dateDebut || undefined}
              onChange={(event) => { setDatesModifiees(true); setDateFin(event.target.value); }}
              className="input-base mt-1"
              required
            />
          </label>
        </div>

        {jours.length > 0 && (
          <div className="space-y-2" data-testid="jours-travailles">
            <p className="text-xs font-medium text-foreground">Sélection rapide</p>
            <div className="flex flex-wrap gap-2">
              <button type="button" onClick={() => appliquerSelection(() => true)} className="btn-secondary px-3 py-1.5 text-xs">Toutes les dates</button>
              <button type="button" onClick={() => appliquerSelection((jour) => jourSemaineISO(jour.date) <= 5)} className="btn-secondary px-3 py-1.5 text-xs">Lundi–vendredi</button>
              <button type="button" onClick={appliquerUneSemaineSurDeux} className="btn-secondary px-3 py-1.5 text-xs">1 semaine civile sur 2</button>
              <button type="button" onClick={() => appliquerSelection(() => false)} className="btn-secondary px-3 py-1.5 text-xs">Aucune</button>
              <button type="button" onClick={appliquerPremierCreneauATous} className="btn-secondary px-3 py-1.5 text-xs">
                <Copy className="mr-1 inline h-3.5 w-3.5" />Appliquer le 1er horaire aux jours sélectionnés
              </button>
            </div>
          </div>
        )}
      </div>

      {jours.length > 0 && (
        <div className="max-h-[46rem] space-y-3 overflow-y-auto pr-1" data-testid="horaires-par-jour">
          {jours.map((jour) => (
            <section
              key={jour.date}
              className={`rounded-2xl border p-4 ${jour.actif ? 'border-primary/25 bg-primary/5' : 'border-border bg-muted/20'}`}
              data-testid={`jour-planning-${jour.date}`}
            >
              <div className="flex items-center justify-between gap-3">
                <label className="flex cursor-pointer items-center gap-3">
                  <input
                    type="checkbox"
                    checked={jour.actif}
                    onChange={() => toggleDate(jour.date)}
                    aria-label={`${libelleDate(jour.date)} travaillé`}
                    className="h-4 w-4 accent-primary"
                  />
                  <span className="text-sm font-semibold capitalize text-foreground">{libelleDate(jour.date)}</span>
                </label>
                <span className={`rounded-full px-2 py-1 text-[11px] font-semibold ${jour.actif ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'}`}>
                  {jour.actif ? 'Travaillé' : 'Repos'}
                </span>
              </div>

              {jour.actif && (
                <div className="mt-3 space-y-2">
                  {jour.creneaux.map((creneau, index) => (
                    <LigneHoraireJour
                      key={creneau.clientId}
                      date={jour.date}
                      creneau={creneau}
                      index={index}
                      enErreur={creneauxEnErreur.has(creneau.clientId)}
                      onChange={(suivant) => modifierJour(jour.date, (courant) => ({
                        ...courant,
                        creneaux: courant.creneaux.map((item) => item.clientId === creneau.clientId ? suivant : item),
                      }))}
                      onRemove={() => modifierJour(jour.date, (courant) => ({
                        ...courant,
                        creneaux: courant.creneaux.filter((item) => item.clientId !== creneau.clientId),
                      }))}
                    />
                  ))}
                  <button
                    type="button"
                    onClick={() => ajouterCreneau(jour.date)}
                    className="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
                  >
                    <Plus className="h-3.5 w-3.5" />Ajouter un créneau ce jour
                  </button>
                </div>
              )}
            </section>
          ))}
        </div>
      )}

      {validation.semaines.length > 0 && (
        <div className="rounded-2xl border border-primary/20 bg-primary/5 p-4" data-testid="recap-semaines">
          <p className="mb-2 text-sm font-semibold text-foreground">Contrôle par semaine civile</p>
          <div className="space-y-1">
            {validation.semaines.map((semaine) => (
              <div key={semaine.cleLundi} className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">{semaine.label}</span>
                <span className={`inline-flex items-center gap-1 font-bold ${semaine.depasse48 ? 'text-destructive' : 'text-primary'}`}>
                  {semaine.totalHeures.toLocaleString('fr-FR')} h
                  {semaine.depasse48 ? <XCircle className="h-3.5 w-3.5" /> : <CheckCircle2 className="h-3.5 w-3.5" />}
                </span>
              </div>
            ))}
          </div>
          <p className="mt-2 text-[10px] text-muted-foreground">Maximum légal : 48 h par semaine civile (lundi–dimanche).</p>
        </div>
      )}

      {validation.erreurs.length > 0 && (datesModifiees || validation.erreurs.some((erreur) => erreur.type !== 'PLAGE_INVALIDE')) && (
        <div className="space-y-2" role="alert">
          {validation.erreurs
            .filter((erreur) => datesModifiees || erreur.type !== 'PLAGE_INVALIDE')
            .map((erreur, index) => (
            <div key={`${erreur.type}-${index}`} className={`flex items-start gap-2 text-xs font-medium ${erreur.gravite === 'bloquant' ? 'text-destructive' : 'text-warning'}`}>
              {erreur.gravite === 'bloquant'
                ? <XCircle className="mt-0.5 h-4 w-4 shrink-0" />
                : <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />}
              <div>
                <p>{erreur.message}</p>
                {erreur.type === 'PLAFOND_48H' && <p className="mt-0.5 text-[10px]">Art. L3121-20 — {ARTICLES_CODE_TRAVAIL['L3121-20']?.explicationSimple}</p>}
                {erreur.type === 'REPOS_11H' && <p className="mt-0.5 text-[10px]">Art. L3131-1 — {ARTICLES_CODE_TRAVAIL['L3131-1']?.explicationSimple}</p>}
              </div>
            </div>
          ))}
        </div>
      )}

      {validation.valide && creneaux.length > 0 && (
        <div className="card-base">
          <p className="mb-3 text-sm font-bold text-foreground">
            Aperçu exact · {creneaux.length} créneau{creneaux.length > 1 ? 'x' : ''}
          </p>
          <div className="max-h-64 space-y-1 overflow-y-auto">
            {creneaux.map((creneau) => (
              <div key={creneau.clientId} className="flex items-start gap-2 text-xs text-foreground">
                <CheckCircle2 className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
                <span>
                  <strong className="capitalize">{formatParis(creneau.debut, 'EEEE d MMMM yyyy')}</strong>
                  {' · '}{formatParis(creneau.debut, 'HH:mm')} →{' '}
                  <strong className="capitalize">{formatParis(creneau.fin, 'EEEE d MMMM yyyy')}</strong>
                  {' · '}{formatParis(creneau.fin, 'HH:mm')} ({formatDuree(creneau.dureeHeures)})
                </span>
              </div>
            ))}
          </div>
          <p className="mt-3 border-t border-border pt-3 text-xs text-muted-foreground">
            Total : <strong className="text-foreground">{formatDuree(totalHeures)}</strong> sur {validation.semaines.length} semaine{validation.semaines.length > 1 ? 's' : ''} civile{validation.semaines.length > 1 ? 's' : ''}.
          </p>
        </div>
      )}
    </div>
  );
}
