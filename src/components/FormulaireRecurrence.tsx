import React, { useState, useMemo, useCallback } from 'react';
import { format, startOfWeek, getISOWeek } from 'date-fns';
import { fr } from 'date-fns/locale';
import { CheckCircle2, XCircle, AlertTriangle } from 'lucide-react';
import { ARTICLES_CODE_TRAVAIL } from '@/constantes/loi';
import { LigneHoraireJour, type HorairesJour, parseHeure, calculerDuree } from '@/components/LigneHoraireJour';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';

const JOURS_SEMAINE_DEF = [
  { jourISO: 1, label: 'Lundi' },
  { jourISO: 2, label: 'Mardi' },
  { jourISO: 3, label: 'Mercredi' },
  { jourISO: 4, label: 'Jeudi' },
  { jourISO: 5, label: 'Vendredi' },
  { jourISO: 6, label: 'Samedi' },
  { jourISO: 7, label: 'Dimanche' },
];

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

export interface ErreurValidation {
  type: 'PLAFOND_48H' | 'REPOS_11H' | 'DUREE_LONGUE';
  message: string;
  gravite: 'bloquant' | 'avertissement';
  joursAffectes?: number[];
}

export interface ValidationFlexResult {
  valide: boolean;
  erreurs: ErreurValidation[];
  totalHebdo: number;
}

// ─── Génération des créneaux ──────────────────────────────────────
// Parse "YYYY-MM-DD" as LOCAL date (not UTC)
function parseDateLocale(str: string): Date {
  const [y, m, d] = str.split('-').map(Number);
  return new Date(y, m - 1, d);
}

