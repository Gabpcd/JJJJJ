// Dérivation pure du planning de mission (formulaire Publier établissement).
//
// PRINCIPE — État dérivé (cf. CLAUDE.md) : la période « Du / Au » est la SEULE
// source de vérité. Les jours travaillés proposés, leur ordre, leurs libellés,
// et le garde-fou 48h sont DÉRIVÉS de la période en temps réel — jamais un
// défaut statique (semaine lundi-first, tout coché) qui contredit la plage.
//
// Fonctions PURES (aucun état React, aucun effet) → couvertes par
// planning-derive.test.ts. Le composant FormulaireRecurrence ne fait que les
// consommer et afficher.

import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import type { HorairesJour } from '@/components/LigneHoraireJour';

const NOMS_JOURS: Record<number, string> = {
  1: 'Lundi', 2: 'Mardi', 3: 'Mercredi', 4: 'Jeudi',
  5: 'Vendredi', 6: 'Samedi', 7: 'Dimanche',
};

// ≤ 14 jours : la plage tient sur ≤ 2 semaines → on affiche les VRAIES dates
// (« Mer. 22/07 ») plutôt que des jours abstraits. Au-delà, motif hebdomadaire
// répété → libellés abstraits (« Mercredi »).
export const SEUIL_LIBELLES_DATES = 14;

/** Parse "YYYY-MM-DD" en date LOCALE (jamais UTC — évite le décalage de jour). */
export function parseDateLocale(str: string): Date {
  const [y, m, d] = str.split('-').map(Number);
  return new Date(y, m - 1, d);
}

