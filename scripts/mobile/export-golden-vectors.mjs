#!/usr/bin/env node
/**
 * Export des vecteurs golden pour le port Swift des règles pures (plan §4.1).
 *
 * Lit directement les modules TypeScript de `src/lib` (type stripping natif de
 * Node, aucune dépendance supplémentaire) et écrit, par règle, un JSON de
 * vecteurs `{ name, input, expected }` dans
 * `ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/Resources/golden/`.
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
// Alias `@/` de Vite (tsconfig `paths`) et imports relatifs sans extension : les
// modules du lot 1 (`planning-candidat.ts`, `selection-serie-candidat.ts`,
// `completude-planning-mission.ts`) importent `@/lib/<x>` et `./<x>`, que le
// résolveur ESM de Node ne connaît pas. Le hook ne touche qu'aux spécificateurs
// qui visent `src/` ; tout le reste (date-fns, node:*) suit la résolution normale.
// ---------------------------------------------------------------------------
const HOOK_ALIAS_SRC = `
import { existsSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
let racineSrc = '';
export async function initialize(data) { racineSrc = data.racineSrc; }
function fichier(url) {
  try { return existsSync(fileURLToPath(url)) && statSync(fileURLToPath(url)).isFile(); } catch { return false; }
}
export async function resolve(specifier, context, next) {
  let base = null;
  if (specifier.startsWith('@/')) {
    base = new URL(specifier.slice(2), racineSrc).href;
  } else if ((specifier.startsWith('./') || specifier.startsWith('../')) && context.parentURL?.startsWith(racineSrc)) {
    base = new URL(specifier, context.parentURL).href;
  }
  if (base === null) return next(specifier, context);
  for (const suffixe of ['', '.ts', '.tsx', '/index.ts']) {
    const candidat = base + suffixe;
    if (fichier(candidat)) return next(candidat, context);
  }
  throw new Error('export-golden-vectors : alias non résolu « ' + specifier + ' » depuis ' + context.parentURL);
}
`;
register(`data:text/javascript,${encodeURIComponent(HOOK_ALIAS_SRC)}`, {
  parentURL: import.meta.url,
  data: { racineSrc: `${pathToFileURL(resolve(RACINE, 'src')).href}/` },
});

const lib = (nom) => import(pathToFileURL(resolve(RACINE, 'src/lib', nom)).href);
const composantPlanning = (nom) => import(pathToFileURL(resolve(RACINE, 'src/components/planning', nom)).href);
const dateHeure = await lib('date-heure-paris.ts');
const formatMission = await lib('format-mission.ts');
const hebdo = await lib('heures-hebdomadaires-mission.ts');
const pointage = await lib('disponibilite-pointage.ts');
const planningCandidat = await composantPlanning('planning-candidat.ts');
const selectionSerie = await composantPlanning('selection-serie-candidat.ts');
const completude = await lib('completude-planning-mission.ts');

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
// Outils communs du lot 1 (planning candidat, série, complétude)
// ---------------------------------------------------------------------------
/** Créneau PostgREST minimal ; `extra` ajoute `id`, `mission_id`, `est_pause`, `type_creneau`. */
const slotPlanning = (debut, fin, extra = {}) => ({ debut, fin, est_pause: false, type_creneau: 'PREVISIONNEL', ...extra });
/** Journée 08:00 → 16:00 Paris (+02:00 en été, +01:00 en hiver selon `offset`). */
const journee = (jour, extra = {}, offset = '+02:00') => slotPlanning(`${jour}T08:00:00${offset}`, `${jour}T16:00:00${offset}`, extra);

/**
 * Le port Swift est fail-closed là où le web lève (`instantJolene` sur une date
 * illisible, écart assumé DECISIONS_LOT0) : un vecteur qui capturerait une
 * exception ne serait pas rejouable et signalerait une grille mal construite.
 */
function sansException(regle, nom, valeur) {
  if (valeur && typeof valeur === 'object' && !Array.isArray(valeur) && 'erreur' in valeur) {
    throw new Error(`${regle}: « ${nom} » lève côté web (${valeur.erreur}) ; ce cas n'est pas un vecteur golden`);
  }
  return valeur;
}

