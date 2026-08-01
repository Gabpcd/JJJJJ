/**
 * Fuseau métier unique de Jolene.
 *
 * Les dates stockées par Supabase représentent des instants absolus. En
 * revanche, un horaire de mission, un jour de planning et une saisie
 * `datetime-local` sont toujours compris dans le fuseau de la France, quel que
 * soit le fuseau configuré sur le téléphone ou l'ordinateur de l'utilisateur.
 */
export const FUSEAU_HORAIRE_JOLENE = 'Europe/Paris';

export type DateJolene = Date | string | number;

export interface PartiesDateHeureParis {
  annee: number;
  mois: number;
  jour: number;
  heure: number;
  minute: number;
  seconde: number;
}

interface DateCivileParis {
  annee: number;
  mois: number;
  jour: number;
}

const formatteurPartiesParis = new Intl.DateTimeFormat('fr-FR', {
  timeZone: FUSEAU_HORAIRE_JOLENE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hourCycle: 'h23',
});

const JOURS_COURTS_FR = ['dim.', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.'] as const;
const JOURS_LONGS_FR = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'] as const;
const MOIS_COURTS_FR = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
] as const;
const MOIS_LONGS_FR = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
] as const;

function dateValide(value: DateJolene): Date {
  // Les anciennes données et plusieurs fixtures utilisent encore un ISO sans
  // suffixe (`Z` ou `+02:00`). Il représente alors une heure murale française,
  // pas une heure locale de l'appareil qui exécute le code.
  if (typeof value === 'string') {
    const sansFuseau = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?$/.exec(value);
    if (sansFuseau) {
      const instant = instantDateHeureParis({
        annee: Number(sansFuseau[1]),
        mois: Number(sansFuseau[2]),
        jour: Number(sansFuseau[3]),
        heure: Number(sansFuseau[4]),
        minute: Number(sansFuseau[5]),
        seconde: Number(sansFuseau[6] ?? 0),
      });
      const millisecondes = Number((sansFuseau[7] ?? '').padEnd(3, '0'));
      return millisecondes > 0
        ? new Date(instant.getTime() + millisecondes)
        : instant;
    }
  }

  const date = value instanceof Date ? new Date(value.getTime()) : new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new RangeError(`Date Jolene invalide: ${String(value)}`);
  }
  return date;
}

/** Convertit toute date Jolene en instant, y compris les ISO legacy sans offset. */
export function instantJolene(value: DateJolene): Date {
  return dateValide(value);
}

function nombrePartie(
  parties: Intl.DateTimeFormatPart[],
  type: Intl.DateTimeFormatPartTypes,
): number {
  const valeur = parties.find((partie) => partie.type === type)?.value;
  const nombre = Number(valeur);
  if (!Number.isFinite(nombre)) throw new RangeError(`Partie de date absente: ${type}`);
  return nombre;
}

/** Retourne les composantes civiles françaises d'un instant absolu. */
export function partiesDateHeureParis(value: DateJolene): PartiesDateHeureParis {
  const parties = formatteurPartiesParis.formatToParts(dateValide(value));
  return {
    annee: nombrePartie(parties, 'year'),
    mois: nombrePartie(parties, 'month'),
    jour: nombrePartie(parties, 'day'),
    heure: nombrePartie(parties, 'hour'),
    minute: nombrePartie(parties, 'minute'),
    seconde: nombrePartie(parties, 'second'),
  };
}

function dateCivileParis(value: DateJolene): DateCivileParis {
  const { annee, mois, jour } = partiesDateHeureParis(value);
  return { annee, mois, jour };
}

function ajouterJoursDateCivile(date: DateCivileParis, jours: number): DateCivileParis {
  // Midi UTC évite tout changement de date pendant la normalisation du
  // calendrier grégorien, y compris aux passages heure d'été/heure d'hiver.
  const resultat = new Date(Date.UTC(date.annee, date.mois - 1, date.jour + jours, 12));
  return {
    annee: resultat.getUTCFullYear(),
    mois: resultat.getUTCMonth() + 1,
    jour: resultat.getUTCDate(),
  };
}

function decalageParisMinutes(instant: Date): number {
  const parties = partiesDateHeureParis(instant);
  const commeUtc = Date.UTC(
    parties.annee,
    parties.mois - 1,
    parties.jour,
    parties.heure,
    parties.minute,
    parties.seconde,
  );
  return Math.round((commeUtc - Math.floor(instant.getTime() / 1000) * 1000) / 60_000);
}

/**
 * Convertit une date/heure murale française en instant absolu, DST compris.
 * Cette fonction est notamment utilisée pour les bornes de jours civils et
 * les champs HTML `datetime-local`, qui ne contiennent volontairement aucun
 * fuseau.
 */