export function fmtDateLocale(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** Jour ISO 1=lundi … 7=dimanche à partir d'un Date. */
function isoDe(d: Date): number {
  const r = d.getDay();
  return r === 0 ? 7 : r;
}

/** Lundi (00:00) de la semaine civile contenant `d`. */
export function lundiDe(d: Date): Date {
  const r = d.getDay(); // 0=dim … 6=sam
  const diff = r === 0 ? -6 : 1 - r;
  const m = new Date(d);
  m.setDate(m.getDate() + diff);
  return m;
}

/** « Mer. 22/07 » — abréviation du jour capitalisée + date. */
export function libelleDate(dateStr: string): string {
  const d = parseDateLocale(dateStr);
  const abbr = format(d, 'EEE', { locale: fr }).replace('.', ''); // 'mer'
  const cap = abbr.charAt(0).toUpperCase() + abbr.slice(1);
  return `${cap}. ${format(d, 'dd/MM')}`;
}

export interface JourPlanifie {
  jourISO: number;        // 1..7
  premiereDate: string;   // 'YYYY-MM-DD' — 1ère occurrence dans la plage
  occurrences: string[];  // toutes les dates de ce jour-de-semaine dans la plage
  label: string;          // daté « Mer. 22/07 » si datesLabels, sinon « Mercredi »
  labelCourt: string;     // « Mer. 22/07 » ou « Mer »
}

export interface Planning {
  jours: JourPlanifie[];  // ordonné À PARTIR du premier jour de la mission
  datesLabels: boolean;   // plage ≤ 14 jours
  nbJours: number;        // nb de jours calendaires dans la plage
}

/**
 * Dérive, depuis la période [debut, fin], la liste ORDONNÉE des jours-de-semaine
 * réellement présents. Ordre = première apparition chronologique à partir de
 * `debut` (une mission qui commence un mercredi commence par mercredi). Un jour
 * absent de la plage n'est pas retourné (donc ni affiché ni cochable côté UI).
 */
export function derivePlanning(debut: string, fin: string): Planning {
  if (!debut || !fin) return { jours: [], datesLabels: false, nbJours: 0 };
  const d = parseDateLocale(debut);
  const f = parseDateLocale(fin);
  if (f < d) return { jours: [], datesLabels: false, nbJours: 0 };

  const ordre: number[] = [];
  const parISO = new Map<number, string[]>();
  const cur = new Date(d);
  let guard = 0;
  let nb = 0;
  while (cur <= f && guard < 400) {
    const iso = isoDe(cur);
    if (!parISO.has(iso)) { parISO.set(iso, []); ordre.push(iso); }
    parISO.get(iso)!.push(fmtDateLocale(cur));
    cur.setDate(cur.getDate() + 1);
    guard++; nb++;
  }

  const datesLabels = nb <= SEUIL_LIBELLES_DATES;
  const jours: JourPlanifie[] = ordre.map((iso) => {
    const occ = parISO.get(iso)!;
    return {
      jourISO: iso,
      premiereDate: occ[0],
      occurrences: occ,
      label: datesLabels ? libelleDate(occ[0]) : NOMS_JOURS[iso],
      labelCourt: datesLabels ? libelleDate(occ[0]) : NOMS_JOURS[iso].slice(0, 3),
    };
  });
  return { jours, datesLabels, nbJours: nb };
}

export interface SemaineCivile {
  cleLundi: string;     // 'YYYY-MM-DD' du lundi
  labelCourt: string;   // '20/07'
  label: string;        // 'Semaine du 20/07'
  totalHeures: number;  // heures des occurrences ACTIVES cette semaine-là
  nbOccurrences: number;
  depasse48: boolean;
}

/**
 * Regroupe les occurrences RÉELLES des jours ACTIFS par semaine CIVILE
 * (lundi→dimanche). Une plage à cheval sur deux semaines produit deux entrées :
 * le total 48h est ainsi contrôlé semaine par semaine, pas sur une semaine
 * canonique fictive.
 */
export function semainesCiviles(
  debut: string, fin: string, horairesParJour: HorairesJour[],
): SemaineCivile[] {
  const plan = derivePlanning(debut, fin);
  const dureeParISO = new Map<number, number>();
  const actifISO = new Set<number>();
  for (const h of horairesParJour) {
    dureeParISO.set(h.jourISO, h.dureeHeures);
    if (h.actif) actifISO.add(h.jourISO);
  }

  const map = new Map<string, SemaineCivile>();
  for (const j of plan.jours) {
    if (!actifISO.has(j.jourISO)) continue;
    const duree = dureeParISO.get(j.jourISO) ?? 0;
    for (const dateStr of j.occurrences) {
      const cle = fmtDateLocale(lundiDe(parseDateLocale(dateStr)));
      let s = map.get(cle);
      if (!s) {
        const lc = format(parseDateLocale(cle), 'dd/MM');
        s = { cleLundi: cle, labelCourt: lc, label: `Semaine du ${lc}`, totalHeures: 0, nbOccurrences: 0, depasse48: false };
        map.set(cle, s);
      }
      s.totalHeures += duree;
      s.nbOccurrences += 1;
    }
  }
  const arr = [...map.values()].sort((a, b) => a.cleLundi.localeCompare(b.cleLundi));
  for (const s of arr) s.depasse48 = s.totalHeures > 48;
  return arr;
}

export interface ErreurPlanning {
  type: 'PLAFOND_48H' | 'REPOS_11H' | 'DUREE_LONGUE';
  message: string;
  gravite: 'bloquant' | 'avertissement';
  joursAffectes?: number[];
  semaine?: string;
}

export interface ValidationPlanning {
  valide: boolean;
  erreurs: ErreurPlanning[];
  totalHebdo: number;        // total de la semaine civile la PLUS chargée
  semaines: SemaineCivile[];
}

function parseHeure(heure: string): number {
  const [h, m] = heure.split(':').map(Number);
  return h + m / 60;
}

/**
 * Valide le planning sur les occurrences RÉELLES : plafond 48h par semaine
 * civile, repos 11h entre jours consécutifs, journées > 12h. `valide` est faux
 * dès qu'une erreur bloquante existe.
 */
export function validerPlanning(
  debut: string, fin: string, horairesParJour: HorairesJour[],
): ValidationPlanning {
  const erreurs: ErreurPlanning[] = [];
  const semaines = semainesCiviles(debut, fin, horairesParJour);
  const joursActifs = horairesParJour.filter((j) => j.actif);

  // Plafond 48h — PAR semaine civile réelle.
  for (const s of semaines) {
    if (s.depasse48) {
      erreurs.push({
        type: 'PLAFOND_48H',
        gravite: 'bloquant',
        semaine: s.labelCourt,
        message: `${s.label} : ${s.totalHeures}h travaillées. Maximum légal : 48h/semaine (Art. L3121-20). Retirez un jour ou réduisez les horaires de cette semaine.`,
      });
    }
  }

  // Repos 11h entre jours-de-semaine consécutifs actifs.
  const joursTries = [...joursActifs].sort((a, b) => a.jourISO - b.jourISO);
  for (let i = 0; i < joursTries.length - 1; i++) {
    const actuel = joursTries[i];
    const suivant = joursTries[i + 1];
    if (suivant.jourISO - actuel.jourISO === 1) {
      const repos = (24 - parseHeure(actuel.heureFin)) + parseHeure(suivant.heureDebut);
      if (repos < 11) {
        erreurs.push({
          type: 'REPOS_11H',
          gravite: 'bloquant',
          joursAffectes: [actuel.jourISO, suivant.jourISO],
          message: `Repos insuffisant entre ${actuel.label} (fin ${actuel.heureFin}) et ${suivant.label} (début ${suivant.heureDebut}) : ${repos.toFixed(1)}h au lieu de 11h`,
        });
      }
    }
  }

  // Journées > 12h (avertissement).
  for (const jour of joursActifs) {
    if (jour.dureeHeures > 12) {
      erreurs.push({
        type: 'DUREE_LONGUE',
        gravite: 'avertissement',
        joursAffectes: [jour.jourISO],
        message: `${jour.label} : créneau de ${jour.dureeHeures}h (recommandation : max 12h)`,
      });
    }
  }

  const totalHebdo = semaines.reduce((max, s) => Math.max(max, s.totalHeures), 0);
  return { valide: !erreurs.some((e) => e.gravite === 'bloquant'), erreurs, totalHebdo, semaines };
}