// ---------------------------------------------------------------------------
// Règle 5 : planning-candidat (construction, filtres horaires, créneaux confirmés)
// ---------------------------------------------------------------------------
function vecteursPlanningCandidat() {
  const c = new Collecteur('planning-candidat');
  const planning = (p) => ({
    creneaux: p.creneaux, exact: p.exact, totalHeures: p.totalHeures, periodeEtendue: p.periodeEtendue, messageBlocage: p.messageBlocage,
  });
  const construire = (nom, mission) => c.ajoute(`construirePlanningCandidat/${nom}`, { fonction: 'construirePlanningCandidat', mission },
    sansException('planning-candidat', nom, capture(() => planning(planningCandidat.construirePlanningCandidat(mission)))));
  const confirmes = (nom, mission) => c.ajoute(`creneauxConfirmesPourAction/${nom}`, { fonction: 'creneauxConfirmesPourAction', mission },
    sansException('planning-candidat', nom, capture(() => planningCandidat.creneauxConfirmesPourAction(mission))));
  const nuit = (nom, creneau) => c.ajoute(`creneauContientNuit/${nom}`, { fonction: 'creneauContientNuit', creneau },
    sansException('planning-candidat', nom, capture(() => planningCandidat.creneauContientNuit(creneau))));
  const weekend = (nom, creneau) => c.ajoute(`creneauChevaucheWeekend/${nom}`, { fonction: 'creneauChevaucheWeekend', creneau },
    sansException('planning-candidat', nom, capture(() => planningCandidat.creneauChevaucheWeekend(creneau))));
  const filtres = (nom, mission) => {
    for (const filtre of ['TOUS', 'JOUR', 'NUIT', 'WEEKEND']) {
      c.ajoute(`planningCorrespondAuFiltre/${nom}-${filtre.toLowerCase()}`, { fonction: 'planningCorrespondAuFiltre', mission, filtre },
        sansException('planning-candidat', nom, capture(() => planningCandidat.planningCorrespondAuFiltre(mission, filtre))));
    }
  };

  // --- Issus des tests vitest (planning-candidat.test.tsx) ------------------
  const missionLongue = { id: 'mission-longue', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-08-31T16:00:00+02:00', nb_creneaux: 2 };
  const deuxCreneaux = [
    journee('2026-07-06', { id: 'jour-1', mission_id: 'mission-longue' }),
    journee('2026-08-31', { id: 'jour-2', mission_id: 'mission-longue' }),
  ];
  construire('vitest-deux-journees-exactes', { ...missionLongue, creneaux_planifies: deuxCreneaux });
  construire('vitest-multi-incomplet', { ...missionLongue, creneaux_planifies: deuxCreneaux.slice(0, 1) });
  construire('vitest-nb-creneaux-depasse', { ...missionLongue, nb_creneaux: 1, creneaux_planifies: deuxCreneaux });
  construire('vitest-ponctuelle-repli', { id: 'ponctuelle', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-06T16:00:00+02:00', nb_creneaux: 1 });
  const nuitVitest = { id: 'nuit', debut_le: '2026-07-06T20:00:00+02:00', fin_le: '2026-07-07T08:00:00+02:00', nb_creneaux: 1,
    creneaux_planifies: [slotPlanning('2026-07-06T20:00:00+02:00', '2026-07-07T08:00:00+02:00')] };
  construire('vitest-nuit-lendemain', nuitVitest);
  const mixte = { ...missionLongue, creneaux_planifies: [slotPlanning('2026-07-11T21:00:00+02:00', '2026-07-12T07:00:00+02:00'), deuxCreneaux[1]] };
  filtres('vitest-mixte-nuit-weekend-jour', mixte);
  confirmes('vitest-deux-journees-exactes', { ...missionLongue, creneaux_planifies: deuxCreneaux });
  confirmes('vitest-multi-incomplet', { ...missionLongue, creneaux_planifies: deuxCreneaux.slice(0, 1) });

  // --- Repli ponctuel (missions legacy sans ligne PREVISIONNEL) ------------
  const ponctuelle = (nom, debut_le, fin_le, nb_creneaux = 1, extra = {}) => construire(`ponctuelle-${nom}`, { id: 'p', debut_le, fin_le, nb_creneaux, ...extra });
  ponctuelle('1h', '2026-07-31T08:00:00+02:00', '2026-07-31T09:00:00+02:00');
  ponctuelle('24h-exactes', '2026-07-31T08:00:00+02:00', '2026-08-01T08:00:00+02:00');
  ponctuelle('24h-plus-1s', '2026-07-31T08:00:00+02:00', '2026-08-01T08:00:01+02:00');
  ponctuelle('nb-null', '2026-07-31T08:00:00+02:00', '2026-07-31T16:00:00+02:00', null);
  ponctuelle('nb-0', '2026-07-31T08:00:00+02:00', '2026-07-31T16:00:00+02:00', 0);
  ponctuelle('nb-2-sans-creneau', '2026-07-31T08:00:00+02:00', '2026-07-31T16:00:00+02:00', 2);
  ponctuelle('duree-nulle', '2026-07-31T08:00:00+02:00', '2026-07-31T08:00:00+02:00');
  ponctuelle('fin-avant-debut', '2026-07-31T16:00:00+02:00', '2026-07-31T08:00:00+02:00');
  ponctuelle('debut-null', null, '2026-07-31T16:00:00+02:00');
  ponctuelle('fin-null', '2026-07-31T08:00:00+02:00', null);
  ponctuelle('debut-vide', '', '2026-07-31T16:00:00+02:00');
  ponctuelle('sans-id', '2026-07-31T08:00:00+02:00', '2026-07-31T16:00:00+02:00', 1, { id: undefined });
  ponctuelle('mission-id-seul', '2026-07-31T08:00:00+02:00', '2026-07-31T16:00:00+02:00', 1, { id: undefined, mission_id: 'via-mission-id' });
  ponctuelle('erreur-chargement', '2026-07-31T08:00:00+02:00', '2026-07-31T16:00:00+02:00', 1, { erreur_planning: true });
  ponctuelle('nuit-dst-mars-11h', '2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00');
  ponctuelle('nuit-dst-octobre-13h', '2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00');
  ponctuelle('legacy-sans-offset', '2026-08-31T08:00:00', '2026-08-31T16:00:00');
  ponctuelle('utc-z', '2026-12-01T07:00:00Z', '2026-12-01T15:00:00.000Z');
  ponctuelle('fin-minuit-paris', '2026-07-31T20:00:00+02:00', '2026-08-01T00:00:00+02:00');
  ponctuelle('fin-23h59m59', '2026-07-31T20:00:00+02:00', '2026-07-31T23:59:59+02:00');

  // --- Créneaux chargés ----------------------------------------------------
  const base = { id: 'm', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00' };
  const travail = journee('2026-07-31', { id: 'travail', mission_id: 'm' });
  const pause = slotPlanning('2026-07-31T12:00:00+02:00', '2026-07-31T12:30:00+02:00', { id: 'pause', mission_id: 'm', est_pause: true });
  const effectif = slotPlanning('2026-07-31T08:05:00+02:00', '2026-07-31T15:55:00+02:00', { id: 'eff', mission_id: 'm', type_creneau: 'EFFECTIF' });
  const ouvert = slotPlanning('2026-07-31T08:00:00+02:00', null, { id: 'ouvert', mission_id: 'm' });
  const charges = (nom, mission) => { construire(`charges-${nom}`, mission); confirmes(`charges-${nom}`, mission); };
  charges('une-journee', { ...base, nb_creneaux: 1, creneaux_planifies: [travail] });
  charges('pause-exclue', { ...base, nb_creneaux: 1, creneaux_planifies: [pause, travail] });
  charges('pause-seule-repli', { ...base, nb_creneaux: 1, creneaux_planifies: [pause] });
  charges('pause-seule-nb-2', { ...base, nb_creneaux: 2, creneaux_planifies: [pause] });
  charges('effectif-ignore', { ...base, nb_creneaux: 1, creneaux_planifies: [effectif, travail] });
  charges('effectif-seul-repli', { ...base, nb_creneaux: 1, creneaux_planifies: [effectif] });
  charges('fin-null-repli-propose', { ...base, nb_creneaux: 1, creneaux_planifies: [ouvert] });
  charges('fin-vide-repli-propose', { ...base, nb_creneaux: 1, creneaux_planifies: [{ ...ouvert, fin: '' }] });
  charges('fin-null-et-travail', { ...base, nb_creneaux: 1, creneaux_planifies: [travail, ouvert] });
  charges('erreur-chargement', { ...base, nb_creneaux: 1, creneaux_planifies: [travail], erreur_planning: true });
  charges('nb-null-avec-creneau', { ...base, nb_creneaux: null, creneaux_planifies: [travail] });
  charges('nb-0-avec-creneau', { ...base, nb_creneaux: 0, creneaux_planifies: [travail] });
  charges('periode-null-avec-creneau', { ...base, debut_le: null, fin_le: null, nb_creneaux: 1, creneaux_planifies: [travail] });
  charges('sans-cles-optionnelles', { ...base, nb_creneaux: 1, creneaux_planifies: [slotPlanning('2026-07-31T08:00:00+02:00', '2026-07-31T16:00:00+02:00')] });
  const semaine = ['2026-08-03', '2026-08-04', '2026-08-05', '2026-08-06', '2026-08-07', '2026-08-08', '2026-08-09'].map((jour, i) => journee(jour, { id: `j${i + 1}`, mission_id: 'serie' }));
  const serie = { id: 'serie', debut_le: '2026-08-03T08:00:00+02:00', fin_le: '2026-08-09T16:00:00+02:00', nb_creneaux: 7 };
  charges('serie-7-jours', { ...serie, creneaux_planifies: semaine });
  charges('serie-7-jours-desordre', { ...serie, creneaux_planifies: [...semaine].reverse() });
  charges('serie-6-sur-7', { ...serie, creneaux_planifies: semaine.slice(0, 6) });
  charges('serie-8-sur-7', { ...serie, creneaux_planifies: [...semaine, journee('2026-08-10', { id: 'j8', mission_id: 'serie' })] });
  charges('meme-debut-ordre-stable', { ...base, nb_creneaux: 2, creneaux_planifies: [
    slotPlanning('2026-07-31T08:00:00+02:00', '2026-07-31T12:00:00+02:00', { id: 'b' }),
    slotPlanning('2026-07-31T08:00:00+02:00', '2026-07-31T10:00:00+02:00', { id: 'a' }),
  ] });
  charges('nuit-minuit-un-creneau', { ...base, debut_le: '2026-07-31T22:00:00+02:00', fin_le: '2026-08-01T06:00:00+02:00', nb_creneaux: 1,
    creneaux_planifies: [slotPlanning('2026-07-31T22:00:00+02:00', '2026-08-01T06:00:00+02:00', { id: 'n' })] });
  charges('journee-dst-29-mars', { ...base, debut_le: '2026-03-29T08:00:00+02:00', fin_le: '2026-03-29T16:00:00+02:00', nb_creneaux: 1,
    creneaux_planifies: [journee('2026-03-29', { id: 'd' })] });
  charges('deux-nuits-dst', { id: 'dst', debut_le: '2026-03-28T20:00:00+01:00', fin_le: '2026-10-25T08:00:00+01:00', nb_creneaux: 2, creneaux_planifies: [
    slotPlanning('2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00', { id: 'hiver' }),
    slotPlanning('2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00', { id: 'ete' }),
  ] });
  charges('melange-formats-iso', { ...base, fin_le: '2026-12-01T15:00:00Z', nb_creneaux: 3, creneaux_planifies: [
    slotPlanning('2026-12-01T07:00:00Z', '2026-12-01T15:00:00.000Z', { id: 'z' }),
    slotPlanning('2026-08-31T08:00:00', '2026-08-31T16:00:00', { id: 'legacy' }),
    slotPlanning('2026-07-31T08:00:00+02:00', '2026-07-31T16:00:00+02:00', { id: 'offset' }),
  ] });
  charges('demi-heures-7h30', { ...base, nb_creneaux: 1, creneaux_planifies: [slotPlanning('2026-07-31T06:45:00+02:00', '2026-07-31T14:15:00+02:00', { id: 'h' })] });

  // --- Nuit (20:00 → 07:00 Paris) et week-end, jour civil par jour civil -----
  const nw = (nom, debut, fin, extra = {}) => { const cr = slotPlanning(debut, fin, extra); nuit(nom, cr); weekend(nom, cr); };
  nw('mardi-07h-20h', '2026-07-28T07:00:00+02:00', '2026-07-28T20:00:00+02:00');
  nw('mardi-07h-19h59', '2026-07-28T07:00:00+02:00', '2026-07-28T19:59:00+02:00');
  nw('mardi-06h59-14h', '2026-07-28T06:59:00+02:00', '2026-07-28T14:00:00+02:00');
  nw('mardi-06h-07h', '2026-07-28T06:00:00+02:00', '2026-07-28T07:00:00+02:00');
  nw('mardi-19h59-20h30', '2026-07-28T19:59:00+02:00', '2026-07-28T20:30:00+02:00');
  nw('mardi-20h-21h', '2026-07-28T20:00:00+02:00', '2026-07-28T21:00:00+02:00');
  nw('mardi-23h-mercredi-01h', '2026-07-28T23:00:00+02:00', '2026-07-29T01:00:00+02:00');
  nw('lundi-07h-mardi-20h', '2026-07-27T07:00:00+02:00', '2026-07-28T20:00:00+02:00');
  nw('fin-null', '2026-07-28T20:00:00+02:00', null);
  nw('fin-vide', '2026-07-28T20:00:00+02:00', '');
  nw('utc-ete-05h-18h', '2026-07-28T05:00:00Z', '2026-07-28T18:00:00Z');
  nw('utc-ete-04h59-18h', '2026-07-28T04:59:00Z', '2026-07-28T18:00:00Z');
  nw('utc-hiver-06h-19h', '2026-01-13T06:00:00Z', '2026-01-13T19:00:00Z');
  nw('utc-hiver-05h59-19h', '2026-01-13T05:59:00Z', '2026-01-13T19:00:00Z');
  nw('legacy-sans-offset-jour', '2026-07-28T07:00:00', '2026-07-28T20:00:00');
  nw('vendredi-20h-23h59m59', '2026-07-31T20:00:00+02:00', '2026-07-31T23:59:59+02:00');
  nw('vendredi-20h-samedi-00h00', '2026-07-31T20:00:00+02:00', '2026-08-01T00:00:00+02:00');
  nw('vendredi-20h-samedi-00h00m01', '2026-07-31T20:00:00+02:00', '2026-08-01T00:00:01+02:00');
  nw('samedi-08h-16h', '2026-08-01T08:00:00+02:00', '2026-08-01T16:00:00+02:00');
  nw('dimanche-08h-16h', '2026-08-02T08:00:00+02:00', '2026-08-02T16:00:00+02:00');
  nw('dimanche-23h-lundi-01h', '2026-08-02T23:00:00+02:00', '2026-08-03T01:00:00+02:00');
  nw('dimanche-23h-lundi-00h00', '2026-08-02T23:00:00+02:00', '2026-08-03T00:00:00+02:00');
  nw('lundi-00h-08h', '2026-08-03T00:00:00+02:00', '2026-08-03T08:00:00+02:00');
  nw('vendredi-08h-lundi-16h', '2026-07-31T08:00:00+02:00', '2026-08-03T16:00:00+02:00');
  nw('utc-vendredi-22h-ete-samedi-paris', '2026-07-31T22:00:00Z', '2026-07-31T23:00:00Z');
  nw('utc-vendredi-22h-hiver-vendredi-paris', '2026-01-16T22:00:00Z', '2026-01-16T22:30:00Z');
  nw('dst-mars-samedi-07h-20h', '2026-03-28T07:00:00+01:00', '2026-03-28T20:00:00+01:00');
  nw('dst-mars-dimanche-07h-20h', '2026-03-29T07:00:00+02:00', '2026-03-29T20:00:00+02:00');
  nw('dst-mars-nuit-samedi-dimanche', '2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00');
  nw('dst-octobre-dimanche-07h-20h', '2026-10-25T07:00:00+01:00', '2026-10-25T20:00:00+01:00');
  nw('dst-octobre-nuit-samedi-dimanche', '2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00');
  nw('dst-octobre-lundi-07h-20h', '2026-10-26T07:00:00+01:00', '2026-10-26T20:00:00+01:00');
  nw('pause-nuit', '2026-07-28T22:00:00+02:00', '2026-07-28T22:30:00+02:00', { est_pause: true });
  nw('effectif-weekend', '2026-08-01T08:00:00+02:00', '2026-08-01T16:00:00+02:00', { type_creneau: 'EFFECTIF' });

  // --- Filtres horaires sur des plannings complets ---------------------------
  filtres('jour-simple', { ...base, nb_creneaux: 1, creneaux_planifies: [travail] });
  filtres('nuit-simple', { ...base, debut_le: '2026-07-28T20:00:00+02:00', fin_le: '2026-07-29T07:00:00+02:00', nb_creneaux: 1,
    creneaux_planifies: [slotPlanning('2026-07-28T20:00:00+02:00', '2026-07-29T07:00:00+02:00')] });
  filtres('weekend-simple', { ...base, debut_le: '2026-08-01T08:00:00+02:00', fin_le: '2026-08-01T16:00:00+02:00', nb_creneaux: 1,
    creneaux_planifies: [journee('2026-08-01')] });
  filtres('nuit-de-weekend', { ...base, debut_le: '2026-08-01T20:00:00+02:00', fin_le: '2026-08-02T07:00:00+02:00', nb_creneaux: 1,
    creneaux_planifies: [slotPlanning('2026-08-01T20:00:00+02:00', '2026-08-02T07:00:00+02:00')] });
  filtres('ponctuelle-repli-jour', { ...base, nb_creneaux: 1 });
  filtres('inexact-nb-2', { ...base, nb_creneaux: 2, creneaux_planifies: [travail] });
  filtres('erreur-chargement', { ...base, nb_creneaux: 1, creneaux_planifies: [travail], erreur_planning: true });
  filtres('serie-7-jours', { ...serie, creneaux_planifies: semaine });
  filtres('jour-limite-07h-20h', { ...base, debut_le: '2026-07-28T07:00:00+02:00', fin_le: '2026-07-28T20:00:00+02:00', nb_creneaux: 1,
    creneaux_planifies: [slotPlanning('2026-07-28T07:00:00+02:00', '2026-07-28T20:00:00+02:00')] });
  filtres('journee-longue-nuit-et-jour', { ...base, debut_le: '2026-07-28T06:00:00+02:00', fin_le: '2026-07-28T21:00:00+02:00', nb_creneaux: 1,
    creneaux_planifies: [slotPlanning('2026-07-28T06:00:00+02:00', '2026-07-28T21:00:00+02:00')] });

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 6 : selection-serie-candidat
// ---------------------------------------------------------------------------
function vecteursSelectionSerie() {
  const c = new Collecteur('selection-serie-candidat');
  const analyse = (nom, missions, idsSelectionnes, idsConflit) => c.ajoute(`analyserSelectionSerie/${nom}`,
    { fonction: 'analyserSelectionSerie', missions, idsSelectionnes, idsConflit },
    sansException('selection-serie-candidat', nom, capture(() => {
      const r = selectionSerie.analyserSelectionSerie(missions, new Set(idsSelectionnes), new Set(idsConflit));
      return {
        missionsSelectionnees: r.missionsSelectionnees.map((m) => m.id),
        idsEnConflit: r.idsEnConflit,
        idsPlanningInexact: r.idsPlanningInexact,
        peutAccepter: r.peutAccepter,
      };
    })));
  const missionSerie = (id, extra = {}) => ({
    id,
    debut_le: `2026-08-0${id}T08:00:00+02:00`,
    fin_le: `2026-08-0${id}T16:00:00+02:00`,
    nb_creneaux: 1,
    creneaux_planifies: [journee(`2026-08-0${id}`, { id: `c-${id}` })],
    ...extra,
  });
  const sept = Array.from({ length: 7 }, (_, index) => missionSerie(String(index + 1)));
  const ids = sept.map((m) => m.id);

  // --- Issus des tests vitest ---------------------------------------------
  analyse('vitest-conflit-conserve', sept, ids, ['7']);
  analyse('vitest-sous-ensemble-six', sept, ids.slice(0, 6), []);
  analyse('vitest-planning-inexact', [{ ...missionSerie('1'), nb_creneaux: 2 }], ['1'], []);

  // --- Grille --------------------------------------------------------------
  analyse('selection-vide', sept, [], []);
  analyse('aucune-mission-ouverte', [], ['1'], ['1']);
  analyse('ids-inconnus-ignores', sept, ['42', '1'], ['42']);
  analyse('ordre-des-missions-ouvertes', sept, ['6', '2', '4'], []);
  analyse('conflit-hors-selection-ignore', sept, ['1', '2'], ['3']);
  analyse('conflit-et-inexact-meme-mission', [...sept.slice(0, 2), { ...missionSerie('3'), nb_creneaux: 2 }], ['1', '2', '3'], ['3']);
  analyse('plusieurs-conflits', sept, ids, ['2', '5', '7']);
  analyse('erreur-chargement-inexact', [missionSerie('1', { erreur_planning: true }), missionSerie('2')], ['1', '2'], []);
  analyse('ponctuelle-sans-creneau-repli', [missionSerie('1', { creneaux_planifies: [] })], ['1'], []);
  analyse('longue-sans-creneau-inexacte', [{ id: 'longue', debut_le: '2026-08-01T08:00:00+02:00', fin_le: '2026-08-07T16:00:00+02:00', nb_creneaux: null, creneaux_planifies: [] }], ['longue'], []);
  analyse('creneau-sans-fin-inexact', [missionSerie('1', { creneaux_planifies: [slotPlanning('2026-08-01T08:00:00+02:00', null)] })], ['1'], []);
  analyse('pause-seule-repli', [missionSerie('1', { creneaux_planifies: [slotPlanning('2026-08-01T12:00:00+02:00', '2026-08-01T12:30:00+02:00', { est_pause: true })] })], ['1'], []);
  analyse('tout-selectionne-sans-conflit', sept, ids, []);
  analyse('ids-dupliques-dans-ouvertes', [missionSerie('1'), missionSerie('1')], ['1'], []);

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 7 : completude-planning-mission
// ---------------------------------------------------------------------------
function vecteursCompletudePlanning() {
  const c = new Collecteur('completude-planning-mission');
  const analyse = (nom, mission, creneaux = []) => c.ajoute(`analyserCompletudePlanningMission/${nom}`,
    { fonction: 'analyserCompletudePlanningMission', mission, creneaux },
    sansException('completude-planning-mission', nom, capture(() => {
      const r = completude.analyserCompletudePlanningMission(mission, creneaux);
      return { complet: r.complet, creneauxPlanifies: r.creneauxPlanifies, nombrePlanifie: r.nombrePlanifie, dureeTotaleHeures: r.dureeTotaleHeures };
    })));

  // --- Issus des tests vitest ---------------------------------------------
  const missionLongue = { id: 'mission-1', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-08-31T16:00:00+02:00', nb_creneaux: 2 };
  const creneauxExacts = [journee('2026-07-06', { id: 'creneau-1' }), journee('2026-08-31', { id: 'creneau-2' })];
  analyse('vitest-nombre-exact', missionLongue, creneauxExacts);
  analyse('vitest-reponse-tronquee', missionLongue, creneauxExacts.slice(0, 1));
  analyse('vitest-creneau-invalide', { ...missionLongue, nb_creneaux: 1 }, [{ ...creneauxExacts[0], fin: '2026-07-06T07:59:00+02:00' }]);
  analyse('vitest-repli-legacy-ponctuelle', { id: 'mission-legacy', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-07-06T16:00:00+02:00', nb_creneaux: null });
  analyse('vitest-longue-legacy-sans-planning', { id: 'mission-longue-legacy', debut_le: '2026-07-06T08:00:00+02:00', fin_le: '2026-08-31T16:00:00+02:00', nb_creneaux: null });

  // --- nb_creneaux vérifiable ---------------------------------------------
  const base = { id: 'm', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00' };
  const travail = journee('2026-07-31', { id: 'travail', mission_id: 'm' });
  const pause = slotPlanning('2026-07-31T12:00:00+02:00', '2026-07-31T12:30:00+02:00', { id: 'pause', mission_id: 'm', est_pause: true });
  const effectif = slotPlanning('2026-07-31T08:05:00+02:00', '2026-07-31T15:55:00+02:00', { id: 'eff', mission_id: 'm', type_creneau: 'EFFECTIF' });
  analyse('nb-1-un-creneau', { ...base, nb_creneaux: 1 }, [travail]);
  analyse('nb-1-pause-exclue', { ...base, nb_creneaux: 1 }, [pause, travail]);
  analyse('nb-1-effectif-ignore', { ...base, nb_creneaux: 1 }, [effectif, travail]);
  analyse('nb-1-effectif-seul', { ...base, nb_creneaux: 1 }, [effectif]);
  analyse('nb-1-pause-seule', { ...base, nb_creneaux: 1 }, [pause]);
  analyse('nb-1-aucun-creneau-pas-de-repli', { ...base, nb_creneaux: 1 }, []);
  analyse('nb-1-fin-null', { ...base, nb_creneaux: 1 }, [slotPlanning('2026-07-31T08:00:00+02:00', null, { id: 'ouvert' })]);
  analyse('nb-1-fin-vide', { ...base, nb_creneaux: 1 }, [slotPlanning('2026-07-31T08:00:00+02:00', '', { id: 'ouvert' })]);
  analyse('nb-1-duree-nulle', { ...base, nb_creneaux: 1 }, [slotPlanning('2026-07-31T08:00:00+02:00', '2026-07-31T08:00:00+02:00', { id: 'nul' })]);
  analyse('nb-1-debut-illisible', { ...base, nb_creneaux: 1 }, [slotPlanning('pas une date', '2026-07-31T16:00:00+02:00', { id: 'x' })]);
  analyse('nb-1-fin-illisible', { ...base, nb_creneaux: 1 }, [slotPlanning('2026-07-31T08:00:00+02:00', 'pas une date', { id: 'x' })]);
  analyse('nb-2-deux-creneaux-desordre', { ...base, nb_creneaux: 2 }, [creneauxExacts[1], creneauxExacts[0]]);
  analyse('nb-2-trois-creneaux', { ...base, nb_creneaux: 2 }, [...creneauxExacts, journee('2026-09-01', { id: 'trois' })]);
  analyse('nb-2-un-valide-un-sans-fin', { ...base, nb_creneaux: 2 }, [creneauxExacts[0], slotPlanning('2026-08-31T08:00:00+02:00', null, { id: 'ouvert' })]);
  analyse('nb-2-un-valide-un-invalide', { ...base, nb_creneaux: 2 }, [creneauxExacts[0], slotPlanning('2026-08-31T16:00:00+02:00', '2026-08-31T08:00:00+02:00', { id: 'inverse' })]);
  analyse('nb-2-meme-debut-ordre-stable', { ...base, nb_creneaux: 2 }, [
    slotPlanning('2026-07-31T08:00:00+02:00', '2026-07-31T12:00:00+02:00', { id: 'b' }),
    slotPlanning('2026-07-31T08:00:00+02:00', '2026-07-31T10:00:00+02:00', { id: 'a' }),
  ]);
  analyse('nb-string-2', { ...base, nb_creneaux: '2' }, creneauxExacts);
  analyse('nb-1-nuit-dst-mars-11h', { ...base, nb_creneaux: 1 }, [slotPlanning('2026-03-28T20:00:00+01:00', '2026-03-29T08:00:00+02:00', { id: 'dst' })]);
  analyse('nb-1-nuit-dst-octobre-13h', { ...base, nb_creneaux: 1 }, [slotPlanning('2026-10-24T20:00:00+02:00', '2026-10-25T08:00:00+01:00', { id: 'dst' })]);
  analyse('nb-3-formats-iso-melanges', { ...base, nb_creneaux: 3 }, [
    slotPlanning('2026-12-01T07:00:00Z', '2026-12-01T15:00:00.000Z', { id: 'z' }),
    slotPlanning('2026-08-31T08:00:00', '2026-08-31T16:00:00', { id: 'legacy' }),
    slotPlanning('2026-07-31T08:00:00+02:00', '2026-07-31T16:00:00+02:00', { id: 'offset' }),
  ]);
  analyse('nb-1-demi-heures', { ...base, nb_creneaux: 1 }, [slotPlanning('2026-07-31T06:45:00+02:00', '2026-07-31T14:15:00+02:00', { id: 'h' })]);
  const semaine = ['2026-08-03', '2026-08-04', '2026-08-05', '2026-08-06', '2026-08-07', '2026-08-08', '2026-08-09'].map((jour, i) => journee(jour, { id: `j${i + 1}` }));
  analyse('nb-7-serie', { id: 'serie', debut_le: '2026-08-03T08:00:00+02:00', fin_le: '2026-08-09T16:00:00+02:00', nb_creneaux: 7 }, semaine);
  analyse('nb-7-serie-six-recus', { id: 'serie', debut_le: '2026-08-03T08:00:00+02:00', fin_le: '2026-08-09T16:00:00+02:00', nb_creneaux: 7 }, semaine.slice(0, 6));

  // --- Repli legacy (nb_creneaux absent, nul ou non vérifiable) -------------
  analyse('legacy-nb-null-1h', { ...base, fin_le: '2026-07-31T09:00:00+02:00', nb_creneaux: null });
  analyse('legacy-nb-absent', { id: 'm', debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00' });
  analyse('legacy-nb-0', { ...base, nb_creneaux: 0 });
  analyse('legacy-nb-negatif', { ...base, nb_creneaux: -1 });
  analyse('legacy-24h-exactes', { ...base, fin_le: '2026-08-01T08:00:00+02:00', nb_creneaux: null });
  analyse('legacy-24h-plus-1s', { ...base, fin_le: '2026-08-01T08:00:01+02:00', nb_creneaux: null });
  analyse('legacy-duree-nulle', { ...base, fin_le: '2026-07-31T08:00:00+02:00', nb_creneaux: null });
  analyse('legacy-fin-avant-debut', { ...base, debut_le: '2026-07-31T16:00:00+02:00', fin_le: '2026-07-31T08:00:00+02:00', nb_creneaux: null });
  analyse('legacy-date-illisible', { ...base, debut_le: 'pas une date', nb_creneaux: null });
  analyse('legacy-sans-id', { debut_le: '2026-07-31T08:00:00+02:00', fin_le: '2026-07-31T16:00:00+02:00', nb_creneaux: null });
  analyse('legacy-nb-0-avec-creneau-recu', { ...base, nb_creneaux: 0 }, [travail]);
  analyse('legacy-nb-null-avec-creneau-recu', { ...base, nb_creneaux: null }, [travail]);
  analyse('legacy-pause-seule-repli', { ...base, nb_creneaux: null }, [pause]);
  analyse('legacy-effectif-seul-repli', { ...base, nb_creneaux: null }, [effectif]);
  analyse('legacy-nuit-dst-mars-11h', { ...base, debut_le: '2026-03-28T20:00:00+01:00', fin_le: '2026-03-29T08:00:00+02:00', nb_creneaux: null });
  analyse('legacy-nuit-dst-octobre-13h', { ...base, debut_le: '2026-10-24T20:00:00+02:00', fin_le: '2026-10-25T08:00:00+01:00', nb_creneaux: null });
  analyse('legacy-sans-offset', { ...base, debut_le: '2026-08-31T08:00:00', fin_le: '2026-08-31T16:00:00', nb_creneaux: null });
  analyse('legacy-utc-z', { ...base, debut_le: '2026-12-01T07:00:00Z', fin_le: '2026-12-01T15:00:00.000Z', nb_creneaux: null });

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
  // Lot 1 (T2) : règles pures de la candidature.
  'planning-candidat.json': vecteursPlanningCandidat(),
  'selection-serie-candidat.json': vecteursSelectionSerie(),
  'completude-planning-mission.json': vecteursCompletudePlanning(),
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