export function instantDateHeureParis({
  annee,
  mois,
  jour,
  heure,
  minute,
  seconde,
}: PartiesDateHeureParis): Date {
  const cibleUtc = Date.UTC(annee, mois - 1, jour, heure, minute, seconde);
  let instant = new Date(cibleUtc);
  for (let iteration = 0; iteration < 3; iteration += 1) {
    instant = new Date(cibleUtc - decalageParisMinutes(instant) * 60_000);
  }

  // `Date` normalise silencieusement les dates civiles impossibles. C'est
  // particulièrement dangereux au passage a l'heure d'ete : 02:30 n'existe
  // pas a Paris le 29/03/2026 et etait auparavant transformee en une autre
  // heure. Un planning doit conserver exactement l'heure saisie ou la refuser.
  const obtenue = partiesDateHeureParis(instant);
  if (
    obtenue.annee !== annee
    || obtenue.mois !== mois
    || obtenue.jour !== jour
    || obtenue.heure !== heure
    || obtenue.minute !== minute
    || obtenue.seconde !== seconde
  ) {
    throw new RangeError(
      `Date/heure inexistante dans le fuseau ${FUSEAU_HORAIRE_JOLENE}: `
      + `${String(annee).padStart(4, '0')}-${String(mois).padStart(2, '0')}-${String(jour).padStart(2, '0')}T`
      + `${String(heure).padStart(2, '0')}:${String(minute).padStart(2, '0')}:${String(seconde).padStart(2, '0')}`,
    );
  }

  // Au retour à l'heure d'hiver, une heure telle que 02:30 désigne deux
  // instants différents. Sans offset ou choix explicite de l'occurrence, en
  // sélectionner une arbitrairement rendrait le planning contractuel ambigu.
  const correspondA = (candidate: Date) => {
    const parties = partiesDateHeureParis(candidate);
    return parties.annee === annee
      && parties.mois === mois
      && parties.jour === jour
      && parties.heure === heure
      && parties.minute === minute
      && parties.seconde === seconde;
  };
  if (correspondA(new Date(instant.getTime() - 3_600_000))
    || correspondA(new Date(instant.getTime() + 3_600_000))) {
    throw new RangeError(
      `Date/heure ambiguë dans le fuseau ${FUSEAU_HORAIRE_JOLENE}: `
      + `${String(annee).padStart(4, '0')}-${String(mois).padStart(2, '0')}-${String(jour).padStart(2, '0')}T`
      + `${String(heure).padStart(2, '0')}:${String(minute).padStart(2, '0')}:${String(seconde).padStart(2, '0')}`,
    );
  }
  return instant;
}

/** Interprète une valeur HTML `datetime-local` comme une heure de Paris. */
export function instantDepuisSaisieParis(value: string): Date {
  const correspondance = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(value);
  if (!correspondance) throw new RangeError(`Date/heure locale invalide: ${value}`);
  return instantDateHeureParis({
    annee: Number(correspondance[1]),
    mois: Number(correspondance[2]),
    jour: Number(correspondance[3]),
    heure: Number(correspondance[4]),
    minute: Number(correspondance[5]),
    seconde: Number(correspondance[6] ?? 0),
  });
}

/** Instant correspondant au début du jour civil français contenant `value`. */
export function debutJourParis(value: DateJolene): Date {
  const { annee, mois, jour } = dateCivileParis(value);
  return instantDateHeureParis({ annee, mois, jour, heure: 0, minute: 0, seconde: 0 });
}

/** Début du jour civil français situé `jours` jours après celui de `value`. */
export function ajouterJoursCivilsParis(value: DateJolene, jours: number): Date {
  const date = ajouterJoursDateCivile(dateCivileParis(value), jours);
  return instantDateHeureParis({ ...date, heure: 0, minute: 0, seconde: 0 });
}

/** Instant correspondant au premier jour du mois civil français à 00:00. */
export function debutMoisParis(value: DateJolene): Date {
  const { annee, mois } = dateCivileParis(value);
  return instantDateHeureParis({ annee, mois, jour: 1, heure: 0, minute: 0, seconde: 0 });
}

/** Premier jour à 00:00 du mois français situé `mois` mois plus loin. */
export function ajouterMoisCivilsParis(value: DateJolene, mois: number): Date {
  const date = dateCivileParis(value);
  const cible = new Date(Date.UTC(date.annee, date.mois - 1 + mois, 1, 12));
  return instantDateHeureParis({
    annee: cible.getUTCFullYear(),
    mois: cible.getUTCMonth() + 1,
    jour: 1,
    heure: 0,
    minute: 0,
    seconde: 0,
  });
}

/** Dernière milliseconde du mois civil français contenant `value`. */
export function finMoisParis(value: DateJolene): Date {
  return new Date(ajouterMoisCivilsParis(value, 1).getTime() - 1);
}

