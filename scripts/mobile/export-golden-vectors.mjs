#!/usr/bin/env node
/**
 * Export des vecteurs golden pour le port Swift des règles pures (plan §4.1).
 *
 * Lit directement les modules TypeScript de `src/lib` et du planning candidat
 * (`src/components/planning/planning-candidat.ts`, `selection-serie-candidat.ts`)
 * par type stripping natif de Node, aucune dépendance supplémentaire, et écrit,
 * par règle, un JSON de vecteurs `{ name, input, expected }` dans
 * `ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/Resources/golden/`.
 * Un hook `module.register()` résout l'alias `@/lib/<module>` et les imports
 * relatifs sans extension de ces modules (lot 1, T2). Lot 3, T2 : liste
 * d'exceptions nommée pour `src/lib/pushNative.ts` seulement (modules inertes,
 * décision 22 du lot 3) et règles push, revenus, profil, session et RPPS ; les
 * `case` de `navigationPathForEvent` sont lus par le compilateur TypeScript
 * (`typescript`, dépendance de développement du dépôt), bornés au corps de la fonction.
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
//
// Exception nommée (lot 3, T2, décision 22) : `src/lib/pushNative.ts` mêle la
// règle pure `navigationPathForEvent` et le cycle de vie Capacitor. Ses imports
// impurs (`@/integrations/supabase/client`, `./platform`, `./logger`,
// `./pushDeviceToken`, `./nativeResume`, `./navigationNotification`) sont
// remplacés, pour ce seul parent, par des modules inertes qui lèvent dès qu'ils
// sont appelés ou lus (aucune règle exportée ne les touche). `./nativeLinks`
// reste réel : son import `@capacitor/core` s'évalue sous Node
// (`Capacitor.isNativePlatform()` → false) et n'est utilisé que par
// `urlCallbackPublique`, hors du routage. Aucun autre parent ni alias n'est
// concerné ; `src/` n'est pas modifié.
const HOOK_RESOLUTION = `
let racineSrc = null;
let inertes = {};
const AVEC_EXTENSION = /\\.[cm]?[jt]sx?$/;
export async function initialize(donnees) {
  racineSrc = donnees.racineSrc;
  inertes = donnees.inertes ?? {};
}
export async function resolve(specifier, context, nextResolve) {
  const inertesDuParent = typeof context.parentURL === 'string' ? inertes[context.parentURL] : undefined;
  if (inertesDuParent && Object.prototype.hasOwnProperty.call(inertesDuParent, specifier)) {
    return { url: inertesDuParent[specifier], shortCircuit: true };
  }
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
// Modules inertes de `pushNative.ts` : un export par nom réellement importé
// (`fonction` lève à l'appel, `objet` à toute lecture de propriété, `valeur` à
// toute conversion en texte ou en nombre).
const PUSH_NATIVE = resolve(RACINE, 'src/lib/pushNative.ts');
const MODULES_INERTES_PUSH = {
  '@/integrations/supabase/client': { supabase: 'objet' },
  './platform': { isNative: 'fonction' },
  './logger': { logger: 'objet' },
  './pushDeviceToken': { memoriserTokenPushAppareil: 'fonction' },
  './nativeResume': { signalerNavigationNative: 'fonction' },
  './navigationNotification': { OUVERTURE_NOTIFICATION: 'valeur' },
};
const IMPORTS_REELS_PUSH = ['./nativeLinks'];
{
  // Garde : si `pushNative.ts` change d'imports, l'exception nommée doit être revue.
  const importsPush = [...readFileSync(PUSH_NATIVE, 'utf8').matchAll(/^import\s[^;]*?from\s+'([^']+)';/gm)].map((m) => m[1]).sort();
  const attendus = [...Object.keys(MODULES_INERTES_PUSH), ...IMPORTS_REELS_PUSH].sort();
  if (JSON.stringify(importsPush) !== JSON.stringify(attendus)) {
    console.error(`export golden : imports de src/lib/pushNative.ts inattendus (${importsPush.join(', ')}) ; attendus : ${attendus.join(', ')}. Revoir MODULES_INERTES_PUSH (décision 22 du lot 3).`);
    process.exit(2);
  }
}
function moduleInerte(specifier, exports) {
  const leve = `throw new Error(${JSON.stringify(`export golden : « ${specifier} » est un module inerte de pushNative.ts, il ne doit pas être utilisé par une règle golden.`)});`;
  const lignes = Object.entries(exports).map(([nom, genre]) => {
    if (genre === 'fonction') return `export function ${nom}() { ${leve} }`;
    if (genre === 'objet') return `export const ${nom} = new Proxy({}, { get() { ${leve} } });`;
    return `export const ${nom} = Object.freeze({ toString() { ${leve} }, valueOf() { ${leve} }, [Symbol.toPrimitive]() { ${leve} } });`;
  });
  return `data:text/javascript,${encodeURIComponent(lignes.join('\n'))}`;
}

register(`data:text/javascript,${encodeURIComponent(HOOK_RESOLUTION)}`, {
  parentURL: import.meta.url,
  data: {
    racineSrc: pathToFileURL(`${resolve(RACINE, 'src')}/`).href,
    inertes: {
      [pathToFileURL(PUSH_NATIVE).href]: Object.fromEntries(
        Object.entries(MODULES_INERTES_PUSH).map(([specifier, exports]) => [specifier, moduleInerte(specifier, exports)]),
      ),
    },
  },
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
// Lot 3, T2.
const pushNative = await lib('pushNative.ts');
const financeMission = await lib('missionFinanceDisplay.ts');
const paiementUi = await lib('paiementSoignantUi.ts');
const validationProfil = await lib('valider-profil-soignant.ts');
const modesExercice = await lib('preferencesModesExercice.ts');
const constantes = await lib('constantes.ts');
const SESSION_COUNT = resolve(RACINE, 'src/lib/session-count.ts');
const ts = (await import('typescript')).default;

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

/**
 * JSON canonique (clés triées) d'une valeur telle que `JSON.stringify` l'écrit : deux valeurs
 * ont le même rendu si et seulement si leurs JSON écrits sont identiques à l'ordre des clés près
 * (comparaison `toEqual` sans dépendre de l'ordre des clés). Comme `JSON.stringify` : `toJSON`
 * appliqué ; clé d'objet de valeur `undefined`, fonction ou symbole omise ; même valeur dans un
 * tableau (trou compris) écrite `null` ; nombre non fini écrit `null`. Une valeur que JSON n'écrit
 * pas rend `undefined`, texte non JSON distinct de tout rendu écrit.
 */
function canon(valeur) {
  if (valeur !== null && typeof valeur === 'object' && typeof valeur.toJSON === 'function') return canon(valeur.toJSON());
  if (valeur === undefined || typeof valeur === 'function' || typeof valeur === 'symbol') return 'undefined';
  if (Array.isArray(valeur)) {
    return `[${Array.from(valeur, (element) => { const rendu = canon(element); return rendu === 'undefined' ? 'null' : rendu; }).join(',')}]`;
  }
  if (valeur !== null && typeof valeur === 'object') {
    const paires = Object.keys(valeur).sort().map((cle) => [cle, canon(valeur[cle])]).filter(([, rendu]) => rendu !== 'undefined');
    return `{${paires.map(([cle, rendu]) => `${JSON.stringify(cle)}:${rendu}`).join(',')}}`;
  }
  return JSON.stringify(valeur);
}

// Garde de `canon` (revue de L3-T2) : la clé de fusion des vecteurs doit suivre le JSON
// réellement écrit (`JSON.stringify`), que relit le contrôle Swift de `RulesGoldenTests`.
// Une clé d'objet de valeur `undefined` n'est pas écrite (≡ clé absente, ≢ `null`) ; dans un
// tableau, `undefined` s'écrit `null` ; `toJSON` (Date) s'applique ; un nombre non fini s'écrit `null`.
for (const [a, b, identiques] of [
  [{ data: undefined }, {}, true],
  [{ data: undefined }, { data: null }, false],
  [{ data: null }, {}, false],
  [{ reponse: { data: undefined, error: null } }, { reponse: { error: null } }, true],
  [[undefined], [null], true],
  [[undefined], [], false],
  [{ b: 1, a: { d: 2, c: 3 } }, { a: { c: 3, d: 2 }, b: 1 }, true],
  [{ instant: new Date(0) }, { instant: '1970-01-01T00:00:00.000Z' }, true],
  [{ n: Number.NaN }, { n: null }, true],
  [{ n: -0 }, { n: 0 }, true],
]) {
  if ((canon(a) === canon(b)) !== identiques) {
    console.error(`export golden : canon() ne suit pas JSON.stringify (${canon(a)} ${identiques ? '≠' : '='} ${canon(b)}).`);
    process.exit(2);
  }
}

