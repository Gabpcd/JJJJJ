#!/usr/bin/env node
/**
 * Export des vecteurs golden pour le port Swift des règles pures (plan §4.1).
 *
 * Lit directement les modules TypeScript de `src/lib` et du planning candidat
 * (`src/components/planning/planning-candidat.ts`, `selection-serie-candidat.ts`)
 * par type stripping natif de Node, aucune dépendance supplémentaire, et écrit,
 * (lot 2, T2 : `synthese-presence-mission.ts`, `presencesSoignantUi.ts`,
 * `documentUpload.ts` rejoué avec `File` de Node, `documents.ts`, `contratMissionUi.ts`,
 * `signatureSmsStagingAdmission.ts` rejoué avec un client RPC simulé ; lot 2, T2b :
 * `documents-requis.ts` et `presences-soignant-listes.ts`, extraits par la PR web W1, #1112)
 * par règle, un JSON de vecteurs `{ name, input, expected }` dans
 * `ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/Resources/golden/`.
 * Un hook `module.register()` résout l'alias `@/lib/<module>` et les imports
 * relatifs sans extension de ces modules (lot 1, T2).
 *
 * Les vecteurs proviennent des tests vitest existants ET de grilles
 * systématiques (changements d'heure Europe/Paris, fins de mois, années
 * bissextiles, pauses, créneaux chevauchant minuit, fenêtre de 15 minutes du
 * pointage). La sortie est déterministe : horloge toujours explicite, fuseau du
 * processus forcé sur Europe/Paris, vecteurs triés par nom, noms uniques.
 *
 * Prérequis : Node >= 22.6 (type stripping). Sous Node 22.x le script se
 * relance seul avec `--experimental-strip-types` ; sous Node 23.6+ et 24 le
 * support est natif.
 *
 * Usage : node scripts/mobile/export-golden-vectors.mjs [--check]
 *   --check : ne réécrit rien, échoue si les fichiers existants diffèrent.
 */
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { register } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Le formateur de mission lit l'heure locale du processus (`getHours`) : le
// fuseau doit être celui de la France avant toute construction de Date.
process.env.TZ = 'Europe/Paris';

const [major, minor] = process.versions.node.split('.').map(Number);
if (!process.features.typescript) {
  if (major < 22 || (major === 22 && minor < 6)) {
    console.error('Node >= 22.6 requis (type stripping natif). Version locale :', process.versions.node);
    process.exit(2);
  }
  const relance = spawnSync(process.execPath, ['--experimental-strip-types', ...process.argv.slice(1)], {
    stdio: 'inherit',
    env: process.env,
  });
  process.exit(relance.status ?? 1);
}

const RACINE = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DOSSIER_SORTIE = resolve(
  RACINE,
  'ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/Resources/golden',
);
const MODE_CHECK = process.argv.includes('--check');

// ---------------------------------------------------------------------------
// date-fns réel (format + locale fr), celui que `src/lib/format-mission.ts`
// utilise en production. Aucun shim : les vecteurs comparent Swift à la
// dépendance réelle, résolue depuis node_modules (`npm ci` avant l'export).
// ---------------------------------------------------------------------------
try {
  await import('date-fns');
  await import('date-fns/locale');
} catch (erreur) {
  console.error("date-fns introuvable : exécutez `npm ci` avant l'export (les vecteurs format-mission doivent être produits contre la dépendance réelle, jamais contre un shim).", String(erreur?.message ?? erreur));
  process.exit(2);
}

// ---------------------------------------------------------------------------
// Résolution des imports du planning candidat (lot 1, T2)
// ---------------------------------------------------------------------------
// `planning-candidat.ts` et `completude-planning-mission.ts` importent
// `@/lib/<module>` (alias Vite) ; `selection-serie-candidat.ts` importe
// './planning-candidat' sans extension. Le chargeur ESM de Node ne connaît ni
// l'alias ni la résolution sans extension : ce hook les traduit vers le fichier
// `.ts` réel, qui est le même module que celui chargé par `lib()` ci-dessous
// (une seule instance de `date-heure-paris`). Tout autre alias `@/` est refusé
// explicitement : une règle golden reste pure (ni client Supabase ni React).
const HOOK_RESOLUTION = `
let racineSrc = null;
const AVEC_EXTENSION = /\\.[cm]?[jt]sx?$/;
export async function initialize(donnees) {
  racineSrc = donnees.racineSrc;
}
export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith('@/')) {
    if (!specifier.startsWith('@/lib/')) {
      throw new Error('export golden : alias « ' + specifier + ' » refusé depuis ' + context.parentURL
        + ' (seul @/lib/<module> est résolu : une règle golden reste pure).');
    }
    const cible = new URL(specifier.slice(2) + (AVEC_EXTENSION.test(specifier) ? '' : '.ts'), racineSrc);
    return nextResolve(cible.href, context);
  }
  const relatif = specifier.startsWith('./') || specifier.startsWith('../');
  const parentTs = typeof context.parentURL === 'string'
    && context.parentURL.startsWith(racineSrc) && context.parentURL.endsWith('.ts');
  if (relatif && parentTs && !AVEC_EXTENSION.test(specifier)) {
    return nextResolve(specifier + '.ts', context);
  }
  return nextResolve(specifier, context);
}
`;
register(`data:text/javascript,${encodeURIComponent(HOOK_RESOLUTION)}`, {
  parentURL: import.meta.url,
  data: { racineSrc: pathToFileURL(`${resolve(RACINE, 'src')}/`).href },
});

const lib = (nom) => import(pathToFileURL(resolve(RACINE, 'src/lib', nom)).href);
const planningComposant = (nom) => import(pathToFileURL(resolve(RACINE, 'src/components/planning', nom)).href);
const dateHeure = await lib('date-heure-paris.ts');
const formatMission = await lib('format-mission.ts');
const hebdo = await lib('heures-hebdomadaires-mission.ts');
const pointage = await lib('disponibilite-pointage.ts');
const planningCandidat = await planningComposant('planning-candidat.ts');
const selectionSerie = await planningComposant('selection-serie-candidat.ts');
const completude = await lib('completude-planning-mission.ts');
// Lot 2, T2 : pointage (synthèse, historique), justificatifs (classement, dispense de
// diplôme), contrats (affichage, admission OTP de recette STAGING).
const synthesePresence = await lib('synthese-presence-mission.ts');
const presencesUi = await lib('presencesSoignantUi.ts');
const documentUpload = await lib('documentUpload.ts');
const documentsRegles = await lib('documents.ts');
const constantes = await lib('constantes.ts');
const contratUi = await lib('contratMissionUi.ts');
const admissionSms = await lib('signatureSmsStagingAdmission.ts');
// Lot 2, T2b : les deux règles que la PR web W1 (#1112) a extraites des composants
// (exigences documentaires de `DocumentsSoignant.tsx`, listes de `PresencesSoignant.tsx`).
const documentsRequis = await lib('documents-requis.ts');
const presencesListes = await lib('presences-soignant-listes.ts');

// ---------------------------------------------------------------------------
// Outils
// ---------------------------------------------------------------------------
const iso = (d) => (d instanceof Date && Number.isFinite(d.getTime()) ? d.toISOString() : null);
const pad2 = (n) => String(n).padStart(2, '0');
const jourCivil = (annee, mois, jour) => `${annee}-${pad2(mois)}-${pad2(jour)}`;

/** Exécute `fn` et renvoie soit la valeur, soit `{ erreur }` typée. */
function capture(fn) {
  try {
    return fn();
  } catch (erreur) {
    const message = String(erreur?.message ?? erreur);
    if (/inexistante/.test(message)) return { erreur: 'INEXISTANTE' };
    if (/ambigu/.test(message)) return { erreur: 'AMBIGUE' };
    return { erreur: 'INVALIDE' };
  }
}

/** Dernier dimanche d'un mois (changements d'heure européens). */
function dernierDimanche(annee, mois) {
  for (let jour = 31; jour >= 25; jour -= 1) {
    const d = new Date(Date.UTC(annee, mois - 1, jour, 12));
    if (d.getUTCMonth() === mois - 1 && d.getUTCDay() === 0) return jour;
  }
  throw new Error('dernier dimanche introuvable');
}

function dernierJourDuMois(annee, mois) {
  return new Date(Date.UTC(annee, mois, 0, 12)).getUTCDate();
}

class Collecteur {
  constructor(regle) {
    this.regle = regle;
    this.vecteurs = [];
    this.noms = new Set();
    this.entrees = new Map();
    this.fusionnes = [];
  }

  ajoute(name, input, expected) {
    if (this.noms.has(name)) throw new Error(`${this.regle}: nom de vecteur dupliqué « ${name} »`);
    // Une entrée identique (même JSON) n'apporte aucune couverture : elle est fusionnée
    // avec le premier vecteur qui la porte (les cas vitest précèdent les grilles). Un
    // attendu différent pour la même entrée serait une incohérence de l'export.
    const cle = JSON.stringify(input);
    const existant = this.entrees.get(cle);
    if (existant) {
      if (JSON.stringify(existant.expected) !== JSON.stringify(expected)) {
        throw new Error(`${this.regle}: entrée identique avec attendus différents (« ${existant.name} », « ${name} »)`);
      }
      this.fusionnes.push(`${name} → ${existant.name}`);
      return;
    }
    this.noms.add(name);
    this.entrees.set(cle, { name, expected });
    this.vecteurs.push({ name, input, expected });
  }

  tries() {
    for (const fusion of this.fusionnes) console.log(`${this.regle}: entrée déjà couverte, vecteur fusionné ${fusion}`);
    return [...this.vecteurs].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  }
}