function lundiDateCivile(date: DateCivileParis): DateCivileParis {
  const jourSemaine = new Date(Date.UTC(date.annee, date.mois - 1, date.jour, 12)).getUTCDay();
  return ajouterJoursDateCivile(date, -(jourSemaine === 0 ? 6 : jourSemaine - 1));
}

/** Instant correspondant au lundi 00:00 français de la semaine de `value`. */
export function debutSemaineParis(value: DateJolene): Date {
  const lundi = lundiDateCivile(dateCivileParis(value));
  return instantDateHeureParis({ ...lundi, heure: 0, minute: 0, seconde: 0 });
}

/** Lundi 00:00 français de la semaine suivante. */
export function semaineSuivanteParis(value: DateJolene): Date {
  return ajouterJoursCivilsParis(debutSemaineParis(value), 7);
}

export function cleJourParis(value: DateJolene): string {
  const { annee, mois, jour } = dateCivileParis(value);
  return `${annee}-${String(mois).padStart(2, '0')}-${String(jour).padStart(2, '0')}`;
}

export function cleSemaineParis(value: DateJolene): string {
  return cleJourParis(debutSemaineParis(value));
}

export function memeJourParis(a: DateJolene, b: DateJolene): boolean {
  return cleJourParis(a) === cleJourParis(b);
}

export function memeMoisParis(a: DateJolene, b: DateJolene): boolean {
  const dateA = dateCivileParis(a);
  const dateB = dateCivileParis(b);
  return dateA.annee === dateB.annee && dateA.mois === dateB.mois;
}

/** Heure décimale française (ex. 8h30 = 8.5), utile aux grilles horaires. */
export function heureDecimaleParis(value: DateJolene): number {
  const { heure, minute } = partiesDateHeureParis(value);
  return heure + minute / 60;
}

function jourSemaineCivilParis(parties: PartiesDateHeureParis): number {
  return new Date(Date.UTC(parties.annee, parties.mois - 1, parties.jour, 12)).getUTCDay();
}

const TOKENS_FORMAT_PARIS = [
  'EEEE', 'yyyy', 'MMM', 'EEE', 'dd', 'MM', 'HH', 'mm', 'ss', 'd', 'M', 'H', 'm', 's',
] as const;

/**
 * Formate directement les composantes civiles Europe/Paris, sans jamais
 * construire une Date dans le fuseau de l'appareil. Le sous-ensemble de
 * jetons couvre les formats de planning Jolene ; les textes entre apostrophes
 * sont traités comme des littéraux, comme avec date-fns.
 */
export function formatParis(
  value: DateJolene,
  masque: string,
): string {
  const parties = partiesDateHeureParis(value);
  const jourSemaine = jourSemaineCivilParis(parties);
  const valeurs: Record<(typeof TOKENS_FORMAT_PARIS)[number], string> = {
    EEEE: JOURS_LONGS_FR[jourSemaine],
    EEE: JOURS_COURTS_FR[jourSemaine],
    MMM: MOIS_COURTS_FR[parties.mois - 1],
    yyyy: String(parties.annee).padStart(4, '0'),
    dd: String(parties.jour).padStart(2, '0'),
    MM: String(parties.mois).padStart(2, '0'),
    HH: String(parties.heure).padStart(2, '0'),
    mm: String(parties.minute).padStart(2, '0'),
    ss: String(parties.seconde).padStart(2, '0'),
    d: String(parties.jour),
    M: String(parties.mois),
    H: String(parties.heure),
    m: String(parties.minute),
    s: String(parties.seconde),
  };

  // MMMM doit être résolu avant MMM. Il est séparé du tableau typé ci-dessus
  // car les deux jetons commencent par la même séquence.
  const tokens = ['MMMM', ...TOKENS_FORMAT_PARIS] as const;
  let resultat = '';
  let index = 0;
  while (index < masque.length) {
    if (masque[index] === "'") {
      index += 1;
      while (index < masque.length) {
        if (masque[index] !== "'") {
          resultat += masque[index];
          index += 1;
          continue;
        }
        if (masque[index + 1] === "'") {
          resultat += "'";
          index += 2;
          continue;
        }
        index += 1;
        break;
      }
      continue;
    }

    const token = tokens.find((candidat) => masque.startsWith(candidat, index));
    if (token) {
      resultat += token === 'MMMM' ? MOIS_LONGS_FR[parties.mois - 1] : valeurs[token];
      index += token.length;
    } else {
      resultat += masque[index];
      index += 1;
    }
  }
  return resultat;
}

/** Valeur compatible avec un champ HTML `datetime-local`, en heure de Paris. */
export function valeurSaisieDateHeureParis(value: DateJolene = new Date()): string {
  return formatParis(value, "yyyy-MM-dd'T'HH:mm");
}