function fmtDateLocale(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

// Jours ISO (1=lundi … 7=dimanche) présents dans la plage [debut, fin].
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

// Plage réellement travaillée : 1ère et dernière date dont le jour est actif,
// dans [debut, fin]. Sert à recaler les dates quand on (dé)coche un jour.
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

export function genererCreneauxFlex(
  dateDebut: string, dateFin: string, horairesParJour: HorairesJour[]
): CreneauFlex[] {
  if (!dateDebut || !dateFin) return [];
  const joursActifs = horairesParJour.filter(j => j.actif);
  if (joursActifs.length === 0) return [];

  const creneaux: CreneauFlex[] = [];
  const debut = parseDateLocale(dateDebut);
  const fin = parseDateLocale(dateFin);


  const d = new Date(debut);
  while (d <= fin) {
    const rawDay = d.getDay(); // 0=Sun..6=Sat
    const jourISO = rawDay === 0 ? 7 : rawDay; // 1=Mon..7=Sun
    const horaireJour = joursActifs.find(j => j.jourISO === jourISO);

    if (horaireJour) {
      const y = d.getFullYear();
      const m = String(d.getMonth() + 1).padStart(2, '0');
      const day = String(d.getDate()).padStart(2, '0');
      const dateStr = `${y}-${m}-${day}`;

      let finCreneau: string;
      if (parseHeure(horaireJour.heureFin) <= parseHeure(horaireJour.heureDebut)) {
        const lendemain = new Date(d);
        lendemain.setDate(lendemain.getDate() + 1);
        const ly = lendemain.getFullYear();
        const lm = String(lendemain.getMonth() + 1).padStart(2, '0');
        const ld = String(lendemain.getDate()).padStart(2, '0');
        finCreneau = `${ly}-${lm}-${ld}T${horaireJour.heureFin}:00`;
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
  }

  
  return creneaux;
}

// ─── Validation ───────────────────────────────────────────────────
export function validerHorairesFlex(horairesParJour: HorairesJour[]): ValidationFlexResult {
  const joursActifs = horairesParJour.filter(j => j.actif);
  const erreurs: ErreurValidation[] = [];

  const totalHebdo = joursActifs.reduce((s, j) => s + j.dureeHeures, 0);
  if (totalHebdo > 48) {
    // Suggestion de fix chiffrée (Lot 11) : retirer un jour si ça suffit, sinon
    // la durée/jour qui ramène la semaine exactement à 48h (ex. « 9h36/jour »).
    const dureeMax = joursActifs.length ? Math.max(...joursActifs.map((j) => j.dureeHeures)) : 0;
    const cibleParJour = joursActifs.length ? 48 / joursActifs.length : 48;
    const hCible = Math.floor(cibleParJour);
    const minCible = Math.round((cibleParJour - hCible) * 60);
    const fix = totalHebdo - dureeMax <= 48
      ? `retirez un jour ou passez à ${hCible}h${String(minCible).padStart(2, '0')}/jour`
      : `passez à ${hCible}h${String(minCible).padStart(2, '0')}/jour maximum`;
    erreurs.push({
      type: 'PLAFOND_48H',
      message: `La semaine totalise ${totalHebdo}h. Maximum légal : 48h (Art. L3121-20). Pour corriger : ${fix}.`,
      gravite: 'bloquant',
    });
  }

  const joursTriés = [...joursActifs].sort((a, b) => a.jourISO - b.jourISO);
  for (let i = 0; i < joursTriés.length - 1; i++) {
    const actuel = joursTriés[i];
    const suivant = joursTriés[i + 1];
    if (suivant.jourISO - actuel.jourISO === 1) {
      const finActuel = parseHeure(actuel.heureFin);
      const debutSuivant = parseHeure(suivant.heureDebut);
      const repos = (24 - finActuel) + debutSuivant;
      if (repos < 11) {
        erreurs.push({
          type: 'REPOS_11H',
          message: `Repos insuffisant entre ${actuel.label} (fin ${actuel.heureFin}) et ${suivant.label} (début ${suivant.heureDebut}) : ${repos.toFixed(1)}h au lieu de 11h`,
          gravite: 'bloquant',
          joursAffectes: [actuel.jourISO, suivant.jourISO],
        });
      }
    }
  }

  for (const jour of joursActifs) {
    if (jour.dureeHeures > 12) {
      erreurs.push({
        type: 'DUREE_LONGUE',
        message: `${jour.label} : créneau de ${jour.dureeHeures}h (recommandation : max 12h)`,
        gravite: 'avertissement',
        joursAffectes: [jour.jourISO],
      });
    }
  }

  return {
    valide: !erreurs.some(e => e.gravite === 'bloquant'),
    erreurs,
    totalHebdo,
  };
}

// ─── Props ────────────────────────────────────────────────────────
interface FormulaireRecurrenceProps {
  onChange: (config: RecurrenceFlexConfig, creneaux: CreneauFlex[], validation: ValidationFlexResult) => void;
}

export function FormulaireRecurrence({ onChange }: FormulaireRecurrenceProps) {
  const [dateDebut, setDateDebut] = useState('');
  const [dateFin, setDateFin] = useState('');
  // Avertissement affiché quand un (dé)cochage de jour recale les dates.
  const [avertissementDates, setAvertissementDates] = useState<string | null>(null);
  const [horairesParJour, setHorairesParJour] = useState<HorairesJour[]>(
    JOURS_SEMAINE_DEF.map(j => ({
      ...j,
      heureDebut: '07:00',
      heureFin: '19:00',
      dureeHeures: 12,
      actif: [1, 2, 3, 4, 5].includes(j.jourISO),
    }))
  );

  // Choisir une plage de dates coche AUTOMATIQUEMENT les jours présents dans
  // cette plage (ex : du vendredi au lundi → ven/sam/dim/lun cochés), au lieu
  // d'un défaut figé lun-ven qui effacerait l'intention de l'utilisateur.
  const appliquerJoursSelonPlage = useCallback((debut: string, fin: string) => {
    if (!debut || !fin) return;
    const presents = joursISODansPlage(debut, fin);
    if (presents.size === 0) return;
    setHorairesParJour(prev => prev.map(j => ({ ...j, actif: presents.has(j.jourISO) })));
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

  const joursActifs = useMemo(() => horairesParJour.filter(j => j.actif), [horairesParJour]);

  const validation = useMemo(() => validerHorairesFlex(horairesParJour), [horairesParJour]);

  const creneaux = useMemo(
    () => genererCreneauxFlex(dateDebut, dateFin, horairesParJour),
    [dateDebut, dateFin, horairesParJour]
  );

  // Group creneaux by ISO week
  const creneauxParSemaine = useMemo(() => {
    const map = new Map<string, { label: string; creneaux: CreneauFlex[]; totalHeures: number }>();
    creneaux.forEach(c => {
      const d = new Date(c.debut);
      const w = startOfWeek(d, { weekStartsOn: 1 });
      const key = w.toISOString().split('T')[0];
      if (!map.has(key)) {
        const fin = new Date(w);
        fin.setDate(fin.getDate() + 6);
        map.set(key, {
          label: `${format(w, 'd MMM', { locale: fr })} → ${format(fin, 'd MMM', { locale: fr })}`,
          creneaux: [],
          totalHeures: 0,
        });
      }
      const entry = map.get(key)!;
      entry.creneaux.push(c);
      entry.totalHeures += c.dureeHeures;
    });
    return [...map.entries()];
  }, [creneaux]);

  const totalHeures = creneaux.reduce((s, c) => s + c.dureeHeures, 0);

  // Notify parent
  React.useEffect(() => {
    onChange({ dateDebut, dateFin, horairesParJour }, creneaux, validation);
  }, [dateDebut, dateFin, horairesParJour, creneaux, validation]);

  // Lot 11 : zone d'erreurs UNIQUE — quand une violation bloquante apparaît,
  // on l'amène à l'écran (scroll de section, pas de focus input — règle iOS).
  const zoneErreursRef = React.useRef<HTMLDivElement | null>(null);
  const aBloquant = validation.erreurs.some((e) => e.gravite === 'bloquant');
  React.useEffect(() => {
    if (aBloquant) zoneErreursRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }, [aBloquant]);

  const toggleJour = useCallback((iso: number) => {
    setHorairesParJour(prev =>
      prev.map(j => j.jourISO === iso ? { ...j, actif: !j.actif } : j)
    );
    // Changer les jours recale automatiquement les dates sur la 1ère/dernière
    // journée réellement travaillée, et le signale.
    const actifsApres = new Set(
      horairesParJour.filter(j => (j.jourISO === iso ? !j.actif : j.actif)).map(j => j.jourISO)
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
    setHorairesParJour(prev =>
      prev.map(j =>
        j.jourISO === jourISO
          ? { ...j, heureDebut, heureFin, dureeHeures: calculerDuree(heureDebut, heureFin) }
          : j
      )
    );
  }, []);

  const appliquerATous = useCallback(() => {
    const premier = horairesParJour.find(j => j.actif);
    if (!premier) return;
    setHorairesParJour(prev =>
      prev.map(j =>
        j.actif
          ? { ...j, heureDebut: premier.heureDebut, heureFin: premier.heureFin, dureeHeures: premier.dureeHeures }
          : j
      )
    );
    toast.success('Horaires appliqués à tous les jours');
  }, [horairesParJour]);

  const joursEnErreur = new Set(validation.erreurs.flatMap(e => e.joursAffectes || []));
  const premierJourActif = joursActifs[0]?.jourISO;

  // Find repos errors between specific pairs for inline display
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
            <input type="date" value={dateDebut} onChange={e => handleDateDebut(e.target.value)} className="input-base" required />
          </div>
          <div>
            <label className="text-xs text-muted-foreground mb-1 block">Au *</label>
            <input type="date" value={dateFin} onChange={e => handleDateFin(e.target.value)} className="input-base" required />
          </div>
        </div>

        {avertissementDates && (
          <div className="flex items-start gap-2 text-xs text-warning bg-warning/10 border border-warning/30 rounded-lg p-2">
            <AlertTriangle className="h-3.5 w-3.5 shrink-0 mt-0.5" />
            <span>{avertissementDates}</span>
          </div>
        )}

        {/* Jours */}
        <div>
          <label className="text-xs text-muted-foreground mb-2 block">Jours travaillés</label>
          <div className="flex flex-wrap gap-2">
            {JOURS_SEMAINE_DEF.map(j => (
              <button
                key={j.jourISO}
                type="button"
                onClick={() => toggleJour(j.jourISO)}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${
                  horairesParJour.find(h => h.jourISO === j.jourISO)?.actif
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-muted text-muted-foreground hover:bg-muted/80'
                }`}
              >
                {horairesParJour.find(h => h.jourISO === j.jourISO)?.actif ? '☑️' : '☐'} {j.label.slice(0, 3)}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Horaires par jour */}
      {joursActifs.length > 0 && (
        <div className="bg-primary/5 border border-primary/20 rounded-2xl p-4 space-y-1">
          <p className="text-sm font-semibold text-foreground mb-3">🕐 Horaires par jour</p>
          {horairesParJour.filter(j => j.actif).map((jour, idx) => {
            const reposErr = reposErreurs.get(jour.jourISO);
            return (
              <React.Fragment key={jour.jourISO}>
                <LigneHoraireJour
                  jour={jour}
                  onChange={(hd, hf) => updateHoraire(jour.jourISO, hd, hf)}
                  estPremierJour={jour.jourISO === premierJourActif}
                  onAppliquerATous={jour.jourISO === premierJourActif ? appliquerATous : undefined}
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

          {/* Récap hebdo */}
          <div className="border-t border-border mt-3 pt-3 flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Total hebdomadaire :</span>
            <span className={`font-bold ${validation.totalHebdo > 48 ? 'text-destructive' : validation.totalHebdo > 36 ? 'text-warning' : 'text-primary'}`}>
              {validation.totalHebdo}h{validation.totalHebdo > 48 && ' — dépasse le plafond légal de 48h'}
            </span>
          </div>
          <p className="text-[10px] text-muted-foreground mt-1">
            Durées : orange = journée de plus de 10h (12h max recommandé), rouge = plus de 12h.
          </p>
        </div>
      )}

      {/* Validations — zone d'erreurs UNIQUE (Lot 11), amenée à l'écran au 1er bloquant */}
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

      {validation.erreurs.length === 0 && joursActifs.length > 0 && (
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-xs font-medium text-primary">
            <CheckCircle2 className="h-4 w-4" />
            Repos inter-créneaux : conforme (≥ 11h)
          </div>
          <div className="flex items-center gap-2 text-xs font-medium text-primary">
            <CheckCircle2 className="h-4 w-4" />
            Heures hebdomadaires : {validation.totalHebdo}h / 48h — conforme
          </div>
        </div>
      )}

      {/* Prévisualisation groupée par semaine */}
      {creneaux.length > 0 && (
        <div className="card-base">
          <p className="text-sm font-bold text-foreground mb-3">
            Prévisualisation : {creneaux.length} créneau{creneaux.length > 1 ? 'x' : ''} sur {creneauxParSemaine.length} semaine{creneauxParSemaine.length > 1 ? 's' : ''}
          </p>

          <div className="max-h-64 overflow-y-auto space-y-4">
            {creneauxParSemaine.map(([key, sem]) => (
              <div key={key}>
                <div className="flex items-center justify-between mb-1">
                  <p className="text-xs font-semibold text-foreground">Semaine ({sem.label})</p>
                  <span className={`text-xs font-bold inline-flex items-center gap-1 ${sem.totalHeures > 48 ? 'text-destructive' : 'text-primary'}`}>
                    {sem.totalHeures}h {sem.totalHeures > 48 ? <XCircle aria-hidden="true" className="h-3.5 w-3.5" /> : <CheckCircle2 aria-hidden="true" className="h-3.5 w-3.5" />}
                  </span>
                </div>
                <div className="space-y-0.5">
                  {sem.creneaux.map((c, i) => (
                    <div key={i} className="flex items-center gap-2 text-xs text-foreground">
                      <CheckCircle2 aria-hidden="true" className="h-3.5 w-3.5 text-primary shrink-0" />
                      <span className="font-medium w-32">
                        {format(new Date(c.debut), 'EEE d MMM', { locale: fr })}
                      </span>
                      <span className="text-muted-foreground">
                        {c.debut.slice(11, 16)} → {c.fin.slice(11, 16)} ({c.dureeHeures}h)
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>

          <div className="border-t border-border mt-3 pt-3 text-xs text-muted-foreground">
            <p>Total : <strong className="text-foreground">{totalHeures.toFixed(0)}h</strong> sur {creneauxParSemaine.length} semaine{creneauxParSemaine.length > 1 ? 's' : ''} ({creneaux.length} créneaux)</p>
          </div>
        </div>
      )}
    </div>
  );
}