// ---------------------------------------------------------------------------
// Règle 1 : date-heure-paris
// ---------------------------------------------------------------------------
function vecteursDateHeureParis() {
  const c = new Collecteur('date-heure-paris');
  const fn = (fonction, args, calcul) => c.ajoute(
    `${fonction}/${args.__nom}`,
    { fonction, ...Object.fromEntries(Object.entries(args).filter(([k]) => k !== '__nom')) },
    capture(calcul),
  );

  // --- Issus des tests vitest -------------------------------------------
  fn('cleMoisParis', { __nom: 'vitest-fin-juillet-utc', valeur: '2026-07-31T22:30:00.000Z' },
    () => dateHeure.cleMoisParis('2026-07-31T22:30:00.000Z'));
  fn('formatParis', { __nom: 'vitest-lundi-31-aout', valeur: '2026-08-31T06:00:00.000Z', masque: "EEEE d MMMM yyyy 'à' HH:mm" },
    () => dateHeure.formatParis('2026-08-31T06:00:00.000Z', "EEEE d MMMM yyyy 'à' HH:mm"));
  fn('instantDepuisSaisieParis', { __nom: 'vitest-31-aout-08h', valeur: '2026-08-31T08:00' },
    () => iso(dateHeure.instantDepuisSaisieParis('2026-08-31T08:00')));
  fn('formatParis', { __nom: 'vitest-legacy-sans-offset', valeur: '2026-08-31T08:00:00', masque: "EEEE d MMMM yyyy 'à' HH:mm" },
    () => dateHeure.formatParis('2026-08-31T08:00:00', "EEEE d MMMM yyyy 'à' HH:mm"));
  fn('instantJolene', { __nom: 'vitest-legacy-sans-offset', valeur: '2026-08-31T08:00:00' },
    () => iso(dateHeure.instantJolene('2026-08-31T08:00:00')));
  fn('formatParis', { __nom: 'vitest-legacy-millisecondes', valeur: '2026-08-31T08:00:00.250', masque: 'HH:mm:ss' },
    () => dateHeure.formatParis('2026-08-31T08:00:00.250', 'HH:mm:ss'));
  fn('formatParis', { __nom: 'vitest-trou-dst-londres', valeur: '2026-03-29T00:30:00.000Z', masque: 'EEEE d MMMM yyyy · HH:mm' },
    () => dateHeure.formatParis('2026-03-29T00:30:00.000Z', 'EEEE d MMMM yyyy · HH:mm'));
  fn('instantDepuisSaisieParis', { __nom: 'vitest-inexistante-2026', valeur: '2026-03-29T02:30' },
    () => iso(dateHeure.instantDepuisSaisieParis('2026-03-29T02:30')));
  fn('instantDepuisSaisieParis', { __nom: 'vitest-ambigue-2026', valeur: '2026-10-25T02:30' },
    () => iso(dateHeure.instantDepuisSaisieParis('2026-10-25T02:30')));
  fn('instantDepuisSaisieParis', { __nom: 'vitest-avant-trou', valeur: '2026-03-29T01:59' },
    () => iso(dateHeure.instantDepuisSaisieParis('2026-03-29T01:59')));
  fn('instantDepuisSaisieParis', { __nom: 'vitest-apres-trou', valeur: '2026-03-29T03:00' },
    () => iso(dateHeure.instantDepuisSaisieParis('2026-03-29T03:00')));

  // --- Grille changements d'heure 2024 → 2028 ----------------------------
  for (const annee of [2024, 2025, 2026, 2027, 2028]) {
    for (const [mois, libelle] of [[3, 'mars'], [10, 'octobre']]) {
      const jour = dernierDimanche(annee, mois);
      const date = jourCivil(annee, mois, jour);
      const midi = `${date}T12:00:00.000Z`;
      const nom = `dst-${libelle}-${annee}`;

      fn('debutJourParis', { __nom: nom, valeur: midi }, () => iso(dateHeure.debutJourParis(midi)));
      fn('ajouterJoursCivilsParis', { __nom: `${nom}-plus-1`, valeur: midi, jours: 1 },
        () => iso(dateHeure.ajouterJoursCivilsParis(midi, 1)));
      fn('ajouterJoursCivilsParis', { __nom: `${nom}-moins-1`, valeur: midi, jours: -1 },
        () => iso(dateHeure.ajouterJoursCivilsParis(midi, -1)));
      fn('debutSemaineParis', { __nom: nom, valeur: midi }, () => iso(dateHeure.debutSemaineParis(midi)));
      fn('semaineSuivanteParis', { __nom: nom, valeur: midi }, () => iso(dateHeure.semaineSuivanteParis(midi)));

      for (const heure of ['01:00', '01:59', '02:00', '02:30', '02:59', '03:00', '03:30', '04:00']) {
        const saisie = `${date}T${heure}`;
        fn('instantDepuisSaisieParis', { __nom: `${nom}-${heure.replace(':', 'h')}`, valeur: saisie },
          () => iso(dateHeure.instantDepuisSaisieParis(saisie)));
      }
      for (const utc of ['00:30', '00:59', '01:00', '01:30', '01:59', '02:00']) {
        const instant = `${date}T${utc}:00.000Z`;
        fn('formatParis', { __nom: `${nom}-utc-${utc.replace(':', 'h')}`, valeur: instant, masque: 'EEEE d MMMM yyyy · HH:mm' },
          () => dateHeure.formatParis(instant, 'EEEE d MMMM yyyy · HH:mm'));
        fn('heureDecimaleParis', { __nom: `${nom}-utc-${utc.replace(':', 'h')}`, valeur: instant },
          () => dateHeure.heureDecimaleParis(instant));
      }
      fn('partiesDateHeureParis', { __nom: `${nom}-utc-01h30`, valeur: `${date}T01:30:45.000Z` },
        () => dateHeure.partiesDateHeureParis(`${date}T01:30:45.000Z`));
      fn('instantJolene', { __nom: `${nom}-legacy-02h30`, valeur: `${date}T02:30:00` },
        () => iso(dateHeure.instantJolene(`${date}T02:30:00`)));
    }
  }

  // --- Fins de mois 2026 + février bissextile ------------------------------
  const moisTestes = [
    ...Array.from({ length: 12 }, (_, i) => [2026, i + 1]),
    [2024, 2], [2028, 2], [2100, 2], [2000, 2],
  ];
  for (const [annee, mois] of moisTestes) {
    const dernier = dernierJourDuMois(annee, mois);
    const finMoisUtc = `${jourCivil(annee, mois, dernier)}T22:30:00.000Z`;
    const nom = `fin-mois-${annee}-${pad2(mois)}`;
    fn('cleMoisParis', { __nom: nom, valeur: finMoisUtc }, () => dateHeure.cleMoisParis(finMoisUtc));
    fn('cleJourParis', { __nom: nom, valeur: finMoisUtc }, () => dateHeure.cleJourParis(finMoisUtc));
    fn('finMoisParis', { __nom: nom, valeur: finMoisUtc }, () => iso(dateHeure.finMoisParis(finMoisUtc)));
    fn('debutMoisParis', { __nom: nom, valeur: finMoisUtc }, () => iso(dateHeure.debutMoisParis(finMoisUtc)));
    fn('ajouterMoisCivilsParis', { __nom: `${nom}-plus-1`, valeur: finMoisUtc, mois: 1 },
      () => iso(dateHeure.ajouterMoisCivilsParis(finMoisUtc, 1)));
    fn('ajouterMoisCivilsParis', { __nom: `${nom}-moins-13`, valeur: finMoisUtc, mois: -13 },
      () => iso(dateHeure.ajouterMoisCivilsParis(finMoisUtc, -13)));
    fn('memeMoisParis', { __nom: `${nom}-22h30-vs-23h30-utc`, a: finMoisUtc, b: `${jourCivil(annee, mois, dernier)}T23:30:00.000Z` },
      () => dateHeure.memeMoisParis(finMoisUtc, `${jourCivil(annee, mois, dernier)}T23:30:00.000Z`));
    fn('formatParis', { __nom: `${nom}-dernier-jour`, valeur: `${jourCivil(annee, mois, dernier)}T10:00:00.000Z`, masque: 'EEEE d MMMM yyyy' },
      () => dateHeure.formatParis(`${jourCivil(annee, mois, dernier)}T10:00:00.000Z`, 'EEEE d MMMM yyyy'));
  }

  // --- 29 février et bornes séculaires ------------------------------------
  for (const [nom, date] of [
    ['bissextile-2024', '2024-02-29'], ['bissextile-2028', '2028-02-29'],
    ['bissextile-2000', '2000-02-29'], ['non-bissextile-2100', '2100-02-28'],
    ['non-bissextile-2027', '2027-02-28'],
  ]) {
    const instant = `${date}T10:00:00.000Z`;
    fn('ajouterJoursCivilsParis', { __nom: `${nom}-plus-1`, valeur: instant, jours: 1 },
      () => iso(dateHeure.ajouterJoursCivilsParis(instant, 1)));
    fn('ajouterJoursCivilsParis', { __nom: `${nom}-plus-365`, valeur: instant, jours: 365 },
      () => iso(dateHeure.ajouterJoursCivilsParis(instant, 365)));
    fn('formatParis', { __nom: nom, valeur: instant, masque: 'EEE d MMM yyyy' },
      () => dateHeure.formatParis(instant, 'EEE d MMM yyyy'));
    fn('cleSemaineParis', { __nom: nom, valeur: instant }, () => dateHeure.cleSemaineParis(instant));
  }
  fn('instantDepuisSaisieParis', { __nom: '29-fevrier-2027-inexistant', valeur: '2027-02-29T10:00' },
    () => iso(dateHeure.instantDepuisSaisieParis('2027-02-29T10:00')));
  fn('instantDepuisSaisieParis', { __nom: '30-fevrier-2026-inexistant', valeur: '2026-02-30T10:00' },
    () => iso(dateHeure.instantDepuisSaisieParis('2026-02-30T10:00')));
  fn('instantDepuisSaisieParis', { __nom: 'mois-13-inexistant', valeur: '2026-13-01T10:00' },
    () => iso(dateHeure.instantDepuisSaisieParis('2026-13-01T10:00')));
  fn('instantDepuisSaisieParis', { __nom: 'format-invalide', valeur: '31/12/2026 10:00' },
    () => iso(dateHeure.instantDepuisSaisieParis('31/12/2026 10:00')));
  fn('instantDepuisSaisieParis', { __nom: 'avec-secondes', valeur: '2026-12-31T23:59:59' },
    () => iso(dateHeure.instantDepuisSaisieParis('2026-12-31T23:59:59')));
  fn('instantJolene', { __nom: 'chaine-invalide', valeur: 'pas une date' },
    () => iso(dateHeure.instantJolene('pas une date')));
  fn('instantJolene', { __nom: 'offset-plus-02', valeur: '2026-07-31T08:00:00+02:00' },
    () => iso(dateHeure.instantJolene('2026-07-31T08:00:00+02:00')));
  fn('instantJolene', { __nom: 'offset-plus-01-hiver', valeur: '2026-01-15T08:00:00+01:00' },
    () => iso(dateHeure.instantJolene('2026-01-15T08:00:00+01:00')));
  fn('instantJolene', { __nom: 'offset-postgres-microsecondes', valeur: '2026-07-31T08:00:00.123456+00:00' },
    () => iso(dateHeure.instantJolene('2026-07-31T08:00:00.123456+00:00')));
  fn('instantJolene', { __nom: 'legacy-sans-secondes', valeur: '2026-07-31T08:05' },
    () => iso(dateHeure.instantJolene('2026-07-31T08:05')));
  fn('instantJolene', { __nom: 'legacy-ms-1-chiffre', valeur: '2026-07-31T08:05:07.5' },
    () => iso(dateHeure.instantJolene('2026-07-31T08:05:07.5')));
  fn('instantJolene', { __nom: 'legacy-ms-2-chiffres', valeur: '2026-07-31T08:05:07.25' },
    () => iso(dateHeure.instantJolene('2026-07-31T08:05:07.25')));
  fn('instantJolene', { __nom: 'legacy-trou-dst', valeur: '2026-03-29T02:15:00' },
    () => iso(dateHeure.instantJolene('2026-03-29T02:15:00')));
  fn('instantJolene', { __nom: 'legacy-ambigu-dst', valeur: '2026-10-25T02:15:00' },
    () => iso(dateHeure.instantJolene('2026-10-25T02:15:00')));
  fn('instantJolene', { __nom: 'date-seule-utc', valeur: '2026-07-31' },
    () => iso(dateHeure.instantJolene('2026-07-31')));

  // --- Semaines : frontière d'année + semaine DST ---------------------------
  const semaines = [
    ['2026-12-28', '2026-12-29', '2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02', '2027-01-03'],
    ['2026-03-23', '2026-03-24', '2026-03-25', '2026-03-26', '2026-03-27', '2026-03-28', '2026-03-29'],
    ['2026-10-26', '2026-10-27', '2026-10-28', '2026-10-29', '2026-10-30', '2026-10-31', '2026-11-01'],
  ];
  for (const jours of semaines) {
    for (const jour of jours) {
      const instant = `${jour}T22:30:00.000Z`; // déjà le lendemain à Paris en été
      fn('debutSemaineParis', { __nom: `semaine-${jour}`, valeur: instant }, () => iso(dateHeure.debutSemaineParis(instant)));
      fn('cleSemaineParis', { __nom: `semaine-${jour}`, valeur: instant }, () => dateHeure.cleSemaineParis(instant));
      fn('semaineSuivanteParis', { __nom: `semaine-${jour}`, valeur: instant }, () => iso(dateHeure.semaineSuivanteParis(instant)));
    }
  }

  // --- Même jour / minuit Paris vs minuit UTC -------------------------------
  const paires = [
    ['ete-avant-minuit-paris', '2026-07-31T21:59:59.000Z', '2026-07-31T12:00:00.000Z', true],
    ['ete-apres-minuit-paris', '2026-07-31T22:00:00.000Z', '2026-07-31T12:00:00.000Z', false],
    ['hiver-avant-minuit-paris', '2026-01-31T22:59:59.000Z', '2026-01-31T12:00:00.000Z', true],
    ['hiver-apres-minuit-paris', '2026-01-31T23:00:00.000Z', '2026-01-31T12:00:00.000Z', false],
    ['legacy-vs-offset', '2026-07-31T23:30:00', '2026-07-31T21:30:00.000Z', true],
  ];
  for (const [nom, a, b] of paires) {
    fn('memeJourParis', { __nom: nom, a, b }, () => dateHeure.memeJourParis(a, b));
  }

  // --- Jetons de format ----------------------------------------------------
  const instantFormat = '2026-01-05T07:08:09.000Z'; // lundi 5 janvier 08:08:09 Paris
  const masques = [
    'yyyy-MM-dd HH:mm:ss', 'd/M/yyyy H:m:s', 'EEE d MMM', 'EEEE d MMMM yyyy', 'MMMM', 'MMM',
    "HH'h'mm", "HH'h'", "'jour' d 'à' HH'h'mm", "yyyy-MM-dd'T'HH:mm", "''", "d 'o''clock'", 'dd/MM/yyyy',
  ];
  masques.forEach((masque, index) => {
    fn('formatParis', { __nom: `jetons-${index}`, valeur: instantFormat, masque },
      () => dateHeure.formatParis(instantFormat, masque));
  });
  fn('formatParis', { __nom: 'jetons-ete-14h', valeur: '2026-07-14T12:00:00.000Z', masque: 'EEEE d MMMM yyyy HH:mm' },
    () => dateHeure.formatParis('2026-07-14T12:00:00.000Z', 'EEEE d MMMM yyyy HH:mm'));
  for (const [nom, valeur] of [
    ['hiver', '2026-01-15T07:05:00.000Z'], ['ete', '2026-07-15T06:05:00.000Z'], ['minuit-paris', '2026-07-14T22:00:00.000Z'],
  ]) {
    fn('valeurSaisieDateHeureParis', { __nom: nom, valeur }, () => dateHeure.valeurSaisieDateHeureParis(valeur));
  }

  // --- Parties + instant (aller-retour) ------------------------------------
  const partiesCas = [
    ['hiver', { annee: 2026, mois: 1, jour: 15, heure: 8, minute: 30, seconde: 0 }],
    ['ete', { annee: 2026, mois: 7, jour: 15, heure: 8, minute: 30, seconde: 15 }],
    ['minuit', { annee: 2026, mois: 7, jour: 15, heure: 0, minute: 0, seconde: 0 }],
    ['trou-dst', { annee: 2026, mois: 3, jour: 29, heure: 2, minute: 0, seconde: 0 }],
    ['ambigu-dst', { annee: 2026, mois: 10, jour: 25, heure: 2, minute: 59, seconde: 59 }],
    ['heure-24-normalisee', { annee: 2026, mois: 7, jour: 15, heure: 24, minute: 0, seconde: 0 }],
    ['29-fevrier-2024', { annee: 2024, mois: 2, jour: 29, heure: 23, minute: 59, seconde: 59 }],
  ];
  for (const [nom, parties] of partiesCas) {
    fn('instantDateHeureParis', { __nom: nom, parties }, () => iso(dateHeure.instantDateHeureParis(parties)));
  }
  for (const [nom, valeur] of [
    ['hiver', '2026-01-15T07:30:00.000Z'], ['ete', '2026-07-15T06:30:15.000Z'], ['fin-annee', '2026-12-31T23:30:00.000Z'],
  ]) {
    fn('partiesDateHeureParis', { __nom: nom, valeur }, () => dateHeure.partiesDateHeureParis(valeur));
  }

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 2 : format-mission
// ---------------------------------------------------------------------------
function vecteursFormatMission() {
  const c = new Collecteur('format-mission');
  const toutes = (nom, mission) => {
    c.ajoute(`estMissionDeNuit/${nom}`, { fonction: 'estMissionDeNuit', mission }, capture(() => formatMission.estMissionDeNuit(mission.debut_le)));
    c.ajoute(`estMultiJours/${nom}`, { fonction: 'estMultiJours', mission }, capture(() => formatMission.estMultiJours(mission)));
    c.ajoute(`nbJoursTravailles/${nom}`, { fonction: 'nbJoursTravailles', mission }, capture(() => formatMission.nbJoursTravailles(mission)));
    c.ajoute(`formatDateMission/${nom}`, { fonction: 'formatDateMission', mission }, capture(() => formatMission.formatDateMission(mission)));
    c.ajoute(`formatHorairesMission/${nom}`, { fonction: 'formatHorairesMission', mission }, capture(() => formatMission.formatHorairesMission(mission)));
    c.ajoute(`formatDureeCompacte/${nom}`, { fonction: 'formatDureeCompacte', mission }, capture(() => formatMission.formatDureeCompacte(mission)));
  };

  // Issus des tests vitest
  toutes('vitest-multi-creneaux-nuit', { debut_le: '2026-09-03T19:00:00+02:00', fin_le: '2026-09-04T19:00:00+02:00', duree_heures: 13, nb_creneaux: 2 });
  toutes('vitest-legacy-sans-creneaux', { debut_le: '2026-09-03T07:00:00+02:00', fin_le: '2026-09-04T19:00:00+02:00', duree_heures: 24, nb_creneaux: null });
  toutes('vitest-une-journee', { debut_le: '2026-09-03T08:00:00+02:00', fin_le: '2026-09-03T15:30:00+02:00', duree_heures: 7.5, nb_creneaux: 1 });

  // Journées simples : jour / nuit / minuit / pause déduite
  toutes('jour-08h-18h', { debut_le: '2026-07-02T08:00:00+02:00', fin_le: '2026-07-02T18:00:00+02:00', duree_heures: 10, nb_creneaux: 1 });
  toutes('jour-13h-21h-sans-duree', { debut_le: '2026-07-02T13:00:00+02:00', fin_le: '2026-07-02T21:00:00+02:00', duree_heures: null, nb_creneaux: null });
  toutes('jour-06h45-14h15', { debut_le: '2026-07-02T06:45:00+02:00', fin_le: '2026-07-02T14:15:00+02:00', duree_heures: 7.5, nb_creneaux: 1 });
  toutes('jour-duree-string', { debut_le: '2026-07-02T08:00:00+02:00', fin_le: '2026-07-02T15:30:00+02:00', duree_heures: '7.5', nb_creneaux: 1 });
  toutes('jour-duree-string-vide', { debut_le: '2026-07-02T08:00:00+02:00', fin_le: '2026-07-02T15:30:00+02:00', duree_heures: '', nb_creneaux: 1 });
  toutes('jour-pause-deduite', { debut_le: '2026-07-02T08:00:00+02:00', fin_le: '2026-07-02T18:00:00+02:00', duree_heures: 9, nb_creneaux: 1 });
  toutes('jour-duree-tiers', { debut_le: '2026-07-02T08:00:00+02:00', fin_le: '2026-07-02T15:20:00+02:00', duree_heures: 7.3333, nb_creneaux: 1 });
  toutes('jour-debut-07h-limite-jour', { debut_le: '2026-07-02T07:00:00+02:00', fin_le: '2026-07-02T15:00:00+02:00', duree_heures: 8, nb_creneaux: 1 });
  toutes('nuit-06h59-limite-nuit', { debut_le: '2026-07-02T06:59:00+02:00', fin_le: '2026-07-02T14:59:00+02:00', duree_heures: 8, nb_creneaux: 1 });
  toutes('nuit-20h00-limite-nuit', { debut_le: '2026-07-02T20:00:00+02:00', fin_le: '2026-07-03T06:00:00+02:00', duree_heures: 10, nb_creneaux: 1 });
  toutes('jour-19h59-limite-jour', { debut_le: '2026-07-02T19:59:00+02:00', fin_le: '2026-07-03T05:59:00+02:00', duree_heures: 10, nb_creneaux: 1 });
  toutes('nuit-23h30-00h30', { debut_le: '2026-07-02T23:30:00+02:00', fin_le: '2026-07-03T00:30:00+02:00', duree_heures: 1, nb_creneaux: 1 });
  toutes('nuit-utc-en-ete', { debut_le: '2026-07-02T19:00:00.000Z', fin_le: '2026-07-03T05:00:00.000Z', duree_heures: 10, nb_creneaux: 1 });
  toutes('jour-utc-en-hiver', { debut_le: '2026-01-12T07:00:00.000Z', fin_le: '2026-01-12T15:00:00.000Z', duree_heures: 8, nb_creneaux: 1 });
  toutes('legacy-sans-offset', { debut_le: '2026-09-03T08:00:00', fin_le: '2026-09-03T15:30:00', duree_heures: 7.5, nb_creneaux: 1 });
  toutes('plage-24h-exactes', { debut_le: '2026-07-02T08:00:00+02:00', fin_le: '2026-07-03T08:00:00+02:00', duree_heures: 24, nb_creneaux: null });
  toutes('plage-24h-plus-1min', { debut_le: '2026-07-02T08:00:00+02:00', fin_le: '2026-07-03T08:01:00+02:00', duree_heures: 24, nb_creneaux: null });
  toutes('jour-dst-mars-23h-reelles', { debut_le: '2026-03-28T20:00:00+01:00', fin_le: '2026-03-29T08:00:00+02:00', duree_heures: 11, nb_creneaux: 1 });
  toutes('jour-dst-octobre-25h-reelles', { debut_le: '2026-10-24T20:00:00+02:00', fin_le: '2026-10-25T08:00:00+01:00', duree_heures: 13, nb_creneaux: 1 });

  // Multi-jours
  toutes('multi-meme-mois-10-creneaux', { debut_le: '2026-07-20T13:00:00+02:00', fin_le: '2026-07-31T21:00:00+02:00', duree_heures: 80, nb_creneaux: 10 });
  toutes('multi-meme-mois-sans-creneaux', { debut_le: '2026-07-20T13:00:00+02:00', fin_le: '2026-07-31T21:00:00+02:00', duree_heures: 80, nb_creneaux: null });
  toutes('multi-meme-mois-sans-duree', { debut_le: '2026-07-20T13:00:00+02:00', fin_le: '2026-07-31T21:00:00+02:00', duree_heures: null, nb_creneaux: null });
  toutes('multi-mois-differents', { debut_le: '2026-07-28T07:00:00+02:00', fin_le: '2026-08-03T19:00:00+02:00', duree_heures: 60, nb_creneaux: 5 });
  toutes('multi-annees-differentes', { debut_le: '2026-12-28T07:00:00+01:00', fin_le: '2027-01-03T19:00:00+01:00', duree_heures: 48, nb_creneaux: null });
  toutes('multi-semaine-dst-mars', { debut_le: '2026-03-23T08:00:00+01:00', fin_le: '2026-03-30T16:00:00+02:00', duree_heures: 48, nb_creneaux: 6 });
  toutes('multi-nuits-4-creneaux', { debut_le: '2026-07-20T21:00:00+02:00', fin_le: '2026-07-24T07:00:00+02:00', duree_heures: 40, nb_creneaux: 4 });
  toutes('multi-nuits-sans-creneaux', { debut_le: '2026-07-20T21:00:00+02:00', fin_le: '2026-07-24T07:00:00+02:00', duree_heures: 40, nb_creneaux: null });
  toutes('multi-duree-string', { debut_le: '2026-07-20T13:00:00+02:00', fin_le: '2026-07-31T21:00:00+02:00', duree_heures: '80', nb_creneaux: 10 });
  toutes('multi-fin-mois-fevrier-bissextile', { debut_le: '2024-02-26T08:00:00+01:00', fin_le: '2024-03-01T16:00:00+01:00', duree_heures: 40, nb_creneaux: 5 });
  toutes('multi-heures-par-jour-decimales', { debut_le: '2026-07-20T08:00:00+02:00', fin_le: '2026-07-24T15:30:00+02:00', duree_heures: 37.5, nb_creneaux: null });
  toutes('multi-2-creneaux-sans-duree', { debut_le: '2026-09-03T19:00:00+02:00', fin_le: '2026-09-04T19:00:00+02:00', duree_heures: null, nb_creneaux: 2 });

  // Données incomplètes
  toutes('sans-debut', { debut_le: null, fin_le: '2026-07-02T18:00:00+02:00', duree_heures: 10, nb_creneaux: 1 });
  toutes('sans-fin', { debut_le: '2026-07-02T08:00:00+02:00', fin_le: null, duree_heures: 10, nb_creneaux: 1 });
  toutes('sans-rien', { debut_le: null, fin_le: null });

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 3 : heures-hebdomadaires-mission
// ---------------------------------------------------------------------------
function vecteursHeuresHebdomadaires() {
  const c = new Collecteur('heures-hebdomadaires-mission');
  const semaine = (s) => ({ cleSemaine: s.cleSemaine, debutSemaine: iso(s.debutSemaine), heures: s.heures });
  const semaines = (liste) => liste.map(semaine);
  const carte = (map) => Object.fromEntries([...map.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([k, v]) => [k, semaine(v)]));

  const mission = { id: 'mission-ete', debut_le: '2026-07-20T13:00:00+02:00', fin_le: '2026-07-31T21:00:00+02:00', duree_heures: 80 };
  const creneau = (jour, type = 'PREVISIONNEL', missionId = mission.id) => ({
    mission_id: missionId, debut: `${jour}T13:00:00+02:00`, fin: `${jour}T21:00:00+02:00`, est_pause: false, type_creneau: type,
  });

  const parSemaine = (nom, m, creneaux) => c.ajoute(`heuresMissionParSemaine/${nom}`,
    { fonction: 'heuresMissionParSemaine', mission: m, creneaux }, capture(() => semaines(hebdo.heuresMissionParSemaine(m, creneaux))));
  const disponible = (nom, m, creneaux) => c.ajoute(`planningMissionHebdomadaireDisponible/${nom}`,
    { fonction: 'planningMissionHebdomadaireDisponible', mission: m, creneaux }, capture(() => hebdo.planningMissionHebdomadaireDisponible(m, creneaux)));
  const addition = (nom, missions, creneaux) => c.ajoute(`additionnerHeuresParSemaine/${nom}`,
    { fonction: 'additionnerHeuresParSemaine', missions, creneaux }, capture(() => carte(hebdo.additionnerHeuresParSemaine(missions, creneaux))));
  const additionSalariee = (nom, missions, creneaux) => c.ajoute(`additionnerHeuresSalarieesParSemaine/${nom}`,
    { fonction: 'additionnerHeuresSalarieesParSemaine', missions, creneaux }, capture(() => carte(hebdo.additionnerHeuresSalarieesParSemaine(missions, creneaux))));

  // --- Issus des tests vitest ---------------------------------------------
  const dixJours = ['2026-07-20', '2026-07-21', '2026-07-22', '2026-07-23', '2026-07-24',
    '2026-07-27', '2026-07-28', '2026-07-29', '2026-07-30', '2026-07-31'];
  parSemaine('vitest-40h-plus-40h', mission, dixJours.map((j) => creneau(j)));
  parSemaine('vitest-pas-de-double-effectif', mission, [creneau('2026-07-20'), creneau('2026-07-20', 'EFFECTIF')]);
  parSemaine('vitest-terminee-effectif', { ...mission, statut: 'TERMINEE' }, [
    creneau('2026-07-20'), { ...creneau('2026-07-20', 'EFFECTIF'), fin: '2026-07-20T20:00:00+02:00' },
  ]);
  const nuitLundi = { ...mission, debut_le: '2026-07-26T20:00:00+02:00', fin_le: '2026-07-27T08:00:00+02:00', duree_heures: 12 };
  parSemaine('vitest-nuit-franchit-lundi', nuitLundi, [{
    mission_id: mission.id, debut: '2026-07-26T20:00:00+02:00', fin: '2026-07-27T08:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL',
  }]);
  const autre = { ...mission, id: 'mission-existante', duree_heures: 8 };
  addition('vitest-deux-missions', [mission, autre], [creneau('2026-07-20'), creneau('2026-07-20', 'PREVISIONNEL', autre.id)]);
  parSemaine('vitest-multi-creneaux-sans-lignes', { ...mission, nb_creneaux: 10 }, []);
  const pause = { mission_id: mission.id, debut: '2026-07-20T16:00:00+02:00', fin: '2026-07-20T16:30:00+02:00', est_pause: true, type_creneau: 'PREVISIONNEL' };
  const missionAvecPause = { ...mission, nb_creneaux: 2 };
  disponible('vitest-pause-incomplet', missionAvecPause, [creneau('2026-07-20'), pause]);
  parSemaine('vitest-pause-incomplet', missionAvecPause, [creneau('2026-07-20'), pause]);
  disponible('vitest-pause-complet', missionAvecPause, [creneau('2026-07-20'), creneau('2026-07-21'), pause]);
  parSemaine('vitest-pause-complet', missionAvecPause, [creneau('2026-07-20'), creneau('2026-07-21'), pause]);
  const salariee = { ...mission, id: 'mission-salariee', type_contrat_applique: 'SALARIE' };
  const liberale = { ...mission, id: 'mission-liberale', type_contrat_applique: 'LIBERAL' };
  additionSalariee('vitest-exclut-liberale', [salariee, liberale], [
    creneau('2026-07-20', 'PREVISIONNEL', salariee.id), creneau('2026-07-20', 'PREVISIONNEL', liberale.id),
  ]);

  // --- Semaines civiles : DST, frontière d'année, bissextile -------------
  const jours = [
    '2026-03-23', '2026-03-24', '2026-03-25', '2026-03-26', '2026-03-27', '2026-03-28', '2026-03-29',
    '2026-10-26', '2026-10-27', '2026-10-28', '2026-10-29', '2026-10-30', '2026-10-31', '2026-11-01',
    '2026-12-28', '2026-12-31', '2027-01-01', '2027-01-03',
    '2024-02-26', '2024-02-29', '2024-03-03',
  ];
  for (const jour of jours) {
    const instant = `${jour}T22:30:00.000Z`;
    c.ajoute(`debutSemaineCivile/${jour}`, { fonction: 'debutSemaineCivile', valeur: instant },
      capture(() => iso(hebdo.debutSemaineCivile(new Date(instant)))));
    c.ajoute(`cleSemaineCivile/${jour}`, { fonction: 'cleSemaineCivile', valeur: instant },
      capture(() => hebdo.cleSemaineCivile(new Date(instant))));
    c.ajoute(`semaineSuivante/${jour}`, { fonction: 'semaineSuivante', valeur: instant },
      capture(() => iso(hebdo.semaineSuivante(new Date(instant)))));
  }

  // --- Créneaux traversant un changement d'heure ou minuit ----------------
  const slot = (debut, fin, extra = {}) => ({ mission_id: mission.id, debut, fin, est_pause: false, type_creneau: 'PREVISIONNEL', ...extra });
  parSemaine('dst-mars-nuit-11h-reelles', { ...mission, debut_le: '2026-03-28T20:00:00+01:00', fin_le: '2026-03-29T08:00:00+02:00', duree_heures: 11 },
    [slot('2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00')]);
  parSemaine('dst-octobre-nuit-13h-reelles', { ...mission, debut_le: '2026-10-24T20:00:00+02:00', fin_le: '2026-10-25T08:00:00+01:00', duree_heures: 13 },
    [slot('2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00')]);
  parSemaine('dst-mars-lundi-suivant', { ...mission, debut_le: '2026-03-29T20:00:00+02:00', fin_le: '2026-03-30T08:00:00+02:00', duree_heures: 12 },
    [slot('2026-03-29T20:00:00+02:00', '2026-03-30T08:00:00+02:00')]);
  parSemaine('dst-octobre-lundi-suivant', { ...mission, debut_le: '2026-10-25T20:00:00+01:00', fin_le: '2026-10-26T08:00:00+01:00', duree_heures: 12 },
    [slot('2026-10-25T20:00:00+01:00', '2026-10-26T08:00:00+01:00')]);
  parSemaine('frontiere-annee-dimanche-lundi', { ...mission, debut_le: '2027-01-03T20:00:00+01:00', fin_le: '2027-01-04T08:00:00+01:00', duree_heures: 12 },
    [slot('2027-01-03T20:00:00+01:00', '2027-01-04T08:00:00+01:00')]);
  parSemaine('creneau-de-3-semaines', { ...mission, debut_le: '2026-07-05T20:00:00+02:00', fin_le: '2026-07-20T08:00:00+02:00', duree_heures: 348 },
    [slot('2026-07-05T20:00:00+02:00', '2026-07-20T08:00:00+02:00')]);
  parSemaine('creneau-exactement-minuit-lundi', { ...mission, debut_le: '2026-07-26T22:00:00+02:00', fin_le: '2026-07-27T00:00:00+02:00', duree_heures: 2 },
    [slot('2026-07-26T22:00:00+02:00', '2026-07-27T00:00:00+02:00')]);
  parSemaine('creneau-debut-minuit-lundi', { ...mission, debut_le: '2026-07-27T00:00:00+02:00', fin_le: '2026-07-27T02:00:00+02:00', duree_heures: 2 },
    [slot('2026-07-27T00:00:00+02:00', '2026-07-27T02:00:00+02:00')]);
  parSemaine('creneau-utc-minuit-lundi-paris', { ...mission, debut_le: '2026-07-26T21:00:00.000Z', fin_le: '2026-07-27T03:00:00.000Z', duree_heures: 6 },
    [slot('2026-07-26T21:00:00.000Z', '2026-07-27T03:00:00.000Z')]);
  parSemaine('creneau-minutes-arrondi-2-decimales', { ...mission, duree_heures: 7.75 },
    [slot('2026-07-20T13:00:00+02:00', '2026-07-20T20:45:00+02:00'), slot('2026-07-21T13:00:00+02:00', '2026-07-21T20:20:00+02:00')]);

  // --- Filtrage des créneaux de référence ---------------------------------
  parSemaine('creneau-fin-null-ignore', mission, [slot('2026-07-20T13:00:00+02:00', null)]);
  parSemaine('creneau-fin-null-plus-un-complet', mission, [slot('2026-07-20T13:00:00+02:00', null), creneau('2026-07-21')]);
  parSemaine('creneau-fin-avant-debut-ignore', mission, [slot('2026-07-20T21:00:00+02:00', '2026-07-20T13:00:00+02:00')]);
  parSemaine('creneau-date-invalide-ignore', mission, [slot('pas une date', '2026-07-20T21:00:00+02:00')]);
  parSemaine('creneau-autre-mission-ignore', mission, [creneau('2026-07-20', 'PREVISIONNEL', 'autre-mission')]);
  parSemaine('creneau-sans-mission-id-ignore', mission, [{ debut: '2026-07-20T13:00:00+02:00', fin: '2026-07-20T21:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' }]);
  parSemaine('effectif-seul-repli', mission, [creneau('2026-07-20', 'EFFECTIF')]);
  parSemaine('pause-seule-previsionnelle-repli-effectif', mission, [pause, creneau('2026-07-20', 'EFFECTIF')]);
  parSemaine('terminee-sans-effectif-travail', { ...mission, statut: 'TERMINEE' }, [creneau('2026-07-20'), { ...pause, type_creneau: 'EFFECTIF' }]);
  parSemaine('terminee-effectif-fin-null', { ...mission, statut: 'TERMINEE' }, [creneau('2026-07-20'), slot('2026-07-20T13:00:00+02:00', null, { type_creneau: 'EFFECTIF' })]);
  parSemaine('en-cours-ignore-effectif-partiel', { ...mission, statut: 'EN_COURS' }, [creneau('2026-07-20'), { ...creneau('2026-07-20', 'EFFECTIF'), fin: '2026-07-20T18:00:00+02:00' }]);
  parSemaine('nb-creneaux-2-une-ligne', { ...mission, nb_creneaux: 2 }, [creneau('2026-07-20')]);
  parSemaine('nb-creneaux-2-trois-lignes', { ...mission, nb_creneaux: 2 }, [creneau('2026-07-20'), creneau('2026-07-21'), creneau('2026-07-22')]);
  parSemaine('nb-creneaux-1-sans-ligne-repli-duree', { ...mission, nb_creneaux: 1 }, []);
  parSemaine('nb-creneaux-null-sans-ligne-repli-duree', mission, []);
  parSemaine('repli-duree-string', { ...mission, duree_heures: '8' }, []);
  parSemaine('repli-duree-zero', { ...mission, duree_heures: 0 }, []);
  parSemaine('repli-duree-null', { ...mission, duree_heures: null }, []);
  parSemaine('repli-duree-invalide', { ...mission, duree_heures: 'abc' }, []);
  parSemaine('repli-debut-invalide', { ...mission, debut_le: 'pas une date' }, []);
  parSemaine('repli-debut-dimanche-soir', { ...mission, debut_le: '2026-07-26T22:30:00.000Z', duree_heures: 8 }, []);
  parSemaine('repli-debut-dst-hiver', { ...mission, debut_le: '2026-10-25T00:30:00.000Z', duree_heures: 8 }, []);

  disponible('ponctuelle-sans-ligne', mission, []);
  disponible('ponctuelle-ligne-ouverte', mission, [slot('2026-07-20T13:00:00+02:00', null)]);
  disponible('ponctuelle-ligne-complete', mission, [creneau('2026-07-20')]);
  disponible('ponctuelle-pause-seule', mission, [pause]);
  disponible('multi-sans-ligne', { ...mission, nb_creneaux: 3 }, []);
  disponible('multi-lignes-incompletes', { ...mission, nb_creneaux: 3 }, [creneau('2026-07-20'), creneau('2026-07-21')]);
  disponible('multi-lignes-completes', { ...mission, nb_creneaux: 3 }, [creneau('2026-07-20'), creneau('2026-07-21'), creneau('2026-07-22')]);
  disponible('multi-effectif-seul', { ...mission, nb_creneaux: 2 }, [creneau('2026-07-20', 'EFFECTIF'), creneau('2026-07-21', 'EFFECTIF')]);

  addition('vide', [], []);
  addition('trois-missions-deux-semaines', [mission, autre, { ...mission, id: 'm3', duree_heures: 12 }], [
    creneau('2026-07-20'), creneau('2026-07-27', 'PREVISIONNEL', autre.id), slot('2026-07-26T20:00:00+02:00', '2026-07-27T08:00:00+02:00', { mission_id: 'm3' }),
  ]);
  addition('repli-duree-sans-lignes', [mission, { ...mission, id: 'm2', duree_heures: 4 }], []);
  additionSalariee('toutes-liberales', [liberale, { ...liberale, id: 'l2' }], [creneau('2026-07-20', 'PREVISIONNEL', liberale.id), creneau('2026-07-20', 'PREVISIONNEL', 'l2')]);
  additionSalariee('tous-sans-choix-compte', [{ ...mission, type_contrat_recherche: 'TOUS' }], [creneau('2026-07-20')]);

  // --- Résolution du régime : matrice systématique ------------------------
  const libelle = (v) => (v === null ? 'null' : v === undefined ? 'absent' : v === '' ? 'vide' : v.trim() === '' ? 'blanc' : v.trim().toLowerCase().replace(/\s+/g, '-') + (v !== v.trim() ? '-espaces' : ''));
  const appliques = [undefined, null, 'SALARIE', 'LIBERAL', ''];
  const choix = [undefined, null, 'LIBERAL', ' liberal ', 'SALARIE', ' '];
  const recherches = [undefined, null, 'LIBERAL', 'TOUS', 'SALARIE'];
  for (const applique of appliques) {
    for (const ch of choix) {
      for (const recherche of recherches) {
        const m = { ...mission };
        if (applique !== undefined) m.type_contrat_applique = applique;
        if (ch !== undefined) m.choix_contrat_soignant = ch;
        if (recherche !== undefined) m.type_contrat_recherche = recherche;
        const nom = `applique-${libelle(applique)}/choix-${libelle(ch)}/recherche-${libelle(recherche)}`;
        c.ajoute(`missionComptePourPlafond48h/${nom}`, { fonction: 'missionComptePourPlafond48h', mission: m },
          capture(() => hebdo.missionComptePourPlafond48h(m)));
        c.ajoute(`missionPlafond48hConditionnel/${nom}`, { fonction: 'missionPlafond48hConditionnel', mission: m },
          capture(() => hebdo.missionPlafond48hConditionnel(m)));
      }
    }
  }

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 4 : disponibilite-pointage
// ---------------------------------------------------------------------------
function vecteursDisponibilitePointage() {
  const c = new Collecteur('disponibilite-pointage');
  const creneau = (debut, fin, type_creneau = 'PREVISIONNEL', extra = {}) => ({ debut, fin, type_creneau, est_pause: false, ...extra });
  const dispo = (nom, args) => c.ajoute(`evaluerDisponibilitePointage/${nom}`,
    { fonction: 'evaluerDisponibilitePointage', ...args },
    capture(() => pointage.evaluerDisponibilitePointage({ ...args, maintenant: new Date(args.maintenant) })));
  const terminaison = (nom, args) => c.ajoute(`evaluerTerminaisonMission/${nom}`,
    { fonction: 'evaluerTerminaisonMission', ...args },
    capture(() => {
      const r = pointage.evaluerTerminaisonMission({ ...args, maintenant: new Date(args.maintenant) });
      return { peutTerminer: r.peutTerminer, motif: r.motif, finReference: iso(r.finReference) };
    }));
  const cloture = (nom, args) => c.ajoute(`evaluerClotureAdminMission/${nom}`,
    { fonction: 'evaluerClotureAdminMission', ...args },
    capture(() => {
      const t = pointage.evaluerTerminaisonMission({ ...args.terminaison, maintenant: new Date(args.terminaison.maintenant) });
      const r = pointage.evaluerClotureAdminMission({ terminaison: t, estAdmin: args.estAdmin, litigeActif: args.litigeActif });
      return { peutTerminer: r.peutTerminer, motif: r.motif, finReference: iso(r.finReference), clotureAnticipee: r.clotureAnticipee };
    }));

  // --- Issus des tests vitest ---------------------------------------------
  c.ajoute('ajouterRepliMissionPonctuelle/vitest-ponctuelle', {
    fonction: 'ajouterRepliMissionPonctuelle', creneaux: [], mission: { id: 'ponctuelle', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00' },
  }, capture(() => pointage.ajouterRepliMissionPonctuelle([], { id: 'ponctuelle', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00' })));
  c.ajoute('ajouterRepliMissionPonctuelle/vitest-longue', {
    fonction: 'ajouterRepliMissionPonctuelle', creneaux: [], mission: { id: 'longue', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-08-31T16:00:00+02:00' },
  }, capture(() => pointage.ajouterRepliMissionPonctuelle([], { id: 'longue', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-08-31T16:00:00+02:00' })));
  const contratsVitest = [
    { id: 'annule', statut: 'ANNULE', cree_le: '2026-07-31T10:00:00Z' },
    { id: 'attente', statut: 'EN_ATTENTE_SIGNATURES', cree_le: '2026-07-30T10:00:00Z' },
    { id: 'signe', statut: 'SIGNE_COMPLET', cree_le: '2026-07-01T10:00:00Z' },
  ];
  c.ajoute('choisirContratPointage/vitest-signe-prioritaire', { fonction: 'choisirContratPointage', contrats: contratsVitest },
    capture(() => pointage.choisirContratPointage(contratsVitest)?.id ?? null));
  c.ajoute('filtrerMissionsEnCours/vitest-en-cours-sans-presence', { fonction: 'filtrerMissionsEnCours', missions: [{ id: 'mission-longue', statut: 'EN_COURS' }] },
    capture(() => pointage.filtrerMissionsEnCours([{ id: 'mission-longue', statut: 'EN_COURS' }]).map((m) => m.id)));
  dispo('vitest-15-min-avant', { creneaux: [creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z')], contratStatut: 'SIGNE_COMPLET', maintenant: '2026-07-31T07:45:00.000Z' });
  dispo('vitest-avant-h-moins-15', { creneaux: [creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z')], contratStatut: 'SIGNE_COMPLET', maintenant: '2026-07-31T07:44:59.000Z' });
  dispo('vitest-entre-deux-creneaux', {
    creneaux: [creneau('2026-07-06T06:00:00.000Z', '2026-07-06T14:00:00.000Z'), creneau('2026-08-31T06:00:00.000Z', '2026-08-31T14:00:00.000Z')],
    contratStatut: 'SIGNE_COMPLET', maintenant: '2026-07-31T12:00:00.000Z',
  });
  dispo('vitest-contrat-manquant', { creneaux: [creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z')], contratStatut: null, maintenant: '2026-07-31T09:00:00.000Z' });
  dispo('vitest-segment-ouvert', { creneaux: [creneau('2026-07-31T08:00:00.000Z', null, 'EFFECTIF')], contratStatut: null, maintenant: '2026-07-31T18:00:00.000Z' });
  const nuit = creneau('2026-07-30T20:00:00.000Z', '2026-07-31T06:00:00.000Z');
  const lendemain = creneau('2026-08-01T08:00:00.000Z', '2026-08-01T16:00:00.000Z');
  c.ajoute('creneauChevauchePeriode/vitest-nuit-chevauche', { fonction: 'creneauChevauchePeriode', creneau: nuit, debutPeriode: '2026-07-31T00:00:00.000Z', finPeriode: '2026-08-01T00:00:00.000Z' },
    capture(() => pointage.creneauChevauchePeriode(nuit, new Date('2026-07-31T00:00:00.000Z'), new Date('2026-08-01T00:00:00.000Z'))));
  c.ajoute('prochainCreneauPointage/vitest-lendemain', { fonction: 'prochainCreneauPointage', creneaux: [nuit, lendemain], maintenant: '2026-07-31T12:00:00.000Z' },
    capture(() => pointage.prochainCreneauPointage([nuit, lendemain], new Date('2026-07-31T12:00:00.000Z'))));
  terminaison('vitest-segment-ouvert', {
    creneaux: [creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z'), creneau('2026-07-31T08:05:00.000Z', null, 'EFFECTIF')],
    finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z',
  });
  terminaison('vitest-apres-dernier-creneau', {
    creneaux: [creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z'), creneau('2026-07-31T08:05:00.000Z', '2026-07-31T15:55:00.000Z', 'EFFECTIF')],
    finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z',
  });
  terminaison('vitest-segment-ouvert-prioritaire', {
    creneaux: [creneau('2026-09-03T17:00:00.000Z', '2026-09-03T18:00:00.000Z'), creneau('2026-09-04T05:00:00.000Z', '2026-09-04T17:00:00.000Z'), creneau('2026-09-03T17:05:00.000Z', null, 'EFFECTIF')],
    finMission: '2026-09-04T17:00:00.000Z', maintenant: '2026-09-03T17:30:00.000Z',
  });
  const terminaisonLitige = {
    creneaux: [creneau('2026-09-03T17:00:00.000Z', '2026-09-03T18:00:00.000Z'), creneau('2026-09-04T05:00:00.000Z', '2026-09-04T17:00:00.000Z'), creneau('2026-09-03T17:05:00.000Z', '2026-09-03T17:25:00.000Z', 'EFFECTIF')],
    finMission: '2026-09-04T17:00:00.000Z', maintenant: '2026-09-03T17:30:00.000Z',
  };
  cloture('vitest-admin-litige', { terminaison: terminaisonLitige, estAdmin: true, litigeActif: true });
  cloture('vitest-non-admin-litige', { terminaison: terminaisonLitige, estAdmin: false, litigeActif: true });
  cloture('vitest-admin-sans-litige', { terminaison: terminaisonLitige, estAdmin: true, litigeActif: false });

  // --- Fenêtre de 15 minutes : grille fine -------------------------------
  const slot = creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z', 'PREVISIONNEL', { id: 'slot-jour' });
  const instants = [
    ['h-moins-16min', '2026-07-31T07:44:00.000Z'], ['h-moins-15min-1s', '2026-07-31T07:44:59.000Z'],
    ['h-moins-15min-1ms', '2026-07-31T07:44:59.999Z'], ['h-moins-15min-exact', '2026-07-31T07:45:00.000Z'],
    ['h-moins-14min-59s', '2026-07-31T07:45:01.000Z'], ['h-moins-1s', '2026-07-31T07:59:59.000Z'],
    ['h-exact', '2026-07-31T08:00:00.000Z'], ['h-plus-1s', '2026-07-31T08:00:01.000Z'], ['milieu', '2026-07-31T12:00:00.000Z'],
    ['fin-moins-1s', '2026-07-31T15:59:59.000Z'], ['fin-exacte', '2026-07-31T16:00:00.000Z'],
    ['fin-plus-1ms', '2026-07-31T16:00:00.001Z'], ['fin-plus-1s', '2026-07-31T16:00:01.000Z'], ['fin-plus-1h', '2026-07-31T17:00:00.000Z'],
  ];
  for (const [nom, maintenant] of instants) {
    for (const [libelle, contratStatut] of [['signe', 'SIGNE_COMPLET'], ['attente', 'EN_ATTENTE_SIGNATURES'], ['sans-contrat', null]]) {
      dispo(`fenetre-${nom}-${libelle}`, { creneaux: [slot], contratStatut, maintenant });
    }
    c.ajoute(`prochainCreneauPointage/fenetre-${nom}`, { fonction: 'prochainCreneauPointage', creneaux: [slot], maintenant },
      capture(() => pointage.prochainCreneauPointage([slot], new Date(maintenant))));
  }

  // --- Créneau de nuit traversant minuit Paris et le changement d'heure ---
  const nuitDst = creneau('2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00', 'PREVISIONNEL', { id: 'nuit-dst' });
  for (const [nom, maintenant] of [
    ['avant-fenetre', '2026-03-28T18:44:00.000Z'], ['ouverture-fenetre', '2026-03-28T18:45:00.000Z'],
    ['minuit-paris', '2026-03-28T23:00:00.000Z'], ['pendant-saut-dst', '2026-03-29T01:00:00.000Z'],
    ['fin-exacte', '2026-03-29T06:00:00.000Z'], ['apres-fin', '2026-03-29T06:00:01.000Z'],
  ]) {
    dispo(`nuit-dst-${nom}`, { creneaux: [nuitDst], contratStatut: 'SIGNE_COMPLET', maintenant });
  }
  const nuitHiver = creneau('2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00', 'PREVISIONNEL', { id: 'nuit-hiver' });
  for (const [nom, maintenant] of [
    ['heure-repetee-premiere', '2026-10-25T00:30:00.000Z'], ['heure-repetee-seconde', '2026-10-25T01:30:00.000Z'], ['fin-exacte', '2026-10-25T07:00:00.000Z'],
  ]) {
    dispo(`nuit-hiver-${nom}`, { creneaux: [nuitHiver], contratStatut: 'SIGNE_COMPLET', maintenant });
  }

  // --- Plusieurs créneaux, pauses, ordre non trié -------------------------
  const matin = creneau('2026-07-31T06:00:00.000Z', '2026-07-31T10:00:00.000Z', 'PREVISIONNEL', { id: 'matin' });
  const pauseMidi = creneau('2026-07-31T10:00:00.000Z', '2026-07-31T10:30:00.000Z', 'PREVISIONNEL', { id: 'pause', est_pause: true });
  const apresMidi = creneau('2026-07-31T10:30:00.000Z', '2026-07-31T14:30:00.000Z', 'PREVISIONNEL', { id: 'apres-midi' });
  const ouvert = creneau('2026-07-31T06:02:00.000Z', null, 'PREVISIONNEL', { id: 'ouvert' });
  const effectifFerme = creneau('2026-07-31T06:02:00.000Z', '2026-07-31T10:01:00.000Z', 'EFFECTIF', { id: 'eff-1' });
  const journee = [apresMidi, pauseMidi, matin];
  for (const [nom, maintanant] of [
    ['avant-matin', '2026-07-31T05:00:00.000Z'], ['fenetre-matin', '2026-07-31T05:45:00.000Z'], ['pendant-matin', '2026-07-31T08:00:00.000Z'],
    ['pendant-pause', '2026-07-31T10:10:00.000Z'], ['fenetre-apres-midi-dans-pause', '2026-07-31T10:16:00.000Z'],
    ['pendant-apres-midi', '2026-07-31T12:00:00.000Z'], ['apres-journee', '2026-07-31T15:00:00.000Z'],
  ]) {
    dispo(`journee-${nom}`, { creneaux: journee, contratStatut: 'SIGNE_COMPLET', maintenant: maintanant });
    c.ajoute(`prochainCreneauPointage/journee-${nom}`, { fonction: 'prochainCreneauPointage', creneaux: journee, maintenant: maintanant },
      capture(() => pointage.prochainCreneauPointage(journee, new Date(maintanant))));
  }
  dispo('journee-pause-seule-aucun-creneau', { creneaux: [pauseMidi], contratStatut: 'SIGNE_COMPLET', maintenant: '2026-07-31T10:10:00.000Z' });
  dispo('journee-previsionnel-ouvert-ignore', { creneaux: [ouvert], contratStatut: 'SIGNE_COMPLET', maintenant: '2026-07-31T08:00:00.000Z' });
  dispo('journee-effectif-ferme-puis-apres-midi', { creneaux: [...journee, effectifFerme], contratStatut: 'SIGNE_COMPLET', maintenant: '2026-07-31T12:00:00.000Z' });
  dispo('journee-deux-segments-ouverts-plus-recent', {
    creneaux: [creneau('2026-07-31T06:02:00.000Z', null, 'EFFECTIF', { id: 'eff-ancien' }), creneau('2026-07-31T10:31:00.000Z', null, 'EFFECTIF', { id: 'eff-recent' })],
    contratStatut: 'SIGNE_COMPLET', maintenant: '2026-07-31T12:00:00.000Z',
  });
  dispo('journee-pause-effective-ouverte-ignoree', {
    creneaux: [...journee, creneau('2026-07-31T10:00:00.000Z', null, 'EFFECTIF', { id: 'pause-eff', est_pause: true })],
    contratStatut: 'SIGNE_COMPLET', maintenant: '2026-07-31T10:05:00.000Z',
  });
  dispo('aucun-creneau-signe', { creneaux: [], contratStatut: 'SIGNE_COMPLET', maintenant: '2026-07-31T10:05:00.000Z' });
  dispo('aucun-creneau-sans-contrat', { creneaux: [], contratStatut: null, maintenant: '2026-07-31T10:05:00.000Z' });

  c.ajoute('creneauxPrevisionnels/tri-et-filtrage', { fonction: 'creneauxPrevisionnels', creneaux: [...journee, ouvert, effectifFerme] },
    capture(() => pointage.creneauxPrevisionnels([...journee, ouvert, effectifFerme])));
  c.ajoute('creneauxPrevisionnels/vide', { fonction: 'creneauxPrevisionnels', creneaux: [] }, capture(() => pointage.creneauxPrevisionnels([])));
  c.ajoute('creneauxPrevisionnels/ordre-stable-meme-debut', {
    fonction: 'creneauxPrevisionnels',
    creneaux: [creneau('2026-07-31T06:00:00.000Z', '2026-07-31T10:00:00.000Z', 'PREVISIONNEL', { id: 'b' }), creneau('2026-07-31T06:00:00.000Z', '2026-07-31T09:00:00.000Z', 'PREVISIONNEL', { id: 'a' })],
  }, capture(() => pointage.creneauxPrevisionnels([
    creneau('2026-07-31T06:00:00.000Z', '2026-07-31T10:00:00.000Z', 'PREVISIONNEL', { id: 'b' }), creneau('2026-07-31T06:00:00.000Z', '2026-07-31T09:00:00.000Z', 'PREVISIONNEL', { id: 'a' }),
  ])));

  // --- Repli mission ponctuelle --------------------------------------------
  const repli = (nom, creneaux, mission) => c.ajoute(`ajouterRepliMissionPonctuelle/${nom}`, { fonction: 'ajouterRepliMissionPonctuelle', creneaux, mission },
    capture(() => pointage.ajouterRepliMissionPonctuelle(creneaux, mission)));
  repli('24h-exactes', [], { id: 'm', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-08-01T08:00:00+02:00' });
  repli('24h-plus-1s', [], { id: 'm', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-08-01T08:00:01+02:00' });
  repli('nuit-dst-23h', [], { id: 'm', debut_le: '2026-03-28T20:00:00+01:00', fin_le: '2026-03-29T20:00:00+02:00' });
  repli('duree-nulle', [], { id: 'm', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T08:00:00+02:00' });
  repli('fin-avant-debut', [], { id: 'm', debut_le: '2026-07-31T16:00:00+02:00', fin_le: '2026-07-31T08:00:00+02:00' });
  repli('date-invalide', [], { id: 'm', debut_le: 'pas une date', fin_le: '2026-07-31T08:00:00+02:00' });
  repli('sans-id', [], { debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00' });
  repli('previsionnel-existant-inchange', [matin], { id: 'm', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00' });
  repli('pause-seule-ajoute-repli', [pauseMidi], { id: 'm', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00' });
  repli('effectif-seul-ajoute-repli', [effectifFerme], { id: 'm', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00' });

  // --- Chevauchement de période -------------------------------------------
  const chevauche = (nom, cr, debut, fin) => c.ajoute(`creneauChevauchePeriode/${nom}`, { fonction: 'creneauChevauchePeriode', creneau: cr, debutPeriode: debut, finPeriode: fin },
    capture(() => pointage.creneauChevauchePeriode(cr, new Date(debut), new Date(fin))));
  chevauche('fin-egale-debut-periode', matin, '2026-07-31T10:00:00.000Z', '2026-07-31T12:00:00.000Z');
  chevauche('debut-egal-fin-periode', matin, '2026-07-31T04:00:00.000Z', '2026-07-31T06:00:00.000Z');
  chevauche('inclus', matin, '2026-07-31T00:00:00.000Z', '2026-08-01T00:00:00.000Z');
  chevauche('englobe', matin, '2026-07-31T07:00:00.000Z', '2026-07-31T08:00:00.000Z');
  chevauche('pause-ignoree', pauseMidi, '2026-07-31T00:00:00.000Z', '2026-08-01T00:00:00.000Z');
  chevauche('effectif-ignore', effectifFerme, '2026-07-31T00:00:00.000Z', '2026-08-01T00:00:00.000Z');
  chevauche('fin-null-ignore', ouvert, '2026-07-31T00:00:00.000Z', '2026-08-01T00:00:00.000Z');
  chevauche('jour-civil-paris-ete', creneau('2026-07-31T21:30:00.000Z', '2026-08-01T05:00:00.000Z'), '2026-07-30T22:00:00.000Z', '2026-07-31T22:00:00.000Z');

  // --- Contrats ------------------------------------------------------------
  const contrats = (nom, liste) => c.ajoute(`choisirContratPointage/${nom}`, { fonction: 'choisirContratPointage', contrats: liste },
    capture(() => pointage.choisirContratPointage(liste)?.id ?? null));
  contrats('vide', []);
  contrats('tous-terminaux', [
    { id: 'a', statut: 'ANNULE' }, { id: 'b', statut: 'EXPIRE' }, { id: 'c', statut: 'REFUSE' }, { id: 'd', statut: 'RUPTURE_ETAB' }, { id: 'e', statut: 'RUPTURE_SOIGNANT' },
  ]);
  contrats('plus-recent-sans-signature', [
    { id: 'ancien', statut: 'EN_ATTENTE_SIGNATURES', cree_le: '2026-07-01T10:00:00Z' }, { id: 'recent', statut: 'EN_ATTENTE_SIGNATURES', cree_le: '2026-07-02T10:00:00Z' },
  ]);
  contrats('deux-signes-plus-recent', [
    { id: 'signe-ancien', statut: 'SIGNE_COMPLET', cree_le: '2026-07-01T10:00:00Z' }, { id: 'signe-recent', statut: 'SIGNE_COMPLET', cree_le: '2026-07-02T10:00:00Z' },
  ]);
  contrats('sans-cree-le-stable', [{ id: 'premier', statut: 'EN_ATTENTE_SIGNATURES' }, { id: 'second', statut: 'EN_ATTENTE_SIGNATURES' }]);
  contrats('cree-le-null-vs-date', [{ id: 'sans-date', statut: 'EN_ATTENTE_SIGNATURES', cree_le: null }, { id: 'avec-date', statut: 'EN_ATTENTE_SIGNATURES', cree_le: '2026-07-02T10:00:00Z' }]);
  contrats('signe-ancien-prime-sur-recent-non-signe', [
    { id: 'recent', statut: 'SIGNE_SOIGNANT', cree_le: '2026-07-31T10:00:00Z' }, { id: 'signe', statut: 'SIGNE_COMPLET', cree_le: '2026-01-01T10:00:00Z' },
  ]);
  contrats('statut-inconnu-conserve', [{ id: 'x', statut: 'BROUILLON', cree_le: '2026-07-31T10:00:00Z' }]);

  c.ajoute('filtrerMissionsEnCours/melange', { fonction: 'filtrerMissionsEnCours', missions: [{ id: 'a', statut: 'EN_COURS' }, { id: 'b', statut: 'TERMINEE' }, { id: 'c', statut: 'ASSIGNEE' }, { id: 'd', statut: 'EN_COURS' }] },
    capture(() => pointage.filtrerMissionsEnCours([{ id: 'a', statut: 'EN_COURS' }, { id: 'b', statut: 'TERMINEE' }, { id: 'c', statut: 'ASSIGNEE' }, { id: 'd', statut: 'EN_COURS' }]).map((m) => m.id)));
  c.ajoute('filtrerMissionsEnCours/vide', { fonction: 'filtrerMissionsEnCours', missions: [] }, capture(() => pointage.filtrerMissionsEnCours([]).map((m) => m.id)));

  // --- Terminaison ---------------------------------------------------------
  const prev = creneau('2026-07-31T08:00:00.000Z', '2026-07-31T16:00:00.000Z');
  const prev2 = creneau('2026-08-01T08:00:00.000Z', '2026-08-01T16:00:00.000Z');
  const effOk = creneau('2026-07-31T08:05:00.000Z', '2026-07-31T15:55:00.000Z', 'EFFECTIF');
  terminaison('planning-incomplet-prime', { creneaux: [prev, creneau('2026-08-01T08:00:00.000Z', null), creneau('2026-07-31T08:05:00.000Z', null, 'EFFECTIF')], finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-08-02T17:00:00.000Z' });
  terminaison('aucun-depart', { creneaux: [prev], finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' });
  terminaison('depart-par-presence-legacy', { creneaux: [prev], finMission: '2026-07-31T16:00:00.000Z', presences: [{ pointage_depart_le: '2026-07-31T15:50:00.000Z' }], maintenant: '2026-07-31T17:00:00.000Z' });
  terminaison('presence-sans-depart', { creneaux: [prev], finMission: '2026-07-31T16:00:00.000Z', presences: [{ pointage_depart_le: null }], maintenant: '2026-07-31T17:00:00.000Z' });
  terminaison('avant-dernier-creneau', { creneaux: [prev, prev2, effOk], finMission: '2026-08-01T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' });
  terminaison('fin-reference-exacte', { creneaux: [prev, prev2, effOk], finMission: '2026-08-01T16:00:00.000Z', maintenant: '2026-08-01T16:00:00.000Z' });
  terminaison('fin-reference-moins-1ms', { creneaux: [prev, prev2, effOk], finMission: '2026-08-01T16:00:00.000Z', maintenant: '2026-08-01T15:59:59.999Z' });
  terminaison('fin-reference-max-des-creneaux', { creneaux: [prev2, prev, effOk], finMission: '2026-07-01T00:00:00.000Z', maintenant: '2026-08-01T17:00:00.000Z' });
  terminaison('sans-previsionnel-fin-mission', { creneaux: [effOk], finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' });
  terminaison('sans-previsionnel-fin-mission-invalide', { creneaux: [effOk], finMission: 'pas une date', maintenant: '2026-07-31T17:00:00.000Z' });
  terminaison('pause-effective-ouverte-ignoree', { creneaux: [prev, effOk, creneau('2026-07-31T12:00:00.000Z', null, 'EFFECTIF', { est_pause: true })], finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' });
  terminaison('pause-previsionnelle-ouverte-ignoree', { creneaux: [prev, effOk, creneau('2026-07-31T12:00:00.000Z', null, 'PREVISIONNEL', { est_pause: true })], finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' });
  terminaison('vide', { creneaux: [], finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' });

  for (const estAdmin of [true, false]) {
    for (const litigeActif of [true, false]) {
      const suffixe = `${estAdmin ? 'admin' : 'non-admin'}-${litigeActif ? 'litige' : 'sans-litige'}`;
      cloture(`avant-dernier-creneau-${suffixe}`, { terminaison: { creneaux: [prev, prev2, effOk], finMission: '2026-08-01T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' }, estAdmin, litigeActif });
      cloture(`segment-ouvert-${suffixe}`, { terminaison: { creneaux: [prev, creneau('2026-07-31T08:05:00.000Z', null, 'EFFECTIF')], finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' }, estAdmin, litigeActif });
      cloture(`deja-terminable-${suffixe}`, { terminaison: { creneaux: [prev, effOk], finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' }, estAdmin, litigeActif });
      cloture(`aucun-depart-${suffixe}`, { terminaison: { creneaux: [prev], finMission: '2026-07-31T16:00:00.000Z', maintenant: '2026-07-31T17:00:00.000Z' }, estAdmin, litigeActif });
    }
  }

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règles 5 à 7 : planning candidat, sélection de série, complétude (lot 1, T2)
// ---------------------------------------------------------------------------

/**
 * `construirePlanningCandidat` lève (`instantJolene`) sur un créneau
 * PREVISIONNEL à date illisible, et `analyserSelectionSerie` avec lui. Le port
 * Swift échoue fermé à la place (planning non exact, écart assumé du lot 0
 * documenté dans `PlanningCandidat.swift` et couvert par `MissionsPlanningTests`).
 * Ce domaine n'a donc aucun vecteur : un vecteur dont le calcul web lève est
 * refusé ici, au lieu d'être exporté en `{ erreur }` qu'aucun port ne rejoue.
 */
function sansLevee(regle, name, valeur) {
  if (valeur && typeof valeur === 'object' && !Array.isArray(valeur)
      && Object.keys(valeur).length === 1 && 'erreur' in valeur) {
    throw new Error(`${regle}: « ${name} » lève côté web (${valeur.erreur}) : hors domaine golden, le port Swift échoue fermé sur une date illisible.`);
  }
  return valeur;
}

/**
 * Format filaire natif de `p_creneaux_confirmes` (blueprint lot 1, T2). Le web
 * envoie les chaînes lues telles quelles ; le port Swift envoie, depuis les
 * mêmes chaînes, l'instant UTC `yyyy-MM-dd'T'HH:mm:ss'Z'` sans fraction, que
 * `fn_valider_creneaux_mission_json` accepte (suffixe Z) et que
 * `fn_confirmer_action_planning_v1` compare en `timestamptz`. Une borne dont la
 * fraction de seconde n'est pas nulle (même au-delà de la milliseconde, que
 * `Date` tronque) n'est pas représentable sans changer l'instant comparé : la
 * liste entière est refusée (null), comme un planning non exact. L'oracle passe
 * par `instantJolene` du web : il confronte la conversion Swift à `Date`
 * (décalages, heure d'été, ISO legacy sans offset = heure murale française).
 */
function filaireSansFraction(valeur) {
  const fraction = /\.(\d+)/.exec(valeur);
  if (fraction && /[1-9]/.test(fraction[1])) return null;
  return dateHeure.instantJolene(valeur).toISOString().replace(/\.000Z$/, 'Z');
}

function creneauxFilaires(lus) {
  if (lus === null) return null;
  const filaires = lus.map(({ debut, fin }) => ({ debut: filaireSansFraction(debut), fin: filaireSansFraction(fin) }));
  return filaires.some((creneau) => creneau.debut === null || creneau.fin === null) ? null : filaires;
}

const resumePlanning = (p) => ({
  creneaux: p.creneaux,
  exact: p.exact,
  totalHeures: p.totalHeures,
  periodeEtendue: p.periodeEtendue,
  messageBlocage: p.messageBlocage,
});

const creneauPlanning = (id, debut, fin, extra = {}) => ({ id, debut, fin, est_pause: false, type_creneau: 'PREVISIONNEL', ...extra });
const journeePlanning = (id, date, extra = {}) => creneauPlanning(id, `${date}T08:00:00+02:00`, `${date}T16:00:00+02:00`, extra);

// Données des tests vitest, partagées par les trois règles.
const missionLongueVitest = { id: 'mission-longue', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-08-31T16:00:00+02:00', nb_creneaux: 2 };
const deuxCreneauxVitest = [
  { id: 'jour-1', mission_id: 'mission-longue', debut: '2026-07-06T08:00:00+02:00', fin: '2026-07-06T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
  { id: 'jour-2', mission_id: 'mission-longue', debut: '2026-08-31T08:00:00+02:00', fin: '2026-08-31T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
];

// ---------------------------------------------------------------------------
// Règle 5 : planning-candidat (src/components/planning/planning-candidat.ts)
// ---------------------------------------------------------------------------
function vecteursPlanningCandidat() {
  const c = new Collecteur('planning-candidat');
  const ajoute = (name, input, calcul) => c.ajoute(name, input, sansLevee('planning-candidat', name, capture(calcul)));
  const construire = (nom, args) => ajoute(`construirePlanningCandidat/${nom}`, { fonction: 'construirePlanningCandidat', ...args },
    () => resumePlanning(planningCandidat.construirePlanningCandidat(args.mission, args.creneaux, args.erreur)));
  const confirmes = (nom, mission) => {
    ajoute(`creneauxConfirmesPourAction/${nom}`, { fonction: 'creneauxConfirmesPourAction', mission },
      () => planningCandidat.creneauxConfirmesPourAction(mission));
    ajoute(`creneauxConfirmesFilaires/${nom}`, { fonction: 'creneauxConfirmesFilaires', mission },
      () => creneauxFilaires(planningCandidat.creneauxConfirmesPourAction(mission)));
  };
  const filtres = (nom, mission) => {
    for (const filtre of ['TOUS', 'JOUR', 'NUIT', 'WEEKEND']) {
      ajoute(`planningCorrespondAuFiltre/${nom}-${filtre.toLowerCase()}`, { fonction: 'planningCorrespondAuFiltre', mission, filtre },
        () => planningCandidat.planningCorrespondAuFiltre(mission, filtre));
    }
  };
  const horaires = (nom, debut, fin) => {
    const creneau = creneauPlanning('h', debut, fin);
    ajoute(`creneauContientNuit/${nom}`, { fonction: 'creneauContientNuit', creneau }, () => planningCandidat.creneauContientNuit(creneau));
    ajoute(`creneauChevaucheWeekend/${nom}`, { fonction: 'creneauChevaucheWeekend', creneau }, () => planningCandidat.creneauChevaucheWeekend(creneau));
  };

  // --- Issus des tests vitest (planning-candidat.test.tsx) ----------------
  construire('vitest-deux-journees-eloignees', { mission: { ...missionLongueVitest, creneaux_planifies: deuxCreneauxVitest } });
  construire('vitest-nuit-lendemain', {
    mission: {
      id: 'nuit', debut_le: '2026-07-06T20:00:00+02:00', fin_le: '2026-07-07T08:00:00+02:00', nb_creneaux: 1,
      creneaux_planifies: [{ debut: '2026-07-06T20:00:00+02:00', fin: '2026-07-07T08:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' }],
    },
  });
  construire('vitest-multi-incomplet', { mission: missionLongueVitest, creneaux: deuxCreneauxVitest.slice(0, 1) });
  construire('vitest-compteur-depasse', { mission: { ...missionLongueVitest, nb_creneaux: 1 }, creneaux: deuxCreneauxVitest });
  const ponctuelleVitest = { id: 'ponctuelle', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-06T16:00:00+02:00', nb_creneaux: 1 };
  construire('vitest-repli-ponctuel', { mission: ponctuelleVitest });
  filtres('vitest-nuit-jour-weekend', {
    ...missionLongueVitest,
    creneaux_planifies: [
      { debut: '2026-07-11T21:00:00+02:00', fin: '2026-07-12T07:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
      deuxCreneauxVitest[1],
    ],
  });
  construire('vitest-cible-creneaux-explicites', { mission: missionLongueVitest, creneaux: deuxCreneauxVitest });
  construire('vitest-entre-deux', { mission: { id: 'entre-deux', debut_le: '2026-07-20T08:00:00+02:00', fin_le: '2026-07-20T16:00:00+02:00', nb_creneaux: 1 } });
  construire('vitest-repos-court', { mission: { id: 'repos-court', debut_le: '2026-07-05T23:00:00+02:00', fin_le: '2026-07-05T23:30:00+02:00', nb_creneaux: 1 } });
  confirmes('vitest-recapitulatif-complet', { ...missionLongueVitest, creneaux_planifies: deuxCreneauxVitest });
  confirmes('vitest-recapitulatif-incomplet', { ...missionLongueVitest, creneaux_planifies: deuxCreneauxVitest.slice(0, 1) });

  // --- Compteur nb_creneaux, repli ponctuel, pauses, EFFECTIF -------------
  const base = { id: 'm', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-06T16:00:00+02:00' };
  const pause = creneauPlanning('pause', '2026-07-06T12:00:00+02:00', '2026-07-06T12:30:00+02:00', { est_pause: true });
  const effectif = journeePlanning('effectif', '2026-07-06', { type_creneau: 'EFFECTIF' });
  for (const [libelle, nb] of [['nb-absent', undefined], ['nb-null', null], ['nb-0', 0], ['nb-1', 1]]) {
    const m = { ...base };
    if (nb !== undefined) m.nb_creneaux = nb;
    construire(`repli-sans-ligne-${libelle}`, { mission: m });
    construire(`une-ligne-${libelle}`, { mission: m, creneaux: [creneauPlanning('l1', '2026-07-06T09:00:00+02:00', '2026-07-06T17:00:00+02:00')] });
    construire(`pause-seule-${libelle}`, { mission: m, creneaux: [pause] });
    construire(`effectif-seul-${libelle}`, { mission: m, creneaux: [effectif] });
    construire(`ligne-sans-fin-${libelle}`, { mission: m, creneaux: [creneauPlanning('ouvert', '2026-07-06T08:00:00+02:00', null)] });
  }
  const multi = { id: 'multi', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-08T16:00:00+02:00' };
  const trois = [journeePlanning('j3', '2026-07-08'), journeePlanning('j1', '2026-07-06'), journeePlanning('j2', '2026-07-07')];
  for (const nb of [1, 2, 3, 4]) construire(`trois-lignes-nb-${nb}`, { mission: { ...multi, nb_creneaux: nb }, creneaux: trois });
  construire('trois-lignes-nb-null', { mission: { ...multi, nb_creneaux: null }, creneaux: trois });
  construire('trois-lignes-plus-pause-et-effectif', { mission: { ...multi, nb_creneaux: 3 }, creneaux: [...trois, pause, effectif] });
  construire('ligne-sans-fin-parmi-trois', { mission: { ...multi, nb_creneaux: 3 }, creneaux: [trois[0], trois[1], creneauPlanning('ouvert', '2026-07-07T08:00:00+02:00', null)] });
  construire('ligne-fin-vide-parmi-trois', { mission: { ...multi, nb_creneaux: 3 }, creneaux: [trois[0], trois[1], creneauPlanning('vide', '2026-07-07T08:00:00+02:00', '')] });
  construire('pause-sans-fin-ignoree', { mission: { ...multi, nb_creneaux: 3 }, creneaux: [...trois, creneauPlanning('pause-ouverte', '2026-07-07T12:00:00+02:00', null, { est_pause: true })] });
  construire('meme-debut-ordre-stable', {
    mission: { ...multi, nb_creneaux: 2 },
    creneaux: [creneauPlanning('b', '2026-07-06T08:00:00+02:00', '2026-07-06T16:00:00+02:00'), creneauPlanning('a', '2026-07-06T08:00:00+02:00', '2026-07-06T12:00:00+02:00')],
  });
  construire('fin-avant-debut-zero-heure', { mission: { ...base, nb_creneaux: 1 }, creneaux: [creneauPlanning('inverse', '2026-07-06T16:00:00+02:00', '2026-07-06T08:00:00+02:00')] });

  // --- Erreur de chargement et paramètres explicites ----------------------
  const exacte = { ...base, nb_creneaux: 1, creneaux_planifies: [journeePlanning('l1', '2026-07-06')] };
  construire('planifies-de-la-mission', { mission: exacte });
  construire('erreur-parametre', { mission: exacte, erreur: true });
  construire('erreur-mission', { mission: { ...exacte, erreur_planning: true } });
  construire('erreur-mission-levee-par-parametre', { mission: { ...exacte, erreur_planning: true }, erreur: false });
  construire('creneaux-parametre-vide-remplacent-planifies', { mission: exacte, creneaux: [] });
  construire('erreur-et-incomplet', { mission: { ...missionLongueVitest, erreur_planning: true }, creneaux: deuxCreneauxVitest.slice(0, 1) });

  // --- Enveloppe : 24 h, dates absentes ou illisibles, sans id ------------
  construire('repli-24h-exactes', { mission: { id: 'm', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-07T08:00:00+02:00', nb_creneaux: null } });
  construire('repli-24h-plus-1s', { mission: { id: 'm', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-07T08:00:01+02:00', nb_creneaux: null } });
  construire('repli-dst-mars-23h', { mission: { id: 'm', debut_le: '2026-03-28T20:00:00+01:00', fin_le: '2026-03-29T20:00:00+02:00', nb_creneaux: 1 } });
  construire('mission-longue-sans-ligne-nb-null', { mission: { ...missionLongueVitest, nb_creneaux: null } });
  construire('mission-longue-sans-ligne-nb-2', { mission: missionLongueVitest });
  construire('debut-null', { mission: { id: 'm', debut_le: null, fin_le: '2026-07-06T16:00:00+02:00', nb_creneaux: 1 } });
  construire('fin-null', { mission: { id: 'm', debut_le: '2026-07-06T08:00:00+02:00', fin_le: null, nb_creneaux: 1 } });
  construire('debut-vide', { mission: { id: 'm', debut_le: '', fin_le: '2026-07-06T16:00:00+02:00', nb_creneaux: 1 } });
  construire('repli-sans-id', { mission: { debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-06T16:00:00+02:00', nb_creneaux: 1 } });
  construire('repli-enveloppe-illisible', { mission: { id: 'm', debut_le: 'pas une date', fin_le: '2026-07-06T16:00:00+02:00', nb_creneaux: 1 } });

  // --- Période étendue, heures, formats de date ---------------------------
  const seul = (nom, debut, fin) => construire(nom, { mission: { id: 'm', debut_le: debut, fin_le: fin, nb_creneaux: 1 }, creneaux: [creneauPlanning('s', debut, fin)] });
  seul('etendue-nuit-minuit-paris', '2026-07-06T20:00:00+02:00', '2026-07-07T08:00:00+02:00');
  seul('etendue-meme-jour-utc-minuit-paris', '2026-07-06T21:00:00.000Z', '2026-07-06T22:30:00.000Z');
  seul('non-etendue-jours-utc-differents-meme-jour-paris', '2026-07-06T22:00:00.000Z', '2026-07-07T01:30:00.000Z');
  seul('etendue-fin-minuit-exact', '2026-07-06T20:00:00+02:00', '2026-07-07T00:00:00+02:00');
  seul('non-etendue-debut-minuit-exact', '2026-07-07T00:00:00+02:00', '2026-07-07T06:00:00+02:00');
  seul('dst-mars-nuit-11h', '2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00');
  seul('dst-octobre-nuit-13h', '2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00');
  seul('legacy-sans-offset', '2026-07-06T08:00:00', '2026-07-06T15:30:00');
  seul('legacy-sans-offset-nuit-sans-secondes', '2026-07-06T21:00', '2026-07-07T05:00');
  seul('postgrest-plus-00-00', '2026-07-06T06:00:00+00:00', '2026-07-06T14:00:00+00:00');
  seul('duree-tiers-heure', '2026-07-06T08:00:00+02:00', '2026-07-06T15:20:00+02:00');
  seul('millisecondes', '2026-07-06T08:00:00.250+02:00', '2026-07-06T16:00:00.750+02:00');
  seul('microsecondes-postgrest', '2026-07-06T06:00:00.123456+00:00', '2026-07-06T14:00:00.654321+00:00');
  construire('trois-nuits-dst-mars', {
    mission: { id: 'm', debut_le: '2026-03-27T20:00:00+01:00', fin_le: '2026-03-30T08:00:00+02:00', nb_creneaux: 3 },
    creneaux: [
      creneauPlanning('n2', '2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00'),
      creneauPlanning('n1', '2026-03-27T20:00:00+01:00', '2026-03-28T08:00:00+01:00'),
      creneauPlanning('n3', '2026-03-29T20:00:00+02:00', '2026-03-30T08:00:00+02:00'),
    ],
  });

  // --- Créneaux confirmés pour l'action (parité web) et format filaire natif
  confirmes('trois-lignes-desordre-pause-effectif', { ...multi, nb_creneaux: 3, creneaux_planifies: [...trois, pause, effectif] });
  confirmes('repli-ponctuel-legacy', ponctuelleVitest);
  confirmes('planifies-de-la-mission', exacte);
  confirmes('erreur-planning', { ...exacte, erreur_planning: true });
  confirmes('mission-longue-sans-ligne', { ...missionLongueVitest, nb_creneaux: null });
  confirmes('ligne-sans-fin', { ...base, nb_creneaux: 1, creneaux_planifies: [creneauPlanning('ouvert', '2026-07-06T08:00:00+02:00', null)] });
  confirmes('compteur-depasse', { ...base, nb_creneaux: 1, creneaux_planifies: trois });
  confirmes('fin-avant-debut', { ...base, nb_creneaux: 1, creneaux_planifies: [creneauPlanning('inverse', '2026-07-06T16:00:00+02:00', '2026-07-06T08:00:00+02:00')] });
  const deuxJours = (nom, format) => confirmes(nom, {
    ...base, nb_creneaux: 2,
    creneaux_planifies: [creneauPlanning('b', ...format('2026-07-07')), creneauPlanning('a', ...format('2026-07-06'))],
  });
  deuxJours('postgrest-plus-00-00', (d) => [`${d}T06:00:00+00:00`, `${d}T14:00:00+00:00`]);
  deuxJours('postgrest-fraction-nulle', (d) => [`${d}T06:00:00.000+00:00`, `${d}T14:00:00.000000+00:00`]);
  deuxJours('postgrest-fraction-milliseconde', (d) => [`${d}T06:00:00.250+00:00`, `${d}T14:00:00+00:00`]);
  deuxJours('postgrest-fraction-microseconde', (d) => [`${d}T06:00:00+00:00`, `${d}T14:00:00.000500+00:00`]);
  deuxJours('utc-z', (d) => [`${d}T06:00:00Z`, `${d}T14:00:00.000Z`]);
  deuxJours('offset-paris-ete', (d) => [`${d}T08:00:00+02:00`, `${d}T16:00:00+02:00`]);
  deuxJours('offset-negatif', (d) => [`${d}T02:00:00-04:00`, `${d}T10:00:00-04:00`]);
  deuxJours('legacy-sans-offset', (d) => [`${d}T08:00:00`, `${d}T16:00`]);
  confirmes('dst-mars-nuit', { id: 'm', debut_le: '2026-03-28T20:00:00+01:00', fin_le: '2026-03-29T08:00:00+02:00', nb_creneaux: 1,
    creneaux_planifies: [creneauPlanning('n', '2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00')] });
  confirmes('dst-octobre-nuit', { id: 'm', debut_le: '2026-10-24T20:00:00+02:00', fin_le: '2026-10-25T08:00:00+01:00', nb_creneaux: 1,
    creneaux_planifies: [creneauPlanning('n', '2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00')] });
  confirmes('frontiere-annee', { id: 'm', debut_le: '2026-12-31T20:00:00+01:00', fin_le: '2027-01-01T08:00:00+01:00', nb_creneaux: 1,
    creneaux_planifies: [creneauPlanning('n', '2026-12-31T20:00:00+01:00', '2027-01-01T08:00:00+01:00')] });

  // --- Filtres horaires sur le planning exact -----------------------------
  const unCreneau = (debut, fin) => ({ id: 'f', debut_le: debut, fin_le: fin, nb_creneaux: 1, creneaux_planifies: [creneauPlanning('f1', debut, fin)] });
  filtres('lundi-jour', unCreneau('2026-07-06T08:00:00+02:00', '2026-07-06T16:00:00+02:00'));
  filtres('mardi-nuit', unCreneau('2026-07-07T21:00:00+02:00', '2026-07-08T07:00:00+02:00'));
  filtres('samedi-jour', unCreneau('2026-07-11T08:00:00+02:00', '2026-07-11T16:00:00+02:00'));
  filtres('vendredi-nuit-vers-samedi', unCreneau('2026-07-10T21:00:00+02:00', '2026-07-11T07:00:00+02:00'));
  filtres('vendredi-soir-jusqua-minuit', unCreneau('2026-07-10T18:00:00+02:00', '2026-07-11T00:00:00+02:00'));
  filtres('planning-inexact', { ...missionLongueVitest, creneaux_planifies: deuxCreneauxVitest.slice(0, 1) });
  filtres('repli-ponctuel', ponctuelleVitest);
  filtres('erreur-planning', { ...exacte, erreur_planning: true });
  filtres('jour-et-nuit', { ...multi, nb_creneaux: 2, creneaux_planifies: [journeePlanning('j', '2026-07-06'), creneauPlanning('n', '2026-07-07T21:00:00+02:00', '2026-07-08T07:00:00+02:00')] });

  // --- Nuit (20:00 → 07:00 Paris) et week-end, jour civil par jour civil ---
  horaires('jour-07h-20h-exact', '2026-07-07T07:00:00+02:00', '2026-07-07T20:00:00+02:00');
  horaires('debut-06h59', '2026-07-07T06:59:00+02:00', '2026-07-07T20:00:00+02:00');
  horaires('fin-20h01', '2026-07-07T07:00:00+02:00', '2026-07-07T20:01:00+02:00');
  horaires('soir-19h30-20h30', '2026-07-07T19:30:00+02:00', '2026-07-07T20:30:00+02:00');
  horaires('nuit-20h-07h', '2026-07-07T20:00:00+02:00', '2026-07-08T07:00:00+02:00');
  horaires('minuit-01h', '2026-07-08T00:00:00+02:00', '2026-07-08T01:00:00+02:00');
  horaires('multi-jours-08h-17h', '2026-07-06T08:00:00+02:00', '2026-07-08T17:00:00+02:00');
  horaires('fin-null', '2026-07-07T08:00:00+02:00', null);
  horaires('fin-vide', '2026-07-07T08:00:00+02:00', '');
  horaires('fin-avant-debut', '2026-07-07T16:00:00+02:00', '2026-07-07T08:00:00+02:00');
  horaires('dst-mars-jour', '2026-03-29T07:00:00+02:00', '2026-03-29T20:00:00+02:00');
  horaires('dst-mars-saut-1h-4h', '2026-03-29T01:00:00+01:00', '2026-03-29T04:00:00+02:00');
  horaires('dst-octobre-jour', '2026-10-25T07:00:00+01:00', '2026-10-25T20:00:00+01:00');
  horaires('dst-octobre-heure-repetee', '2026-10-25T02:30:00+02:00', '2026-10-25T02:30:00+01:00');
  horaires('vendredi-jusqua-samedi-minuit', '2026-07-10T18:00:00+02:00', '2026-07-11T00:00:00+02:00');
  horaires('vendredi-jusqua-samedi-minuit-plus-1s', '2026-07-10T18:00:00+02:00', '2026-07-11T00:00:01+02:00');
  horaires('samedi-jour', '2026-07-11T08:00:00+02:00', '2026-07-11T16:00:00+02:00');
  horaires('dimanche-vers-lundi', '2026-07-12T22:00:00+02:00', '2026-07-13T06:00:00+02:00');
  horaires('lundi-depuis-minuit', '2026-07-13T00:00:00+02:00', '2026-07-13T08:00:00+02:00');
  horaires('utc-dimanche-lundi-paris', '2026-07-12T22:00:00.000Z', '2026-07-13T04:00:00.000Z');
  horaires('utc-vendredi-samedi-paris', '2026-07-10T21:30:00.000Z', '2026-07-10T22:30:00.000Z');
  horaires('legacy-sans-offset-samedi', '2026-07-11T08:00:00', '2026-07-11T16:00:00');
  horaires('semaine-complete', '2026-07-06T00:00:00+02:00', '2026-07-13T00:00:00+02:00');
  horaires('hiver-utc-07h-20h', '2026-01-12T06:00:00.000Z', '2026-01-12T19:00:00.000Z');
  horaires('hiver-utc-06h59', '2026-01-12T05:59:00.000Z', '2026-01-12T07:00:00.000Z');
  horaires('reveillon-annee', '2026-12-31T20:00:00+01:00', '2027-01-01T08:00:00+01:00');

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 6 : selection-serie-candidat (src/components/planning/selection-serie-candidat.ts)
// ---------------------------------------------------------------------------
function vecteursSelectionSerie() {
  const c = new Collecteur('selection-serie-candidat');
  // `missionsSelectionnees` est un filtre qui conserve l'identité des missions :
  // l'attendu en garde les `id`, dans l'ordre des missions ouvertes.
  const analyser = (nom, missionsOuvertes, idsSelectionnes, idsConflit) => {
    const name = `analyserSelectionSerie/${nom}`;
    c.ajoute(name, { fonction: 'analyserSelectionSerie', missionsOuvertes, idsSelectionnes, idsConflit },
      sansLevee('selection-serie-candidat', name, capture(() => {
        const r = selectionSerie.analyserSelectionSerie(missionsOuvertes, new Set(idsSelectionnes), new Set(idsConflit));
        return {
          missionsSelectionnees: r.missionsSelectionnees.map((mission) => mission.id),
          idsEnConflit: r.idsEnConflit,
          idsPlanningInexact: r.idsPlanningInexact,
          peutAccepter: r.peutAccepter,
        };
      })));
  };

  // --- Issus des tests vitest (selection-serie-candidat.test.ts) -----------
  const mission = (id) => ({
    id,
    debut_le: `2026-08-0${id}T08:00:00+02:00`,
    fin_le: `2026-08-0${id}T16:00:00+02:00`,
    nb_creneaux: 1,
    creneaux_planifies: [{ id: `c-${id}`, debut: `2026-08-0${id}T08:00:00+02:00`, fin: `2026-08-0${id}T16:00:00+02:00`, est_pause: false, type_creneau: 'PREVISIONNEL' }],
  });
  const sept = Array.from({ length: 7 }, (_, index) => mission(String(index + 1)));
  const tous = sept.map((m) => m.id);
  analyser('vitest-conflit-jamais-retire', sept, tous, ['7']);
  analyser('vitest-six-apres-decochage', sept, tous.slice(0, 6), []);
  analyser('vitest-planning-exact-absent', [{ ...mission('1'), nb_creneaux: 2 }], ['1'], []);

  // --- Grille --------------------------------------------------------------
  analyser('selection-vide', sept, [], []);
  analyser('aucune-mission-ouverte', [], ['1'], ['1']);
  analyser('id-selectionne-inconnu-ignore', sept.slice(0, 2), ['1', '9'], []);
  analyser('conflit-non-selectionne-ignore', sept, ['1', '2'], ['3']);
  analyser('ordre-des-missions-pas-de-la-selection', sept, ['5', '2', '7'], []);
  analyser('plusieurs-conflits-ordre-des-missions', sept, tous, ['6', '2', '4']);
  analyser('tout-en-conflit', sept.slice(0, 3), ['1', '2', '3'], ['1', '2', '3']);
  analyser('conflit-et-inexact', [mission('1'), { ...mission('2'), nb_creneaux: 2 }, mission('3')], ['1', '2', '3'], ['3']);
  analyser('inexact-non-selectionne-ignore', [mission('1'), { ...mission('2'), nb_creneaux: 2 }], ['1'], []);
  analyser('erreur-planning-inexacte', [mission('1'), { ...mission('2'), erreur_planning: true }], ['1', '2'], []);
  analyser('repli-ponctuel-sans-ligne-exact', [{ id: '1', debut_le: '2026-08-01T08:00:00+02:00', fin_le: '2026-08-01T16:00:00+02:00', nb_creneaux: null }], ['1'], []);
  analyser('mission-longue-sans-ligne-inexacte', [{ id: '1', debut_le: '2026-08-01T08:00:00+02:00', fin_le: '2026-08-07T16:00:00+02:00', nb_creneaux: null }], ['1'], []);
  analyser('ligne-sans-fin-inexacte', [{ ...mission('1'), creneaux_planifies: [{ ...mission('1').creneaux_planifies[0], fin: null }] }], ['1'], []);
  analyser('pause-seule-repli-exact', [{ ...mission('1'), creneaux_planifies: [{ ...mission('1').creneaux_planifies[0], est_pause: true }] }], ['1'], []);
  analyser('mission-dupliquee-conservee', [mission('1'), mission('1')], ['1'], []);
  analyser('selection-avec-doublons', sept, ['1', '1', '2'], ['2', '2']);
  analyser('nuits-dst-mars', [
    { id: 'n1', debut_le: '2026-03-28T20:00:00+01:00', fin_le: '2026-03-29T08:00:00+02:00', nb_creneaux: 1,
      creneaux_planifies: [creneauPlanning('c-n1', '2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00')] },
    { id: 'n2', debut_le: '2026-03-29T20:00:00+02:00', fin_le: '2026-03-30T08:00:00+02:00', nb_creneaux: 2,
      creneaux_planifies: [creneauPlanning('c-n2', '2026-03-29T20:00:00+02:00', '2026-03-30T08:00:00+02:00')] },
  ], ['n1', 'n2'], []);

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 7 : completude-planning-mission (src/lib/completude-planning-mission.ts)
// ---------------------------------------------------------------------------
function vecteursCompletudePlanning() {
  const c = new Collecteur('completude-planning-mission');
  const analyser = (nom, mission, creneaux) => {
    const name = `analyserCompletudePlanningMission/${nom}`;
    c.ajoute(name, { fonction: 'analyserCompletudePlanningMission', mission, creneaux },
      sansLevee('completude-planning-mission', name, capture(() => completude.analyserCompletudePlanningMission(mission, creneaux))));
  };

  // --- Issus des tests vitest (completude-planning-mission.test.ts) --------
  const missionLongue = { id: 'mission-1', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-08-31T16:00:00+02:00', nb_creneaux: 2 };
  const exacts = [
    { id: 'creneau-1', debut: '2026-07-06T08:00:00+02:00', fin: '2026-07-06T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
    { id: 'creneau-2', debut: '2026-08-31T08:00:00+02:00', fin: '2026-08-31T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
  ];
  analyser('vitest-nombre-exact', missionLongue, exacts);
  analyser('vitest-reponse-tronquee', missionLongue, exacts.slice(0, 1));
  analyser('vitest-creneau-invalide', { ...missionLongue, nb_creneaux: 1 }, [{ ...exacts[0], fin: '2026-07-06T07:59:00+02:00' }]);
  analyser('vitest-repli-legacy-ponctuel', { id: 'mission-legacy', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-06T16:00:00+02:00', nb_creneaux: null });
  analyser('vitest-longue-legacy-sans-planning', { id: 'mission-longue-legacy', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-08-31T16:00:00+02:00', nb_creneaux: null });

  // --- Compteur non vérifiable : repli ponctuel seulement sans ligne -------
  const ponctuelle = { id: 'p', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-06T16:00:00+02:00' };
  const ligne = creneauPlanning('l1', '2026-07-06T09:00:00+02:00', '2026-07-06T17:00:00+02:00');
  const pause = creneauPlanning('pause', '2026-07-06T12:00:00+02:00', '2026-07-06T12:30:00+02:00', { est_pause: true });
  const effectif = journeePlanning('effectif', '2026-07-06', { type_creneau: 'EFFECTIF' });
  for (const [libelle, nb] of [['absent', undefined], ['null', null], ['0', 0], ['moins-1', -1]]) {
    const m = { ...ponctuelle };
    if (nb !== undefined) m.nb_creneaux = nb;
    analyser(`nb-${libelle}-repli-sans-ligne`, m, []);
    analyser(`nb-${libelle}-une-ligne-aucun-repli`, m, [ligne]);
    analyser(`nb-${libelle}-pause-seule-repli`, m, [pause]);
    analyser(`nb-${libelle}-effectif-seul-repli`, m, [effectif]);
  }
  analyser('nb-absent-creneaux-absents', { ...ponctuelle }, undefined);

  // --- Compteur vérifiable : nombre exact de lignes valides ----------------
  const multi = { id: 'multi', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-08T16:00:00+02:00' };
  const trois = [journeePlanning('j3', '2026-07-08'), journeePlanning('j1', '2026-07-06'), journeePlanning('j2', '2026-07-07')];
  for (const nb of [1, 2, 3, 4]) analyser(`trois-lignes-nb-${nb}`, { ...multi, nb_creneaux: nb }, trois);
  analyser('trois-lignes-plus-pause-et-effectif', { ...multi, nb_creneaux: 3 }, [...trois, pause, effectif]);
  analyser('ligne-sans-fin-comptee-brute', { ...multi, nb_creneaux: 3 }, [trois[0], trois[1], creneauPlanning('ouvert', '2026-07-07T08:00:00+02:00', null)]);
  analyser('ligne-sans-fin-en-plus', { ...multi, nb_creneaux: 3 }, [...trois, creneauPlanning('ouvert', '2026-07-09T08:00:00+02:00', null)]);
  analyser('ligne-fin-vide', { ...multi, nb_creneaux: 3 }, [trois[0], trois[1], creneauPlanning('vide', '2026-07-07T08:00:00+02:00', '')]);
  const une = (nom, debut, fin) => analyser(nom, { ...ponctuelle, nb_creneaux: 1 }, [creneauPlanning('u', debut, fin)]);
  une('ligne-duree-nulle', '2026-07-06T08:00:00+02:00', '2026-07-06T08:00:00+02:00');
  une('ligne-fin-avant-debut', '2026-07-06T16:00:00+02:00', '2026-07-06T08:00:00+02:00');
  une('ligne-debut-illisible', 'pas une date', '2026-07-06T16:00:00+02:00');
  une('ligne-fin-illisible', '2026-07-06T08:00:00+02:00', 'pas une date');
  une('ligne-plus-de-24h-valide', '2026-07-06T08:00:00+02:00', '2026-07-07T10:00:00+02:00');
  une('dst-mars-nuit-11h', '2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00');
  une('dst-octobre-nuit-13h', '2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00');
  une('millisecondes', '2026-07-06T08:00:00.250+02:00', '2026-07-06T16:00:00.750+02:00');
  une('duree-tiers-heure', '2026-07-06T08:00:00+02:00', '2026-07-06T15:20:00+02:00');
  une('legacy-sans-offset', '2026-07-06T08:00:00', '2026-07-06T15:30');
  une('postgrest-plus-00-00', '2026-07-06T06:00:00+00:00', '2026-07-06T14:00:00+00:00');
  analyser('meme-debut-ordre-stable', { ...multi, nb_creneaux: 2 }, [
    creneauPlanning('b', '2026-07-06T08:00:00+02:00', '2026-07-06T16:00:00+02:00'), creneauPlanning('a', '2026-07-06T08:00:00+02:00', '2026-07-06T12:00:00+02:00'),
  ]);
  analyser('trois-nuits-dst-mars', { id: 'm', debut_le: '2026-03-27T20:00:00+01:00', fin_le: '2026-03-30T08:00:00+02:00', nb_creneaux: 3 }, [
    creneauPlanning('n2', '2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00'),
    creneauPlanning('n1', '2026-03-27T20:00:00+01:00', '2026-03-28T08:00:00+01:00'),
    creneauPlanning('n3', '2026-03-29T20:00:00+02:00', '2026-03-30T08:00:00+02:00'),
  ]);

  // --- Repli ponctuel : enveloppe de 24 h au plus ---------------------------
  const repli = (nom, mission) => analyser(nom, { nb_creneaux: null, ...mission }, []);
  repli('repli-24h-exactes', { id: 'p', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-07T08:00:00+02:00' });
  repli('repli-24h-plus-1s', { id: 'p', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-07T08:00:01+02:00' });
  repli('repli-duree-nulle', { id: 'p', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-06T08:00:00+02:00' });
  repli('repli-fin-avant-debut', { id: 'p', debut_le: '2026-07-06T16:00:00+02:00', fin_le: '2026-07-06T08:00:00+02:00' });
  repli('repli-enveloppe-illisible', { id: 'p', debut_le: 'pas une date', fin_le: '2026-07-06T16:00:00+02:00' });
  repli('repli-sans-id', { debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-06T16:00:00+02:00' });
  repli('repli-legacy-sans-offset', { id: 'p', debut_le: '2026-07-06T08:00:00', fin_le: '2026-07-06T16:00:00' });
  repli('repli-dates-seules', { id: 'p', debut_le: '2026-07-06', fin_le: '2026-07-07' });
  repli('repli-dst-mars-23h', { id: 'p', debut_le: '2026-03-28T20:00:00+01:00', fin_le: '2026-03-29T20:00:00+02:00' });
  repli('repli-dst-octobre-25h', { id: 'p', debut_le: '2026-10-24T20:00:00+02:00', fin_le: '2026-10-25T20:00:00+01:00' });

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règles 8 à 13 : lot 2, T2 (pointage, justificatifs, contrats)
// ---------------------------------------------------------------------------
// Les deux règles extraites par la PR web W1 (`documents-requis.ts`,
// `presences-soignant-listes.ts`) sont les règles 14 et 15 (tranche T2b, décision « Lot 2 T2 »
// de LOTS_2_5_DECISIONS).

// Un créneau porte toujours ses quatre clés (`fin: null` explicite) : l'attendu le recopie
// tel quel et le port Swift le ré-encode (`MissionSlot.golden`) avec les mêmes clés.
const creneauLot2 = (debut, fin, type_creneau = 'PREVISIONNEL', extra = {}) => ({ debut, fin, est_pause: false, type_creneau, ...extra });

/** Refuse qu'un résultat web porte une clé que la projection golden ne rejoue pas. */
function clesExactes(regle, objet, cles) {
  const obtenues = Object.keys(objet).sort();
  const attendues = [...cles].sort();
  if (JSON.stringify(obtenues) !== JSON.stringify(attendues)) {
    throw new Error(`${regle}: clés ${JSON.stringify(obtenues)} au lieu de ${JSON.stringify(attendues)} : mettre à jour la projection et le port Swift.`);
  }
}

// ---------------------------------------------------------------------------
// Règle 8 : synthese-presence-mission (src/lib/synthese-presence-mission.ts)
// ---------------------------------------------------------------------------
function vecteursSynthesePresence() {
  const c = new Collecteur('synthese-presence-mission');
  const resume = (s) => {
    clesExactes('synthese-presence-mission', s, ['previsionnels', 'effectifsFermes', 'effectifsOuverts', 'minutesPlanifiees',
      'minutesTravaillees', 'dernierPrevisionnelFin', 'planningTermine', 'validationPossible']);
    return { ...s, dernierPrevisionnelFin: iso(s.dernierPrevisionnelFin) };
  };
  const construire = (nom, creneaux, maintenant) => c.ajoute(`construireSynthesePresenceMission/${nom}`,
    { fonction: 'construireSynthesePresenceMission', creneaux, maintenant },
    resume(synthesePresence.construireSynthesePresenceMission(creneaux, new Date(maintenant))));
  const duree = (nom, minutes) => c.ajoute(`formatDureeMinutes/${nom}`, { fonction: 'formatDureeMinutes', minutes },
    synthesePresence.formatDureeMinutes(minutes));

  // --- Issus des tests vitest (synthese-presence-mission.test.ts) ----------
  const prevJuillet = creneauLot2('2026-07-06T08:00:00+02:00', '2026-07-06T16:00:00+02:00');
  const prevAout = creneauLot2('2026-08-31T08:00:00+02:00', '2026-08-31T16:00:00+02:00');
  construire('vitest-effectifs-fermes-seulement', [
    prevJuillet, prevAout,
    creneauLot2('2026-07-06T08:15:00+02:00', '2026-07-06T14:15:00+02:00', 'EFFECTIF'),
    creneauLot2('2026-07-31T08:00:00+02:00', null, 'EFFECTIF'),
    creneauLot2('2026-07-06T12:00:00+02:00', '2026-07-06T12:30:00+02:00', 'EFFECTIF', { est_pause: true }),
  ], '2026-09-01T08:00:00+02:00');
  const vitestValidation = [prevJuillet, prevAout, creneauLot2('2026-07-06T08:00:00+02:00', '2026-07-06T16:00:00+02:00', 'EFFECTIF')];
  construire('vitest-avant-dernier-prevu', vitestValidation, '2026-07-31T12:00:00+02:00');
  construire('vitest-apres-dernier-prevu', vitestValidation, '2026-08-31T16:01:00+02:00');

  // --- Fin du planning : bornes exactes ------------------------------------
  const prev = creneauLot2('2026-07-31T06:00:00.000Z', '2026-07-31T14:00:00.000Z', 'PREVISIONNEL', { id: 'prev' });
  const effFerme = creneauLot2('2026-07-31T06:05:00.000Z', '2026-07-31T13:55:00.000Z', 'EFFECTIF', { id: 'eff' });
  for (const [nom, maintenant] of [
    ['avant-fin', '2026-07-31T13:59:59.999Z'], ['fin-exacte', '2026-07-31T14:00:00.000Z'], ['apres-fin', '2026-07-31T14:00:00.001Z'],
  ]) {
    construire(`previsionnel-et-effectif-${nom}`, [prev, effFerme], maintenant);
    construire(`previsionnel-seul-${nom}`, [prev], maintenant);
    construire(`effectif-ouvert-${nom}`, [prev, effFerme, creneauLot2('2026-07-31T14:30:00.000Z', null, 'EFFECTIF', { id: 'ouvert' })], maintenant);
  }
  construire('vide', [], '2026-07-31T12:00:00.000Z');
  construire('effectif-sans-previsionnel', [effFerme], '2026-08-01T12:00:00.000Z');

  // --- Filtres : pauses, types, fins absentes ou vides ---------------------
  const apres = '2026-08-01T12:00:00.000Z';
  construire('pause-previsionnelle-exclue', [prev, creneauLot2('2026-07-31T10:00:00.000Z', '2026-07-31T10:30:00.000Z', 'PREVISIONNEL', { est_pause: true }), effFerme], apres);
  construire('pause-effective-ouverte-ignoree', [prev, effFerme, creneauLot2('2026-07-31T10:00:00.000Z', null, 'EFFECTIF', { est_pause: true })], apres);
  construire('previsionnel-sans-fin-ignore', [prev, creneauLot2('2026-08-01T06:00:00.000Z', null), effFerme], apres);
  construire('previsionnel-fin-vide-ignore', [prev, creneauLot2('2026-08-01T06:00:00.000Z', ''), effFerme], apres);
  construire('effectif-fin-vide-ouvert', [prev, creneauLot2('2026-07-31T06:05:00.000Z', '', 'EFFECTIF')], apres);
  construire('type-inconnu-ignore', [prev, effFerme, creneauLot2('2026-07-31T06:00:00.000Z', '2026-07-31T18:00:00.000Z', 'AUTRE')], apres);
  construire('identifiants-conserves', [
    creneauLot2('2026-07-31T06:00:00.000Z', '2026-07-31T14:00:00.000Z', 'PREVISIONNEL', { id: 'p1', mission_id: 'm1' }),
    creneauLot2('2026-07-31T06:02:00.000Z', '2026-07-31T14:01:00.000Z', 'EFFECTIF', { id: 'e1', mission_id: 'm1' }),
  ], apres);

  // --- Tri, dernier prévu par début, durées ---------------------------------
  construire('previsionnels-desordre', [
    creneauLot2('2026-08-02T06:00:00.000Z', '2026-08-02T14:00:00.000Z', 'PREVISIONNEL', { id: 'j3' }),
    creneauLot2('2026-07-31T06:00:00.000Z', '2026-07-31T14:00:00.000Z', 'PREVISIONNEL', { id: 'j1' }),
    creneauLot2('2026-08-01T06:00:00.000Z', '2026-08-01T14:00:00.000Z', 'PREVISIONNEL', { id: 'j2' }),
  ], '2026-08-02T14:00:00.000Z');
  construire('dernier-prevu-par-debut-pas-par-fin', [
    creneauLot2('2026-07-31T06:00:00.000Z', '2026-07-31T20:00:00.000Z', 'PREVISIONNEL', { id: 'long' }),
    creneauLot2('2026-07-31T08:00:00.000Z', '2026-07-31T10:00:00.000Z', 'PREVISIONNEL', { id: 'court' }),
    creneauLot2('2026-07-31T06:00:00.000Z', '2026-07-31T09:00:00.000Z', 'EFFECTIF', { id: 'e' }),
  ], '2026-07-31T12:00:00.000Z');
  construire('effectifs-desordre', [
    prev,
    creneauLot2('2026-07-31T11:00:00.000Z', '2026-07-31T14:00:00.000Z', 'EFFECTIF', { id: 'apres-midi' }),
    creneauLot2('2026-07-31T06:00:00.000Z', '2026-07-31T10:00:00.000Z', 'EFFECTIF', { id: 'matin' }),
    creneauLot2('2026-07-31T15:00:00.000Z', null, 'EFFECTIF', { id: 'soir-ouvert' }),
    creneauLot2('2026-07-31T05:00:00.000Z', null, 'EFFECTIF', { id: 'aube-ouvert' }),
  ], apres);
  construire('effectif-fin-avant-debut-zero-minute', [prev, creneauLot2('2026-07-31T14:00:00.000Z', '2026-07-31T06:00:00.000Z', 'EFFECTIF')], apres);
  construire('effectif-duree-nulle', [prev, creneauLot2('2026-07-31T06:00:00.000Z', '2026-07-31T06:00:00.000Z', 'EFFECTIF')], apres);
  construire('duree-en-secondes', [prev, creneauLot2('2026-07-31T06:00:00.000Z', '2026-07-31T06:00:30.000Z', 'EFFECTIF'),
    creneauLot2('2026-07-31T07:00:00.000Z', '2026-07-31T07:00:00.250Z', 'EFFECTIF')], apres);
  construire('effectif-debut-illisible-zero-minute', [prev, creneauLot2('pas une date', '2026-07-31T14:00:00.000Z', 'EFFECTIF')], apres);
  construire('previsionnel-fin-illisible', [creneauLot2('2026-07-31T06:00:00.000Z', 'pas une date', 'PREVISIONNEL', { id: 'illisible' })], apres);
  construire('mission-longue-jours-de-repos', [
    prevJuillet, prevAout,
    creneauLot2('2026-07-06T08:00:00+02:00', '2026-07-06T16:10:00+02:00', 'EFFECTIF'),
    creneauLot2('2026-08-31T07:55:00+02:00', '2026-08-31T15:40:00+02:00', 'EFFECTIF'),
  ], '2026-09-01T00:00:00+02:00');

  // --- Formats de date et changements d'heure --------------------------------
  construire('dst-mars-nuit-11h', [
    creneauLot2('2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00'),
    creneauLot2('2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00', 'EFFECTIF'),
  ], '2026-03-29T08:00:00+02:00');
  construire('dst-octobre-nuit-13h', [
    creneauLot2('2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00'),
    creneauLot2('2026-10-24T20:10:00+02:00', '2026-10-25T07:50:00+01:00', 'EFFECTIF'),
  ], '2026-10-25T08:00:00+01:00');
  construire('legacy-sans-offset', [
    creneauLot2('2026-07-31T08:00:00', '2026-07-31T16:00:00'),
    creneauLot2('2026-07-31T08:05:00', '2026-07-31T15:45', 'EFFECTIF'),
  ], '2026-07-31T16:00:00');
  construire('postgrest-microsecondes', [
    creneauLot2('2026-07-31T06:00:00+00:00', '2026-07-31T14:00:00+00:00'),
    creneauLot2('2026-07-31T06:00:00.123456+00:00', '2026-07-31T13:59:59.654321+00:00', 'EFFECTIF'),
  ], '2026-07-31T14:00:00.000Z');

  // --- formatDureeMinutes ----------------------------------------------------
  for (const minutes of [0, 1, 9, 10, 59, 60, 61, 90, 450, 480, 600, 660, 780, 1439, 1440, 6000, 100000]) {
    duree(`entier-${minutes}`, minutes);
  }
  for (const [nom, minutes] of [
    ['0-4', 0.4], ['0-5', 0.5], ['0-6', 0.6], ['59-4', 59.4], ['59-5', 59.5], ['119-6-arrondi-60', 119.6],
    ['heures-7-33', 7.33 * 60], ['heures-0-1', 0.1 * 60], ['secondes-30', 0.5 + 60],
    ['un-tiers', 20 / 3], ['negatif-30', -30],
  ]) {
    duree(`decimal-${nom}`, minutes);
  }

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 9 : presencesSoignantUi (src/lib/presencesSoignantUi.ts)
// ---------------------------------------------------------------------------
function vecteursPresencesSoignantUi() {
  const c = new Collecteur('presences-soignant-ui');
  const CLES_LIGNE = ['id', 'mission_id', 'soignant_id', 'pointage_arrivee_le', 'pointage_depart_le', 'valide_par_etablissement',
    'valide_le', 'methode_pointage_arrivee', 'methode_pointage_depart', 'origine_effectifs_sans_presence', 'missions'];
  // `missions` recopie la mission lue (`...mission`) : l'attendu n'en garde que l'identifiant,
  // l'établissement résolu et les créneaux, seuls champs que le modèle natif expose.
  const projeter = (ligne, missions) => {
    clesExactes('presences-soignant-ui', ligne, CLES_LIGNE);
    const source = missions.find((mission) => mission.id === ligne.mission_id);
    clesExactes('presences-soignant-ui (missions)', ligne.missions, [...Object.keys(source), 'etablissements', 'creneaux']);
    return {
      ...ligne,
      missions: { id: ligne.missions.id, etablissements: ligne.missions.etablissements, creneaux: ligne.missions.creneaux },
    };
  };
  const historique = (nom, args) => c.ajoute(`construireHistoriqueEffectifsSansPresence/${nom}`,
    { fonction: 'construireHistoriqueEffectifsSansPresence', ...args },
    presencesUi.construireHistoriqueEffectifsSansPresence(args).map((ligne) => projeter(ligne, args.missions)));
  const gps = (nom, valeur) => c.ajoute(`mesureGpsDisponible/${nom}`, { fonction: 'mesureGpsDisponible', valeur },
    presencesUi.mesureGpsDisponible(valeur));

  // --- Issus des tests vitest (presencesSoignantUi.test.ts) ----------------
  historique('vitest-effectifs-seuls', {
    missions: [{ id: 'mission-longue', intitule: 'Mission longue', etablissement_id: 'etab-1', statut: 'TERMINEE' }],
    presences: [],
    creneauxParMission: {
      'mission-longue': [
        creneauLot2('2026-07-06T06:00:00Z', '2026-07-06T14:00:00Z', 'PREVISIONNEL', { id: 'prevu' }),
        creneauLot2('2026-07-06T06:00:00Z', '2026-07-06T14:00:00Z', 'EFFECTIF', { id: 'effectif' }),
      ],
    },
    etablissements: { 'etab-1': { nom: 'Clinique Test' } },
    soignantId: 'soignant-1',
  });
  historique('vitest-ni-presence-ni-sans-effectif', {
    missions: [{ id: 'avec-presence' }, { id: 'sans-effectif' }],
    presences: [{ mission_id: 'avec-presence' }],
    creneauxParMission: {
      'avec-presence': [creneauLot2('2026-07-06T06:00:00Z', '2026-07-06T14:00:00Z', 'EFFECTIF')],
      'sans-effectif': [creneauLot2('2026-07-07T06:00:00Z', '2026-07-07T14:00:00Z')],
    },
    etablissements: {},
    soignantId: 'soignant-1',
  });
  for (const [nom, valeur] of [['zero', 0], ['dixieme', 0.2], ['700', 700]]) gps(`vitest-mesure-${nom}`, valeur);
  for (const [nom, valeur] of [['null', null], ['absente', undefined], ['chaine-vide', ''], ['chaine-zero', '0'], ['faux', false], ['negative', -1]]) {
    gps(`vitest-invalide-${nom}`, valeur);
  }

  // --- Grille ----------------------------------------------------------------
  const base = { presences: [], etablissements: { 'etab-1': { nom: 'Clinique Test', ville: 'Lyon' } }, soignantId: 'soignant-1' };
  const mission = { id: 'm', etablissement_id: 'etab-1' };
  const avec = (nom, creneaux, extra = {}) => historique(nom, { ...base, missions: [mission], creneauxParMission: { m: creneaux }, ...extra });
  avec('arrivee-premier-depart-dernier-par-debut', [
    creneauLot2('2026-07-07T06:00:00Z', '2026-07-07T10:00:00Z', 'EFFECTIF', { id: 'e2' }),
    creneauLot2('2026-07-06T06:00:00Z', '2026-07-08T20:00:00Z', 'EFFECTIF', { id: 'e1-long' }),
    creneauLot2('2026-07-07T12:00:00Z', '2026-07-07T13:00:00Z', 'EFFECTIF', { id: 'e3' }),
  ]);
  avec('effectif-ouvert-ignore', [
    creneauLot2('2026-07-06T06:00:00Z', '2026-07-06T14:00:00Z', 'EFFECTIF', { id: 'ferme' }),
    creneauLot2('2026-07-07T06:00:00Z', null, 'EFFECTIF', { id: 'ouvert' }),
  ]);
  avec('seul-effectif-ouvert-aucune-ligne', [creneauLot2('2026-07-07T06:00:00Z', null, 'EFFECTIF')]);
  avec('effectif-fin-vide-ignore', [creneauLot2('2026-07-07T06:00:00Z', '', 'EFFECTIF')]);
  avec('pause-effective-ignoree', [
    creneauLot2('2026-07-06T12:00:00Z', '2026-07-06T12:30:00Z', 'EFFECTIF', { est_pause: true }),
    creneauLot2('2026-07-06T13:00:00Z', '2026-07-06T15:00:00Z', 'EFFECTIF'),
  ]);
  avec('pause-effective-seule-aucune-ligne', [creneauLot2('2026-07-06T12:00:00Z', '2026-07-06T12:30:00Z', 'EFFECTIF', { est_pause: true })]);
  avec('previsionnel-seul-aucune-ligne', [creneauLot2('2026-07-06T06:00:00Z', '2026-07-06T14:00:00Z')]);
  avec('legacy-sans-offset', [creneauLot2('2026-07-06T08:00:00', '2026-07-06T16:00:00', 'EFFECTIF')]);
  avec('creneaux-identifiants-conserves', [creneauLot2('2026-07-06T06:00:00Z', '2026-07-06T14:00:00Z', 'EFFECTIF', { id: 'c1', mission_id: 'm' })]);
  const effectifJour = [creneauLot2('2026-07-06T06:00:00Z', '2026-07-06T14:00:00Z', 'EFFECTIF')];
  avec('presence-mission-id-null-ignoree', effectifJour, { presences: [{ mission_id: null }] });
  avec('presence-mission-id-vide-ignoree', effectifJour, { presences: [{ mission_id: '' }] });
  avec('presence-sans-mission-id-ignoree', effectifJour, { presences: [{}] });
  avec('presence-autre-mission', effectifJour, { presences: [{ mission_id: 'autre' }] });
  avec('presence-meme-mission-exclut', effectifJour, { presences: [{ mission_id: 'autre' }, { mission_id: 'm' }] });
  avec('etablissement-inconnu', effectifJour, { etablissements: {} });
  avec('soignant-propage', effectifJour, { soignantId: 'soignant-42' });
  const sansEtab = (nom, m) => historique(nom, { ...base, missions: [m], creneauxParMission: { m: effectifJour } });
  sansEtab('etablissement-id-null', { id: 'm', etablissement_id: null });
  sansEtab('etablissement-id-vide', { id: 'm', etablissement_id: '' });
  sansEtab('etablissement-id-absent', { id: 'm' });
  historique('mission-sans-creneaux', { ...base, missions: [mission], creneauxParMission: {} });
  historique('plusieurs-missions-ordre-conserve', {
    ...base,
    missions: [{ id: 'b', etablissement_id: 'etab-1' }, { id: 'a', etablissement_id: 'etab-2' }, { id: 'c' }],
    creneauxParMission: {
      a: [creneauLot2('2026-07-01T06:00:00Z', '2026-07-01T14:00:00Z', 'EFFECTIF')],
      b: [creneauLot2('2026-07-02T06:00:00Z', '2026-07-02T14:00:00Z', 'EFFECTIF')],
      c: [creneauLot2('2026-07-03T06:00:00Z', '2026-07-03T14:00:00Z', 'EFFECTIF')],
    },
    etablissements: { 'etab-1': { nom: 'Clinique Test' }, 'etab-2': { nom: 'Hôpital Nord' } },
  });
  historique('mission-dupliquee-deux-lignes', { ...base, missions: [mission, mission], creneauxParMission: { m: effectifJour } });
  historique('aucune-mission', { ...base, missions: [], creneauxParMission: { m: effectifJour } });

  for (const [nom, valeur] of [['grande', 12345.678], ['negative-zero-virgule', -0.5], ['chaine-nombre', '12'], ['vrai', true], ['objet', {}], ['tableau', []]]) {
    gps(`grille-${nom}`, valeur);
  }

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 10 : documentUpload (src/lib/documentUpload.ts)
// ---------------------------------------------------------------------------
// `verifierFichierDocument` est rejoué avec le `File` de Node : l'entrée décrit le fichier par
// son nom, son type déclaré, sa taille et ses premiers octets (le reste vaut zéro). Une
// `entete` nulle simule une lecture impossible (`slice().arrayBuffer()` rejeté). Le `File`
// de Node met le type en minuscules et le vide s'il n'est pas ASCII : l'export refuse un type
// que le constructeur aurait modifié autrement, pour que l'entrée soit celle que la règle lit.
const octetsTexte = (texte) => [...Buffer.from(texte, 'latin1')];
const SIGNATURES = {
  pdf: octetsTexte('%PDF-1.7\n'),
  jpeg: [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01],
  png: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d],
  webp: [...octetsTexte('RIFF'), 0x24, 0x00, 0x00, 0x00, ...octetsTexte('WEBPVP8 ')],
  heic: [0x00, 0x00, 0x00, 0x18, ...octetsTexte('ftypheic')],
  gif: octetsTexte('GIF89a'),
  wave: [...octetsTexte('RIFF'), 0x24, 0x00, 0x00, 0x00, ...octetsTexte('WAVE')],
  pdfSansTiret: octetsTexte('%PDF1.7'),
  pngTronque: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a],
  html: octetsTexte('<html>'),
};
const MO = 1024 * 1024;

async function vecteursDocumentUpload() {
  const c = new Collecteur('document-upload');
  const classer = (nom, name, type) => c.ajoute(`classerFormatDocument/${nom}`, { fonction: 'classerFormatDocument', name, type },
    documentUpload.classerFormatDocument({ name, type }));
  const sanitiser = (nom, name, mime) => c.ajoute(`sanitiserNomFichier/${nom}`, { fonction: 'sanitiserNomFichier', name, mime },
    documentUpload.sanitiserNomFichier(name, mime));
  const verifier = async (nom, { name, type, entete, taille = entete === null ? 16 : entete.length, options }) => {
    if (entete !== null && entete.length > taille) throw new Error(`document-upload: « ${nom} » : en-tête plus long que le fichier`);
    const contenu = new Uint8Array(taille);
    if (entete !== null) contenu.set(entete);
    const FichierIllisible = class extends File {
      slice() { return { arrayBuffer: () => Promise.reject(new Error('lecture simulée impossible')) }; }
    };
    const fichier = entete === null ? new FichierIllisible([contenu], name, { type }) : new File([contenu], name, { type });
    if (fichier.type !== type.toLowerCase()) throw new Error(`document-upload: « ${nom} » : type « ${type} » modifié par File`);
    const resultat = await documentUpload.verifierFichierDocument(fichier, options);
    c.ajoute(`verifierFichierDocument/${nom}`, { fonction: 'verifierFichierDocument', name, type, taille, entete, options }, resultat);
  };

  // --- Issus des tests vitest (documentUpload.test.ts) ----------------------
  for (const [name, type] of [['preuve.pdf', 'application/pdf'], ['photo.jpg', 'image/jpeg'], ['photo.png', 'image/png'],
    ['photo.webp', 'image/webp'], ['scan.PDF', 'application/octet-stream']]) {
    classer(`vitest-accepte-${name}`, name, type);
  }
  for (const [name, type] of [['photo.heic', 'image/heic'], ['photo.heif', 'image/heif'], ['photo.HEIC', '']]) {
    classer(`vitest-heic-${name}`, name, type);
  }
  classer('vitest-extension-image-contredite', 'malware.jpg', 'text/html');
  classer('vitest-deux-formats-contradictoires', 'piece.jpg', 'application/pdf');
  await verifier('vitest-signature-binaire', { name: 'piece.pdf', type: 'application/pdf', entete: [0xff, 0xd8, 0xff, 0x00] });
  await verifier('vitest-pdf-sans-mime', { name: 'SCAN.PDF', type: '', entete: octetsTexte('%PDF-1.7\n') });
  await verifier('vitest-sous-ensemble-pdf', { name: 'photo.jpg', type: 'image/jpeg', entete: [0xff, 0xd8, 0xff, 0x00], options: { allowedMimes: ['application/pdf'] } });
  await verifier('vitest-vide', { name: 'vide.pdf', type: 'application/pdf', entete: [] });
  await verifier('vitest-trop-lourd', { name: 'lourd.pdf', type: 'application/pdf', entete: octetsTexte('%PDF-1.7'), options: { maxBytes: 4 } });
  sanitiser('vitest-chemin-et-points', '../../Pièce.. finale.jpg', 'application/pdf');

  // --- Classement : grille nom × type déclaré ------------------------------
  const noms = ['preuve.pdf', 'scan.PDF', 'photo.jpg', 'photo.JPEG', 'photo.jpeg', 'photo.png', 'photo.webp', 'photo.heic', 'photo.HEIF',
    'photo.gif', 'sans-extension', 'archive.tar.gz', 'dossier/sous/photo.jpg', 'C:\\Users\\x\\scan.pdf', '.pdf', 'photo.',
    'photo.jpg.exe', 'photo.pdf.jpg', 'dossier.pdf/photo', 'photo.jpé', ''];
  const types = ['', 'application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
    'application/octet-stream', 'text/html', ' IMAGE/JPEG ', 'image/jpg', 'Image/HEIC', ' '];
  for (const name of noms) {
    for (const type of types) classer(`grille/nom=${name}|type=${type}`, name, type);
  }

  // --- Vérification : signatures, tailles, sous-ensembles, lecture ---------
  const formats = [
    ['pdf', 'preuve.pdf', 'application/pdf'], ['jpeg', 'photo.jpg', 'image/jpeg'], ['png', 'photo.png', 'image/png'], ['webp', 'photo.webp', 'image/webp'],
  ];
  for (const [format, name, type] of formats) {
    await verifier(`${format}-mime-exact`, { name, type, entete: SIGNATURES[format] });
    await verifier(`${format}-mime-absent`, { name, type: '', entete: SIGNATURES[format] });
    await verifier(`${format}-octet-stream`, { name, type: 'application/octet-stream', entete: SIGNATURES[format] });
    await verifier(`${format}-mime-majuscules-espaces`, { name, type: ` ${type.toUpperCase()} `, entete: SIGNATURES[format] });
    await verifier(`${format}-sans-extension`, { name: 'fichier', type, entete: SIGNATURES[format] });
    await verifier(`${format}-signature-gif`, { name, type, entete: SIGNATURES.gif });
    await verifier(`${format}-sous-ensemble-images`, { name, type, entete: SIGNATURES[format], options: { allowedMimes: ['image/jpeg', 'image/png', 'image/webp'] } });
    await verifier(`${format}-sous-ensemble-pdf`, { name, type, entete: SIGNATURES[format], options: { allowedMimes: ['application/pdf'] } });
    await verifier(`${format}-lecture-impossible`, { name, type, entete: null });
  }
  await verifier('jpeg-extension-jpeg', { name: 'photo.JPEG', type: '', entete: SIGNATURES.jpeg });
  await verifier('png-annonce-jpeg', { name: 'photo.jpg', type: 'image/jpeg', entete: SIGNATURES.png });
  await verifier('jpeg-annonce-png', { name: 'photo.png', type: 'image/png', entete: SIGNATURES.jpeg });
  await verifier('pdf-annonce-jpeg-sans-mime', { name: 'photo.jpg', type: '', entete: SIGNATURES.pdf });
  await verifier('webp-riff-wave', { name: 'photo.webp', type: 'image/webp', entete: SIGNATURES.wave });
  await verifier('webp-riff-tronque-11-octets', { name: 'photo.webp', type: 'image/webp', entete: SIGNATURES.webp.slice(0, 11) });
  await verifier('pdf-sans-tiret', { name: 'preuve.pdf', type: 'application/pdf', entete: SIGNATURES.pdfSansTiret });
  await verifier('png-tronque', { name: 'photo.png', type: 'image/png', entete: SIGNATURES.pngTronque });
  await verifier('pdf-tronque-3-octets', { name: 'preuve.pdf', type: 'application/pdf', entete: octetsTexte('%PD') });
  await verifier('html-annonce-pdf', { name: 'preuve.pdf', type: 'application/pdf', entete: SIGNATURES.html });
  await verifier('heic-contenu', { name: 'photo.heic', type: 'image/heic', entete: SIGNATURES.heic });
  await verifier('heic-sans-mime', { name: 'IMG_0001.HEIC', type: '', entete: SIGNATURES.heic });
  await verifier('heic-vide', { name: 'photo.heic', type: 'image/heic', entete: [] });
  await verifier('mime-jpg-non-standard', { name: 'photo.jpg', type: 'image/jpg', entete: SIGNATURES.jpeg });
  await verifier('mime-texte', { name: 'note.txt', type: 'text/plain', entete: octetsTexte('bonjour') });
  await verifier('sans-extension-sans-mime', { name: 'scan', type: '', entete: SIGNATURES.pdf });
  await verifier('mime-pdf-extension-jpg', { name: 'piece.jpg', type: 'application/pdf', entete: SIGNATURES.pdf });
  await verifier('signature-au-dela-de-12-octets-ignoree', { name: 'preuve.pdf', type: 'application/pdf', entete: [...octetsTexte('xxxxxxxxxxxx'), ...SIGNATURES.pdf] });
  await verifier('defaut-10-mo-exact', { name: 'preuve.pdf', type: 'application/pdf', entete: SIGNATURES.pdf, taille: 10 * MO });
  await verifier('defaut-10-mo-plus-1', { name: 'preuve.pdf', type: 'application/pdf', entete: SIGNATURES.pdf, taille: 10 * MO + 1 });
  await verifier('max-5-mo-exact', { name: 'preuve.pdf', type: 'application/pdf', entete: SIGNATURES.pdf, taille: 5 * MO, options: { maxBytes: 5 * MO } });
  await verifier('max-5-mo-plus-1', { name: 'preuve.pdf', type: 'application/pdf', entete: SIGNATURES.pdf, taille: 5 * MO + 1, options: { maxBytes: 5 * MO } });
  await verifier('max-5-octets-message-0-mo', { name: 'photo.png', type: 'image/png', entete: SIGNATURES.png, options: { maxBytes: 5 } });
  await verifier('trop-lourd-avant-format', { name: 'photo.heic', type: 'image/heic', entete: SIGNATURES.heic, taille: 10 * MO + 1 });
  await verifier('vide-avant-format', { name: 'note.txt', type: 'text/plain', entete: [] });
  await verifier('un-octet-pdf', { name: 'preuve.pdf', type: 'application/pdf', entete: [0x25] });

  // --- Nom de fichier assaini : grille nom × MIME ---------------------------
  const nomsAssainis = [
    'photo.jpg', 'PHOTO.JPG', 'Carte d’identité recto.pdf', 'Élodie Durand — diplôme.PNG', 'scan', '', '.pdf', '...', '---.jpg',
    'dossier/sous-dossier/fichier.webp', 'C:\\Users\\Élise\\Documents\\RIB.pdf', 'nom_avec_underscore-et-tiret.jpeg',
    'emoji 😀 test.png', 'x.tar.gz', `${'a'.repeat(100)}.pdf`, `${'é'.repeat(90)}.jpg`, 'Œuvre ß æ.pdf', 'e\u0301cole.pdf',
    'ﬁchier.pdf', '한국어.pdf', 'dossier/', 'photo.jpé', '-début-.pdf', ' espace .pdf', 'Ça été ÇA.jpg', 'ñandú.png',
  ];
  const mimes = ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'];
  nomsAssainis.forEach((name, index) => {
    for (const mime of mimes) sanitiser(`grille-${String(index).padStart(2, '0')}/${mime}`, name, mime);
  });

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 11 : documents (src/lib/documents.ts) — dispense de diplôme
// ---------------------------------------------------------------------------
function vecteursDocuments() {
  const c = new Collecteur('documents');
  const sansIndefini = (objet) => Object.fromEntries(Object.entries(objet).filter(([, v]) => v !== undefined));
  const libelle = (v) => (v === undefined ? 'absent' : JSON.stringify(v));
  const dispense = (profession, rppsVerifie) => c.ajoute(`rppsDispenseDiplome/${libelle(profession)}/${libelle(rppsVerifie)}`,
    sansIndefini({ fonction: 'rppsDispenseDiplome', profession, rppsVerifie }),
    documentsRegles.rppsDispenseDiplome(profession, rppsVerifie));
  const compatible = (profession, professionCertifiee) => c.ajoute(`diplomeCompatibleProfession/${libelle(profession)}/${libelle(professionCertifiee)}`,
    sansIndefini({ fonction: 'diplomeCompatibleProfession', profession, professionCertifiee }),
    documentsRegles.diplomeCompatibleProfession(profession, professionCertifiee));

  // La liste elle-même est un vecteur : un ajout côté web rougit le port Swift avant toute grille.
  c.ajoute('constante/PROFESSIONS_SANS_RPPS', { fonction: 'PROFESSIONS_SANS_RPPS' }, [...constantes.PROFESSIONS_SANS_RPPS]);

  // Les cas vitest (documents.test.ts) sont tous dans ces grilles (professions IADE, IBODE, AS,
  // AES, AUXILIAIRE_PUERICULTURE, IDE, MEDECIN, KINE, PHARMACIEN ; profession absente).
  const professions = ['IDE', 'MEDECIN', 'KINE', 'PHARMACIEN', 'SAGE_FEMME', 'DENTISTE', 'IADE', 'IBODE', 'AS', 'AES',
    'AUXILIAIRE_PUERICULTURE', 'PREPARATEUR_PHARMA', 'ide', 'iade', '', null, undefined];
  for (const profession of professions) {
    for (const rpps of [true, false, null, undefined]) dispense(profession, rpps);
  }
  const certifiees = ['IADE', 'iade', 'Iade', 'IBODE', 'ibode', 'IDE', 'AS', '', ' IADE', null, undefined, 42, true];
  for (const profession of ['IADE', 'IBODE', 'IDE', 'AS', 'MEDECIN', 'iade', '', null, undefined]) {
    for (const certifiee of certifiees) compatible(profession, certifiee);
  }

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 12 : contratMissionUi (src/lib/contratMissionUi.ts)
// ---------------------------------------------------------------------------
function vecteursContratMissionUi() {
  const c = new Collecteur('contrat-mission-ui');
  const sansIndefini = (objet) => Object.fromEntries(Object.entries(objet).filter(([, v]) => v !== undefined));
  const variables = (nom, html) => c.ajoute(`contientVariablesContratNonRendues/${nom}`,
    sansIndefini({ fonction: 'contientVariablesContratNonRendues', html }), contratUi.contientVariablesContratNonRendues(html));
  const signature = (nom, contrat) => c.ajoute(`contratPossedeSignature/${nom}`,
    sansIndefini({ fonction: 'contratPossedeSignature', contrat }), contratUi.contratPossedeSignature(contrat));
  const rendu = (nom, html, storagePath, contrat) => c.ajoute(`contratNecessiteRenduServeur/${nom}`,
    sansIndefini({ fonction: 'contratNecessiteRenduServeur', html, storagePath, contrat }),
    contratUi.contratNecessiteRenduServeur(html, storagePath, contrat));
  const contenu = (nom, contenuServeur, contenuReconstitue, conserverOriginal) => c.ajoute(`choisirContenuContratAffiche/${nom}`,
    sansIndefini({ fonction: 'choisirContenuContratAffiche', contenuServeur, contenuReconstitue, conserverOriginal }),
    contratUi.choisirContenuContratAffiche(contenuServeur, contenuReconstitue, conserverOriginal));

  // --- Issus des tests vitest (contratMissionUi.test.ts) --------------------
  variables('vitest-motif-cdd', '<p>{{motif_cdd}}</p>');
  contenu('vitest-apercu-si-variables', '<p>{{motif_cdd}}</p>', '<p>Aperçu</p>');
  rendu('vitest-apercu-sans-stockage', '<p>Aperçu</p>', null);
  rendu('vitest-stockage-ancien-sans-variable', '<p>10h/jour (L3121-18)</p>', 'contrat/ancien.html');
  rendu('vitest-stockage-ancien-avec-variable', '<p>{{motif_cdd}}</p>', 'contrat/ancien.html');
  const preuvesVitest = [['statut-signe-complet', { statut: 'SIGNE_COMPLET' }], ['statut-signe-soignant', { statut: 'SIGNE_SOIGNANT' }],
    ['signature-soignant', { signature_soignant: true }], ['signature-etablissement', { signature_etablissement: true }],
    ['signature-soignant-le', { signature_soignant_le: '2026-01-01' }], ['signature-etablissement-le', { signature_etablissement_le: '2026-01-01' }]];
  for (const [nom, contrat] of preuvesVitest) {
    signature(`vitest-${nom}`, contrat);
    rendu(`vitest-preuve-sans-stockage-${nom}`, null, null, contrat);
  }
  contenu('vitest-original-absent-conserve', null, '<p>Nouveau template</p>', true);
  contenu('vitest-original-avec-variable-conserve', '<p>Original {{variable}}</p>', '<p>Nouveau template</p>', true);

  // --- Variables de gabarit non rendues --------------------------------------
  for (const [nom, html] of [
    ['espaces', '{{ motif }}'], ['vide', '{{}}'], ['espace-seul', '{{ }}'], ['accolades-espacees', '{ {x} }'],
    ['fermeture-simple', '{{x}'], ['ouverture-simple', '{x}}'], ['triple', '{{{x}}}'], ['multiligne', '{{a\nb}}'],
    ['sans-variable', 'texte sans variable'], ['chaine-vide', ''], ['null', null], ['absent', undefined],
    ['inversees', '}}{{'], ['deux-variables', '{{x}} et {{y}}'], ['accolade-interne', '{{ x } }}'], ['quadruple', '{{{{}}}}'],
    ['html-attribut', '<a title="{{titre}}">x</a>'], ['accents', '{{prénom_soignant}}'], ['fin-de-texte', 'Signé par {{'],
  ]) {
    variables(nom, html);
  }

  // --- Preuve de signature ----------------------------------------------------
  for (const [nom, contrat] of [
    ['null', null], ['absent', undefined], ['vide', {}], ['statut-signe', { statut: 'SIGNE' }], ['statut-minuscules', { statut: 'signe_complet' }],
    ['statut-non-signe', { statut: 'NON_SIGNE' }], ['statut-en-attente', { statut: 'EN_ATTENTE_SIGNATURES' }], ['statut-null', { statut: null }],
    ['statut-vide', { statut: '' }], ['statut-espace-signe', { statut: ' SIGNE_COMPLET' }], ['signature-soignant-faux', { signature_soignant: false }],
    ['signature-soignant-null', { signature_soignant: null }], ['signature-etablissement-faux', { signature_etablissement: false }],
    ['signature-soignant-le-vide', { signature_soignant_le: '' }], ['signature-soignant-le-null', { signature_soignant_le: null }],
    ['signature-etablissement-le-iso', { signature_etablissement_le: '2026-01-01T10:00:00Z' }],
    ['expire-sans-preuve', { statut: 'EXPIRE', signature_soignant: false, signature_etablissement: false, signature_soignant_le: null, signature_etablissement_le: null }],
    ['annule-avec-date-etablissement', { statut: 'ANNULE', signature_etablissement_le: '2026-01-01' }],
  ]) {
    signature(nom, contrat);
  }

  // --- Rendu serveur nécessaire : grille stockage × contrat × html ignoré -----
  const stockages = [['stockage-null', null], ['stockage-absent', undefined], ['stockage-vide', ''], ['stockage-present', 'contrat/ancien.html']];
  const contrats = [['contrat-absent', undefined], ['contrat-null', null], ['en-attente', { statut: 'EN_ATTENTE_SIGNATURES' }],
    ['signe-soignant', { statut: 'SIGNE_SOIGNANT' }], ['signature-etablissement', { signature_etablissement: true }]];
  for (const [nomStockage, storagePath] of stockages) {
    for (const [nomContrat, contrat] of contrats) {
      for (const [nomHtml, html] of [['apercu', '<p>Aperçu</p>'], ['variables', '<p>{{motif_cdd}}</p>']]) {
        rendu(`grille/${nomStockage}/${nomContrat}/${nomHtml}`, html, storagePath, contrat);
      }
    }
  }

  // --- Contenu affiché : grille serveur × reconstitué × conservation --------
  const serveurs = [['original', '<p>Original</p>'], ['original-variable', '<p>Original {{variable}}</p>'], ['vide', ''], ['null', null], ['absent', undefined]];
  const reconstitues = [['apercu', '<p>Aperçu</p>'], ['vide', ''], ['null', null], ['absent', undefined]];
  for (const [nomServeur, serveur] of serveurs) {
    for (const [nomReconstitue, reconstitue] of reconstitues) {
      for (const [nomConserver, conserver] of [['conserver', true], ['ne-pas-conserver', false], ['conservation-absente', undefined]]) {
        contenu(`grille/${nomServeur}/${nomReconstitue}/${nomConserver}`, serveur, reconstitue, conserver);
      }
    }
  }

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 13 : signatureSmsStagingAdmission (src/lib/signatureSmsStagingAdmission.ts)
// ---------------------------------------------------------------------------
// Rejoué avec un client RPC simulé : `reponse` est ce que le client renvoie (`{ data, error }`)
// ou `{ leve: true }` (transport en erreur). L'attendu consigne les arguments de chaque appel
// (aucun appel quand l'URL ou l'identifiant est refusé avant) et le résultat, instants en ISO.
// Domaine des dates : ISO 8601, celui de `to_jsonb(timestamptz)` ; `Date.parse` accepte aussi
// des formats non ISO (RFC 2822…) que le port Swift refuse (échec fermé), hors vecteurs.
async function vecteursAdmissionSms() {
  const c = new Collecteur('signature-sms-staging-admission');
  const URL_STAGING = 'https://mejpriaetwgtcstbgfid.supabase.co';
  const CONTRAT = '3f2c9a10-5b7d-4e21-9c3a-0d8e6f4b2a17';
  const MAINTENANT = '2026-11-02T10:00:00.000Z';
  const NOM_RPC = 'fn_admission_otp_signature_recette';
  const plus = (minutes, ms = 0) => new Date(Date.parse(MAINTENANT) + minutes * 60_000 + ms).toISOString();
  const lire = async (nom, { url = URL_STAGING, contratId = CONTRAT, maintenant = MAINTENANT, reponse }) => {
    const appels = [];
    const client = {
      rpc: async (name, args) => {
        appels.push({ name, args });
        if (reponse.leve) throw new Error('transport simulé');
        return { data: reponse.data, error: reponse.error ?? null };
      },
    };
    const r = await admissionSms.readSignatureSmsStagingAdmission(client, url, contratId, Date.parse(maintenant));
    if (appels.some((appel) => appel.name !== NOM_RPC)) throw new Error(`signature-sms-staging-admission: « ${nom} » : RPC inattendue`);
    c.ajoute(`readSignatureSmsStagingAdmission/${nom}`, { fonction: 'readSignatureSmsStagingAdmission', url, contratId, maintenant, reponse }, {
      appels: appels.map((appel) => appel.args),
      resultat: r === null ? null : {
        expiresAt: iso(new Date(r.expiresAt)),
        canSend: r.canSend,
        canValidate: r.canValidate,
        otpExpiresAt: r.otpExpiresAt === null ? null : iso(new Date(r.otpExpiresAt)),
      },
    });
  };
  const envoi = { admitted: true, can_send: true, can_validate: false, otp_expires_at: null, expires_at: plus(30), remaining: 2 };
  const validation = { admitted: true, can_send: true, can_validate: true, otp_expires_at: plus(5), expires_at: plus(30), remaining: 1 };
  const donnees = (nom, data) => lire(nom, { reponse: { data, error: null } });

  // --- Admissions acceptées --------------------------------------------------
  await donnees('envoi-seul', envoi);
  await donnees('envoi-et-validation', validation);
  await donnees('validation-seule-plus-aucun-envoi', { ...validation, can_send: false, remaining: 0 });
  await donnees('otp-borne-par-capacite', { ...validation, expires_at: plus(3), otp_expires_at: plus(5) });
  await donnees('capacite-60-min-exactes', { ...envoi, expires_at: plus(60) });
  await donnees('otp-10-min-exactes', { ...validation, otp_expires_at: plus(10) });
  await donnees('otp-absent-sans-validation', (({ otp_expires_at: _o, ...reste }) => reste)(envoi));
  await donnees('dates-postgres-microsecondes', { ...validation, expires_at: '2026-11-02T10:30:00.123456+00:00', otp_expires_at: '2026-11-02T10:05:00.654321+00:00' });
  await donnees('dates-offset-paris', { ...validation, expires_at: '2026-11-02T11:30:00+01:00', otp_expires_at: '2026-11-02T11:05:00+01:00' });
  await donnees('dates-legacy-heure-de-paris', { ...envoi, expires_at: '2026-11-02T11:30:00' });
  await donnees('cles-supplementaires-ignorees', { ...envoi, run_id: 'sms-signature-recette', message: 'ok' });
  await lire('uuid-majuscules', { contratId: CONTRAT.toUpperCase(), reponse: { data: envoi, error: null } });

  // --- Refus avant tout appel --------------------------------------------------
  for (const [nom, url] of [
    ['url-production', 'https://flripxtsyegjshnhzjkz.supabase.co'], ['url-barre-finale', `${URL_STAGING}/`], ['url-http', 'http://mejpriaetwgtcstbgfid.supabase.co'],
    ['url-majuscules', 'https://MEJPRIAETWGTCSTBGFID.supabase.co'], ['url-vide', ''], ['url-suffixe', `${URL_STAGING}.evil.example`],
  ]) {
    await lire(nom, { url, reponse: { data: envoi, error: null } });
  }
  for (const [nom, contratId] of [
    ['contrat-vide', ''], ['contrat-non-uuid', 'contrat-1'], ['contrat-uuid-tronque', CONTRAT.slice(0, 35)], ['contrat-uuid-accolades', `{${CONTRAT}}`],
    ['contrat-uuid-sans-tirets', CONTRAT.replaceAll('-', '')], ['contrat-uuid-espace', ` ${CONTRAT}`], ['contrat-uuid-hex-invalide', CONTRAT.replace('3f', 'zz')],
  ]) {
    await lire(nom, { contratId, reponse: { data: envoi, error: null } });
  }

  // --- Réponse en erreur ou malformée ----------------------------------------
  await lire('erreur-rpc', { reponse: { data: null, error: { code: 'PGRST202', message: 'Could not find the function' } } });
  await lire('erreur-avec-donnees', { reponse: { data: envoi, error: { code: '42501', message: 'permission denied' } } });
  await lire('transport-leve', { reponse: { leve: true } });
  for (const [nom, data] of [['null', null], ['absente', undefined], ['tableau', [envoi]], ['chaine', 'admitted'], ['vrai', true], ['zero', 0], ['objet-vide', {}]]) {
    await lire(`donnees-${nom}`, { reponse: { data, error: null } });
  }
  for (const [nom, champs] of [
    ['admitted-faux', { admitted: false }], ['admitted-chaine', { admitted: 'true' }], ['admitted-un', { admitted: 1 }],
    ['admitted-absent', { admitted: undefined }], ['expires-at-absent', { expires_at: undefined }], ['expires-at-nombre', { expires_at: Date.parse(plus(30)) }],
    ['expires-at-illisible', { expires_at: 'demain' }], ['expires-at-null', { expires_at: null }], ['remaining-decimal', { remaining: 1.5 }],
    ['remaining-negatif', { remaining: -1 }], ['remaining-trois', { remaining: 3 }], ['remaining-chaine', { remaining: '2' }],
    ['remaining-null', { remaining: null }], ['remaining-zero-envoi-annonce', { remaining: 0 }], ['envoi-refuse-avec-capacite', { can_send: false }],
    ['can-send-chaine', { can_send: 'true' }], ['can-validate-null', { can_validate: null }], ['can-validate-absent', { can_validate: undefined }],
    ['capacite-expiree-maintenant', { expires_at: MAINTENANT }], ['capacite-passee', { expires_at: plus(-1) }], ['capacite-60-min-plus-1-ms', { expires_at: plus(60, 1) }],
    ['otp-chaine-sans-validation', { otp_expires_at: plus(5) }],
  ]) {
    await donnees(`envoi/${nom}`, { ...envoi, ...champs });
  }
  for (const [nom, champs] of [
    ['ni-envoi-ni-validation', { can_send: false, can_validate: false, remaining: 0 }], ['otp-absent', { otp_expires_at: undefined }],
    ['otp-null', { otp_expires_at: null }], ['otp-nombre', { otp_expires_at: Date.parse(plus(5)) }], ['otp-illisible', { otp_expires_at: 'bientôt' }],
    ['otp-maintenant', { otp_expires_at: MAINTENANT }], ['otp-passe', { otp_expires_at: plus(-1) }], ['otp-10-min-plus-1-ms', { otp_expires_at: plus(10, 1) }],
  ]) {
    await donnees(`validation/${nom}`, { ...validation, ...champs });
  }

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règles 14 et 15 : lot 2, T2b (règles extraites par la PR web W1, #1112)
// ---------------------------------------------------------------------------
const estChaineOuNul = (v) => v === undefined || v === null || typeof v === 'string';
const estBooleenOuNul = (v) => v === undefined || v === null || typeof v === 'boolean';
/** Refuse une entrée hors du domaine rejoué par le port Swift (le message nomme le champ). */
function domaine(regle, condition, quoi) {
  if (!condition) throw new Error(`${regle}: entrée hors domaine (${quoi}) : la décoder côté Swift ou retirer le vecteur.`);
}

// ---------------------------------------------------------------------------
// Règle 14 : documents-requis (src/lib/documents-requis.ts)
// ---------------------------------------------------------------------------
// `filtrerDocumentsRequis` est générique : il renvoie les lignes reçues qu'il retient, dans leur
// ordre. L'attendu recopie donc ces lignes telles quelles, et le port Swift rend les lignes JSON
// d'entrée qu'il retient. Domaine relu dans `public.sql` (`documents_requis_par_profession`
// l.69057-69067) : `profession` et `type_document` sont NOT NULL ; `type_exercice_requis` est
// NOT NULL et contraint (`TOUS`, `SALARIE_ONLY`, `LIBERAL_ONLY`), mais la règle web replie nul,
// vide ou inconnu sur `TOUS` : ces valeurs restent dans les vecteurs. Profil : chaînes ou nul,
// booléens ou nul (absent compris). Pièce (`documents_soignants`) : `type_document` NOT NULL,
// `statut_verification` NULLable (l.408), donc chaîne ou nul. `documentValidePourExigence` lit `valide_jusqua` par
// `new Date` : date seule (colonne `date`, minuit UTC) ou ISO avec ou sans décalage (heure de
// Paris, fuseau forcé du processus) ; tout autre format de date est hors domaine.
function vecteursDocumentsRequis() {
  const c = new Collecteur('documents-requis');
  const R = 'documents-requis';
  const verifierRegle = (r) => {
    domaine(R, typeof r.profession === 'string' && typeof r.type_document === 'string', 'profession et type_document : chaînes NOT NULL');
    domaine(R, estChaineOuNul(r.type_exercice_requis), 'type_exercice_requis : chaîne ou nul');
  };
  const verifierSoignant = (s) => {
    domaine(R, estChaineOuNul(s.profession) && estChaineOuNul(s.type_exercice), 'profession, type_exercice : chaîne ou nul');
    domaine(R, estBooleenOuNul(s.rpps_verifie) && estBooleenOuNul(s.adeli_verifie), 'rpps_verifie, adeli_verifie : booléen ou nul');
  };
  const filtrer = (nom, regles, soignant) => {
    (regles ?? []).forEach(verifierRegle);
    verifierSoignant(soignant);
    c.ajoute(`filtrerDocumentsRequis/${nom}`, { fonction: 'filtrerDocumentsRequis', regles, soignant },
      documentsRequis.filtrerDocumentsRequis(regles, soignant));
  };
  const valide = (nom, document, exigence, profession, maintenant) => {
    domaine(R, typeof document.type_document === 'string', 'type_document : chaîne NOT NULL');
    // `statut_verification` est NULLable (DEFAULT 'EN_ATTENTE' sans NOT NULL, `public.sql` l.408 ;
    // `| null` dans `types.ts`) : le web garde la ligne et la juge non valide (`=== 'VERIFIE'`).
    domaine(R, estChaineOuNul(document.statut_verification), 'statut_verification : chaîne ou nul');
    domaine(R, estChaineOuNul(document.valide_jusqua) && typeof exigence.type_document === 'string' && estChaineOuNul(profession), 'valide_jusqua, exigence, profession');
    c.ajoute(`documentValidePourExigence/${nom}`, { fonction: 'documentValidePourExigence', document, exigence, profession, maintenant },
      documentsRequis.documentValidePourExigence(document, exigence, profession, new Date(maintenant)));
  };

  // La liste elle-même est un vecteur : un type ajouté côté web rougit le port Swift.
  c.ajoute('constante/TYPES_DOCUMENTS_EXCLUS_UPLOAD', { fonction: 'TYPES_DOCUMENTS_EXCLUS_UPLOAD' }, [...documentsRegles.TYPES_DOCUMENTS_EXCLUS_UPLOAD]);

  // --- Issus des tests vitest (documents-requis.test.ts) -------------------
  const regle = (type_document, extra = {}) => ({
    id: `${type_document}-${String(extra.profession ?? 'IDE')}-${String(extra.type_exercice_requis ?? 'TOUS')}`,
    profession: 'IDE', type_document, est_critique: true, type_exercice_requis: 'TOUS', ...extra,
  });
  const REGLES_IDE = [
    regle('CARTE_IDENTITE'), regle('DIPLOME'), regle('RPPS_ADELI'), regle('AUTORISATION_EXERCICE', { est_critique: false }),
    regle('VACCINATIONS'), regle('MEDECINE_TRAVAIL'), regle('RCP_ASSURANCE', { type_exercice_requis: 'LIBERAL_ONLY' }),
    regle('ATTESTATION_URSSAF', { type_exercice_requis: 'LIBERAL_ONLY' }), regle('CASIER_JUDICIAIRE', { type_exercice_requis: 'SALARIE_ONLY' }),
  ];
  const soignant = (extra = {}) => ({ profession: 'IDE', type_exercice: 'SALARIE', rpps_verifie: false, adeli_verifie: false, ...extra });
  const pour = (profession) => REGLES_IDE.map((r) => ({ ...r, profession }));

  filtrer('vitest-profession-ordre-recu', [
    regle('DIPLOME', { profession: 'KINE' }), regle('CARTE_IDENTITE'), regle('DIPLOME'), regle('CARTE_IDENTITE', { profession: 'AS' }),
  ], soignant());
  filtrer('vitest-mixte-exclus-upload-et-cumul', REGLES_IDE, soignant({ type_exercice: 'MIXTE' }));
  filtrer('vitest-liberal', REGLES_IDE, soignant({ type_exercice: 'LIBERAL' }));
  for (const typeExercice of ['SALARIE', 'CDD', 'INTERIM']) filtrer(`vitest-salarie-${typeExercice}`, REGLES_IDE, soignant({ type_exercice: typeExercice }));
  for (const [nom, typeExercice] of [['null', null], ['absent', undefined], ['vide', '']]) {
    filtrer(`vitest-sans-type-exercice-${nom}`, REGLES_IDE, soignant({ type_exercice: typeExercice }));
  }
  filtrer('vitest-type-exercice-requis-repli-tous', [
    regle('CARTE_IDENTITE', { type_exercice_requis: null }), regle('DIPLOME', { type_exercice_requis: undefined }),
    regle('RIB', { type_exercice_requis: 'AUTRE_VALEUR' }),
  ], soignant({ type_exercice: null }));
  filtrer('vitest-regles-null', null, soignant());
  filtrer('vitest-regles-absentes', undefined, soignant());
  filtrer('vitest-rpps-ide-dispenses', REGLES_IDE, soignant({ rpps_verifie: true }));
  for (const profession of ['IADE', 'IBODE']) filtrer(`vitest-rpps-specialite-${profession}`, pour(profession), soignant({ profession, rpps_verifie: true }));
  for (const profession of ['AS', 'AES', 'AUXILIAIRE_PUERICULTURE']) {
    filtrer(`vitest-sans-rpps-${profession}`, pour(profession), soignant({ profession, rpps_verifie: true }));
  }
  filtrer('vitest-adeli-ide', REGLES_IDE, soignant({ adeli_verifie: true }));
  filtrer('vitest-adeli-as', pour('AS'), soignant({ profession: 'AS', adeli_verifie: true }));
  for (const [nom, valeur] of [['faux', false], ['null', null], ['absent', undefined]]) {
    filtrer(`vitest-rpps-${nom}-garde-diplome`, REGLES_IDE, soignant({ rpps_verifie: valeur }));
  }

  const MAINTENANT = '2026-11-02T10:00:00Z';
  const doc = (extra = {}) => ({ type_document: 'CARTE_IDENTITE', statut_verification: 'VERIFIE', valide_jusqua: null, profession_certifiee: null, ...extra });
  const carte = { type_document: 'CARTE_IDENTITE' };
  const diplome = { type_document: 'DIPLOME' };
  valide('vitest-meme-type-verifie', doc(), carte, 'IDE', MAINTENANT);
  valide('vitest-autre-type', doc({ type_document: 'PASSEPORT' }), carte, 'IDE', MAINTENANT);
  for (const statut of ['EN_ATTENTE', 'REJETE', 'EXPIRE', 'REVUE_MANUELLE_REQUISE', 'API_INDISPONIBLE']) {
    valide(`vitest-statut-${statut}`, doc({ statut_verification: statut }), carte, 'IDE', MAINTENANT);
  }
  valide('vitest-fin-validite-plus-1-ms', doc({ valide_jusqua: '2026-11-02T10:00:00.001Z' }), carte, 'IDE', MAINTENANT);
  valide('vitest-fin-validite-atteinte', doc({ valide_jusqua: '2026-11-02T10:00:00Z' }), carte, 'IDE', MAINTENANT);
  valide('vitest-fin-validite-veille', doc({ valide_jusqua: '2026-11-01' }), carte, 'IDE', MAINTENANT);
  valide('vitest-fin-validite-vide', doc({ valide_jusqua: '' }), carte, 'IDE', MAINTENANT);
  for (const profession of ['IADE', 'IBODE']) {
    for (const [nom, certifiee] of [['exacte', profession], ['minuscules', profession.toLowerCase()], ['IDE', 'IDE'], ['null', null]]) {
      valide(`vitest-diplome-${profession}-certifie-${nom}`, doc({ type_document: 'DIPLOME', profession_certifiee: certifiee }), diplome, profession, MAINTENANT);
    }
  }
  valide('vitest-specialite-hors-diplome', doc(), carte, 'IADE', MAINTENANT);
  valide('vitest-diplome-ide-sans-certification', doc({ type_document: 'DIPLOME', profession_certifiee: null }), diplome, 'IDE', MAINTENANT);

  // --- Grille : type d'exercice × exigence de régime ------------------------
  // Une ligne par valeur de `type_exercice_requis` (dont nul, vide, inconnu, minuscules, absent),
  // plus les deux types remplacés par l'attestation sur l'honneur sous chaque régime.
  // Lignes de grille réduites aux colonnes que lit la règle (le port rend la ligne reçue entière).
  const ligne = (type_document, type_exercice_requis = 'TOUS', profession = 'IDE') => ({ profession, type_document, type_exercice_requis });
  const REGIMES = [
    ligne('CARTE_IDENTITE'), ligne('RCP_ASSURANCE', 'LIBERAL_ONLY'), ligne('CASIER_JUDICIAIRE', 'SALARIE_ONLY'), ligne('RIB', null),
    ligne('ATTESTATION_URSSAF', ''), ligne('EXTRAIT_KBIS', 'AUTRE'), ligne('PERMIS', 'liberal_only'), ligne('PHOTO', 'salarie_only'),
    { profession: 'IDE', type_document: 'JUSTIFICATIF_DOMICILE' },
    ligne('VACCINATIONS', 'LIBERAL_ONLY'), ligne('MEDECINE_TRAVAIL', 'SALARIE_ONLY'), ligne('vaccinations'), ligne('MEDECINE_TRAVAIL '),
  ];
  for (const [nom, typeExercice] of [
    ['SALARIE', 'SALARIE'], ['LIBERAL', 'LIBERAL'], ['MIXTE', 'MIXTE'], ['CDD', 'CDD'], ['INTERIM', 'INTERIM'],
    ['inconnu', 'AUTRE_REGIME'], ['liberal-minuscules', 'liberal'], ['mixte-minuscules', 'mixte'], ['espace-LIBERAL', ' LIBERAL'],
    ['null', null], ['vide', ''], ['absent', undefined],
  ]) {
    filtrer(`grille/regime/${nom}`, REGIMES, { profession: 'IDE', type_exercice: typeExercice, rpps_verifie: false, adeli_verifie: false });
  }

  // --- Grille : profession × registre (RPPS, ADELI), régime MIXTE ------------
  // Les quatre types que les registres masquent, plus un type témoin ; une ligne d'une autre
  // profession dans chaque liste vérifie que le filtre de profession précède les dispenses.
  // MEDECIN représente les autres professions à RPPS (KINE, SAGE_FEMME… : même branche de la règle).
  const professionsRegistre = ['IDE', 'MEDECIN', 'IADE', 'IBODE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE', 'ide'];
  const libelleBool = (v) => (v === undefined ? 'absent' : String(v));
  // Vrai et faux pour chaque profession ; nul (qui vaut faux) sur trois professions témoins :
  // avec RPPS, spécialité exacte, sans RPPS.
  const avecNul = new Set(['IDE', 'IADE', 'AS']);
  for (const profession of professionsRegistre) {
    const regles = ['CARTE_IDENTITE', 'DIPLOME', 'RPPS_ADELI', 'AUTORISATION_EXERCICE'].map((type_document) => ligne(type_document, 'TOUS', profession));
    regles.push(ligne('DIPLOME', 'TOUS', profession === 'IDE' ? 'KINE' : 'IDE'));
    const valeurs = avecNul.has(profession) ? [true, false, null] : [true, false];
    for (const rpps of valeurs) {
      for (const adeli of valeurs) {
        filtrer(`grille/registre/${profession}/rpps-${libelleBool(rpps)}/adeli-${libelleBool(adeli)}`, regles,
          { profession, type_exercice: 'MIXTE', rpps_verifie: rpps, adeli_verifie: adeli });
      }
    }
  }
  const reglesIde = ['CARTE_IDENTITE', 'DIPLOME', 'RPPS_ADELI', 'AUTORISATION_EXERCICE'].map((type_document) => ({ profession: 'IDE', type_document }));
  for (const [nom, extra] of [['rpps-absent-adeli-absent', {}], ['rpps-vrai-adeli-absent', { rpps_verifie: true }], ['rpps-absent-adeli-vrai', { adeli_verifie: true }]]) {
    filtrer(`grille/registre/IDE/${nom}`, reglesIde, { profession: 'IDE', type_exercice: 'SALARIE', ...extra });
  }

  // --- Grille : profession du soignant absente, vide ou d'une autre casse ---
  const reglesProfessions = [
    { profession: 'IDE', type_document: 'DIPLOME', type_exercice_requis: 'TOUS' },
    { profession: 'ide', type_document: 'DIPLOME', type_exercice_requis: 'TOUS' },
    { profession: '', type_document: 'CARTE_IDENTITE', type_exercice_requis: 'TOUS' },
    { profession: 'KINE', type_document: 'DIPLOME', type_exercice_requis: 'TOUS' },
    { profession: 'IDE', type_document: 'RPPS_ADELI', type_exercice_requis: 'TOUS' },
  ];
  for (const [nom, profession] of [['IDE', 'IDE'], ['ide', 'ide'], ['vide', ''], ['null', null], ['absente', undefined]]) {
    for (const rpps of [true, false]) {
      filtrer(`grille/profession/${nom}/rpps-${rpps}`, reglesProfessions, { profession, type_exercice: 'LIBERAL', rpps_verifie: rpps, adeli_verifie: false });
    }
  }

  // --- Grille : ordre et doublons conservés, liste vide ---------------------
  filtrer('grille/ordre-et-doublons', [
    regle('RIB', { type_exercice_requis: 'LIBERAL_ONLY' }), regle('CARTE_IDENTITE'), regle('RIB', { type_exercice_requis: 'LIBERAL_ONLY' }),
    regle('DIPLOME'), regle('CARTE_IDENTITE', { est_critique: false }),
  ], soignant({ type_exercice: 'LIBERAL' }));
  filtrer('grille/liste-vide', [], soignant());
  filtrer('grille/seulement-exclus-upload', [regle('VACCINATIONS'), regle('MEDECINE_TRAVAIL')], soignant({ type_exercice: 'MIXTE' }));

  // --- Grille : documentValidePourExigence ----------------------------------
  for (const statut of ['VERIFIE', 'verifie', 'Verifie', 'EN_ATTENTE', 'REJETE', 'EXPIRE', 'REVUE_MANUELLE_REQUISE', 'API_INDISPONIBLE', '']) {
    valide(`grille/statut/${statut || 'vide'}`, doc({ statut_verification: statut }), carte, 'IDE', MAINTENANT);
  }
  // Statut NULL (colonne NULLable) : la ligne reste lisible et la pièce n'est pas valide.
  valide('grille/statut/null', doc({ statut_verification: null }), carte, 'IDE', MAINTENANT);
  valide('grille/type/casse-differente', doc({ type_document: 'carte_identite' }), carte, 'IDE', MAINTENANT);
  valide('grille/type/diplome-pour-carte', doc({ type_document: 'DIPLOME', profession_certifiee: 'IADE' }), carte, 'IADE', MAINTENANT);
  valide('grille/type/carte-pour-diplome', doc(), diplome, 'IDE', MAINTENANT);
  // Fin de validité : nulle, absente, vide ; date seule (minuit UTC) ; ISO avec ou sans décalage.
  const { valide_jusqua: _sansFin, ...docSansFin } = doc();
  valide('grille/fin/absente', docSansFin, carte, 'IDE', MAINTENANT);
  for (const [nom, fin] of [
    ['null', null], ['date-seule-jour-meme', '2026-11-02'], ['date-seule-lendemain', '2026-11-03'], ['date-seule-an-prochain', '2027-11-02'],
    ['date-seule-passee', '2020-01-31'], ['utc-moins-1-ms', '2026-11-02T09:59:59.999Z'], ['utc-plus-1-s', '2026-11-02T10:00:01Z'],
    ['decalage-paris-egal', '2026-11-02T11:00:00+01:00'], ['decalage-paris-plus-1-ms', '2026-11-02T11:00:00.001+01:00'],
    ['decalage-postgrest-microsecondes-egal', '2026-11-02T10:00:00.000999+00:00'], ['decalage-postgrest-microsecondes-apres', '2026-11-02T10:00:00.001999+00:00'],
    ['sans-decalage-heure-paris-egale', '2026-11-02T11:00:00'], ['sans-decalage-heure-paris-plus-1-s', '2026-11-02T11:00:01'],
    ['sans-decalage-heure-utc', '2026-11-02T10:00:00'], ['illisible', 'pas une date'],
  ]) {
    valide(`grille/fin/${nom}`, doc({ valide_jusqua: fin }), carte, 'IDE', MAINTENANT);
  }
  // Changement d'heure : une fin de validité en date seule vaut minuit UTC, pas minuit à Paris.
  valide('grille/fin/date-seule-dst-mars-avant-minuit-utc', doc({ valide_jusqua: '2026-03-29' }), carte, 'IDE', '2026-03-28T23:30:00Z');
  valide('grille/fin/date-seule-dst-mars-apres-minuit-utc', doc({ valide_jusqua: '2026-03-29' }), carte, 'IDE', '2026-03-29T00:30:00Z');
  valide('grille/fin/date-seule-minuit-paris-avant-minuit-utc', doc({ valide_jusqua: '2026-11-02' }), carte, 'IDE', '2026-11-01T23:30:00Z');
  // Diplôme : profession de la mission × profession certifiée (toute valeur non textuelle compte pour absente).
  // La correspondance elle-même est couverte par `documents.json` (diplomeCompatibleProfession) :
  // cette grille vérifie qu'elle n'est appliquée qu'à l'exigence DIPLOME, avec la profession reçue.
  for (const profession of ['IADE', 'IBODE', 'IDE', 'iade', null, undefined]) {
    for (const [nom, certifiee] of [['IADE', 'IADE'], ['iade', 'iade'], ['IDE', 'IDE'], ['espace', ' IADE'],
      ['null', null], ['absente', undefined], ['nombre', 42]]) {
      const pieces = doc({ type_document: 'DIPLOME', profession_certifiee: certifiee });
      if (certifiee === undefined) delete pieces.profession_certifiee;
      valide(`grille/diplome/${libelleBool(profession) || 'vide'}/certifiee-${nom}`, pieces, diplome, profession, MAINTENANT);
    }
  }
  valide('grille/diplome/IADE-certifie-mais-rejete', doc({ type_document: 'DIPLOME', profession_certifiee: 'IADE', statut_verification: 'REJETE' }), diplome, 'IADE', MAINTENANT);
  valide('grille/diplome/IADE-certifie-mais-expire', doc({ type_document: 'DIPLOME', profession_certifiee: 'IADE', valide_jusqua: '2026-11-01' }), diplome, 'IADE', MAINTENANT);

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 15 : presences-soignant-listes (src/lib/presences-soignant-listes.ts)
// ---------------------------------------------------------------------------
// `construireListesPresences` recopie chaque mission lue (`...mission`) : l'attendu n'en garde que
// l'identifiant, les créneaux (avec le repli ponctuel) et l'établissement résolu, plus, pour
// « À venir », la date, le prochain créneau, la durée (NaN → null, comme `JSON.stringify`) et
// `planningAConfirmer` (absent → faux). Le contrat retenu par mission est réduit à son
// identifiant. Domaine relu dans `public.sql` : `mission_creneaux.mission_id` (l.70567) et
// `contrats_mission.mission_id` (l.68776) sont NOT NULL ; un créneau porte exactement les colonnes
// lues par la page (`id, mission_id, debut, fin, est_pause, type_creneau`) ; un établissement
// est un objet (`fn_etablissements_safe`). L'ordre des clés d'un regroupement n'est pas comparé
// (les vecteurs sont comparés structurellement) : seul l'ordre des créneaux d'une mission l'est.
function vecteursPresencesSoignantListes() {
  const c = new Collecteur('presences-soignant-listes');
  const R = 'presences-soignant-listes';
  const COLONNES_CRENEAU = new Set(['id', 'mission_id', 'debut', 'fin', 'est_pause', 'type_creneau']);
  const verifierCreneau = (cr) => {
    domaine(R, ['debut', 'fin', 'est_pause', 'type_creneau'].every((cle) => Object.hasOwn(cr, cle))
      && Object.keys(cr).every((cle) => COLONNES_CRENEAU.has(cle)), `créneau aux colonnes ${JSON.stringify(Object.keys(cr))}`);
    domaine(R, typeof cr.debut === 'string' && (cr.fin === null || typeof cr.fin === 'string')
      && typeof cr.est_pause === 'boolean' && typeof cr.type_creneau === 'string', 'créneau : types des colonnes');
    domaine(R, cr.id === undefined || typeof cr.id === 'string', 'créneau : id');
    domaine(R, cr.mission_id === undefined || typeof cr.mission_id === 'string', 'créneau : mission_id');
  };
  const regrouper = (nom, creneaux) => {
    for (const cr of creneaux ?? []) {
      verifierCreneau(cr);
      domaine(R, typeof cr.mission_id === 'string', 'regroupement : mission_id NOT NULL');
    }
    c.ajoute(`regrouperCreneauxParMission/${nom}`, { fonction: 'regrouperCreneauxParMission', creneaux },
      presencesListes.regrouperCreneauxParMission(creneaux));
  };
  const projeter = (m, source, autres) => {
    clesExactes(R, m, [...new Set([...Object.keys(source), 'creneaux', 'etablissements', ...autres])]);
    return { id: m.id, creneaux: m.creneaux, etablissements: m.etablissements };
  };
  const construire = (nom, args) => {
    for (const m of args.missions) {
      domaine(R, typeof m.id === 'string' && typeof m.statut === 'string' && typeof m.debut_le === 'string' && typeof m.fin_le === 'string',
        'mission : id, statut, debut_le, fin_le');
      domaine(R, m.duree_heures === undefined || m.duree_heures === null || typeof m.duree_heures === 'number', 'mission : duree_heures');
      domaine(R, estChaineOuNul(m.etablissement_id), 'mission : etablissement_id');
    }
    for (const liste of Object.values(args.creneauxParMission)) liste.forEach(verifierCreneau);
    for (const contrat of args.contrats ?? []) {
      // `contrats_mission.statut` est NULLable (`public.sql` l.68786, `types.ts`) : `ContratPointage`
      // le décode en `""` depuis T3 (même effet que le web : non terminal, priorité 0), d'où le vecteur
      // `statut: null` de `grille/contrats/choix` (consigne T3 de DECISIONS_LOT2.md).
      domaine(R, typeof contrat.id === 'string' && typeof contrat.mission_id === 'string' && estChaineOuNul(contrat.statut)
        && estChaineOuNul(contrat.cree_le), 'contrat : id, mission_id, statut, cree_le');
    }
    for (const etablissement of Object.values(args.etablissements ?? {})) {
      domaine(R, typeof etablissement === 'object' && etablissement !== null && !Array.isArray(etablissement), 'établissement : objet');
    }
    const r = presencesListes.construireListesPresences({ ...args, maintenant: new Date(args.maintenant) });
    clesExactes(R, r, ['missionsAujourdhui', 'missionsAVenir', 'missionsEnCours', 'contrats']);
    // Une mission dupliquée garde sa source par position : la recherche par identifiant suffit (mêmes clés).
    const source = (m) => args.missions.find((mission) => mission.id === m.id);
    c.ajoute(`construireListesPresences/${nom}`, { fonction: 'construireListesPresences', ...args }, {
      missionsAujourdhui: r.missionsAujourdhui.map((m) => projeter(m, source(m), [])),
      missionsAVenir: r.missionsAVenir.map((m) => ({
        ...projeter(m, source(m), ['dateAffichage', 'prochainCreneau', 'dureeAffichageHeures', ...(Object.hasOwn(m, 'planningAConfirmer') ? ['planningAConfirmer'] : [])]),
        dateAffichage: m.dateAffichage,
        prochainCreneau: m.prochainCreneau,
        dureeAffichageHeures: Number.isFinite(m.dureeAffichageHeures) ? m.dureeAffichageHeures : null,
        planningAConfirmer: m.planningAConfirmer === true,
      })),
      missionsEnCours: r.missionsEnCours.map((m) => projeter(m, source(m), [])),
      contrats: Object.fromEntries(Object.entries(r.contrats).map(([missionId, contrat]) => [missionId, contrat.id])),
    });
  };

  const prevu = (id, debut, fin, extra = {}) => creneauLot2(debut, fin, 'PREVISIONNEL', { id, ...extra });
  const effectif = (id, debut, fin, extra = {}) => creneauLot2(debut, fin, 'EFFECTIF', { id, ...extra });
  const mission = (id, statut, debut_le, fin_le, extra = {}) => ({
    id, intitule: `Mission ${id}`, statut, debut_le, fin_le, duree_heures: 7, etablissement_id: 'etab-1', ...extra,
  });
  // Lundi 2 novembre 2026, 10 h à Paris (UTC+1) : aujourd'hui = [2026-11-01T23:00Z, 2026-11-02T23:00Z[.
  const MAINTENANT = '2026-11-02T09:00:00Z';
  // Mission longue (plus de 24 h) : jamais de repli ponctuel. Colonnes réduites à celles que lit la
  // règle (les grilles qui testent l'établissement ou la durée les ajoutent).
  const longue = (id, statut, extra = {}) => ({ id, statut, debut_le: '2026-10-20T07:00:00Z', fin_le: '2026-11-20T15:00:00Z', ...extra });

  // --- Issus des tests vitest (presences-soignant-listes.test.ts) ----------
  regrouper('vitest-ordre-conserve', [
    { ...prevu('a1', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z'), mission_id: 'a' },
    { ...prevu('b1', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z'), mission_id: 'b' },
    { ...prevu('a2', '2026-11-04T07:00:00Z', '2026-11-04T15:00:00Z'), mission_id: 'a' },
  ]);
  regrouper('vitest-null', null);
  regrouper('vitest-absente', undefined);

  construire('vitest-aujourdhui-creneau-du-jour', {
    missions: [mission('du-jour', 'ASSIGNEE', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z')],
    creneauxParMission: { 'du-jour': [prevu('c', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z')] },
    contrats: [], maintenant: MAINTENANT,
  });
  construire('vitest-aujourdhui-segment-ouvert', {
    missions: [mission('segment-ouvert', 'EN_COURS', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z')],
    creneauxParMission: { 'segment-ouvert': [effectif('e', '2026-11-01T07:00:00Z', null), prevu('p', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z')] },
    contrats: [], maintenant: MAINTENANT,
  });
  construire('vitest-aujourdhui-pauses-et-segment-ferme-ignores', {
    missions: [mission('pauses', 'EN_COURS', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z')],
    creneauxParMission: {
      pauses: [
        effectif('pause-ouverte', '2026-11-02T08:00:00Z', null, { est_pause: true }),
        effectif('ferme', '2026-11-02T07:00:00Z', '2026-11-02T08:00:00Z'),
        prevu('pause-prevue', '2026-11-02T11:00:00Z', '2026-11-02T12:00:00Z', { est_pause: true }),
      ],
    },
    contrats: [], maintenant: MAINTENANT,
  });
  construire('vitest-aujourdhui-bornes-minuit-paris', {
    missions: [
      mission('fini-minuit', 'ASSIGNEE', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z'),
      mission('commence-demain', 'ASSIGNEE', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z'),
      mission('chevauche-minuit', 'ASSIGNEE', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z'),
    ],
    creneauxParMission: {
      'fini-minuit': [prevu('a', '2026-11-01T15:00:00Z', '2026-11-01T23:00:00Z')],
      'commence-demain': [prevu('b', '2026-11-02T23:00:00Z', '2026-11-03T07:00:00Z')],
      'chevauche-minuit': [prevu('c', '2026-11-01T20:00:00Z', '2026-11-02T06:00:00Z')],
    },
    contrats: [], maintenant: MAINTENANT,
  });
  construire('vitest-aujourdhui-jour-civil-paris', {
    missions: [mission('mardi', 'ASSIGNEE', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z')],
    creneauxParMission: { mardi: [prevu('m', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z')] },
    contrats: [], maintenant: '2026-11-02T23:30:00Z',
  });
  construire('vitest-aujourdhui-repli-ponctuel', {
    missions: [mission('ponctuelle', 'ASSIGNEE', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z')],
    creneauxParMission: {}, contrats: [], maintenant: MAINTENANT,
  });
  construire('vitest-a-venir-prochain-creneau-et-duree', {
    missions: [
      mission('segment-ouvert', 'EN_COURS', '2026-10-30T07:00:00Z', '2026-11-06T15:00:00Z'),
      mission('jeudi', 'ASSIGNEE', '2026-11-05T07:00:00Z', '2026-11-05T19:00:00Z', { duree_heures: 99 }),
    ],
    creneauxParMission: {
      'segment-ouvert': [
        prevu('hier', '2026-11-01T07:00:00Z', '2026-11-01T15:00:00Z'), prevu('jour', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z'),
        prevu('apres', '2026-11-04T07:00:00Z', '2026-11-04T11:00:00Z'), prevu('demain', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z'),
      ],
      jeudi: [prevu('j', '2026-11-05T07:00:00Z', '2026-11-05T19:00:00Z')],
    },
    contrats: [], maintenant: MAINTENANT,
  });
  construire('vitest-a-venir-planning-a-confirmer', {
    missions: [
      mission('longue-sans-creneau', 'ASSIGNEE', '2026-11-10T07:00:00Z', '2026-11-20T15:00:00Z'),
      mission('en-cours-sans-creneau', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z'),
      mission('incomplete', 'ASSIGNEE', '2026-11-10T07:00:00Z', '2026-11-20T15:00:00Z'),
      mission('datee', 'ASSIGNEE', '2026-11-09T07:00:00Z', '2026-11-09T15:00:00Z'),
    ],
    creneauxParMission: {
      incomplete: [prevu('sans-fin', '2026-11-10T07:00:00Z', null)],
      datee: [prevu('d', '2026-11-09T07:00:00Z', '2026-11-09T15:00:00Z')],
    },
    contrats: [], maintenant: MAINTENANT,
  });
  const vingtDeux = Array.from({ length: 22 }, (_, i) => {
    const jour = String(25 - i).padStart(2, '0');
    return mission(`m-${jour}`, 'ASSIGNEE', `2026-11-${jour}T07:00:00Z`, `2026-11-${jour}T15:00:00Z`);
  });
  construire('vitest-a-venir-tri-et-coupe-20', {
    missions: [...vingtDeux, mission('a-confirmer', 'ASSIGNEE', '2026-12-01T07:00:00Z', '2026-12-10T15:00:00Z')],
    creneauxParMission: {}, contrats: [], maintenant: MAINTENANT,
  });
  construire('vitest-actives-en-cours', {
    missions: [
      mission('a', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z'),
      mission('b', 'ASSIGNEE', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z'),
      mission('c', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z'),
    ],
    creneauxParMission: {}, contrats: [], maintenant: MAINTENANT,
  });
  construire('vitest-contrat-de-pointage-par-mission', {
    missions: [], creneauxParMission: {},
    contrats: [
      { id: 'annule', mission_id: 'm1', statut: 'ANNULE', cree_le: '2026-10-20T00:00:00Z' },
      { id: 'envoye', mission_id: 'm1', statut: 'ENVOYE', cree_le: '2026-10-10T00:00:00Z' },
      { id: 'signe', mission_id: 'm1', statut: 'SIGNE_COMPLET', cree_le: '2026-09-01T00:00:00Z' },
      { id: 'ancien', mission_id: 'm2', statut: 'EN_ATTENTE_SIGNATURE', cree_le: '2026-10-01T00:00:00Z' },
      { id: 'recent', mission_id: 'm2', statut: 'EN_ATTENTE_SIGNATURE', cree_le: '2026-10-15T00:00:00Z' },
      { id: 'expire', mission_id: 'm3', statut: 'EXPIRE', cree_le: '2026-10-15T00:00:00Z' },
    ],
    maintenant: MAINTENANT,
  });
  construire('vitest-enrichissement-etablissement', {
    missions: [
      mission('connue', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z', { service: 'Urgences' }),
      mission('inconnue', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z', { etablissement_id: 'etab-2' }),
    ],
    creneauxParMission: { connue: [effectif('e', '2026-11-02T07:00:00Z', null)] },
    contrats: [], maintenant: MAINTENANT, etablissements: { 'etab-1': { nom: 'Clinique Test' } },
  });
  construire('vitest-sans-carte-etablissements', {
    missions: [mission('m', 'EN_COURS', '2026-10-10T07:00:00Z', '2026-11-20T15:00:00Z')],
    creneauxParMission: {}, contrats: [], maintenant: MAINTENANT,
  });

  // --- Grille : regroupement -------------------------------------------------
  regrouper('grille/vide', []);
  regrouper('grille/une-mission-desordre-conserve', [
    { ...prevu('tard', '2026-11-05T07:00:00Z', '2026-11-05T15:00:00Z'), mission_id: 'm' },
    { ...effectif('eff', '2026-11-01T07:00:00Z', null), mission_id: 'm' },
    { ...prevu('tot', '2026-11-01T07:00:00Z', '2026-11-01T15:00:00Z'), mission_id: 'm' },
  ]);
  regrouper('grille/trois-missions-entrelacees', ['x', 'y', 'x', 'z', 'y', 'x'].map((missionId, i) => ({
    ...prevu(`c${i}`, `2026-11-0${i + 1}T07:00:00Z`, `2026-11-0${i + 1}T15:00:00Z`), mission_id: missionId,
  })));
  regrouper('grille/sans-identifiant-de-creneau', [{ ...creneauLot2('2026-11-02T07:00:00Z', null, 'EFFECTIF'), mission_id: 'm' }]);

  // --- Grille : jour civil de Paris aux changements d'heure ------------------
  // 29 mars 2026 (23 h) : [2026-03-28T23:00Z, 2026-03-29T22:00Z[ ; 25 octobre 2026 (25 h) :
  // [2026-10-24T22:00Z, 2026-10-25T23:00Z[. Une mission par créneau, toutes longues.
  const bornes = (nom, maintenant, creneaux) => construire(`grille/jour/${nom}`, {
    missions: creneaux.map(([id]) => ({ id, statut: 'ASSIGNEE', debut_le: '2026-01-01T07:00:00Z', fin_le: '2026-12-31T15:00:00Z' })),
    creneauxParMission: Object.fromEntries(creneaux.map(([id, debut, fin]) => [id, [prevu(id, debut, fin)]])),
    contrats: [], maintenant,
  });
  bornes('dst-mars-journee-23-h', '2026-03-29T10:00:00Z', [
    ['finit-au-debut-du-jour', '2026-03-28T20:00:00Z', '2026-03-28T23:00:00Z'],
    ['finit-1-ms-apres-le-debut', '2026-03-28T20:00:00Z', '2026-03-28T23:00:00.001Z'],
    ['commence-1-ms-avant-la-fin', '2026-03-29T21:59:59.999Z', '2026-03-30T05:00:00Z'],
    ['commence-a-la-fin-du-jour', '2026-03-29T22:00:00Z', '2026-03-30T05:00:00Z'],
    ['couvre-le-jour', '2026-03-28T22:00:00Z', '2026-03-29T23:00:00Z'],
  ]);
  bornes('dst-octobre-journee-25-h', '2026-10-25T10:00:00Z', [
    ['finit-au-debut-du-jour', '2026-10-24T18:00:00Z', '2026-10-24T22:00:00Z'],
    ['commence-a-23-h-30-heure-de-paris', '2026-10-25T22:30:00Z', '2026-10-25T23:30:00Z'],
    ['commence-a-la-fin-du-jour', '2026-10-25T23:00:00Z', '2026-10-26T07:00:00Z'],
    ['heure-repetee', '2026-10-25T00:30:00Z', '2026-10-25T01:30:00Z'],
  ]);
  for (const [nom, maintenant] of [['minuit-paris-exact', '2026-11-01T23:00:00Z'], ['minuit-paris-moins-1-ms', '2026-11-01T22:59:59.999Z'],
    ['fin-de-journee-paris', '2026-11-02T22:59:59.999Z'], ['minuit-paris-suivant', '2026-11-02T23:00:00Z']]) {
    bornes(`horloge-${nom}`, maintenant, [
      ['lundi', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z'], ['mardi', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z'],
      ['dimanche', '2026-11-01T07:00:00Z', '2026-11-01T15:00:00Z'],
    ]);
  }
  bornes('formats-de-date', MAINTENANT, [
    ['decalage-paris', '2026-11-02T08:00:00+01:00', '2026-11-02T16:00:00+01:00'],
    ['legacy-sans-decalage', '2026-11-02T08:00:00', '2026-11-02T16:00:00'],
    ['postgrest-microsecondes', '2026-11-03T07:00:00.123456+00:00', '2026-11-03T15:00:00.654321+00:00'],
    ['legacy-sans-decalage-demain', '2026-11-03T00:00:00', '2026-11-03T08:00:00'],
    ['legacy-sans-decalage-23-h-59', '2026-11-02T23:59:00', '2026-11-03T08:00:00'],
  ]);

  // --- Grille : segment ouvert ----------------------------------------------
  construire('grille/segment-ouvert/variantes', {
    missions: ['fin-null', 'fin-vide', 'pause-ouverte', 'prevu-sans-fin', 'ferme', 'ouvert-futur', 'type-inconnu'].map((id) => longue(id, 'EN_COURS')),
    creneauxParMission: {
      'fin-null': [effectif('e1', '2026-10-21T07:00:00Z', null)],
      'fin-vide': [effectif('e2', '2026-10-21T07:00:00Z', '')],
      'pause-ouverte': [effectif('e3', '2026-10-21T07:00:00Z', null, { est_pause: true })],
      'prevu-sans-fin': [prevu('p4', '2026-10-21T07:00:00Z', null)],
      ferme: [effectif('e5', '2026-10-21T07:00:00Z', '2026-10-21T15:00:00Z')],
      'ouvert-futur': [effectif('e6', '2026-11-10T07:00:00Z', null)],
      'type-inconnu': [creneauLot2('2026-10-21T07:00:00Z', null, 'AUTRE', { id: 'x7' })],
    },
    contrats: [], maintenant: MAINTENANT,
  });

  // --- Grille : À venir (bornes, prochain créneau, durée) --------------------
  construire('grille/a-venir/bornes-de-demain', {
    missions: ['a-demain-pile', 'a-demain-moins-1-ms', 'pause-demain', 'prevu-sans-fin-demain', 'effectif-demain', 'desordre', 'deux-ordre-recu']
      .map((id) => longue(id, 'ASSIGNEE')),
    creneauxParMission: {
      'a-demain-pile': [prevu('a', '2026-11-02T23:00:00Z', '2026-11-03T07:00:00Z')],
      'a-demain-moins-1-ms': [prevu('b', '2026-11-02T22:59:59.999Z', '2026-11-03T07:00:00Z')],
      'pause-demain': [prevu('c', '2026-11-03T10:00:00Z', '2026-11-03T11:00:00Z', { est_pause: true })],
      'prevu-sans-fin-demain': [prevu('d', '2026-11-03T07:00:00Z', null)],
      'effectif-demain': [effectif('e', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z')],
      desordre: [prevu('f3', '2026-11-08T07:00:00Z', '2026-11-08T15:00:00Z'), prevu('f1', '2026-11-04T07:00:00Z', '2026-11-04T09:30:00Z'),
        prevu('f0', '2026-11-01T07:00:00Z', '2026-11-01T15:00:00Z'), prevu('f2', '2026-11-06T07:00:00Z', '2026-11-06T15:00:00Z')],
      'deux-ordre-recu': [prevu('g1', '2026-11-05T07:00:00Z', '2026-11-05T09:00:00Z'), prevu('g2', '2026-11-05T07:00:00Z', '2026-11-05T19:00:00Z')],
    },
    contrats: [], maintenant: MAINTENANT,
  });
  construire('grille/a-venir/durees', {
    missions: ['sept-heures-trente', 'nulle', 'negative', 'fin-illisible', 'nuit-dst-octobre', 'un-tiers'].map((id) => longue(id, 'ASSIGNEE')),
    creneauxParMission: {
      'sept-heures-trente': [prevu('a', '2026-11-04T07:00:00Z', '2026-11-04T14:30:00Z')],
      nulle: [prevu('b', '2026-11-04T07:00:00Z', '2026-11-04T07:00:00Z')],
      negative: [prevu('c', '2026-11-04T15:00:00Z', '2026-11-04T07:00:00Z')],
      'fin-illisible': [prevu('d', '2026-11-04T07:00:00Z', 'pas une date')],
      'nuit-dst-octobre': [prevu('e', '2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00')],
      'un-tiers': [prevu('f', '2026-11-04T07:00:00Z', '2026-11-04T07:20:00Z')],
    },
    contrats: [], maintenant: '2026-10-20T09:00:00Z',
  });

  // --- Grille : repli des missions ponctuelles (24 h au plus) ---------------
  construire('grille/repli-ponctuel', {
    missions: [
      mission('24-h-exactes-demain', 'ASSIGNEE', '2026-11-04T07:00:00Z', '2026-11-05T07:00:00Z'),
      mission('24-h-plus-1-ms', 'ASSIGNEE', '2026-11-04T07:00:00Z', '2026-11-05T07:00:00.001Z'),
      mission('duree-nulle', 'ASSIGNEE', '2026-11-04T07:00:00Z', '2026-11-04T07:00:00Z'),
      mission('duree-negative', 'ASSIGNEE', '2026-11-04T15:00:00Z', '2026-11-04T07:00:00Z'),
      mission('debut-illisible', 'ASSIGNEE', 'bientôt', '2026-11-04T07:00:00Z'),
      mission('en-cours-du-jour', 'EN_COURS', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z'),
      mission('effectifs-seuls', 'EN_COURS', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z'),
      mission('prevu-sans-fin', 'ASSIGNEE', '2026-11-04T07:00:00Z', '2026-11-04T15:00:00Z'),
      mission('pause-prevue-seule', 'ASSIGNEE', '2026-11-04T07:00:00Z', '2026-11-04T15:00:00Z'),
      mission('legacy-sans-decalage', 'ASSIGNEE', '2026-11-04T08:00:00', '2026-11-04T16:00:00'),
      mission('a-cheval-sur-minuit', 'ASSIGNEE', '2026-11-02T20:00:00Z', '2026-11-03T06:00:00Z'),
    ],
    creneauxParMission: {
      'effectifs-seuls': [effectif('e', '2026-11-02T07:05:00Z', '2026-11-02T08:00:00Z')],
      'prevu-sans-fin': [prevu('p', '2026-11-04T07:00:00Z', null)],
      'pause-prevue-seule': [prevu('q', '2026-11-04T10:00:00Z', '2026-11-04T10:30:00Z', { est_pause: true })],
    },
    contrats: [], maintenant: MAINTENANT,
  });

  // --- Grille : statuts (aucun filtre de statut sauf Actives et « à confirmer ») ---
  construire('grille/statuts', {
    missions: [
      longue('terminee-du-jour', 'TERMINEE'), longue('brouillon-sans-creneau', 'BROUILLON'), longue('assignee-sans-creneau', 'ASSIGNEE'),
      longue('en-cours-sans-creneau', 'EN_COURS'), longue('en-cours-minuscules', 'en_cours'), longue('assignee-minuscules', 'assignee'),
      longue('litige-a-venir', 'LITIGE'),
    ],
    creneauxParMission: {
      'terminee-du-jour': [prevu('t', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z')],
      'litige-a-venir': [prevu('l', '2026-11-05T07:00:00Z', '2026-11-05T15:00:00Z')],
    },
    contrats: [], maintenant: MAINTENANT,
  });

  // --- Grille : tri de « À venir » et coupe à 20 -----------------------------
  construire('grille/tri/egalites-et-non-datees-en-tete', {
    missions: [
      longue('a-confirmer-1', 'ASSIGNEE'), longue('meme-date-1', 'ASSIGNEE'), longue('plus-tard', 'ASSIGNEE'),
      longue('a-confirmer-2', 'ASSIGNEE'), longue('meme-date-2', 'ASSIGNEE'), longue('plus-tot', 'ASSIGNEE'),
      longue('meme-instant-autre-format', 'ASSIGNEE'),
    ],
    creneauxParMission: {
      'meme-date-1': [prevu('m1', '2026-11-05T07:00:00Z', '2026-11-05T15:00:00Z')],
      'plus-tard': [prevu('pt', '2026-11-09T07:00:00Z', '2026-11-09T15:00:00Z')],
      'meme-date-2': [prevu('m2', '2026-11-05T07:00:00Z', '2026-11-05T19:00:00Z')],
      'plus-tot': [prevu('po', '2026-11-03T07:00:00Z', '2026-11-03T15:00:00Z')],
      'meme-instant-autre-format': [prevu('mf', '2026-11-05T08:00:00+01:00', '2026-11-05T16:00:00+01:00')],
    },
    contrats: [], maintenant: MAINTENANT,
  });
  const datees = (n) => Array.from({ length: n }, (_, i) => longue(`d-${String(i).padStart(2, '0')}`, 'ASSIGNEE'));
  const creneauxDatees = (n) => Object.fromEntries(Array.from({ length: n }, (_, i) => {
    const jour = String(3 + ((i * 7) % n)).padStart(2, '0');
    return [`d-${String(i).padStart(2, '0')}`, [prevu(`c-${i}`, `2026-11-${jour}T07:00:00Z`, `2026-11-${jour}T15:00:00Z`)]];
  }));
  construire('grille/tri/19-datees-3-a-confirmer', {
    missions: [longue('x-1', 'ASSIGNEE'), ...datees(19), longue('x-2', 'ASSIGNEE'), longue('x-3', 'ASSIGNEE')],
    creneauxParMission: creneauxDatees(19), contrats: [], maintenant: MAINTENANT,
  });
  construire('grille/tri/21-datees', { missions: datees(21), creneauxParMission: creneauxDatees(21), contrats: [], maintenant: MAINTENANT });
  construire('grille/tri/21-a-confirmer-coupe-20', {
    missions: Array.from({ length: 21 }, (_, i) => longue(`ac-${String(i).padStart(2, '0')}`, 'ASSIGNEE')),
    creneauxParMission: {}, contrats: [], maintenant: MAINTENANT,
  });

  // --- Grille : contrat de pointage par mission -----------------------------
  const contrat = (id, missionId, statut, creeLe, sansDate = false) => (sansDate
    ? { id, mission_id: missionId, statut }
    : { id, mission_id: missionId, statut, cree_le: creeLe });
  construire('grille/contrats/choix', {
    missions: [longue('m1', 'EN_COURS')], creneauxParMission: {},
    contrats: [
      ...['ANNULE', 'EXPIRE', 'REFUSE', 'RUPTURE_ETAB', 'RUPTURE_SOIGNANT'].map((statut, i) => contrat(`terminal-${i}`, 'tous-terminaux', statut, '2026-10-01T00:00:00Z')),
      contrat('signe-ancien', 'deux-signes', 'SIGNE_COMPLET', '2026-09-01T00:00:00Z'), contrat('signe-recent', 'deux-signes', 'SIGNE_COMPLET', '2026-09-02T00:00:00Z'),
      contrat('sans-date', 'date-nulle', 'EN_ATTENTE_SIGNATURES', null), contrat('date', 'date-nulle', 'EN_ATTENTE_SIGNATURES', '1970-01-01T00:00:00.001Z'),
      contrat('absente', 'date-absente', 'SIGNE_SOIGNANT', null, true), contrat('epoque', 'date-absente', 'SIGNE_SOIGNANT', '1970-01-01T00:00:00Z'),
      contrat('premier', 'egalite', 'ENVOYE', '2026-10-01T00:00:00Z'), contrat('second', 'egalite', 'ENVOYE', '2026-10-01T00:00:00Z'),
      contrat('seul-terminal-minuscules', 'casse', 'annule', '2026-10-01T00:00:00Z'),
      contrat('legacy', 'formats', 'ENVOYE', '2026-10-01T02:00:00'), contrat('utc', 'formats', 'ENVOYE', '2026-10-01T00:30:00Z'),
      // Statut nul (colonne NULLable, consigne T3) : non terminal, priorité 0 ; le plus récent l'emporte sur un
      // ENVOYE, jamais sur un SIGNE_COMPLET.
      contrat('nul-recent', 'statut-nul', null, '2026-10-02T00:00:00Z'), contrat('envoye-ancien', 'statut-nul', 'ENVOYE', '2026-10-01T00:00:00Z'),
      contrat('nul', 'statut-nul-signe', null, '2026-10-03T00:00:00Z'), contrat('signe', 'statut-nul-signe', 'SIGNE_COMPLET', '2026-10-01T00:00:00Z'),
      contrat('pour-m1', 'm1', 'SIGNE_COMPLET', '2026-10-01T00:00:00Z'),
    ],
    maintenant: MAINTENANT,
  });
  construire('grille/contrats/null', { missions: [longue('m1', 'EN_COURS')], creneauxParMission: {}, contrats: null, maintenant: MAINTENANT });
  construire('grille/contrats/absents', { missions: [longue('m1', 'EN_COURS')], creneauxParMission: {}, maintenant: MAINTENANT });

  // --- Grille : établissements ----------------------------------------------
  construire('grille/etablissements', {
    missions: [
      longue('connu', 'EN_COURS', { etablissement_id: 'etab-1' }), longue('autre', 'EN_COURS', { etablissement_id: 'etab-2' }), longue('inconnu', 'EN_COURS', { etablissement_id: 'etab-3' }),
      longue('id-null', 'EN_COURS', { etablissement_id: null }), longue('id-vide', 'EN_COURS', { etablissement_id: '' }),
      longue('sans-id', 'EN_COURS', { etablissement_id: undefined }),
    ],
    creneauxParMission: { orpheline: [prevu('o', '2026-11-02T07:00:00Z', '2026-11-02T15:00:00Z')] },
    contrats: [], maintenant: MAINTENANT,
    etablissements: { 'etab-1': { nom: 'Clinique Test', adresse_ville: 'Lyon' }, 'etab-2': { nom: 'Hôpital Nord' } },
  });
  construire('grille/aucune-mission', { missions: [], creneauxParMission: {}, contrats: [], maintenant: MAINTENANT });
  construire('grille/mission-dupliquee', {
    missions: [longue('d', 'EN_COURS'), longue('d', 'EN_COURS')],
    creneauxParMission: { d: [effectif('e', '2026-11-02T07:00:00Z', null)] }, contrats: [], maintenant: MAINTENANT,
  });
  construire('grille/duree-heures-absente-ou-nulle', {
    missions: [longue('absente', 'ASSIGNEE', { duree_heures: undefined }), longue('nulle', 'ASSIGNEE', { duree_heures: null }),
      longue('datee', 'ASSIGNEE', { duree_heures: null })],
    creneauxParMission: { datee: [prevu('d', '2026-11-04T07:00:00Z', '2026-11-04T15:00:00Z')] },
    contrats: [], maintenant: MAINTENANT,
  });

  return c.tries();
}

// ---------------------------------------------------------------------------
// Écriture
// ---------------------------------------------------------------------------
const fichiers = {
  'date-heure-paris.json': vecteursDateHeureParis(),
  'format-mission.json': vecteursFormatMission(),
  'heures-hebdomadaires-mission.json': vecteursHeuresHebdomadaires(),
  'disponibilite-pointage.json': vecteursDisponibilitePointage(),
  'planning-candidat.json': vecteursPlanningCandidat(),
  'selection-serie-candidat.json': vecteursSelectionSerie(),
  'completude-planning-mission.json': vecteursCompletudePlanning(),
  // Lot 2, T2.
  'synthese-presence-mission.json': vecteursSynthesePresence(),
  'presences-soignant-ui.json': vecteursPresencesSoignantUi(),
  'document-upload.json': await vecteursDocumentUpload(),
  'documents.json': vecteursDocuments(),
  'contrat-mission-ui.json': vecteursContratMissionUi(),
  'signature-sms-staging-admission.json': await vecteursAdmissionSms(),
  // Lot 2, T2b : règles extraites par la PR web W1 (#1112).
  'documents-requis.json': vecteursDocumentsRequis(),
  'presences-soignant-listes.json': vecteursPresencesSoignantListes(),
};

let total = 0;
let divergences = 0;
mkdirSync(DOSSIER_SORTIE, { recursive: true });
for (const [nom, vecteurs] of Object.entries(fichiers)) {
  total += vecteurs.length;
  const contenu = `${JSON.stringify(vecteurs, null, 2)}\n`;
  const chemin = resolve(DOSSIER_SORTIE, nom);
  if (MODE_CHECK) {
    const actuel = existsSync(chemin) ? readFileSync(chemin, 'utf8') : null;
    const identique = actuel === contenu;
    if (!identique) divergences += 1;
    console.log(`${identique ? 'OK ' : 'DIFF'} ${nom} (${vecteurs.length} vecteurs)`);
  } else {
    writeFileSync(chemin, contenu, 'utf8');
    console.log(`écrit ${nom} (${vecteurs.length} vecteurs)`);
  }
}
console.log(`total : ${total} vecteurs golden`);
if (total < 200) {
  console.error('Moins de 200 vecteurs : critère du lot 0 non atteint.');
  process.exit(1);
}
if (MODE_CHECK && divergences > 0) {
  console.error(`${divergences} fichier(s) divergent(s) : relancer sans --check.`);
  process.exit(1);
}