/**
 * JSON canonique d'une valeur écrite dans un vecteur. Refuse ce que `JSON.stringify` n'écrit pas
 * (`undefined` : la clé `input` ou `expected` disparaîtrait du fichier) et vérifie que `canon`
 * coïncide avec la forme relue du JSON écrit (garde : l'export échoue sinon).
 */
function canonEcrit(regle, quoi, valeur) {
  if (valeur === undefined) throw new Error(`${regle}: ${quoi} vaut undefined, que JSON.stringify n'écrit pas.`);
  const ecrit = canon(valeur);
  const relu = canon(JSON.parse(JSON.stringify(valeur)));
  if (ecrit !== relu) {
    throw new Error(`${regle}: ${quoi} : le JSON canonique ${ecrit} ne suit pas le JSON écrit ${relu}.`);
  }
  return ecrit;
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
    // Une entrée identique (même JSON écrit, rendu canonique à clés triées, comme le contrôle
    // Swift de `RulesGoldenTests` qui relit ce JSON) n'apporte aucune couverture : elle est
    // fusionnée avec le premier vecteur qui la porte (les cas vitest précèdent les grilles).
    // Un attendu différent pour la même entrée serait une incohérence de l'export.
    const cle = canonEcrit(this.regle, `« ${name} » (input)`, input);
    const attendu = canonEcrit(this.regle, `« ${name} » (expected)`, expected);
    const existant = this.entrees.get(cle);
    if (existant) {
      if (existant.attendu !== attendu) {
        throw new Error(`${this.regle}: entrée identique avec attendus différents (« ${existant.name} », « ${name} »)`);
      }
      this.fusionnes.push(`${name} → ${existant.name}`);
      return;
    }
    this.noms.add(name);
    this.entrees.set(cle, { name, attendu });
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
// Règles 8 à 14 : lot 3, T2 (push, session, revenus, profil, modes d'exercice, RPPS)
// ---------------------------------------------------------------------------

/**
 * Garde des cas vitest : l'export échoue si le web ne vérifie plus son propre test
 * (`partiel` = `toMatchObject`). Comparaison sur la forme écrite (`canon`) : une clé de valeur
 * `undefined` vaut une clé absente, jamais `null`. Le vecteur exporté porte la sortie complète.
 */
function verifieVitest(regle, name, obtenu, attendu, partiel = false) {
  const ok = partiel && obtenu && typeof obtenu === 'object'
    ? Object.entries(attendu).every(([cle, valeur]) => canon({ [cle]: obtenu[cle] }) === canon({ [cle]: valeur }))
    : canon(obtenu) === canon(attendu);
  if (!ok) throw new Error(`${regle}: « ${name} » ne vérifie plus l'attente vitest ${canon(attendu)} (obtenu ${canon(obtenu)}).`);
  return obtenu;
}

// ---------------------------------------------------------------------------
// Règle 8 : push-routing (`navigationPathForEvent`, src/lib/pushNative.ts)
// ---------------------------------------------------------------------------
/**
 * Domaine : valeurs JSON du payload (`send-push` n'envoie que des chaînes ; toute
 * autre valeur est ignorée par `valeurTexte`). Les liens restent dans le domaine de
 * `JoleneLink.normalize` (lot 0 : ASCII imprimable, sans espace interne, sans
 * tabulation ni saut de ligne, que `new URL()` encoderait ou retirerait à la volée).
 */
function vecteursPushRouting() {
  const c = new Collecteur('push-routing');
  const route = (nom, data, role, vitest) => {
    const name = `navigationPathForEvent/${nom}`;
    const obtenu = pushNative.navigationPathForEvent(data, role);
    if (vitest !== undefined) verifieVitest('push-routing', name, obtenu, vitest);
    c.ajoute(name, { fonction: 'navigationPathForEvent', data, role }, obtenu);
  };

  // Types routés, lus dans les `case` du corps de `navigationPathForEvent` seul (arbre du
  // compilateur TypeScript : une fonction voisine n'y entre pas) : garde de dérive (le port
  // Swift doit router exactement la même liste, dans le même ordre).
  const source = readFileSync(PUSH_NATIVE, 'utf8');
  const arbre = ts.createSourceFile(PUSH_NATIVE, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const declarations = arbre.statements.filter((noeud) => ts.isFunctionDeclaration(noeud) && noeud.name?.text === 'navigationPathForEvent');
  if (declarations.length !== 1 || !declarations[0].body) {
    throw new Error('push-routing: déclaration de navigationPathForEvent introuvable ou dupliquée dans src/lib/pushNative.ts.');
  }
  const types = [];
  const visite = (noeud) => {
    if (ts.isCaseClause(noeud)) {
      if (!ts.isStringLiteral(noeud.expression)) {
        throw new Error(`push-routing: case non littéral dans navigationPathForEvent (${noeud.expression.getText(arbre)}).`);
      }
      types.push(noeud.expression.text);
    }
    ts.forEachChild(noeud, visite);
  };
  visite(declarations[0].body);
  if (types.length === 0 || new Set(types).size !== types.length) {
    throw new Error('push-routing: liste des types de navigationPathForEvent illisible ou dupliquée.');
  }
  c.ajoute('typesRoutes/switch-navigationPathForEvent', { fonction: 'typesRoutes' }, types);

  // --- Issus de pushNative.test.ts (6 it, 15 attentes) -------------------
  route('vitest-1-lien-externe-refuse', { lien: 'https://evil.example/phishing' }, null, null);
  route('vitest-1-lien-interne-query-hash', { lien: '/soignant/missions?id=1#pointage' }, null, '/soignant/missions?id=1#pointage');
  route('vitest-2-candidature-recue', { type_evenement: 'CANDIDATURE_RECUE', mission_id: 'm1' }, null, '/etablissement/missions/m1');
  route('vitest-2-candidature-acceptee', { type_evenement: 'CANDIDATURE_ACCEPTEE', mission_id: 'm1' }, null, '/soignant/missions/m1');
  route('vitest-3-annulation-soignant-vue-etab', { type_evenement: 'CANDIDATURE_ANNULEE_SOIGNANT' }, 'ADMIN_ETABLISSEMENT', '/etablissement/missions');
  route('vitest-3-mission-annulee-etab-vue-soignant', { type_evenement: 'MISSION_ANNULEE_ETAB' }, 'SOIGNANT', '/soignant/missions');
  route('vitest-4-mission-urgente', { type_evenement: 'MISSION_URGENTE', mission_id: 'm1' }, 'SOIGNANT', '/soignant/missions/m1');
  route('vitest-4-mission-a-pourvoir', { type_evenement: 'MISSION_A_POURVOIR' }, 'SOIGNANT', '/soignant/recherche-missions');
  route('vitest-4-rappel-mission', { type_evenement: 'RAPPEL_MISSION', mission_id: 'm1' }, 'SOIGNANT', '/soignant/missions/m1');
  route('vitest-4-dpae-non-regularisee', { type_evenement: 'DPAE_NON_REGULARISEE_POINTAGE', contrat_id: 'c1' }, 'ADMIN_ETABLISSEMENT', '/contrat/c1');
  route('vitest-5-racine-avec-type', { lien: '/', type_evenement: 'MISSION_ASSIGNEE' }, 'SOIGNANT', '/soignant/missions');
  route('vitest-5-racine-sans-type', { lien: '/' }, null, '/');
  route('vitest-6-litige-vue-etab', { type_evenement: 'LITIGE_OUVERT', litige_id: 'l1' }, 'ADMIN_ETABLISSEMENT', '/etablissement/litiges#l1');
  route('vitest-6-facture-vue-etab', { type_evenement: 'FACTURE_EMISE', facture_id: 'f1' }, 'ADMIN_ETABLISSEMENT', '/etablissement/facturation/f1');
  route('vitest-6-facture-vue-soignant', { type_evenement: 'FACTURE_EMISE' }, 'SOIGNANT', '/soignant/mes-gains?tab=factures');

  // --- Grille types × rôles × identifiants ----------------------------------
  const ROLES = [['soignant', 'SOIGNANT'], ['admin-etab', 'ADMIN_ETABLISSEMENT'], ['etab-legacy', 'ETABLISSEMENT'],
    ['admin-plateforme', 'ADMIN_PLATEFORME'], ['admin', 'ADMIN'], ['sans-role', null]];
  const IDS = [
    ['sans-id', {}],
    ['ids-simples', { mission_id: 'm1', contrat_id: 'c1', facture_id: 'f1', litige_id: 'l1' }],
    ['ids-a-encoder', { mission_id: ' m 1/2#?é ', contrat_id: 'c/1?x=1&y', facture_id: 'f#1%', litige_id: "l 1😀!'()*~-_." }],
  ];
  const TYPES_GRILLE = [...types.map((t) => [t, t]), ['type-inconnu', 'TYPE_INCONNU'], ['type-absent', undefined],
    ['type-entoure-espaces', '  MISSION_URGENTE\t'], ['type-minuscules', 'mission_urgente']];
  const avecType = (type, reste) => (type === undefined ? { ...reste } : { type_evenement: type, ...reste });
  for (const [nomType, type] of TYPES_GRILLE) {
    for (const [nomRole, role] of ROLES) {
      for (const [nomIds, ids] of IDS) route(`grille/${nomType}/${nomRole}/${nomIds}`, avecType(type, ids), role);
    }
    for (const [nomRole, role] of [['admin-groupe', 'ADMIN_GROUPE'], ['role-inconnu', 'INCONNU']]) {
      route(`grille/${nomType}/${nomRole}/ids-simples`, avecType(type, IDS[1][1]), role);
    }
    // Espaces JavaScript (`trim`) et valeurs non textuelles : ignorées comme absentes.
    for (const [nomRole, role] of [['soignant', 'SOIGNANT'], ['admin-etab', 'ADMIN_ETABLISSEMENT']]) {
      route(`grille/${nomType}/${nomRole}/ids-blancs-ou-non-texte`,
        avecType(type, { mission_id: '   ', contrat_id: 42, facture_id: true, litige_id: ' ﻿　' }), role);
      route(`grille/${nomType}/${nomRole}/ids-espaces-unicode`,
        avecType(type, { mission_id: '\u0085m1', contrat_id: '　c1 ', facture_id: '᠎f1', litige_id: ' l1 ' }), role);
    }
  }

  // --- Liens explicites : clés `lien`, `link`, `url` ---------------------------
  const LIENS = [
    ['interne-query-hash', '/soignant/missions?id=1#pointage'],
    ['interne-simple', '/soignant/stripe-connect'],
    ['racine', '/'],
    ['racine-query', '/?x=1'],
    ['racine-fragment', '/#x'],
    ['https-jolene', 'https://jolene.app/soignant/notifications'],
    ['https-www', 'https://www.jolene.app/soignant/profil?tab=a'],
    ['https-app', 'https://app.jolene.app/soignant/mes-gains?tab=factures#f1'],
    ['https-majuscules', 'HTTPS://JOLENE.APP/Soignant/Missions'],
    ['https-sans-chemin', 'https://jolene.app'],
    ['https-port-443', 'https://jolene.app:443/soignant/missions'],
    ['https-port-8443', 'https://jolene.app:8443/soignant/missions'],
    ['https-externe', 'https://evil.example/phishing'],
    ['https-sous-domaine-piege', 'https://jolene.app.evil.example/x'],
    ['https-identifiants-piege', 'https://jolene.app@evil.example/x'],
    ['http-jolene', 'http://jolene.app/soignant/missions'],
    ['protocole-relatif', '//evil.example/x'],
    ['antislash', '/\\evil.example'],
    ['javascript', 'javascript:alert(1)'],
    ['relatif-sans-barre', 'soignant/missions'],
    ['segments-points', '/soignant/../admin/./litiges'],
    ['pourcent-encode', '/soignant/missions/a%20b'],
    ['entoure-espaces', '  /soignant/missions  '],
    ['vide', ''],
    ['blanc', '   '],
  ];
  for (const [nomLien, lien] of LIENS) {
    for (const [nomType, type] of [['sans-type', undefined], ['type-connu', 'MISSION_ASSIGNEE'], ['type-inconnu', 'TYPE_INCONNU']]) {
      route(`lien/${nomLien}/${nomType}`, avecType(type, { lien, mission_id: 'm1' }), 'SOIGNANT');
    }
    route(`link/${nomLien}`, { link: lien }, 'SOIGNANT');
    route(`url/${nomLien}`, { url: lien }, 'SOIGNANT');
  }

  // --- Priorité des clés et type non textuel --------------------------------
  route('priorite/lien-invalide-masque-link', { lien: 'https://evil.example/x', link: '/soignant/profil', type_evenement: 'MISSION_ASSIGNEE', mission_id: 'm1' }, 'SOIGNANT');
  route('priorite/lien-blanc-cede-a-link', { lien: '   ', link: '/soignant/profil' }, 'SOIGNANT');
  route('priorite/lien-non-texte-cede-a-url', { lien: 5, url: '/soignant/notifications' }, 'SOIGNANT');
  route('priorite/link-vide-cede-a-url', { link: '', url: 'https://jolene.app/soignant/stripe-connect?success=true' }, 'SOIGNANT');
  route('priorite/lien-racine-masque-link-avec-type', { lien: '/', link: '/soignant/profil', type_evenement: 'MISSION_ASSIGNEE' }, 'SOIGNANT');
  route('priorite/link-racine-sans-type', { link: '/' }, null);
  route('priorite/lien-gagne-sur-type-etab', { lien: '/soignant/profil', type_evenement: 'FACTURE_EMISE', facture_id: 'f1' }, 'ADMIN_ETABLISSEMENT');
  route('priorite/type-non-texte', { type_evenement: 5, mission_id: 'm1' }, 'SOIGNANT');
  route('priorite/type-blanc', { type_evenement: '   ', mission_id: 'm1' }, 'SOIGNANT');
  route('priorite/lien-racine-type-non-texte', { lien: '/', type_evenement: 5 }, 'SOIGNANT');
  route('priorite/lien-racine-type-blanc', { lien: '/', type_evenement: ' ' }, 'SOIGNANT');
  route('priorite/lien-racine-type-inconnu', { lien: '/', type_evenement: 'TYPE_INCONNU' }, 'SOIGNANT');
  route('priorite/payload-vide', {}, 'SOIGNANT');

  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 9 : session-count (`estSessionRecurrente` sur compteur, src/lib/session-count.ts)
// ---------------------------------------------------------------------------
/**
 * Le module lit `localStorage` / `sessionStorage` et garde un drapeau de module :
 * chaque vecteur charge une instance neuve (`?instance=N`) sur des stockages simulés.
 * Domaine : compteurs dont le successeur reste sous 1e21 (au-delà, `String(n)` passe
 * en notation exponentielle) ; au-delà de 2^53, `String(n)` écrit les chiffres les plus
 * courts qui relisent le même nombre (vecteurs 2^60, 2^69, 21 chiffres), que le port
 * reproduit. « Stockage indisponible » est hors domaine natif (UserDefaults ne lève pas).
 */
async function vecteursSessionCount() {
  const c = new Collecteur('session-count');
  const globaux = ['window', 'localStorage', 'sessionStorage'];
  const avant = Object.fromEntries(globaux.map((nom) => [nom, Object.getOwnPropertyDescriptor(globalThis, nom)]));
  const stockage = (entrees) => {
    const valeurs = new Map(entrees);
    return { getItem: (cle) => (valeurs.has(cle) ? valeurs.get(cle) : null), setItem: (cle, valeur) => { valeurs.set(cle, String(valeur)); }, valeurs };
  };
  let instance = 0;
  const charger = async (local, session) => {
    for (const [nom, valeur] of [['window', globalThis], ['localStorage', local], ['sessionStorage', session]]) {
      Object.defineProperty(globalThis, nom, { value: valeur, configurable: true, writable: true });
    }
    instance += 1;
    return import(`${pathToFileURL(SESSION_COUNT).href}?instance=${instance}`);
  };
  const COMPTEURS = [['absent', null], ['vide', ''], ['zero', '0'], ['un', '1'], ['deux', '2'], ['dix', '10'],
    ['espaces-trois', '  3'], ['nbsp-deux', ' 2'], ['deux-suffixe-texte', '2abc'], ['un-virgule-neuf', '1.9'],
    ['deux-virgule-cinq', '2.5'], ['moins-un', '-1'], ['moins-zero', '-0'], ['plus-deux', '+2'], ['exposant', '1e3'],
    ['hexadecimal', '0x10'], ['texte', 'abc'], ['chiffre-arabe', '٢'], ['blanc', '   '],
    ['au-dela-2-puissance-53', '9007199254740993'], ['vingt-chiffres', '99999999999999999999'],
    // Au-delà de 2^53, `String(n)` écrit les chiffres les plus courts, pas la valeur exacte du
    // Double (2^60 → « 1152921504606847000 », non « 1152921504606846976 »).
    ['deux-puissance-60', '1152921504606846976'], ['deux-puissance-69', '590295810358705651712'],
    ['vingt-et-un-chiffres', '123456789012345678901']];
  try {
    for (const [nom, brut] of COMPTEURS) {
      const entrees = brut === null ? [] : [['jolene_session_count', brut]];
      const lecture = await charger(stockage(entrees), stockage([]));
      c.ajoute(`estSessionRecurrente/${nom}`, { fonction: 'estSessionRecurrente', compteur: brut },
        { numero: lecture.getNumeroSession(), recurrente: lecture.estSessionRecurrente() });

      for (const dejaComptee of [false, true]) {
        const local = stockage(entrees);
        const session = stockage(dejaComptee ? [['jolene_session_counted', '1']] : []);
        const module = await charger(local, session);
        const retours = [module.incrementerSession(), module.incrementerSession()];
        c.ajoute(`incrementerSession/${nom}/${dejaComptee ? 'session-deja-comptee' : 'nouvelle-session'}`,
          { fonction: 'incrementerSession', compteur: brut, dejaCompteeCetteSession: dejaComptee, appels: 2 },
          { retours, compteurApres: local.valeurs.has('jolene_session_count') ? local.valeurs.get('jolene_session_count') : null,
            recurrenteApres: module.estSessionRecurrente() });
      }
    }
  } finally {
    for (const nom of globaux) {
      if (avant[nom]) Object.defineProperty(globalThis, nom, avant[nom]);
      else delete globalThis[nom];
    }
  }
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 10 : mission-finance-display (src/lib/missionFinanceDisplay.ts)
// ---------------------------------------------------------------------------
/**
 * Domaine : types de l'interface `MissionFinanceAffichee` (nombre JSON ou null, booléen
 * ou null, texte ou null, clé absente). La correction du plafond Rist est vectorisée
 * même si l'écran natif ne lit pas ces colonnes (décision 5 du lot 3, correction 19).
 */
function vecteursMissionFinance() {
  const c = new Collecteur('mission-finance-display');
  const net = (nom, mission, vitest) => {
    const name = `netEstimeAfficheMission/${nom}`;
    const obtenu = financeMission.netEstimeAfficheMission(mission);
    if (vitest !== undefined) verifieVitest('mission-finance-display', name, obtenu, vitest);
    c.ajoute(name, { fonction: 'netEstimeAfficheMission', mission }, obtenu);
  };
  const montant = (nom, mission, vitest) => {
    const name = `montantFinanceAfficheMission/${nom}`;
    const obtenu = financeMission.montantFinanceAfficheMission(mission);
    if (vitest !== undefined) verifieVitest('mission-finance-display', name, obtenu, vitest, vitest !== null);
    c.ajoute(name, { fonction: 'montantFinanceAfficheMission', mission }, obtenu);
  };

  // --- Issus de missionFinanceDisplay.test.ts --------------------------------
  net('vitest-medecin-liberal-plafond-historique', { profession_requise: 'MEDECIN', type_contrat_recherche: 'LIBERAL', soignant_assigne_id: null,
    taux_horaire_base: 90, taux_rist_plafonne: 30, rist_plafond_applique: true, net_estime: 280.80 }, 842.40);
  net('vitest-ide-taux-coherent', { profession_requise: 'IDE', type_contrat_recherche: 'SALARIE', soignant_assigne_id: null,
    taux_horaire_base: 31, taux_rist_plafonne: 31, rist_plafond_applique: false, net_estime: 351.11 }, 351.11);
  net('vitest-vrai-plafond-salarie-assigne', { profession_requise: 'IDE', type_contrat_applique: 'SALARIE', soignant_assigne_id: 'soignant-1',
    taux_horaire_base: 35, taux_rist_plafonne: 30, rist_plafond_applique: true, net_estime: 339.77 }, 339.77);
  net('vitest-net-a-payer-jamais-net', { type_contrat_applique: 'SALARIE', net_estime: null, net_a_payer: 100 }, null);
  montant('vitest-honoraires-sans-abattement', { type_contrat_applique: 'LIBERAL', net_a_payer: 1_000, net_estime: 780, total_brut: 1_000 },
    { montant: 1_000, nature: 'HONORAIRES_LIBERAUX', libelleCourt: 'honoraires' });
  montant('vitest-net-estime-salarie', { type_contrat_applique: 'SALARIE', net_a_payer: 444.68, net_estime: 346.85 },
    { montant: 346.85, nature: 'NET_SALARIE_ESTIME' });
  montant('vitest-pas-de-net-invente', { type_contrat_recherche: 'SALARIE', net_a_payer: 444.68, net_estime: null }, null);
  montant('vitest-brut-contrat-a-choisir', { type_contrat_recherche: 'TOUS', total_brut: 500, net_a_payer: 590, net_estime: 460 },
    { montant: 500, nature: 'BRUT_INDICATIF', libelleCourt: 'brut indicatif' });

  // --- Contrat effectif : appliqué × recherché ---------------------------------
  const CONTRATS = [['absent', undefined], ['null', null], ['liberal', 'LIBERAL'], ['salarie', 'SALARIE'], ['tous', 'TOUS'], ['vide', ''], ['cdd', 'CDD']];
  const avec = (base, champs) => {
    const mission = { ...base };
    for (const [cle, valeur] of Object.entries(champs)) if (valeur !== undefined) mission[cle] = valeur;
    return mission;
  };
  const montantsTypes = { net_a_payer: 444.68, total_brut: 500, net_estime: 346.85 };
  for (const [nomA, applique] of CONTRATS) {
    for (const [nomR, recherche] of CONTRATS) {
      const mission = avec(montantsTypes, { type_contrat_applique: applique, type_contrat_recherche: recherche });
      montant(`contrat/applique-${nomA}/recherche-${nomR}`, mission);
    }
  }

  // --- Montants disponibles par régime -----------------------------------------
  const VALEURS = [['absent', undefined], ['null', null], ['zero', 0], ['positif', 123.45]];
  for (const [nomRegime, regime] of [['liberal', { type_contrat_applique: 'LIBERAL' }], ['salarie', { type_contrat_applique: 'SALARIE' }],
    ['a-choisir', { type_contrat_recherche: 'TOUS' }]]) {
    for (const [nomN, netAPayer] of VALEURS) {
      for (const [nomB, totalBrut] of VALEURS) {
        for (const [nomE, netEstime] of VALEURS) {
          const mission = avec(regime, { net_a_payer: netAPayer, total_brut: totalBrut, net_estime: netEstime });
          montant(`montants/${nomRegime}/net-a-payer-${nomN}/total-brut-${nomB}/net-estime-${nomE}`, mission);
        }
      }
    }
    for (const [nomV, valeur] of [['negatif', -12.5], ['tres-grand', 1e21], ['somme-flottante', 0.1 + 0.2], ['minuscule', 1e-7]]) {
      for (const champ of ['net_a_payer', 'total_brut', 'net_estime']) {
        montant(`montants/${nomRegime}/${champ}-${nomV}`, avec(regime, { [champ]: valeur }));
      }
    }
  }

  // --- Correction de l'ancien plafond Rist -------------------------------------
  const CONTRATS_RIST = [['liberal-applique', { type_contrat_applique: 'LIBERAL' }], ['liberal-recherche', { type_contrat_recherche: 'LIBERAL' }],
    ['salarie-applique', { type_contrat_applique: 'SALARIE' }], ['tous-recherche', { type_contrat_recherche: 'TOUS' }],
    ['applique-salarie-recherche-liberal', { type_contrat_applique: 'SALARIE', type_contrat_recherche: 'LIBERAL' }],
    ['applique-vide-recherche-liberal', { type_contrat_applique: '', type_contrat_recherche: 'LIBERAL' }]];
  const TAUX = [['90-sur-30', 90, 30], ['31-sur-31', 31, 31], ['30-sur-35', 30, 35], ['sans-taux-publie', null, 30],
    ['plafond-nul', 90, 0], ['35-sur-30', 35, 30]];
  const montantsRist = { net_a_payer: 280.80, total_brut: 300, net_estime: 210.6 };
  for (const [nomContrat, contrat] of CONTRATS_RIST) {
    for (const [nomAssigne, assigne] of [['non-assignee', null], ['assigne-vide', ''], ['assignee', 's1']]) {
      for (const [nomTaux, base, plafond] of TAUX) {
        for (const [nomRist, rist] of [['plafond-applique', true], ['plafond-non-applique', false]]) {
          const mission = avec({ ...montantsRist, ...contrat }, { soignant_assigne_id: assigne, taux_horaire_base: base, taux_rist_plafonne: plafond, rist_plafond_applique: rist });
          const nom = `rist/${nomContrat}/${nomAssigne}/${nomTaux}/${nomRist}`;
          montant(nom, mission);
          if (nomContrat === 'salarie-applique') net(nom, mission);
        }
      }
    }
  }
  for (const [nomRist, rist] of [['rist-null', null], ['rist-absent', undefined]]) {
    const mission = avec({ ...montantsRist, type_contrat_recherche: 'LIBERAL' }, { taux_horaire_base: 90, taux_rist_plafonne: 30, rist_plafond_applique: rist });
    montant(`rist/liberal-recherche/${nomRist}`, mission);
    net(`rist/liberal-recherche/${nomRist}`, mission);
  }
  for (const [nomTaux, base, plafond] of [['plafond-negatif', 90, -5], ['plafond-absent', 90, undefined], ['taux-absent', undefined, 30]]) {
    const mission = avec({ ...montantsRist, type_contrat_recherche: 'LIBERAL', rist_plafond_applique: true }, { taux_horaire_base: base, taux_rist_plafonne: plafond });
    montant(`rist/liberal-recherche/${nomTaux}`, mission);
  }

  // --- Arrondi `Math.round(x * 100) / 100` de la correction ----------------------
  for (const valeur of [0.01, 0.03, 0.05, 0.125, 1.005, 2.675, 33.33, 100.125, 1e-7, 123456789.12, 280.8, 0.015]) {
    const mission = { type_contrat_recherche: 'LIBERAL', taux_horaire_base: 3, taux_rist_plafonne: 2, rist_plafond_applique: true, net_a_payer: valeur };
    montant(`arrondi/ratio-1-5/${String(valeur)}`, mission);
  }
  for (const valeur of [0.01, 1.005, 280.8, 351.11]) {
    const mission = { type_contrat_recherche: 'LIBERAL', taux_horaire_base: 90, taux_rist_plafonne: 30, rist_plafond_applique: true, net_a_payer: valeur };
    montant(`arrondi/ratio-3/${String(valeur)}`, mission);
  }
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 11 : paiement-soignant-ui (src/lib/paiementSoignantUi.ts)
// ---------------------------------------------------------------------------
/**
 * Domaine : `unknown` = toute valeur JSON (NaN et ±Infinity ne sont pas représentables :
 * le port les couvre par un test unitaire Swift). Dates : formats ISO de PostgREST
 * (date seule, offset ou Z, fractions) et ISO sans offset hors changement d'heure ;
 * identifiants en minuscules ASCII, chiffres et tirets (uuid), où `localeCompare`
 * suit l'ordre des points de code.
 */
function vecteursPaiementUi() {
  const c = new Collecteur('paiement-soignant-ui');
  const repartir = (nom, du, regle, vitest) => {
    const name = `repartirPaiementConfirme/${nom}`;
    const obtenu = paiementUi.repartirPaiementConfirme(du, regle);
    if (vitest !== undefined) verifieVitest('paiement-soignant-ui', name, obtenu, vitest);
    const input = { fonction: 'repartirPaiementConfirme' };
    if (du !== undefined) input.montantDu = du;
    if (regle !== undefined) input.montantRegle = regle;
    c.ajoute(name, input, obtenu);
  };
  const indexer = (nom, paiements, vitest) => {
    const name = `indexerDernierPaiementParMission/${nom}`;
    const index = paiementUi.indexerDernierPaiementParMission(paiements);
    const obtenu = Object.fromEntries(Object.entries(index).map(([mission, paiement]) => [mission, paiement.id]));
    if (vitest !== undefined) verifieVitest('paiement-soignant-ui', name, obtenu, vitest);
    c.ajoute(name, { fonction: 'indexerDernierPaiementParMission', paiements }, obtenu);
  };
  const classer = (nom, paiement, vitest, partiel = false) => {
    const name = `classerPaiementSalaire/${nom}`;
    const obtenu = paiementUi.classerPaiementSalaire(paiement);
    if (vitest !== undefined) verifieVitest('paiement-soignant-ui', name, obtenu, vitest, partiel);
    const input = { fonction: 'classerPaiementSalaire' };
    if (paiement !== undefined) input.paiement = paiement;
    c.ajoute(name, input, obtenu);
  };

  // --- Issus de paiementSoignantUi.test.ts ---------------------------------
  indexer('vitest-plus-recent-quel-que-soit-l-ordre', [
    { id: 'ancien', mission_id: 'm1', statut: 'DECLARE', cree_le: '2026-07-01T10:00:00Z' },
    { id: 'autre', mission_id: 'm2', statut: 'CONFIRME', cree_le: '2026-07-02T10:00:00Z' },
    { id: 'recent', mission_id: 'm1', statut: 'CONFIRME', cree_le: '2026-07-03T10:00:00Z' },
  ], { m1: 'recent', m2: 'autre' });
  indexer('vitest-mise-a-jour-et-departage', [
    { id: 'a', mission_id: 'm1', modifie_le: '2026-07-04T10:00:00Z' },
    { id: 'b', mission_id: 'm1', modifie_le: '2026-07-04T10:00:00Z' },
    { id: 'cree-apres', mission_id: 'm2', cree_le: '2026-07-06T10:00:00Z', date_paiement: '2026-07-01' },
    { id: 'paye-apres', mission_id: 'm2', cree_le: '2026-07-05T10:00:00Z', date_paiement: '2026-07-07' },
  ], { m1: 'b', m2: 'cree-apres' });
  repartir('vitest-partiel', 346.85, 300, { montantPaye: 300, montantRestant: 46.85, estPartiel: true });
  repartir('vitest-complet', 500, 500, { montantPaye: 500, montantRestant: 0, estPartiel: false });
  repartir('vitest-superieur-au-du', 500, 510, { montantPaye: 510, montantRestant: 0, estPartiel: false });

  const confirme = { statut: 'CONFIRME', confirme_par_soignant: true, conteste: false, montant_net: 300 };
  classer('vitest-reference-employeur-distincte', { ...confirme, montant_du_reference: 425, source_montant_du: 'BULLETIN_OFFICIEL_ETABLISSEMENT' },
    { etat: 'confirme', libelle: 'Réception confirmée', montantDeclare: 300, montantReferenceEmployeur: 425 });
  for (const [nom, confirmation] of [['false', false], ['null', null], ['absente', undefined]]) {
    const paiement = { ...confirme };
    if (confirmation === undefined) delete paiement.confirme_par_soignant; else paiement.confirme_par_soignant = confirmation;
    classer(`vitest-confirmation-explicite-${nom}`, paiement, { etat: 'a_verifier' }, true);
  }
  for (const [nom, montantNet] of [['null', null], ['absent', undefined], ['vide', ''], ['blanc', ' '], ['zero', 0], ['zero-texte', '0'],
    ['negatif', -1], ['texte', 'invalide'], ['vrai', true], ['objet', {}]]) {
    const paiement = { ...confirme };
    if (montantNet === undefined) delete paiement.montant_net; else paiement.montant_net = montantNet;
    classer(`vitest-montant-invalide-${nom}`, paiement, { etat: 'a_verifier', montantDeclare: null }, true);
  }
  for (const statut of ['RESOLU', 'CONTESTE', 'DECLARE', 'EN_ATTENTE', 'INCONNU']) {
    const name = `vitest-statut-${statut}-pas-confirme`;
    const obtenu = paiementUi.classerPaiementSalaire({ ...confirme, statut });
    if (obtenu.etat === 'confirme') throw new Error(`paiement-soignant-ui: « ${name} » ne vérifie plus l'attente vitest.`);
    classer(name, { ...confirme, statut });
  }
  classer('vitest-contestation-prime', { ...confirme, conteste: true }, { etat: 'conteste' }, true);
  for (const [nom, source] of [['estimation', 'ESTIMATION_AVANT_PAS_A_CONFIRMER'], ['facture-honoraires', 'FACTURE_HONORAIRES'], ['null', null], ['absente', undefined]]) {
    const paiement = { ...confirme, montant_du_reference: 999 };
    if (source !== undefined) paiement.source_montant_du = source;
    classer(`vitest-source-non-employeur-${nom}`, paiement, { montantReferenceEmployeur: null }, true);
  }
  classer('vitest-decimal-postgrest', { ...confirme, montant_net: '300.25' }, { montantDeclare: 300.25 }, true);
  classer('vitest-absence-de-declaration', undefined, { etat: 'absent' }, true);

  // --- Grille de `repartirPaiementConfirme` ------------------------------------
  const MONTANTS = [['absent', undefined], ['null', null], ['zero', 0], ['300', 300], ['346-85', 346.85], ['500', 500], ['510', 510],
    ['negatif', -10], ['texte-decimal', '300.25'], ['texte-vide', ''], ['texte-invalide', 'abc'], ['vrai', true], ['objet', {}],
    ['tableau-un', [5]], ['demi-centime', 0.005], ['huitieme', 0.125]];
  for (const [nomDu, du] of MONTANTS) {
    for (const [nomRegle, regle] of MONTANTS) repartir(`grille/du-${nomDu}/regle-${nomRegle}`, du, regle);
  }
  for (const [nom, du, regle] of [
    ['texte-espaces', ' 12 ', '2'], ['texte-hexadecimal', '0x1A', '0'], ['texte-exposant', '1e3', '2.5e2'], ['texte-infini', 'Infinity', 0],
    ['texte-infini-negatif', 0, '-Infinity'], ['texte-plus', '+5', '.5'], ['texte-point-final', '5.', '0'], ['texte-separateur', '1_000', 0],
    ['texte-octal', '0o17', '0b11'], ['texte-signe-hexadecimal', '-0x10', 0], ['texte-nbsp', ' 7 ', '﻿2'],
    ['texte-nel', '\u00857', 0], ['faux', false, false], ['tableau-vide', [], 3], ['tableau-texte', ['  5 '], [null]],
    ['tableau-deux', [1, 2], [[3]]], ['tableau-booleen', [true], [{}]], ['tableau-imbrique-vide', [[]], 0],
    ['tres-grand', 1e21, 0], ['tres-grand-regle', 2e21, 1e21], ['ecart-flottant', 0.3, 0.1], ['egalite-flottante', 0.1 + 0.2, 0.3],
    ['solde-minuscule', 100.004, 100], ['paye-minuscule', 5, 0.001], ['demi-centimes', 2.675, 1.005], ['huitiemes', 100.375, 0.625],
    ['negatif-du', -50, 10], ['entiers-grands', 123456789.125, 0.375],
  ]) repartir(`limites/${nom}`, du, regle);

  // --- Grille de `classerPaiementSalaire` ---------------------------------------
  for (const [nomStatut, statut] of [['absent', undefined], ['null', null], ['declare', 'DECLARE'], ['confirme', 'CONFIRME'], ['conteste', 'CONTESTE'],
    ['resolu', 'RESOLU'], ['en-attente', 'EN_ATTENTE'], ['inconnu', 'INCONNU'], ['vide', ''], ['minuscules', 'confirme']]) {
    for (const [nomConfirme, confirmeParSoignant] of [['confirme-vrai', true], ['confirme-faux', false], ['confirme-null', null]]) {
      for (const [nomConteste, conteste] of [['conteste-vrai', true], ['conteste-faux', false], ['conteste-null', null]]) {
        for (const [nomMontant, montantNet] of [['montant-300', 300], ['montant-null', null], ['montant-texte-zero', '0']]) {
          const paiement = { confirme_par_soignant: confirmeParSoignant, conteste, montant_net: montantNet };
          if (statut !== undefined) paiement.statut = statut;
          classer(`grille/${nomStatut}/${nomConfirme}/${nomConteste}/${nomMontant}`, paiement);
        }
      }
    }
  }
  for (const [nomSource, source] of [['bulletin', 'BULLETIN_OFFICIEL_ETABLISSEMENT'], ['estimation', 'ESTIMATION_AVANT_PAS_A_CONFIRMER'],
    ['facture', 'FACTURE_HONORAIRES'], ['null', null], ['vide', ''], ['minuscules', 'bulletin_officiel_etablissement']]) {
    for (const [nomRef, reference] of [['425', 425], ['texte-425-5', '425.5'], ['zero', 0], ['negatif', -1], ['null', null],
      ['absente', undefined], ['texte', 'x'], ['vrai', true]]) {
      const paiement = { statut: 'DECLARE', montant_net: 300, source_montant_du: source };
      if (reference !== undefined) paiement.montant_du_reference = reference;
      classer(`reference/${nomSource}/${nomRef}`, paiement);
    }
  }
  for (const [nom, montantNet] of [['texte-espaces', ' 12.5 '], ['texte-hexadecimal', '0x10'], ['texte-exposant', '3e2'], ['texte-infini', 'Infinity'],
    ['texte-nbsp', ' 300'], ['tableau', [300]], ['minuscule', 1e-9], ['tres-grand', 1e21]]) {
    classer(`montant/${nom}`, { ...confirme, montant_net: montantNet });
  }
  classer('paiement-null', null);
  classer('paiement-vide', {});

  // --- Grille de `indexerDernierPaiementParMission` -----------------------------
  const p = (id, missionId, dates = {}) => ({ id, ...(missionId === undefined ? {} : { mission_id: missionId }), ...dates });
  indexer('liste-vide', []);
  indexer('ordre-inverse', [p('recent', 'm1', { cree_le: '2026-07-03T10:00:00Z' }), p('ancien', 'm1', { cree_le: '2026-07-01T10:00:00Z' })]);
  indexer('egalite-ordre-inverse', [p('b', 'm1', { modifie_le: '2026-07-04T10:00:00Z' }), p('a', 'm1', { modifie_le: '2026-07-04T10:00:00Z' })]);
  indexer('modifie-le-prioritaire', [p('x', 'm1', { modifie_le: '2026-07-01T10:00:00Z', cree_le: '2026-07-09T10:00:00Z' }), p('y', 'm1', { cree_le: '2026-07-05T10:00:00Z' })]);
  indexer('modifie-le-null-cede-a-cree-le', [p('x', 'm1', { modifie_le: null, cree_le: '2026-07-09T10:00:00Z' }), p('y', 'm1', { cree_le: '2026-07-05T10:00:00Z' })]);
  indexer('modifie-le-vide-vaut-zero', [p('x', 'm1', { modifie_le: '', cree_le: '2026-07-09T10:00:00Z' }), p('y', 'm1', { cree_le: '2026-07-01T10:00:00Z' })]);
  indexer('date-paiement-seule', [p('x', 'm1', { date_paiement: '2026-07-02' }), p('y', 'm1', { date_paiement: '2026-07-01' })]);
  indexer('date-illisible-vaut-zero', [p('x', 'm1', { cree_le: 'pas une date' }), p('y', 'm1', { cree_le: '2026-07-01T10:00:00Z' })]);
  indexer('toutes-sans-date-departage-id', [p('b', 'm1'), p('c', 'm1'), p('a', 'm1')]);
  indexer('sans-mission-ignore', [p('a', null, { cree_le: '2026-07-09T10:00:00Z' }), p('b', '', { cree_le: '2026-07-09T10:00:00Z' }),
    p('c', undefined, { cree_le: '2026-07-09T10:00:00Z' }), p('d', 'm1', { cree_le: '2026-07-01T10:00:00Z' })]);
  indexer('meme-instant-offsets', [p('a', 'm1', { cree_le: '2026-07-04T12:00:00+02:00' }), p('b', 'm1', { cree_le: '2026-07-04T10:00:00Z' })]);
  indexer('meme-instant-offsets-ordre-inverse', [p('b', 'm1', { cree_le: '2026-07-04T10:00:00Z' }), p('a', 'm1', { cree_le: '2026-07-04T12:00:00+02:00' })]);
  indexer('microsecondes-tronquees', [p('a', 'm1', { cree_le: '2026-07-04T10:00:00.123456+00:00' }), p('b', 'm1', { cree_le: '2026-07-04T10:00:00.123Z' })]);
  indexer('microsecondes-ordre', [p('b', 'm1', { cree_le: '2026-07-04T10:00:00.123+00:00' }), p('a', 'm1', { cree_le: '2026-07-04T10:00:00.124+00:00' })]);
  indexer('iso-sans-offset-heure-de-paris', [p('a', 'm1', { cree_le: '2026-07-04T12:00:00' }), p('b', 'm1', { cree_le: '2026-07-04T10:00:00Z' })]);
  indexer('iso-sans-offset-hiver', [p('b', 'm1', { cree_le: '2026-01-04T11:00:00' }), p('a', 'm1', { cree_le: '2026-01-04T10:00:00.001Z' })]);
  indexer('date-seule-minuit-utc', [p('a', 'm1', { date_paiement: '2026-07-04' }), p('b', 'm1', { cree_le: '2026-07-04T00:00:00Z' })]);
  indexer('plusieurs-missions', [p('a1', 'm1', { cree_le: '2026-07-01T10:00:00Z' }), p('b1', 'm2', { cree_le: '2026-07-09T10:00:00Z' }),
    p('a2', 'm1', { cree_le: '2026-07-02T10:00:00Z' }), p('b2', 'm2', { cree_le: '2026-07-08T10:00:00Z' }), p('c1', 'm3')]);
  indexer('uuid-departage', [
    p('5b0e2f6a-1c3d-4e5f-8a9b-0c1d2e3f4a5b', 'm1', { cree_le: '2026-07-04T10:00:00Z' }),
    p('5b0e2f6a-1c3d-4e5f-8a9b-0c1d2e3f4a5c', 'm1', { cree_le: '2026-07-04T10:00:00Z' }),
    p('5b0e2f6a-1c3d-4e5f-8a9b-0c1d2e3f4a59', 'm1', { cree_le: '2026-07-04T10:00:00Z' }),
  ]);
  indexer('ids-tirets-et-chiffres', [p('a-1', 'm1'), p('a1', 'm1'), p('a-b', 'm1'), p('ab', 'm1'), p('a', 'm1')]);
  indexer('date-anterieure-1970', [p('a', 'm1', { cree_le: '1969-12-31T23:59:59Z' }), p('b', 'm1')]);
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 12 : valider-profil-soignant (src/lib/valider-profil-soignant.ts)
// ---------------------------------------------------------------------------
/**
 * Sortie : `{ specialites }` si le profil est accepté, `{ erreur: 'PROFIL_INVALIDE' }`
 * pour toute levée (le web traite de la même façon l'erreur `PROFIL_INVALIDE` et la
 * `SyntaxError` de `JSON.parse`, `ProfilSoignant.tsx` l.153-156). Domaine : valeurs JSON
 * (sans séquence `\uD800` isolée, qu'aucune chaîne Swift ne représente).
 */
function vecteursValidationProfil() {
  const c = new Collecteur('valider-profil-soignant');
  const valider = (nom, data, userId = 'a', vitestValide) => {
    const name = `validerProfilSoignant/${nom}`;
    let obtenu;
    try {
      obtenu = { specialites: validationProfil.validerProfilSoignant(data, userId).specialites };
    } catch {
      obtenu = { erreur: 'PROFIL_INVALIDE' };
    }
    if (vitestValide !== undefined) verifieVitest('valider-profil-soignant', name, obtenu, vitestValide);
    c.ajoute(name, { fonction: 'validerProfilSoignant', data, userId }, obtenu);
  };
  const base = { id: 'a', prenom: null, nom: null, email: null, profession: null };
  const refus = { erreur: 'PROFIL_INVALIDE' };

  // --- Issus de valider-profil-soignant.test.ts -------------------------------
  valider('vitest-specialites-json-historiques', { ...base, prenom: null, specialites: '["Urgences"]' }, 'a', { specialites: ['Urgences'] });
  valider('vitest-specialites-vides', { ...base, specialites: '' }, 'a', { specialites: [] });
  valider('vitest-specialites-null', { ...base, specialites: null }, 'a', { specialites: [] });
  for (const [nom, delta] of [['prenom-objet', { prenom: {} }], ['heures-texte', { heures_cumulees: '4' }],
    ['rpps-verifie-texte', { rpps_verifie: 'true' }], ['specialites-objet', { specialites: [{}] }], ['specialites-faux', { specialites: false }],
    ['specialites-json-null', { specialites: 'null' }], ['specialites-json-objet', { specialites: '{}' }]]) {
    valider(`vitest-refus-${nom}`, { ...base, ...delta }, 'a', refus);
  }
  // `{ adresse_lat: Infinity }` (vitest) n'est pas représentable en JSON : test unitaire Swift.

  // --- Forme générale ------------------------------------------------------------
  valider('accepte-base', base);
  valider('accepte-profil-rempli', { ...base, prenom: 'Léa', nom: 'Martin', email: 'lea@example.invalid', profession: 'IDE',
    specialites: ['Urgences', 'Bloc'], heures_cumulees: 120.5, rpps_verifie: true, numero_secu: '1', champ_inconnu: { a: 1 } });
  for (const [nom, data] of [['null', null], ['tableau', [base]], ['texte', 'profil'], ['nombre', 5], ['vrai', true], ['objet-vide', {}]]) valider(`refus-donnee-${nom}`, data);
  valider('refus-id-different', base, 'b');
  valider('refus-id-absent', { prenom: null, nom: null, email: null, profession: null });
  valider('refus-id-nombre', { ...base, id: 5 }, '5');
  valider('refus-id-null', { ...base, id: null });
  valider('accepte-user-id-vide', { ...base, id: '' }, '');
  valider('refus-cle-error-null', { ...base, error: null });
  valider('refus-cle-error-texte', { ...base, error: 'Profil introuvable' });
  for (const cle of ['prenom', 'nom', 'email', 'profession']) {
    const sans = { ...base };
    delete sans[cle];
    valider(`refus-cle-obligatoire-absente-${cle}`, sans);
  }

  // --- Types par famille de champs -----------------------------------------------
  const TEXTES = ['email', 'prenom', 'nom', 'profession', 'specialite_medicale', 'specialite_medicale_declaree', 'specialite_source',
    'rpps_verifie_le', 'statut_liberal', 'type_exercice', 'telephone', 'date_naissance', 'numero_rpps', 'bio', 'avatar_url',
    'ville_recherche', 'types_contrat_acceptes', 'type_contrat'];
  const NOMBRES = ['heures_cumulees', 'adresse_lat', 'adresse_lng', 'rayon_deplacement_km', 'annees_experience', 'taux_horaire_minimum', 'urgence_rayon_km'];
  const BOOLEENS = ['specialite_verifiee', 'rpps_verifie', 'attestation_cumul_activite', 'consentement_gps', 'disponible_urgence', 'tous_documents_valides'];
  const familles = [
    ['texte', TEXTES, [['texte', 'x'], ['texte-vide', ''], ['null', null], ['nombre', 42], ['vrai', true], ['objet', {}], ['tableau', ['x']]]],
    ['nombre', NOMBRES, [['entier', 12], ['zero', 0], ['negatif', -1.5], ['null', null], ['texte', '4'], ['vrai', true], ['objet', {}], ['tableau', [1]]]],
    ['booleen', BOOLEENS, [['vrai', true], ['faux', false], ['null', null], ['texte', 'true'], ['un', 1], ['objet', {}]]],
  ];
  for (const [famille, cles, valeurs] of familles) {
    for (const cle of cles) for (const [nomValeur, valeur] of valeurs) valider(`${famille}/${cle}/${nomValeur}`, { ...base, [cle]: valeur });
  }
  // Champ hors des trois listes : jamais contrôlé.
  valider('champ-hors-liste-objet', { ...base, numero_secu: { a: 1 }, specialite: 5 });

  // --- Spécialités -----------------------------------------------------------------
  for (const [nom, specialites] of [
    ['absentes', undefined], ['tableau-vide', []], ['tableau-textes', ['Urgences', 'Bloc']], ['tableau-texte-vide', ['']],
    ['tableau-nombre', [1]], ['tableau-null', [null]], ['tableau-mixte', ['a', 1]], ['tableau-imbrique', [['a']]],
    ['nombre', 3], ['vrai', true], ['objet', { a: 'b' }],
    ['json-tableau-vide', '[]'], ['json-espaces', ' \t\n[ "a" , "b" ]\r\n'], ['json-echappements', '["\\u00e9\\n\\"x\\"\\/\\\\", "\\ud83d\\ude00"]'],
    ['json-nombre', '[1]'], ['json-null', '[null]'], ['json-mixte', '["a",1]'], ['json-imbrique', '[["a"]]'], ['json-objet-texte', '{"a":"b"}'],
    ['json-texte', '"Urgences"'], ['json-nombre-seul', '5'], ['json-vrai', 'true'], ['json-null-seul', 'null'],
    ['syntaxe-texte-nu', 'Urgences'], ['syntaxe-virgule-finale', '["a",]'], ['syntaxe-virgule-seule', '[,]'], ['syntaxe-non-ferme', '["a"'],
    ['syntaxe-apostrophes', "['a']"], ['syntaxe-reste', '["a"]x'], ['syntaxe-deux-tableaux', '[][]'], ['syntaxe-controle', '["a\tb"]'],
    ['syntaxe-echappement-inconnu', '["\\x"]'], ['syntaxe-unicode-court', '["\\u00e"]'], ['syntaxe-blanc', '   '],
    ['syntaxe-espace-insecable', ' []'], ['syntaxe-virgule-debut', '[,"a"]'], ['syntaxe-deux-virgules', '["a",,"b"]'],
    ['syntaxe-sans-virgule', '["a" "b"]'],
  ]) {
    const data = { ...base };
    if (specialites !== undefined) data.specialites = specialites;
    valider(`specialites/${nom}`, data);
  }
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 13 : preferences-modes-exercice (src/lib/preferencesModesExercice.ts)
// ---------------------------------------------------------------------------
function vecteursModesExercice() {
  const c = new Collecteur('preferences-modes-exercice');
  const selectionne = (nom, contrats, mode, vitest) => {
    const name = `modeExerciceSelectionne/${nom}`;
    const obtenu = modesExercice.modeExerciceSelectionne(contrats, mode);
    if (vitest !== undefined) verifieVitest('preferences-modes-exercice', name, obtenu, vitest);
    c.ajoute(name, { fonction: 'modeExerciceSelectionne', contrats, mode }, obtenu);
  };
  const modifier = (nom, contrats, mode, choix, vitest) => {
    const name = `modifierPreferenceModeExercice/${nom}`;
    const obtenu = modesExercice.modifierPreferenceModeExercice(contrats, mode, choix);
    if (vitest !== undefined) verifieVitest('preferences-modes-exercice', name, obtenu, vitest);
    c.ajoute(name, { fonction: 'modifierPreferenceModeExercice', contrats, mode, selectionne: choix }, obtenu);
  };

  // --- Issus de preferencesModesExercice.test.ts --------------------------------
  for (const code of ['CDD', 'VACATION', 'SALARIE']) {
    selectionne(`vitest-${code}-salarie`, [code, 'LIBERAL'], 'SALARIE', true);
    modifier(`vitest-${code}-conserve`, [code, 'LIBERAL'], 'SALARIE', true, [code, 'LIBERAL']);
    modifier(`vitest-${code}-retire-liberal`, [code, 'LIBERAL'], 'LIBERAL', false, [code]);
  }
  modifier('vitest-ajoute-salarie', [], 'SALARIE', true, ['SALARIE']);
  modifier('vitest-ajoute-liberal', ['SALARIE'], 'LIBERAL', true, ['SALARIE', 'LIBERAL']);
  modifier('vitest-retire-salarie', ['SALARIE', 'LIBERAL'], 'SALARIE', false, ['LIBERAL']);
  modifier('vitest-retire-toutes-variantes-salariees', ['CDD', 'VACATION', 'SALARIE', 'LIBERAL'], 'SALARIE', false, ['LIBERAL']);

  // --- Grille listes × mode × choix ---------------------------------------------
  const LISTES = [['vide', []], ['cdd', ['CDD']], ['vacation', ['VACATION']], ['salarie', ['SALARIE']], ['liberal', ['LIBERAL']],
    ['tous', ['TOUS']], ['mixte', ['MIXTE']], ['minuscules', ['salarie', 'liberal']], ['texte-vide', ['']],
    ['cdd-liberal', ['CDD', 'LIBERAL']], ['quatre-codes', ['CDD', 'VACATION', 'SALARIE', 'LIBERAL']],
    ['doublons-liberal', ['LIBERAL', 'LIBERAL']], ['doublons-salarie', ['SALARIE', 'CDD', 'SALARIE']],
    ['inconnu-et-liberal', ['TOUS', 'LIBERAL', 'AUTRE']], ['ordre-liberal-d-abord', ['LIBERAL', 'VACATION']]];
  for (const [nomListe, contrats] of LISTES) {
    for (const mode of ['SALARIE', 'LIBERAL']) {
      selectionne(`grille/${nomListe}/${mode}`, contrats, mode);
      for (const choix of [true, false]) modifier(`grille/${nomListe}/${mode}/${choix ? 'coche' : 'decoche'}`, contrats, mode, choix);
    }
  }
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 14 : professions-rpps (listes de src/lib/constantes.ts l.55 et l.61)
// ---------------------------------------------------------------------------
/** Vecteur de dérive (pas une règle juridique) : listes verbatim et appartenance par profession. */
function vecteursProfessionsRpps() {
  const c = new Collecteur('professions-rpps');
  c.ajoute('liste/PROFESSIONS_SANS_RPPS', { fonction: 'PROFESSIONS_SANS_RPPS' }, constantes.PROFESSIONS_SANS_RPPS);
  c.ajoute('liste/PROFESSIONS_RPPS_REQUIS', { fonction: 'PROFESSIONS_RPPS_REQUIS' }, constantes.PROFESSIONS_RPPS_REQUIS);
  const professions = [...constantes.PROFESSIONS.map((p) => p.valeur), 'INCONNUE', '', 'as', 'medecin'];
  for (const profession of professions) {
    c.ajoute(`classer/${profession || 'vide'}`, { fonction: 'classer', profession }, {
      sansRpps: constantes.PROFESSIONS_SANS_RPPS.includes(profession),
      rppsRequis: constantes.PROFESSIONS_RPPS_REQUIS.includes(profession),
    });
  }
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
  // Lot 3, T2.
  'push-routing.json': vecteursPushRouting(),
  'session-count.json': await vecteursSessionCount(),
  'mission-finance-display.json': vecteursMissionFinance(),
  'paiement-soignant-ui.json': vecteursPaiementUi(),
  'valider-profil-soignant.json': vecteursValidationProfil(),
  'preferences-modes-exercice.json': vecteursModesExercice(),
  'professions-rpps.json': vecteursProfessionsRpps(),
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
