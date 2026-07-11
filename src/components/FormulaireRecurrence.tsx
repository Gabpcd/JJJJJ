import React, { useState, useMemo, useCallback } from 'react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { CheckCircle2, XCircle, AlertTriangle } from 'lucide-react';
import { ARTICLES_CODE_TRAVAIL } from '@/constantes/loi';
import { LigneHoraireJour, type HorairesJour, parseHeure } from '@/components/LigneHoraireJour';
import { calculerDuree } from '@/components/LigneHoraireJour';
import {
  derivePlanning, validerPlanning, parseDateLocale, fmtDateLocale, libelleDate,
  type SemaineCivile, type ValidationPlanning,
} from '@/lib/planning-derive';
import { toast } from 'sonner';

const NOMS_JOURS_ISO: Record<number, string> = {
  1: 'Lundi', 2: 'Mardi', 3: 'Mercredi', 4: 'Jeudi', 5: 'Vendredi', 6: 'Samedi', 7: 'Dimanche',
};

export interface CreneauFlex {
  debut: string;
  fin: string;
  jourLabel: string;
  dureeHeures: number;
}

export interface RecurrenceFlexConfig {
  dateDebut: string;
  dateFin: string;
  horairesParJour: HorairesJour[];
}

// Compat : FormulaireMission importe `ValidationFlexResult` — c'est désormais la
// validation dérivée par semaine civile réelle (mêmes champs valide/erreurs/totalHebdo).
export type ErreurValidation = ValidationPlanning['erreurs'][number];
export type ValidationFlexResult = ValidationPlanning;

// ─── Génération des créneaux (par date réelle) ────────────────────
export function genererCreneauxFlex(
  dateDebut: string, dateFin: string, horairesParJour: HorairesJour[],
): CreneauFlex[] {
  if (!dateDebut || !dateFin) return [];
  const joursActifs = horairesParJour.filter((j) => j.actif);
  if (joursActifs.length === 0) return [];

  const creneaux: CreneauFlex[] = [];
  const debut = parseDateLocale(dateDebut);
  const fin = parseDateLocale(dateFin);

  const d = new Date(debut);
  let guard = 0;
  while (d <= fin && guard < 400) {
    const rawDay = d.getDay();
    const jourISO = rawDay === 0 ? 7 : rawDay;
    const horaireJour = joursActifs.find((j) => j.jourISO === jourISO);

    if (horaireJour) {
      const dateStr = fmtDateLocale(d);
      let finCreneau: string;
      if (parseHeure(horaireJour.heureFin) <= parseHeure(horaireJour.heureDebut)) {
        const lendemain = new Date(d);
        lendemain.setDate(lendemain.getDate() + 1);
        finCreneau = `${fmtDateLocale(lendemain)}T${horaireJour.heureFin}:00`;
      } else {
        finCreneau = `${dateStr}T${horaireJour.heureFin}:00`;
      }
      creneaux.push({
        debut: `${dateStr}T${horaireJour.heureDebut}:00`,
        fin: finCreneau,
        jourLabel: horaireJour.label,
        dureeHeures: horaireJour.dureeHeures,
      });
    }
    d.setDate(d.getDate() + 1);
    guard++;
  }
  return creneaux;
}

/** Conservé pour compat : validation d'un jeu d'horaires hors période (motif). */
export function validerHorairesFlex(horairesParJour: HorairesJour[]): ValidationFlexResult {
  const total = horairesParJour.filter((j) => j.actif).reduce((s, j) => s + j.dureeHeures, 0);
  const erreurs: ValidationFlexResult['erreurs'] = [];
  if (total > 48) {
    erreurs.push({ type: 'PLAFOND_48H', gravite: 'bloquant', message: `La semaine totalise ${total}h. Maximum légal : 48h (Art. L3121-20).` });
  }
  return { valide: !erreurs.some((e) => e.gravite === 'bloquant'), erreurs, totalHebdo: total, semaines: [] };
}

// Jours ISO présents dans la plage (pour (dé)cocher automatiquement).
function joursISODansPlage(debut: string, fin: string): Set<number> {
  const set = new Set<number>();
  if (!debut || !fin) return set;
  const d = parseDateLocale(debut);
  const f = parseDateLocale(fin);
  if (f < d) return set;
  const cur = new Date(d);
  let guard = 0;
  while (cur <= f && guard < 400) {
    const raw = cur.getDay();
    set.add(raw === 0 ? 7 : raw);
    cur.setDate(cur.getDate() + 1);
    guard++;
  }
  return set;
}

