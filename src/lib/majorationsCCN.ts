/**
 * Helpers majorations CCN Sprint 8 BIS PR 3 (chantier 7.3 - P2 §6).
 *
 * Détecte les majorations applicables sur une plage horaire selon la CCN.
 * Référentiel CCN 51 (FEHAP) — majorations indicatives, à valider contractuellement.
 */

const HEURE_NUIT_DEBUT = 22;
const HEURE_NUIT_FIN = 6;

/**
 * Majoration nuit (22h-6h) — +10% selon CCN 51 art. 82.
 * Source : Convention collective FEHAP du 31 octobre 1951.
 */
export const MAJORATION_NUIT_PCT = 10;

/**
 * Majoration dimanche / jour férié — +15% selon CCN 51.
 */
export const MAJORATION_DIMANCHE_PCT = 15;

/**
 * Jours fériés français 2026 (à étendre annuellement).
 */
const JOURS_FERIES_FR: string[] = [
  '2026-01-01',
  '2026-04-06',
  '2026-05-01',
  '2026-05-08',
  '2026-05-14',
  '2026-05-25',
  '2026-07-14',
  '2026-08-15',
  '2026-11-01',
  '2026-11-11',
  '2026-12-25',
];

export type Majoration = {
  type: 'nuit' | 'dimanche' | 'ferie';
  libelle: string;
  pourcentage: number;
  reference: string;
};

function chevaucheNuit(debut: Date, fin: Date): boolean {
  // La mission couvre-t-elle une partie de la nuit 22h-6h ?
  // Approximation simple : vérifier toutes les heures entre debut et fin.
  const heureDebut = debut.getHours();
  const heureFin = fin.getHours() === 0 ? 24 : fin.getHours();

  // Cas 1 : nuit sur le même jour
  if (heureDebut >= HEURE_NUIT_DEBUT) return true;
  // Cas 2 : termine après minuit
  if (heureFin <= HEURE_NUIT_FIN || heureFin > 24) return true;
  // Cas 3 : couvre minuit
  if (fin.getDate() !== debut.getDate()) return true;

  return false;
}

function estDimancheOuFerie(date: Date): { dimanche: boolean; ferie: boolean } {
  const dimanche = date.getDay() === 0;
  const iso = date.toISOString().slice(0, 10);
  const ferie = JOURS_FERIES_FR.includes(iso);
  return { dimanche, ferie };
}

/**
 * Retourne la liste des majorations applicables sur une mission.
 *
 * @param debut - Début mission ISO 8601
 * @param fin - Fin mission ISO 8601
 */
export function detecterMajorations(debut: string | Date, fin: string | Date): Majoration[] {
  const d = typeof debut === 'string' ? new Date(debut) : debut;
  const f = typeof fin === 'string' ? new Date(fin) : fin;
  const majorations: Majoration[] = [];

  if (chevaucheNuit(d, f)) {
    majorations.push({
      type: 'nuit',
      libelle: 'Travail de nuit (22h-6h)',
      pourcentage: MAJORATION_NUIT_PCT,
      reference: 'CCN 51 art. 82',
    });
  }

  const { dimanche, ferie } = estDimancheOuFerie(d);
  if (ferie) {
    majorations.push({
      type: 'ferie',
      libelle: 'Jour férié',
      pourcentage: MAJORATION_DIMANCHE_PCT,
      reference: 'CCN 51 art. 83',
    });
  } else if (dimanche) {
    majorations.push({
      type: 'dimanche',
      libelle: 'Travail le dimanche',
      pourcentage: MAJORATION_DIMANCHE_PCT,
      reference: 'CCN 51 art. 83',
    });
  }

  return majorations;
}

/**
 * Calcule le taux horaire après application des majorations.
 *
 * Note : les majorations s'additionnent simplement dans cette estimation.
 * Le calcul réel peut différer selon la CCN et la convention locale.
 */
export function calculerTauxAvecMajorations(tauxBase: number, majorations: Majoration[]): number {
  const totalPct = majorations.reduce((s, m) => s + m.pourcentage, 0);
  return tauxBase * (1 + totalPct / 100);
}
