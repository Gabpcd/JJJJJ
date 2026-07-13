export interface MissionPourCalculHebdomadaire {
  id: string;
  debut_le: string;
  fin_le: string;
  duree_heures: number | string | null;
  nb_creneaux?: number | null;
  statut?: string | null;
  type_contrat_applique?: string | null;
  choix_contrat_soignant?: string | null;
  type_contrat_recherche?: string | null;
}

export interface CreneauMissionPourCalculHebdomadaire {
  mission_id: string;
  debut: string;
  fin: string | null;
  est_pause: boolean;
  type_creneau: string;
}

export interface HeuresSemaineMission {
  cleSemaine: string;
  debutSemaine: Date;
  heures: number;
}

const MS_HEURE = 3_600_000;
const TIME_ZONE = 'Europe/Paris';

interface DateParis {
  annee: number;
  mois: number;
  jour: number;
}

const formatteurDateParis = new Intl.DateTimeFormat('fr-FR', {
  timeZone: TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

const formatteurDateHeureParis = new Intl.DateTimeFormat('fr-FR', {
  timeZone: TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hourCycle: 'h23',
});

function nombrePartie(parts: Intl.DateTimeFormatPart[], type: Intl.DateTimeFormatPartTypes): number {
  return Number(parts.find((partie) => partie.type === type)?.value);
}

function dateParis(date: Date): DateParis {
  const parties = formatteurDateParis.formatToParts(date);
  return {
    annee: nombrePartie(parties, 'year'),
    mois: nombrePartie(parties, 'month'),
    jour: nombrePartie(parties, 'day'),
  };
}

function ajouterJours(date: DateParis, jours: number): DateParis {
  const resultat = new Date(Date.UTC(date.annee, date.mois - 1, date.jour + jours, 12));
  return {
    annee: resultat.getUTCFullYear(),
    mois: resultat.getUTCMonth() + 1,
    jour: resultat.getUTCDate(),
  };
}

function lundiDe(date: DateParis): DateParis {
  const jourSemaine = new Date(Date.UTC(date.annee, date.mois - 1, date.jour, 12)).getUTCDay();
  return ajouterJours(date, -(jourSemaine === 0 ? 6 : jourSemaine - 1));
}

function cleDate(date: DateParis): string {
  return `${date.annee}-${String(date.mois).padStart(2, '0')}-${String(date.jour).padStart(2, '0')}`;
}

function decalageParisMinutes(instant: Date): number {
  const parties = formatteurDateHeureParis.formatToParts(instant);
  const commeUtc = Date.UTC(
    nombrePartie(parties, 'year'),
    nombrePartie(parties, 'month') - 1,
    nombrePartie(parties, 'day'),
    nombrePartie(parties, 'hour'),
    nombrePartie(parties, 'minute'),
    nombrePartie(parties, 'second'),
  );
  return Math.round((commeUtc - Math.floor(instant.getTime() / 1000) * 1000) / 60_000);
}

/** Convertit un minuit civil français en instant, DST compris. */
function minuitParis(date: DateParis): Date {
  const baseUtc = Date.UTC(date.annee, date.mois - 1, date.jour);
  let instant = new Date(baseUtc);
  for (let i = 0; i < 2; i += 1) {
    instant = new Date(baseUtc - decalageParisMinutes(instant) * 60_000);
  }
  return instant;
}

export function debutSemaineCivile(date: Date): Date {
  return minuitParis(lundiDe(dateParis(date)));
}

export function cleSemaineCivile(date: Date): string {
  return cleDate(lundiDe(dateParis(date)));
}

export function semaineSuivante(debutSemaine: Date): Date {
  return minuitParis(ajouterJours(lundiDe(dateParis(debutSemaine)), 7));
}

/**
 * Retient les créneaux prévisionnels lorsqu'ils existent. Les créneaux
 * effectifs ne servent de repli que pour une mission historique sans planning
 * prévisionnel, afin de ne jamais additionner deux fois la même journée.
 */
function creneauxDeReference(
  mission: MissionPourCalculHebdomadaire,
  creneaux: CreneauMissionPourCalculHebdomadaire[],
): CreneauMissionPourCalculHebdomadaire[] {
  const valides = creneaux.filter((c) => c.mission_id === mission.id && c.fin);
  const previsionnels = valides.filter((c) => c.type_creneau === 'PREVISIONNEL');
  const effectifs = valides.filter((c) => c.type_creneau === 'EFFECTIF');
  const reference = mission.statut === 'TERMINEE' && effectifs.some((c) => !c.est_pause)
    ? effectifs
    : previsionnels.some((c) => !c.est_pause)
      ? previsionnels
      : effectifs;

  // nb_creneaux inclut les pauses explicites. Elles comptent donc pour
  // vérifier que le planning est complet, mais jamais dans les heures.
  if ((mission.nb_creneaux ?? 0) > 1 && reference.length < (mission.nb_creneaux ?? 0)) {
    return [];
  }

  return reference.filter((c) => !c.est_pause);
}

export function planningMissionHebdomadaireDisponible(
  mission: MissionPourCalculHebdomadaire,
  creneaux: CreneauMissionPourCalculHebdomadaire[],
): boolean {
  if ((mission.nb_creneaux ?? 0) <= 1) return true;
  return creneauxDeReference(mission, creneaux).length > 0;
}

function ajouterHeures(
  resultat: Map<string, HeuresSemaineMission>,
  cle: string,
  debut: Date,
  heures: number,
) {
  const courant = resultat.get(cle);
  if (courant) {
    courant.heures += heures;
  } else {
    resultat.set(cle, { cleSemaine: cle, debutSemaine: debut, heures });
  }
}

/**
 * Répartit une mission sur ses semaines civiles réelles (lundi→dimanche).
 * Un créneau de nuit qui franchit un lundi est lui-même scindé au bon
 * endroit. Pour les anciennes missions mono-créneau, `duree_heures` reste le
 * repli compatible avec le modèle historique.
 */
export function heuresMissionParSemaine(
  mission: MissionPourCalculHebdomadaire,
  creneaux: CreneauMissionPourCalculHebdomadaire[],
): HeuresSemaineMission[] {
  const resultat = new Map<string, HeuresSemaineMission>();
  const reference = creneauxDeReference(mission, creneaux);

  for (const creneau of reference) {
    let curseur = new Date(creneau.debut);
    const fin = new Date(creneau.fin!);
    if (!Number.isFinite(curseur.getTime()) || !Number.isFinite(fin.getTime()) || fin <= curseur) continue;

    while (curseur < fin) {
      const debutSemaine = debutSemaineCivile(curseur);
      const prochaineSemaine = semaineSuivante(debutSemaine);
      const finSegment = fin < prochaineSemaine ? fin : prochaineSemaine;
      ajouterHeures(
        resultat,
        cleSemaineCivile(curseur),
        debutSemaine,
        (finSegment.getTime() - curseur.getTime()) / MS_HEURE,
      );
      curseur = finSegment;
    }
  }

  if (resultat.size === 0) {
    // Une mission annoncée multi-créneaux ne doit jamais retomber sur sa
    // durée globale : sans les créneaux, la ventilation est indisponible.
    if ((mission.nb_creneaux ?? 0) > 1) return [];
    const debut = new Date(mission.debut_le);
    const heures = Number(mission.duree_heures) || 0;
    if (Number.isFinite(debut.getTime()) && heures > 0) {
      const debutSemaine = debutSemaineCivile(debut);
      ajouterHeures(resultat, cleSemaineCivile(debut), debutSemaine, heures);
    }
  }

  return [...resultat.values()]
    .map((semaine) => ({ ...semaine, heures: Math.round(semaine.heures * 100) / 100 }))
    .sort((a, b) => a.cleSemaine.localeCompare(b.cleSemaine));
}

export function additionnerHeuresParSemaine(
  missions: MissionPourCalculHebdomadaire[],
  creneaux: CreneauMissionPourCalculHebdomadaire[],
): Map<string, HeuresSemaineMission> {
  const resultat = new Map<string, HeuresSemaineMission>();
  for (const mission of missions) {
    for (const semaine of heuresMissionParSemaine(mission, creneaux)) {
      ajouterHeures(resultat, semaine.cleSemaine, semaine.debutSemaine, semaine.heures);
    }
  }
  return resultat;
}

/**
 * Reproduit la résolution utilisée par les gardes SQL du plafond de 48 h :
 * contrat appliqué, puis choix du soignant, puis LIBERAL uniquement lorsque
 * la mission le demande explicitement. `TOUS` et toute valeur absente restent
 * salariées par défaut.
 */
export function missionComptePourPlafond48h(
  mission: MissionPourCalculHebdomadaire,
): boolean {
  const choix = mission.choix_contrat_soignant?.trim().toUpperCase() || null;
  const regime = mission.type_contrat_applique
    ?? choix
    ?? (mission.type_contrat_recherche === 'LIBERAL' ? 'LIBERAL' : 'SALARIE');
  return regime !== 'LIBERAL';
}

/** Une mission TOUS encore ouverte doit laisser choisir le régime au CTA. */
export function missionPlafond48hConditionnel(
  mission: MissionPourCalculHebdomadaire,
): boolean {
  const choix = mission.choix_contrat_soignant?.trim() || null;
  return !mission.type_contrat_applique
    && !choix
    && mission.type_contrat_recherche === 'TOUS';
}

export function additionnerHeuresSalarieesParSemaine(
  missions: MissionPourCalculHebdomadaire[],
  creneaux: CreneauMissionPourCalculHebdomadaire[],
): Map<string, HeuresSemaineMission> {
  return additionnerHeuresParSemaine(
    missions.filter(missionComptePourPlafond48h),
    creneaux,
  );
}
