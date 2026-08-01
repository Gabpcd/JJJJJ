import {
  ajouterJoursCivilsParis,
  cleJourParis,
  cleSemaineParis,
  debutJourParis,
  debutSemaineParis,
  formatParis,
  instantDateHeureParis,
  instantDepuisSaisieParis,
  instantJolene,
  partiesDateHeureParis,
  semaineSuivanteParis,
} from '@/lib/date-heure-paris';

export interface CreneauPlanningDate {
  clientId: string;
  id?: string;
  heureDebut: string;
  heureFin: string;
  finJourSuivant: boolean;
  /**
   * Instants contractuels chargés depuis la base. Ils permettent de conserver
   * l'occurrence exacte d'une heure murale répétée au passage à l'heure
   * d'hiver tant que la borne visible correspondante n'a pas été modifiée.
   */
  debutInitial?: string;
  finInitial?: string;
}

export interface JourPlanningDate {
  date: string;
  actif: boolean;
  creneaux: CreneauPlanningDate[];
}

export interface CreneauPlanningMaterialise {
  clientId: string;
  id?: string;
  date: string;
  dateFin: string;
  debut: string;
  fin: string;
  dureeHeures: number;
}

export interface SemaineCivile {
  cleLundi: string;
  labelCourt: string;
  label: string;
  totalHeures: number;
  nbOccurrences: number;
  depasse48: boolean;
}

export interface ErreurPlanning {
  type:
    | 'PLAGE_INVALIDE'
    | 'CRENEAU_MANQUANT'
    | 'CRENEAU_INVALIDE'
    | 'CHEVAUCHEMENT'
    | 'PLAFOND_48H'
    | 'REPOS_11H'
    | 'DUREE_LONGUE';
  message: string;
  gravite: 'bloquant' | 'avertissement';
  datesAffectees?: string[];
  creneauxAffectes?: string[];
  semaine?: string;
}