function plageEffectiveJours(debut: string, fin: string, actifsISO: Set<number>): [string, string] | null {
  if (!debut || !fin || actifsISO.size === 0) return null;
  const d = parseDateLocale(debut);
  const f = parseDateLocale(fin);
  if (f < d) return null;
  let first: Date | null = null;
  let last: Date | null = null;
  const cur = new Date(d);
  let guard = 0;
  while (cur <= f && guard < 400) {
    const raw = cur.getDay();
    const iso = raw === 0 ? 7 : raw;
    if (actifsISO.has(iso)) {
      if (!first) first = new Date(cur);
      last = new Date(cur);
    }
    cur.setDate(cur.getDate() + 1);
    guard++;
  }
  if (!first || !last) return null;
  return [fmtDateLocale(first), fmtDateLocale(last)];
}

function formatDateFr(str: string): string {
  if (!str) return '';
  return format(parseDateLocale(str), 'EEEE d MMMM', { locale: fr });
}

// ─── Props ────────────────────────────────────────────────────────
interface FormulaireRecurrenceProps {
  onChange: (config: RecurrenceFlexConfig, creneaux: CreneauFlex[], validation: ValidationFlexResult) => void;
}

export function FormulaireRecurrence({ onChange }: FormulaireRecurrenceProps) {
  const [dateDebut, setDateDebut] = useState('');
  const [dateFin, setDateFin] = useState('');
  const [avertissementDates, setAvertissementDates] = useState<string | null>(null);
  // État des horaires PAR jour-de-semaine ISO. Les heures saisies sont conservées
  // par jour même quand la période change (seul `actif` est re-dérivé). `actif`
  // initial = false : rien n'est proposé tant que la période n'est pas choisie.
  const [horairesParJour, setHorairesParJour] = useState<HorairesJour[]>(
    [1, 2, 3, 4, 5, 6, 7].map((jourISO) => ({
      jourISO,
      label: NOMS_JOURS_ISO[jourISO],
      heureDebut: '07:00',
      heureFin: '19:00',
      dureeHeures: 12,
      actif: false,
    })),
  );

  // ── ÉTAT DÉRIVÉ : la période est la seule source de vérité. ──
  const plan = useMemo(() => derivePlanning(dateDebut, dateFin), [dateDebut, dateFin]);

  // Choisir/ajuster la période coche automatiquement les jours présents dans la
  // plage (sans effacer les heures déjà saisies) — jamais un défaut figé lun-ven.
  const appliquerJoursSelonPlage = useCallback((debut: string, fin: string) => {
    if (!debut || !fin) return;
    const presents = joursISODansPlage(debut, fin);
    if (presents.size === 0) return;
    setHorairesParJour((prev) => prev.map((j) => ({ ...j, actif: presents.has(j.jourISO) })));
  }, []);

  const handleDateDebut = useCallback((val: string) => {
    setDateDebut(val);
    setAvertissementDates(null);
    appliquerJoursSelonPlage(val, dateFin);
  }, [dateFin, appliquerJoursSelonPlage]);

  const handleDateFin = useCallback((val: string) => {
    setDateFin(val);
    setAvertissementDates(null);
    appliquerJoursSelonPlage(dateDebut, val);
  }, [dateDebut, appliquerJoursSelonPlage]);

  // Horaire (par jour ISO) enrichi du libellé DÉRIVÉ (daté si plage ≤ 14 j).
  const jourISOversLabel = useMemo(() => {
    const m = new Map<number, string>();
    for (const j of plan.jours) m.set(j.jourISO, j.label);
    return m;
  }, [plan]);

  // Liste des jours ACTIFS dans l'ORDRE CHRONOLOGIQUE réel (depuis le 1er jour).
  const joursActifsOrdonnes = useMemo(() => {
    return plan.jours
      .filter((pj) => horairesParJour.find((h) => h.jourISO === pj.jourISO)?.actif)
      .map((pj) => {
        const h = horairesParJour.find((x) => x.jourISO === pj.jourISO)!;
        return { ...h, label: pj.label };
      });
  }, [plan, horairesParJour]);

  const validation = useMemo(
    () => validerPlanning(dateDebut, dateFin, horairesParJour),
    [dateDebut, dateFin, horairesParJour],
  );

  const creneaux = useMemo(
    () => genererCreneauxFlex(dateDebut, dateFin, horairesParJour),
    [dateDebut, dateFin, horairesParJour],
  );

  const totalHeures = creneaux.reduce((s, c) => s + c.dureeHeures, 0);

  React.useEffect(() => {
    onChange({ dateDebut, dateFin, horairesParJour }, creneaux, validation);
  }, [dateDebut, dateFin, horairesParJour, creneaux, validation]);

  const zoneErreursRef = React.useRef<HTMLDivElement | null>(null);
  const aBloquant = validation.erreurs.some((e) => e.gravite === 'bloquant');
  React.useEffect(() => {
    if (aBloquant) zoneErreursRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }, [aBloquant]);

  const toggleJour = useCallback((iso: number) => {
    setHorairesParJour((prev) => prev.map((j) => (j.jourISO === iso ? { ...j, actif: !j.actif } : j)));
    const actifsApres = new Set(
      horairesParJour.filter((j) => (j.jourISO === iso ? !j.actif : j.actif)).map((j) => j.jourISO),
    );
    const eff = plageEffectiveJours(dateDebut, dateFin, actifsApres);
    if (eff && (eff[0] !== dateDebut || eff[1] !== dateFin)) {
      setDateDebut(eff[0]);
      setDateFin(eff[1]);
      setAvertissementDates(`Vos dates ont été ajustées : du ${formatDateFr(eff[0])} au ${formatDateFr(eff[1])}.`);
    } else {
      setAvertissementDates(null);
    }
  }, [horairesParJour, dateDebut, dateFin]);

  const updateHoraire = useCallback((jourISO: number, heureDebut: string, heureFin: string) => {
    setHorairesParJour((prev) => prev.map((j) => (
      j.jourISO === jourISO
        ? { ...j, heureDebut, heureFin, dureeHeures: calculerDuree(heureDebut, heureFin) }
        : j
    )));
  }, []);

  const premierJourActifISO = joursActifsOrdonnes[0]?.jourISO;

  const appliquerATous = useCallback(() => {
    const premier = joursActifsOrdonnes[0];
    if (!premier) return;
    setHorairesParJour((prev) => prev.map((j) => (
      j.actif
        ? { ...j, heureDebut: premier.heureDebut, heureFin: premier.heureFin, dureeHeures: premier.dureeHeures }
        : j
    )));
    toast.success('Horaires appliqués à tous les jours');
  }, [joursActifsOrdonnes]);

  const joursEnErreur = new Set(validation.erreurs.flatMap((e) => e.joursAffectes || []));

  const reposErreurs = useMemo(() => {
    const map = new Map<number, string>();
    for (const e of validation.erreurs) {
      if (e.type === 'REPOS_11H' && e.joursAffectes && e.joursAffectes.length === 2) {
        map.set(e.joursAffectes[0], e.message);
      }
    }
    return map;
  }, [validation.erreurs]);

  return (
    <div className="space-y-4">
      {/* Période */}
      <div className="bg-primary/5 border border-primary/20 rounded-2xl p-5 space-y-4">
        <p className="text-sm font-semibold text-foreground">📅 Période du remplacement</p>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div>
            <label className="text-xs text-muted-foreground mb-1 block">Du *</label>
            <input type="date" value={dateDebut} onChange={(e) => handleDateDebut(e.target.value)} className="input-base" required />
          </div>
          <div>
            <label className="text-xs text-muted-foreground mb-1 block">Au *</label>
            <input type="date" value={dateFin} onChange={(e) => handleDateFin(e.target.value)} className="input-base" required />
          </div>
        </div>

        {avertissementDates && (
          <div className="flex items-start gap-2 text-xs text-warning bg-warning/10 border border-warning/30 rounded-lg p-2">
            <AlertTriangle className="h-3.5 w-3.5 shrink-0 mt-0.5" />
            <span>{avertissementDates}</span>
          </div>
        )}

        {/* Jours travaillés — DÉRIVÉS de la période : seuls les jours présents
            dans la plage sont proposés, ordonnés depuis le 1er jour de mission,
            libellés datés si la plage tient sur ≤ 14 jours. */}
        <div>
          <label className="text-xs text-muted-foreground mb-2 block">Jours travaillés</label>
          {plan.jours.length === 0 ? (
            <p className="text-xs text-muted-foreground italic">Choisissez d'abord une période Du / Au ci-dessus.</p>
          ) : (
            <div className="flex flex-wrap gap-2" data-testid="jours-travailles">
              {plan.jours.map((pj) => {
                const actif = horairesParJour.find((h) => h.jourISO === pj.jourISO)?.actif;
                return (
                  <button
                    key={pj.jourISO}
                    type="button"
                    onClick={() => toggleJour(pj.jourISO)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${
                      actif ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'
                    }`}
                  >
                    {actif ? '☑️' : '☐'} {pj.label}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* Horaires par jour — liste UNIQUEMENT les jours cochés, dans l'ordre
          chronologique réel (une mission qui commence un mercredi commence par
          mercredi), libellés datés réels si plage ≤ 14 jours. */}
      {joursActifsOrdonnes.length > 0 && (
        <div className="bg-primary/5 border border-primary/20 rounded-2xl p-4 space-y-1">
          <p className="text-sm font-semibold text-foreground mb-3">🕐 Horaires par jour</p>
          <div data-testid="horaires-par-jour">
            {joursActifsOrdonnes.map((jour) => {
              const reposErr = reposErreurs.get(jour.jourISO);
              return (
                <React.Fragment key={jour.jourISO}>
                  <LigneHoraireJour
                    jour={jour}
                    onChange={(hd, hf) => updateHoraire(jour.jourISO, hd, hf)}
                    estPremierJour={jour.jourISO === premierJourActifISO}
                    onAppliquerATous={jour.jourISO === premierJourActifISO ? appliquerATous : undefined}
                    enErreur={joursEnErreur.has(jour.jourISO)}
                  />
                  {reposErr && (
                    <div className="flex items-center gap-2 text-xs text-destructive font-medium pl-4 py-1">
                      <XCircle aria-hidden="true" className="h-4 w-4 shrink-0" />
                      <span>{reposErr}</span>
                    </div>
                  )}
                </React.Fragment>
              );
            })}
          </div>

          {/* Récap PAR SEMAINE CIVILE réelle (48h contrôlé semaine par semaine). */}
          <div className="border-t border-border mt-3 pt-3 space-y-1" data-testid="recap-semaines">
            {validation.semaines.map((s: SemaineCivile) => (
              <div key={s.cleLundi} className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">{s.label} :</span>
                <span className={`font-bold inline-flex items-center gap-1 ${s.depasse48 ? 'text-destructive' : 'text-primary'}`}>
                  {s.totalHeures}h{s.depasse48 && ' — dépasse 48h'}
                  {s.depasse48 ? <XCircle aria-hidden="true" className="h-3.5 w-3.5" /> : <CheckCircle2 aria-hidden="true" className="h-3.5 w-3.5" />}
                </span>
              </div>
            ))}
          </div>
          <p className="text-[10px] text-muted-foreground mt-1">
            Plafond légal : 48h par semaine civile (lundi-dimanche). Chaque semaine est contrôlée séparément.
          </p>
        </div>
      )}

      {/* Zone d'erreurs UNIQUE, amenée à l'écran au 1er bloquant */}
      {validation.erreurs.length > 0 && (
        <div ref={zoneErreursRef} className="space-y-2" role="alert">
          {validation.erreurs.map((e, i) => (
            <div key={i} className={`flex items-start gap-2 text-xs font-medium ${e.gravite === 'bloquant' ? 'text-destructive' : 'text-warning'}`}>
              {e.gravite === 'bloquant' ? <XCircle aria-hidden="true" className="h-4 w-4 shrink-0 mt-0.5" /> : <AlertTriangle aria-hidden="true" className="h-4 w-4 shrink-0 mt-0.5" />}
              <div>
                <p>{e.message}</p>
                {e.type === 'PLAFOND_48H' && (
                  <p className="text-[10px] mt-0.5">Art. L3121-20 — {ARTICLES_CODE_TRAVAIL['L3121-20']?.explicationSimple}</p>
                )}
                {e.type === 'REPOS_11H' && (
                  <p className="text-[10px] mt-0.5">Art. L3131-1 — {ARTICLES_CODE_TRAVAIL['L3131-1']?.explicationSimple}</p>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {validation.erreurs.length === 0 && joursActifsOrdonnes.length > 0 && (
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-xs font-medium text-primary">
            <CheckCircle2 className="h-4 w-4" />
            Repos inter-créneaux : conforme (≥ 11h)
          </div>
          <div className="flex items-center gap-2 text-xs font-medium text-primary">
            <CheckCircle2 className="h-4 w-4" />
            Chaque semaine civile ≤ 48h — conforme
          </div>
        </div>
      )}

      {/* Prévisualisation groupée (créneaux réels, ordre chronologique) */}
      {creneaux.length > 0 && (
        <div className="card-base">
          <p className="text-sm font-bold text-foreground mb-3">
            Prévisualisation : {creneaux.length} créneau{creneaux.length > 1 ? 'x' : ''} sur {validation.semaines.length} semaine{validation.semaines.length > 1 ? 's' : ''}
          </p>
          <div className="max-h-64 overflow-y-auto space-y-0.5">
            {creneaux.map((c, i) => (
              <div key={i} className="flex items-center gap-2 text-xs text-foreground">
                <CheckCircle2 aria-hidden="true" className="h-3.5 w-3.5 text-primary shrink-0" />
                <span className="font-medium w-28">{libelleDate(c.debut.slice(0, 10))}</span>
                <span className="text-muted-foreground">
                  {c.debut.slice(11, 16)} → {c.fin.slice(11, 16)} ({c.dureeHeures}h)
                </span>
              </div>
            ))}
          </div>
          <div className="border-t border-border mt-3 pt-3 text-xs text-muted-foreground">
            <p>Total : <strong className="text-foreground">{totalHeures.toFixed(0)}h</strong> sur {validation.semaines.length} semaine{validation.semaines.length > 1 ? 's' : ''} ({creneaux.length} créneaux)</p>
          </div>
        </div>
      )}
    </div>
  );
}