export interface ValidationPlanning {
  valide: boolean;
  erreurs: ErreurPlanning[];
  totalHebdo: number;
  semaines: SemaineCivile[];
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const HEURE_RE = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

function instantMidiParis(date: string): Date {
  return instantDepuisSaisieParis(`${date}T12:00`);
}

export function ajouterJoursDate(date: string, nombre: number): string {
  return cleJourParis(ajouterJoursCivilsParis(instantMidiParis(date), nombre));
}

export function datesDansPlage(dateDebut: string, dateFin: string): string[] {
  if (!DATE_RE.test(dateDebut) || !DATE_RE.test(dateFin) || dateFin < dateDebut) return [];
  const dates: string[] = [];
  let date = dateDebut;
  while (date <= dateFin && dates.length <= 366) {
    dates.push(date);
    date = ajouterJoursDate(date, 1);
  }
  return dates;
}

export function jourSemaineISO(date: string): number {
  const [annee, mois, jour] = date.split('-').map(Number);
  const js = new Date(Date.UTC(annee, mois - 1, jour, 12)).getUTCDay();
  return js === 0 ? 7 : js;
}

export function libelleDate(date: string): string {
  return formatParis(instantMidiParis(date), 'EEEE d MMMM yyyy');
}

export function libelleDateCourte(date: string): string {
  return formatParis(instantMidiParis(date), 'EEE d MMM');
}

export function dateFinCreneau(date: string, creneau: Pick<CreneauPlanningDate, 'finJourSuivant'>): string {
  return creneau.finJourSuivant ? ajouterJoursDate(date, 1) : date;
}

function resoudreBorneCreneau(
  date: string,
  heure: string,
  instantInitial?: string,
): { instant: Date; valeur: string } {
  if (instantInitial) {
    const instant = instantJolene(instantInitial);
    if (cleJourParis(instant) === date && formatParis(instant, 'HH:mm') === heure) {
      return { instant, valeur: instantInitial };
    }
  }

  const instant = instantDepuisSaisieParis(`${date}T${heure}`);
  return { instant, valeur: instant.toISOString() };
}

export function materialiserCreneau(
  date: string,
  creneau: CreneauPlanningDate,
): { valeur: CreneauPlanningMaterialise | null; erreur: string | null } {
  if (!DATE_RE.test(date) || !HEURE_RE.test(creneau.heureDebut) || !HEURE_RE.test(creneau.heureFin)) {
    return { valeur: null, erreur: 'Renseignez une heure de début et une heure de fin valides.' };
  }

  const dateFin = dateFinCreneau(date, creneau);
  let debut: { instant: Date; valeur: string };
  let fin: { instant: Date; valeur: string };
  try {
    debut = resoudreBorneCreneau(date, creneau.heureDebut, creneau.debutInitial);
    fin = resoudreBorneCreneau(dateFin, creneau.heureFin, creneau.finInitial);
  } catch (error) {
    if (error instanceof RangeError) {
      return {
        valeur: null,
        erreur: error.message.includes('ambiguë')
          ? 'Cette heure existe deux fois à Paris lors du passage à l’heure d’hiver. Choisissez un horaire non ambigu.'
          : 'Cette heure n\u2019existe pas à Paris en raison du passage à l\u2019heure d’été.',
      };
    }
    throw error;
  }
  const dureeHeures = (fin.instant.getTime() - debut.instant.getTime()) / 3_600_000;

  if (!creneau.finJourSuivant && fin.instant <= debut.instant) {
    return {
      valeur: null,
      erreur: 'La fin doit être après le début. Pour une garde de nuit, choisissez « lendemain ».',
    };
  }
  if (!Number.isFinite(dureeHeures) || dureeHeures <= 0 || dureeHeures > 24) {
    return { valeur: null, erreur: 'Un créneau doit durer plus de 0 h et au maximum 24 h.' };
  }

  return {
    valeur: {
      clientId: creneau.clientId,
      id: creneau.id,
      date,
      dateFin,
      debut: debut.valeur,
      fin: fin.valeur,
      dureeHeures,
    },
    erreur: null,
  };
}

export function materialiserPlanning(jours: JourPlanningDate[]): CreneauPlanningMaterialise[] {
  return jours
    .filter((jour) => jour.actif)
    .flatMap((jour) => jour.creneaux.map((creneau) => materialiserCreneau(jour.date, creneau).valeur))
    .filter((creneau): creneau is CreneauPlanningMaterialise => Boolean(creneau))
    .sort((a, b) => new Date(a.debut).getTime() - new Date(b.debut).getTime());
}

/** Calcule l'intersection exacte avec les périodes de nuit 21 h–06 h à Paris. */
export function calculerHeuresNuitParis(
  creneaux: Array<Pick<CreneauPlanningMaterialise, 'debut' | 'fin'>>,
): number {
  let totalMillisecondes = 0;

  for (const creneau of creneaux) {
    const debut = instantJolene(creneau.debut);
    const fin = instantJolene(creneau.fin);
    if (fin <= debut) continue;

    // Inclure la nuit commencée la veille pour un créneau situé avant 06 h.
    let jour = ajouterJoursCivilsParis(debutJourParis(debut), -1);
    while (jour < fin) {
      const lendemain = ajouterJoursCivilsParis(jour, 1);
      const debutNuit = instantDateHeureParis({
        ...partiesDateHeureParis(jour),
        heure: 21,
        minute: 0,
        seconde: 0,
      });
      const finNuit = instantDateHeureParis({
        ...partiesDateHeureParis(lendemain),
        heure: 6,
        minute: 0,
        seconde: 0,
      });
      const debutIntersection = Math.max(debut.getTime(), debutNuit.getTime());
      const finIntersection = Math.min(fin.getTime(), finNuit.getTime());
      if (finIntersection > debutIntersection) {
        totalMillisecondes += finIntersection - debutIntersection;
      }
      jour = lendemain;
    }
  }

  return totalMillisecondes / 3_600_000;
}

function semainesDepuisCreneaux(creneaux: CreneauPlanningMaterialise[]): SemaineCivile[] {
  const semaines = new Map<string, SemaineCivile & { occurrences: Set<string> }>();

  for (const creneau of creneaux) {
    let curseur = new Date(creneau.debut);
    const fin = new Date(creneau.fin);
    while (curseur < fin) {
      const lundi = debutSemaineParis(curseur);
      const lundiSuivant = semaineSuivanteParis(curseur);
      const finSegment = new Date(Math.min(fin.getTime(), lundiSuivant.getTime()));
      const cle = cleSemaineParis(curseur);
      const semaine = semaines.get(cle) ?? {
        cleLundi: cle,
        labelCourt: formatParis(lundi, 'dd/MM'),
        label: `Semaine du ${formatParis(lundi, 'dd/MM')}`,
        totalHeures: 0,
        nbOccurrences: 0,
        depasse48: false,
        occurrences: new Set<string>(),
      };
      semaine.totalHeures += (finSegment.getTime() - curseur.getTime()) / 3_600_000;
      semaine.occurrences.add(creneau.clientId);
      semaines.set(cle, semaine);
      curseur = finSegment;
    }
  }

  return [...semaines.values()]
    .sort((a, b) => a.cleLundi.localeCompare(b.cleLundi))
    .map(({ occurrences, ...semaine }) => ({
      ...semaine,
      totalHeures: Math.round(semaine.totalHeures * 100) / 100,
      nbOccurrences: occurrences.size,
      depasse48: semaine.totalHeures > 48,
    }));
}

export function validerPlanningDates(jours: JourPlanningDate[]): ValidationPlanning {
  const erreurs: ErreurPlanning[] = [];
  const creneauxValides: CreneauPlanningMaterialise[] = [];

  for (const jour of jours.filter((item) => item.actif)) {
    if (jour.creneaux.length === 0) {
      erreurs.push({
        type: 'CRENEAU_MANQUANT',
        gravite: 'bloquant',
        datesAffectees: [jour.date],
        message: `${libelleDate(jour.date)} est travaillé mais ne contient aucun créneau.`,
      });
      continue;
    }

    let dureeJour = 0;
    for (const creneau of jour.creneaux) {
      const resultat = materialiserCreneau(jour.date, creneau);
      if (!resultat.valeur) {
        erreurs.push({
          type: 'CRENEAU_INVALIDE',
          gravite: 'bloquant',
          datesAffectees: [jour.date],
          creneauxAffectes: [creneau.clientId],
          message: `${libelleDate(jour.date)} : ${resultat.erreur}`,
        });
        continue;
      }
      creneauxValides.push(resultat.valeur);
      dureeJour += resultat.valeur.dureeHeures;
    }

    if (dureeJour > 12) {
      erreurs.push({
        type: 'DUREE_LONGUE',
        gravite: 'avertissement',
        datesAffectees: [jour.date],
        message: `${libelleDate(jour.date)} : ${dureeJour.toLocaleString('fr-FR', { maximumFractionDigits: 2 })} h planifiées (recommandation : max 12 h).`,
      });
    }
  }

  creneauxValides.sort((a, b) => new Date(a.debut).getTime() - new Date(b.debut).getTime());
  for (let index = 1; index < creneauxValides.length; index += 1) {
    const precedent = creneauxValides[index - 1];
    const courant = creneauxValides[index];
    if (new Date(courant.debut) < new Date(precedent.fin)) {
      erreurs.push({
        type: 'CHEVAUCHEMENT',
        gravite: 'bloquant',
        datesAffectees: [precedent.date, courant.date],
        creneauxAffectes: [precedent.clientId, courant.clientId],
        message: `Chevauchement entre les créneaux des ${libelleDateCourte(precedent.date)} et ${libelleDateCourte(courant.date)}.`,
      });
    }
  }

  const bornesParDate = new Map<string, { debut: Date; fin: Date; ids: string[] }>();
  for (const creneau of creneauxValides) {
    const debut = new Date(creneau.debut);
    const fin = new Date(creneau.fin);
    const bornes = bornesParDate.get(creneau.date);
    if (!bornes) {
      bornesParDate.set(creneau.date, { debut, fin, ids: [creneau.clientId] });
    } else {
      if (debut < bornes.debut) bornes.debut = debut;
      if (fin > bornes.fin) bornes.fin = fin;
      bornes.ids.push(creneau.clientId);
    }
  }

  const datesTravaillees = [...bornesParDate.entries()].sort((a, b) => a[1].debut.getTime() - b[1].debut.getTime());
  for (let index = 1; index < datesTravaillees.length; index += 1) {
    const [datePrecedente, precedent] = datesTravaillees[index - 1];
    const [dateCourante, courant] = datesTravaillees[index];
    const reposHeures = (courant.debut.getTime() - precedent.fin.getTime()) / 3_600_000;
    if (reposHeures >= 0 && reposHeures < 11) {
      erreurs.push({
        type: 'REPOS_11H',
        gravite: 'bloquant',
        datesAffectees: [datePrecedente, dateCourante],
        creneauxAffectes: [...precedent.ids, ...courant.ids],
        message: `Repos insuffisant entre ${libelleDateCourte(datePrecedente)} et ${libelleDateCourte(dateCourante)} : ${reposHeures.toLocaleString('fr-FR', { maximumFractionDigits: 2 })} h au lieu de 11 h.`,
      });
    }
  }

  const semaines = semainesDepuisCreneaux(creneauxValides);
  for (const semaine of semaines.filter((item) => item.depasse48)) {
    erreurs.push({
      type: 'PLAFOND_48H',
      gravite: 'bloquant',
      semaine: semaine.labelCourt,
      message: `${semaine.label} : ${semaine.totalHeures.toLocaleString('fr-FR')} h travaillées. Maximum légal : 48 h/semaine.`,
    });
  }

  const totalHebdo = semaines.reduce((maximum, semaine) => Math.max(maximum, semaine.totalHeures), 0);
  return {
    valide: !erreurs.some((erreur) => erreur.gravite === 'bloquant'),
    erreurs,
    totalHebdo,
    semaines,
  };
}
