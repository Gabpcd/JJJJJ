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
 * relatifs sans extension de ces modules (lot 1, T2). Lot 3, T2 : liste
 * d'exceptions nommée pour `src/lib/pushNative.ts` seulement (modules inertes,
 * décision 22 du lot 3) et règles push, revenus, profil, session et RPPS ; les
 * `case` de `navigationPathForEvent` sont lus par le compilateur TypeScript
 * (`typescript`, dépendance de développement du dépôt), bornés au corps de la fonction.
 * Lot 4, T2 : règles extraites par la PR web W0 (`raisons-score-matching.ts`,
 * `filtre-paquet-swipe.ts`, `statut-litige-regles.ts`), `alertes-recherche-missions.ts`,
 * copies de bulletins (`copiesBulletins.ts`, seconde exception nommée de modules inertes) et
 * grille des disponibilités de `MesDisponibilites.tsx` (date-fns réel, calcul recopié sous
 * garde d'extraits : la page n'est pas un module importable).
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
//
// Seconde exception nommée (lot 4, T2) : `src/lib/copiesBulletins.ts` mêle les règles
// pures `validerListeCopiesBulletins` et `copieBulletinTelechargeable` (décodage strict des
// copies de bulletins, LOT4_PLAN §2.4) et les appels Supabase. Ses trois imports impurs
// (`@supabase/supabase-js`, lu seulement par `instanceof` dans `pdfRefuseParServeur`, le
// client Supabase et `@/lib/platform`) sont inertes ; `documentUpload`, `date-heure-paris`,
// `avecDelai` et `uuid` restent réels (modules sans import, évalués sans effet). Le blueprint
// prévoyait des vecteurs recopiés du test vitest, « module non importable par Node » : les
// modules inertes le rendent importable, les vecteurs sortent donc de la fonction réelle.
const PUSH_NATIVE = resolve(RACINE, 'src/lib/pushNative.ts');
const COPIES_BULLETINS = resolve(RACINE, 'src/lib/copiesBulletins.ts');
const EXCEPTIONS_INERTES = [
  {
    fichier: PUSH_NATIVE,
    reference: 'décision 22 du lot 3',
    inertes: {
      '@/integrations/supabase/client': { supabase: 'objet' },
      './platform': { isNative: 'fonction' },
      './logger': { logger: 'objet' },
      './pushDeviceToken': { memoriserTokenPushAppareil: 'fonction' },
      './nativeResume': { signalerNavigationNative: 'fonction' },
      './navigationNotification': { OUVERTURE_NOTIFICATION: 'valeur' },
    },
    reels: ['./nativeLinks'],
  },
  {
    fichier: COPIES_BULLETINS,
    reference: 'L4-T2, LOT4_PLAN §3 T2',
    inertes: {
      '@supabase/supabase-js': { FunctionsHttpError: 'fonction' },
      '@/integrations/supabase/client': { supabase: 'objet' },
      '@/lib/platform': { isNative: 'fonction' },
    },
    reels: ['@/lib/documentUpload', '@/lib/date-heure-paris', '@/lib/avecDelai', '@/lib/uuid'],
  },
];
for (const { fichier, reference, inertes, reels } of EXCEPTIONS_INERTES) {
  // Garde : si le module change d'imports, l'exception nommée doit être revue.
  const importsReels = [...readFileSync(fichier, 'utf8').matchAll(/^import\s[^;]*?from\s+'([^']+)';/gm)].map((m) => m[1]).sort();
  const attendus = [...Object.keys(inertes), ...reels].sort();
  if (JSON.stringify(importsReels) !== JSON.stringify(attendus)) {
    console.error(`export golden : imports de ${fichier.slice(RACINE.length + 1)} inattendus (${importsReels.join(', ')}) ; attendus : ${attendus.join(', ')}. Revoir EXCEPTIONS_INERTES (${reference}).`);
    process.exit(2);
  }
}
function moduleInerte(specifier, exports, parent) {
  const leve = `throw new Error(${JSON.stringify(`export golden : « ${specifier} » est un module inerte de ${parent.slice(RACINE.length + 1).replace(/^src\/lib\//, '')}, il ne doit pas être utilisé par une règle golden.`)});`;
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
    inertes: Object.fromEntries(EXCEPTIONS_INERTES.map(({ fichier, inertes }) => [
      pathToFileURL(fichier).href,
      Object.fromEntries(Object.entries(inertes).map(([specifier, exports]) => [specifier, moduleInerte(specifier, exports, fichier)])),
    ])),
  },
});

const lib = (nom) => import(pathToFileURL(resolve(RACINE, 'src/lib', nom)).href);
const planningComposant = (nom) => import(pathToFileURL(resolve(RACINE, 'src/components/planning', nom)).href);
const dateHeure = await lib('date-heure-paris.ts');
const formatMission = await lib('format-mission.ts');
const hebdo = await lib('heures-hebdomadaires-mission.ts');
const pointage = await lib('disponibilite-pointage.ts');
// Lot 5, T3 : dérivation structurelle du planning de publication établissement.
const planningDerive = await lib('planning-derive.ts');
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
// Lot 3, T2.
const pushNative = await lib('pushNative.ts');
const financeMission = await lib('missionFinanceDisplay.ts');
const paiementUi = await lib('paiementSoignantUi.ts');
const validationProfil = await lib('valider-profil-soignant.ts');
const modesExercice = await lib('preferencesModesExercice.ts');
// Lot 4, T2 : règles extraites par la PR web W0 (swipe, alerte, litiges) et copies de bulletins.
const alertesRecherche = await lib('alertes-recherche-missions.ts');
const raisonsScoreMatching = await lib('raisons-score-matching.ts');
const filtrePaquetSwipe = await lib('filtre-paquet-swipe.ts');
const statutLitigeRegles = await lib('statut-litige-regles.ts');
const copiesBulletins = await lib('copiesBulletins.ts');
// `constantes` (lot 2, T2) est aussi lu par le lot 3 (professions RPPS) : importé une seule fois ci-dessus.
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
// Règle lot 5, T3 : planning-derive (src/lib/planning-derive.ts), dérivation
// STRUCTURELLE seulement : dates d'une période, jour ISO, fin de créneau,
// matérialisation (heure d'été/d'hiver Europe/Paris) et, de `validerPlanningDates`,
// les seules erreurs structurelles CRENEAU_MANQUANT, CRENEAU_INVALIDE, CHEVAUCHEMENT.
// Exclus par construction (blueprint lot 5 §2.9, D9) : PLAFOND_48H, REPOS_11H et
// DUREE_LONGUE (règles et recommandation du droit du travail, appliquées par le
// serveur `fn_valider_creneaux_mission_json` et affichées verbatim), les semaines
// civiles et `calculerHeuresNuitParis` (estimation de coût, non portée).
// ---------------------------------------------------------------------------
const TYPES_PLANNING_STRUCTURELS = new Set(['CRENEAU_MANQUANT', 'CRENEAU_INVALIDE', 'CHEVAUCHEMENT']);

function vecteursPlanningDerive() {
  const c = new Collecteur('planning-derive');
  const creneauDerive = (clientId, heureDebut = '07:00', heureFin = '19:00', finJourSuivant = false, extra = {}) => (
    { clientId, heureDebut, heureFin, finJourSuivant, ...extra }
  );
  const jourDerive = (date, actif = true, creneaux = [creneauDerive(date)]) => ({ date, actif, creneaux });

  const ajouter = (nom, date, nombre) => c.ajoute(`ajouterJoursDate/${nom}`,
    { fonction: 'ajouterJoursDate', date, nombre }, capture(() => planningDerive.ajouterJoursDate(date, nombre)));
  const plage = (nom, dateDebut, dateFin) => c.ajoute(`datesDansPlage/${nom}`,
    { fonction: 'datesDansPlage', dateDebut, dateFin }, capture(() => planningDerive.datesDansPlage(dateDebut, dateFin)));
  // `NaN` (date illisible) devient `null` dans le JSON, comme `JSON.stringify`.
  const jourIso = (nom, date) => c.ajoute(`jourSemaineISO/${nom}`,
    { fonction: 'jourSemaineISO', date }, capture(() => {
      const valeur = planningDerive.jourSemaineISO(date);
      return Number.isFinite(valeur) ? valeur : null;
    }));
  const finCreneau = (nom, date, finJourSuivant) => c.ajoute(`dateFinCreneau/${nom}`,
    { fonction: 'dateFinCreneau', date, finJourSuivant }, capture(() => planningDerive.dateFinCreneau(date, { finJourSuivant })));
  const materialiser = (nom, date, creneau) => c.ajoute(`materialiserCreneau/${nom}`,
    { fonction: 'materialiserCreneau', date, creneau }, capture(() => planningDerive.materialiserCreneau(date, creneau)));
  const planning = (nom, jours) => c.ajoute(`materialiserPlanning/${nom}`,
    { fonction: 'materialiserPlanning', jours }, capture(() => planningDerive.materialiserPlanning(jours)));
  const structure = (nom, jours) => c.ajoute(`validerPlanningDates/${nom}`,
    { fonction: 'validerPlanningDates', jours }, capture(() => ({
      erreursStructurelles: planningDerive.validerPlanningDates(jours).erreurs
        .filter((erreur) => TYPES_PLANNING_STRUCTURELS.has(erreur.type)),
    })));

  // --- Issus des tests vitest (planning-derive.test.ts), partie structurelle ----
  // Les deux cas `calculerHeuresNuitParis` (fractions de nuit, nuit à l'heure d'été)
  // ne sont pas portés ; les cas 48 h et repos 11 h ne gardent que leur part structurelle.
  plage('vitest-dates-reelles', '2026-07-22', '2026-07-29');
  planning('vitest-dates-repos-exclues', [
    jourDerive('2026-07-22'),
    jourDerive('2026-07-23', false),
    jourDerive('2026-07-29', true, [creneauDerive('dernier', '09:00', '13:00')]),
  ]);
  const deuxCreneauxJour = [jourDerive('2026-08-03', true, [creneauDerive('matin', '07:00', '11:00'), creneauDerive('soir', '15:00', '19:00')])];
  structure('vitest-deux-creneaux-non-chevauchants', deuxCreneauxJour);
  planning('vitest-deux-creneaux-non-chevauchants', deuxCreneauxJour);
  structure('vitest-chevauchement', [jourDerive('2026-08-03', true, [creneauDerive('un', '07:00', '12:00'), creneauDerive('deux', '11:30', '16:00')])]);
  materialiser('vitest-nuit-sans-lendemain', '2026-08-02', creneauDerive('nuit', '20:00', '08:00', false));
  materialiser('vitest-nuit-lendemain', '2026-08-02', creneauDerive('nuit', '20:00', '08:00', true));
  structure('vitest-repos-dimanche-lundi-structurel', [
    jourDerive('2026-08-02', true, [creneauDerive('dimanche-nuit', '20:00', '08:00', true)]),
    jourDerive('2026-08-03', true, [creneauDerive('lundi', '09:00', '17:00')]),
  ]);
  materialiser('vitest-dst-ete-duree-absolue', '2026-03-29', creneauDerive('dst', '01:00', '05:00'));
  materialiser('vitest-trou-dst', '2026-03-29', creneauDerive('trou-dst', '02:30', '05:00'));
  structure('vitest-trou-dst', [jourDerive('2026-03-29', true, [creneauDerive('trou-dst', '02:30', '05:00')])]);
  materialiser('vitest-automne-occurrence-initiale', '2026-10-25', creneauDerive('heure-repetee', '02:30', '03:30', false, {
    debutInitial: '2026-10-25T00:30:00.000Z', finInitial: '2026-10-25T02:30:00.000Z',
  }));
  materialiser('vitest-automne-saisie-ambigue', '2026-10-25', creneauDerive('heure-repetee-nouvelle', '02:30', '03:30'));
  materialiser('vitest-automne-borne-initiale-preservee', '2026-10-25', creneauDerive('heure-repetee-modifiee', '02:30', '04:30', false, {
    debutInitial: '2026-10-25T00:30:00.000Z', finInitial: '2026-10-25T02:30:00.000Z',
  }));
  const cinqJours = ['2026-07-20', '2026-07-21', '2026-07-22', '2026-07-23', '2026-07-24']
    .map((date) => jourDerive(date, true, [creneauDerive(date, '07:00', '17:00')]));
  structure('vitest-50h-semaine-structurel', cinqJours);
  planning('vitest-50h-semaine', cinqJours);
  materialiser('vitest-garde-dimanche-lundi', '2026-08-02', creneauDerive('nuit', '22:00', '06:00', true));
  structure('vitest-garde-dimanche-lundi-structurel', [jourDerive('2026-08-02', true, [creneauDerive('nuit', '22:00', '06:00', true)])]);

  // --- Périodes de 0, 1, 7, 31, 366, 367 jours (et au-delà, plafonnée) ---------
  const avant = (date, n) => planningDerive.ajouterJoursDate(date, n);
  for (const debut of ['2026-01-01', '2026-03-23', '2026-10-19', '2027-12-31', '2028-02-27']) {
    plage(`${debut}-0-jour-fin-avant-debut`, debut, avant(debut, -1));
    for (const jours of [1, 2, 7, 31]) {
      plage(`${debut}-${jours}-jours`, debut, avant(debut, jours - 1));
    }
  }
  // Plafond de la boucle (`dates.length <= 366` : 367 dates au plus, que le formulaire
  // refuse ensuite), sur une année qui traverse les deux changements d'heure et sur
  // une année bissextile.
  for (const debut of ['2026-03-23', '2027-12-31']) {
    for (const jours of [366, 367, 368]) plage(`${debut}-${jours}-jours`, debut, avant(debut, jours - 1));
  }
  plage('annee-bissextile-2028', '2028-01-01', '2028-12-31');
  plage('fevrier-bissextile', '2028-02-27', '2028-03-02');
  plage('fevrier-non-bissextile', '2027-02-27', '2027-03-02');
  for (const [nom, dateDebut, dateFin] of [
    ['format-mois-sans-zero', '2026-7-1', '2026-07-03'], ['format-fin-illisible', '2026-07-01', 'demain'],
    ['chaines-vides', '', ''], ['debut-vide', '', '2026-07-03'], ['avec-heure', '2026-07-01T08:00', '2026-07-03'],
    ['date-impossible-debut', '2026-02-30', '2026-03-02'], ['date-impossible-fin-non-atteinte', '2026-02-27', '2026-02-30'],
    ['meme-jour', '2026-11-02', '2026-11-02'], ['jour-13-mois', '2026-13-01', '2026-13-02'],
  ]) {
    plage(nom, dateDebut, dateFin);
  }

  // --- ajouterJoursDate : fins de mois, d'année, heure d'été/d'hiver -----------
  for (const date of ['2026-01-31', '2026-02-28', '2028-02-28', '2026-03-28', '2026-03-29', '2026-10-24', '2026-10-25',
    '2026-12-31', '2027-03-27', '2027-03-28', '2027-10-30', '2027-10-31']) {
    for (const nombre of [-366, -31, -1, 0, 1, 2, 7, 31, 365, 366]) ajouter(`${date}-plus-${nombre}`, date, nombre);
  }
  for (const [nom, date] of [['illisible', 'pas une date'], ['vide', ''], ['impossible', '2026-02-30'], ['mois-13', '2026-13-01'], ['avec-heure', '2026-07-01T08:00']]) {
    ajouter(`entree-${nom}`, date, 1);
  }

  // --- jourSemaineISO : une semaine complète, bissextile, normalisation Date.UTC --
  for (const date of ['2026-08-03', '2026-08-04', '2026-08-05', '2026-08-06', '2026-08-07', '2026-08-08', '2026-08-09',
    '2028-02-29', '2026-03-29', '2026-10-25', '2027-01-01', '2026-02-30', '2026-12-32']) {
    jourIso(date, date);
  }
  jourIso('illisible', 'pas une date');
  jourIso('vide', '');

  // --- dateFinCreneau -----------------------------------------------------------
  for (const date of ['2026-08-02', '2026-08-31', '2026-12-31', '2028-02-28', '2026-03-28', '2026-10-24']) {
    finCreneau(`${date}-meme-jour`, date, false);
    finCreneau(`${date}-lendemain`, date, true);
  }
  finCreneau('illisible-meme-jour', 'pas une date', false);
  finCreneau('illisible-lendemain', 'pas une date', true);
  finCreneau('impossible-lendemain', '2026-02-30', true);

  // --- materialiserCreneau : grilles des deux transitions de l'hiver 2026-2027 ---
  // Pour la veille et le jour du changement d'heure (25/10/2026 et 28/03/2027), chaque
  // heure de début de 00:00 à 23:30 au pas de 30 min, avec une fin 1 h plus tard le
  // même jour, ou à la même heure murale le lendemain (« lendemain »).
  const hhmm = (minutes) => `${pad2(Math.floor(minutes / 60))}:${pad2(minutes % 60)}`;
  for (const dst of ['2026-10-25', '2027-03-28']) {
    for (const date of [avant(dst, -1), dst]) {
      for (let minutes = 0; minutes < 24 * 60; minutes += 30) {
        const debut = hhmm(minutes);
        const finMemeJour = minutes + 60 < 24 * 60 ? hhmm(minutes + 60) : hhmm(minutes + 60 - 24 * 60);
        materialiser(`grille-${date}-${debut}-plus-1h`, date, creneauDerive(`g-${date}-${debut}`, debut, finMemeJour, minutes + 60 >= 24 * 60));
        materialiser(`grille-${date}-${debut}-lendemain-meme-heure`, date, creneauDerive(`g-${date}-${debut}-l`, debut, debut, true));
      }
    }
  }

  // --- materialiserCreneau : saisies invalides et bornes initiales --------------
  const cas = (nom, date, ...args) => materialiser(nom, date, creneauDerive(nom, ...args));
  cas('heure-un-chiffre', '2026-08-03', '7:00', '19:00');
  cas('heure-24', '2026-08-03', '07:00', '24:00');
  cas('minute-60', '2026-08-03', '07:60', '19:00');
  cas('heure-vide', '2026-08-03', '', '19:00');
  cas('fin-vide', '2026-08-03', '07:30', '');
  cas('heure-avec-secondes', '2026-08-03', '07:00:00', '19:00');
  cas('date-mal-formee', '2026-8-3', '07:00', '19:00');
  cas('date-vide', '', '07:00', '19:00');
  cas('date-impossible-meme-jour', '2026-02-30', '07:00', '19:00');
  cas('date-impossible-lendemain', '2026-02-30', '20:00', '08:00', true);
  cas('fin-egale-debut', '2026-08-03', '08:00', '08:00');
  cas('fin-avant-debut', '2026-08-03', '19:00', '07:00');
  cas('lendemain-plus-de-24h', '2026-08-03', '08:00', '09:00', true);
  cas('lendemain-24h-exactes', '2026-08-03', '08:00', '08:00', true);
  cas('lendemain-une-minute', '2026-08-03', '23:59', '00:00', true);
  cas('journee-23h59', '2026-08-03', '00:00', '23:59');
  cas('minuit-reveillon', '2026-12-31', '20:00', '08:00', true);
  cas('fin-fevrier-bissextile', '2028-02-28', '20:00', '08:00', true);
  cas('avec-id-persiste', '2026-08-03', '07:00', '19:00', false, { id: 'creneau-persiste' });
  const initial = (nom, date, heureDebut, heureFin, finJourSuivant, debutInitial, finInitial) => materialiser(nom, date,
    creneauDerive(nom, heureDebut, heureFin, finJourSuivant, { id: `id-${nom}`, debutInitial, finInitial }));
  initial('initiale-offset-conservee', '2026-08-03', '09:00', '17:00', false, '2026-08-03T09:00:00+02:00', '2026-08-03T17:00:00+02:00');
  initial('initiale-heure-modifiee', '2026-08-03', '10:00', '17:00', false, '2026-08-03T09:00:00+02:00', '2026-08-03T17:00:00+02:00');
  initial('initiale-autre-date', '2026-08-04', '09:00', '17:00', false, '2026-08-03T09:00:00+02:00', '2026-08-03T17:00:00+02:00');
  initial('initiale-utc-microsecondes', '2026-08-03', '09:00', '17:00', false, '2026-08-03T07:00:00.123456+00:00', '2026-08-03T15:00:00+00:00');
  initial('initiale-legacy-sans-offset', '2026-08-03', '09:00', '17:00', false, '2026-08-03T09:00:00', '2026-08-03T17:00:00');
  initial('initiale-illisible', '2026-08-03', '09:00', '17:00', false, 'pas une date', '2026-08-03T17:00:00+02:00');
  initial('initiale-legacy-ambigue', '2026-10-25', '02:30', '03:30', false, '2026-10-25T02:30:00', undefined);
  initial('initiale-seconde-occurrence-automne', '2026-10-25', '02:30', '04:00', false, '2026-10-25T01:30:00.000Z', undefined);
  initial('initiale-nuit-lendemain', '2026-08-02', '20:00', '08:00', true, '2026-08-02T18:00:00.000Z', '2026-08-03T06:00:00.000Z');
  initial('initiale-fin-seule', '2026-10-25', '01:00', '02:30', false, undefined, '2026-10-25T00:30:00.000Z');

  // --- materialiserPlanning : filtre des jours, invalides écartés, tri par début ----
  planning('vide', []);
  planning('tous-inactifs', [jourDerive('2026-08-03', false), jourDerive('2026-08-04', false)]);
  planning('jour-actif-sans-creneau', [jourDerive('2026-08-03', true, [])]);
  planning('tri-par-debut-entre-jours', [
    jourDerive('2026-08-05', true, [creneauDerive('c', '07:00', '12:00')]),
    jourDerive('2026-08-03', true, [creneauDerive('a', '14:00', '18:00'), creneauDerive('b', '07:00', '12:00')]),
  ]);
  planning('creneau-invalide-ecarte', [jourDerive('2026-08-03', true, [creneauDerive('ok', '07:00', '12:00'), creneauDerive('ko', '12:00', '11:00')])]);
  planning('nuit-puis-matin', [
    jourDerive('2026-08-02', true, [creneauDerive('nuit', '20:00', '08:00', true)]),
    jourDerive('2026-08-03', true, [creneauDerive('matin', '06:00', '07:00')]),
  ]);
  planning('meme-debut-ordre-stable', [jourDerive('2026-08-03', true, [creneauDerive('long', '07:00', '19:00'), creneauDerive('court', '07:00', '09:00')])]);
  planning('transition-automne', [jourDerive('2026-10-24', true, [creneauDerive('veille', '20:00', '08:00', true)]), jourDerive('2026-10-25', true, [creneauDerive('jour', '09:00', '17:00')])]);
  planning('transition-printemps', [jourDerive('2027-03-27', true, [creneauDerive('veille', '20:00', '08:00', true)]), jourDerive('2027-03-28', true, [creneauDerive('trou', '02:00', '05:00')])]);
  planning('date-impossible-lendemain-leve', [jourDerive('2026-02-30', true, [creneauDerive('x', '20:00', '08:00', true)])]);

  // --- validerPlanningDates : erreurs structurelles seulement ---------------------
  structure('vide', []);
  structure('tous-inactifs', [jourDerive('2026-08-03', false, [])]);
  structure('jour-actif-sans-creneau', [jourDerive('2026-08-03', true, [])]);
  structure('deux-jours-sans-creneau', [jourDerive('2026-08-03', true, []), jourDerive('2026-08-04', false, []), jourDerive('2026-08-05', true, [])]);
  structure('creneau-invalide-et-valide', [jourDerive('2026-08-03', true, [creneauDerive('ok', '07:00', '12:00'), creneauDerive('ko', '19:00', '07:00')])]);
  structure('heure-mal-formee', [jourDerive('2026-08-03', true, [creneauDerive('ko', '7:00', '12:00')])]);
  structure('heure-ambigue', [jourDerive('2026-10-25', true, [creneauDerive('ko', '02:30', '05:00')])]);
  structure('plus-de-24h', [jourDerive('2026-08-03', true, [creneauDerive('ko', '08:00', '09:00', true)])]);
  structure('chevauchement-nuit-sur-lendemain', [
    jourDerive('2026-08-02', true, [creneauDerive('nuit', '20:00', '08:00', true)]),
    jourDerive('2026-08-03', true, [creneauDerive('matin', '07:00', '12:00')]),
  ]);
  structure('creneaux-contigus-sans-chevauchement', [jourDerive('2026-08-03', true, [creneauDerive('a', '07:00', '12:00'), creneauDerive('b', '12:00', '16:00')])]);
  structure('trois-chevauchements-en-chaine', [jourDerive('2026-08-03', true, [
    creneauDerive('a', '07:00', '12:00'), creneauDerive('b', '11:00', '15:00'), creneauDerive('c', '14:00', '18:00'),
  ])]);
  structure('creneau-englobant', [jourDerive('2026-08-03', true, [creneauDerive('long', '07:00', '19:00'), creneauDerive('court', '09:00', '10:00')])]);
  structure('ordre-des-erreurs', [
    jourDerive('2026-08-03', true, [creneauDerive('a', '07:00', '12:00'), creneauDerive('b', '11:00', '15:00')]),
    jourDerive('2026-08-04', true, []),
    jourDerive('2026-08-05', true, [creneauDerive('ko', '18:00', '17:00')]),
  ]);
  structure('jour-inactif-invalide-ignore', [jourDerive('2026-08-03', false, [creneauDerive('ko', '18:00', '17:00')]), jourDerive('2026-08-04')]);
  structure('journee-13h-avertissement-exclu', [jourDerive('2026-08-03', true, [creneauDerive('long', '06:00', '19:00')])]);
  structure('repos-court-exclu', [jourDerive('2026-08-03', true, [creneauDerive('soir', '14:00', '22:00')]), jourDerive('2026-08-04', true, [creneauDerive('matin', '06:00', '14:00')])]);
  structure('transition-printemps-trou', [jourDerive('2027-03-28', true, [creneauDerive('trou', '02:00', '05:00')])]);
  structure('date-illisible-leve', [jourDerive('pas une date', true, [creneauDerive('x')])]);
  structure('date-impossible-lendemain-leve', [jourDerive('2026-02-30', true, [creneauDerive('x', '20:00', '08:00', true)])]);

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
// Règles 16 à 22 : lot 3, T2 (push, session, revenus, profil, modes d'exercice, RPPS) — numérotées 8 à 14 sur la
// branche du lot 3, renumérotées à la fusion avec le lot 2 (règles 8 à 15)
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
// Règle 16 : push-routing (`navigationPathForEvent`, src/lib/pushNative.ts)
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
// Règle 17 : session-count (`estSessionRecurrente` sur compteur, src/lib/session-count.ts)
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
// Règle 18 : mission-finance-display (src/lib/missionFinanceDisplay.ts)
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
// Règle 19 : paiement-soignant-ui (src/lib/paiementSoignantUi.ts)
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
// Règle 20 : valider-profil-soignant (src/lib/valider-profil-soignant.ts)
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
// Règle 21 : preferences-modes-exercice (src/lib/preferencesModesExercice.ts)
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
// Règle 22 : professions-rpps (listes de src/lib/constantes.ts l.55 et l.61)
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
// Lot 4, T2 (LOT4_PLAN §3 T2) : règles extraites par la PR web W0 et copies de bulletins.
// ---------------------------------------------------------------------------
const { format: formatDateFns, startOfWeek, addDays } = await import('date-fns');
const { fr: localeFr } = await import('date-fns/locale');

/**
 * Garde d'un calcul recopié d'une page ou d'une fonction interne (non exportée) : le texte
 * source doit contenir chaque extrait mot pour mot, sinon l'exporteur rejoue une règle que le
 * web n'applique plus. L'export échoue alors (code 2) au lieu de produire des vecteurs périmés.
 */
function exigeExtraits(fichier, extraits, raison) {
  const texte = readFileSync(resolve(RACINE, fichier), 'utf8');
  const absents = extraits.filter((extrait) => !texte.includes(extrait));
  if (absents.length > 0) {
    console.error(`export golden : ${fichier} ne contient plus ${absents.map((e) => `« ${e} »`).join(', ')} (${raison}). Revoir l'export du lot 4.`);
    process.exit(2);
  }
}

// ---------------------------------------------------------------------------
// Règle 23 : raisons-score-matching (src/lib/raisons-score-matching.ts)
// ---------------------------------------------------------------------------
/**
 * Domaine : clés de breakdown propres, hors chaîne de prototype (écart connu documenté par W0 :
 * une clé héritée d'`Object.prototype` passerait le filtre côté web ; le breakdown v3 n'en émet
 * aucune) et hors clés « index de tableau » (que JavaScript réordonne). L'entrée porte des paires
 * ordonnées (`entrees`) : l'ordre du breakdown départage les égalités et un objet JSON relu par
 * Swift ne garde pas l'ordre de ses clés.
 */
function vecteursRaisonsScore() {
  const c = new Collecteur('raisons-score-matching');
  const LABELS = raisonsScoreMatching.RAISON_LABELS;
  const CLES = Object.keys(LABELS);
  c.ajoute('liste/RAISON_LABELS', { fonction: 'RAISON_LABELS' },
    verifieVitest('raisons-score-matching', 'RAISON_LABELS', LABELS, {
      distance: 'proche de chez toi', tarif: 'bien payée vs le marché', horaire: 'à tes horaires préférés',
      etablissement: 'établissement bien noté', urgence: 'mission urgente', soignant_fiabilite: 'ton profil correspond',
      connaissance_etab: 'tu connais cet établissement', paiement_rapide: 'paiement rapide ⚡',
    }));
  c.ajoute('liste/RAISONS_EPINGLEES', { fonction: 'RAISONS_EPINGLEES' },
    verifieVitest('raisons-score-matching', 'RAISONS_EPINGLEES', raisonsScoreMatching.RAISONS_EPINGLEES, ['connaissance_etab', 'paiement_rapide']));

  const raisons = (nom, entrees, vitest) => {
    for (const [cle] of entrees) {
      if (cle in Object.prototype || cle === '__proto__' || /^(0|[1-9]\d*)$/.test(cle)) {
        throw new Error(`raisons-score-matching: « ${nom} » : clé « ${cle} » hors domaine golden.`);
      }
    }
    const breakdown = Object.fromEntries(entrees);
    if (JSON.stringify(Object.keys(breakdown)) !== JSON.stringify(entrees.map(([cle]) => cle))) {
      throw new Error(`raisons-score-matching: « ${nom} » : clés dupliquées ou réordonnées.`);
    }
    const obtenu = raisonsScoreMatching.raisonsScore(breakdown);
    if (vitest !== undefined) verifieVitest('raisons-score-matching', nom, obtenu, vitest);
    c.ajoute(`raisonsScore/${nom}`, { fonction: 'raisonsScore', entrees }, obtenu);
  };
  const raisonsBrut = (nom, breakdown, vitest) => {
    const obtenu = raisonsScoreMatching.raisonsScore(breakdown);
    if (vitest !== undefined) verifieVitest('raisons-score-matching', nom, obtenu, vitest);
    c.ajoute(`raisonsScore/${nom}`, breakdown === undefined ? { fonction: 'raisonsScore', absent: true } : { fonction: 'raisonsScore', breakdown }, obtenu);
  };

  // --- Issus de raisons-score-matching.test.ts -----------------------------------
  raisons('vitest-tri-points', [['distance', 10], ['tarif', 25], ['horaire', 15], ['urgence', 5]], 'bien payée vs le marché · à tes horaires préférés');
  raisons('vitest-epingle-connaissance', [['distance', 30], ['connaissance_etab', 5]], 'tu connais cet établissement · proche de chez toi');
  raisons('vitest-epingle-ordre', [['paiement_rapide', 1], ['distance', 40], ['connaissance_etab', 1]], 'tu connais cet établissement · paiement rapide ⚡');
  raisons('vitest-epingle-paiement', [['paiement_rapide', 2], ['tarif', 20], ['horaire', 10]], 'paiement rapide ⚡ · bien payée vs le marché');
  raisons('vitest-epinglees-a-zero', [['connaissance_etab', 0], ['paiement_rapide', 0], ['horaire', 3]], 'à tes horaires préférés');
  raisons('vitest-cles-inconnues', [['fiabilite', 50], ['inconnu', 99], ['distance', 0], ['tarif', '30'], ['urgence', -1], ['horaire', 5]], 'à tes horaires préférés');
  raisons('vitest-fiabilite-v3', [['soignant_fiabilite', 12], ['etablissement', 4]], 'ton profil correspond · établissement bien noté');
  raisons('vitest-egalite-ordre', [['tarif', 10], ['distance', 10], ['horaire', 10]], 'bien payée vs le marché · proche de chez toi');
  raisons('vitest-vide', [], '');
  raisonsBrut('vitest-null', null, '');
  raisonsBrut('vitest-absent', undefined, '');

  // --- Grille : une clé seule, valeurs JSON de tout type ----------------------------
  const VALEURS = [['un', 1], ['zero', 0], ['negatif', -1], ['demi', 0.5], ['infime', 1e-9], ['cent', 100],
    ['texte', '5'], ['vrai', true], ['null', null], ['tableau', [5]], ['objet', { v: 5 }]];
  for (const cle of [...CLES, 'fiabilite', 'Distance', 'distance ', 'score']) {
    for (const [nomValeur, valeur] of VALEURS) raisons(`seule/${cle}/${nomValeur}`, [[cle, valeur]]);
  }
  // --- Grille : paires ordonnées (épinglage, égalité, tri décroissant) ---------------
  for (const a of CLES) {
    for (const b of CLES) {
      if (a === b) continue;
      for (const [nomMotif, va, vb] of [['egalite', 1, 1], ['croissant', 1, 2], ['decroissant', 2, 1]]) {
        raisons(`paire/${a}/${b}/${nomMotif}`, [[a, va], [b, vb]]);
      }
    }
  }
  // --- Grille : triplets (ordre canonique des libellés), deux motifs -----------------
  for (let i = 0; i < CLES.length; i += 1) {
    for (let j = i + 1; j < CLES.length; j += 1) {
      for (let k = j + 1; k < CLES.length; k += 1) {
        raisons(`triplet/${CLES[i]}/${CLES[j]}/${CLES[k]}/croissant`, [[CLES[i], 1], [CLES[j], 2], [CLES[k], 3]]);
        raisons(`triplet/${CLES[k]}/${CLES[j]}/${CLES[i]}/egalite`, [[CLES[k], 5], [CLES[j], 5], [CLES[i], 5]]);
      }
    }
  }
  // --- Cas choisis ---------------------------------------------------------------------
  raisons('cas/toutes-les-cles', CLES.map((cle, i) => [cle, i + 1]));
  raisons('cas/toutes-les-cles-inversees', [...CLES].reverse().map((cle, i) => [cle, i + 1]));
  raisons('cas/ordre-jsonb-v3', [['tarif', 25], ['horaire', 15], ['urgence', 15], ['distance', 20], ['etablissement', 12],
    ['paiement_rapide', 3], ['connaissance_etab', 2], ['soignant_fiabilite', 10]]);
  raisons('cas/flottants-proches', [['distance', 0.3], ['tarif', 0.30000000000000004]]);
  raisons('cas/epinglee-negative', [['paiement_rapide', -2], ['distance', 1]]);
  raisons('cas/epinglee-texte', [['connaissance_etab', '1'], ['tarif', 1]]);
  raisons('cas/une-seule-epinglee-et-rien', [['paiement_rapide', 4]]);
  raisons('cas/inconnues-seules', [['fiabilite', 50], ['inconnu', 99]]);
  for (const [nom, breakdown] of [['texte', 'distance'], ['nombre', 5], ['vrai', true], ['faux', false], ['tableau', [1, 2]],
    ['zero', 0], ['texte-vide', '']]) {
    raisonsBrut(`non-objet/${nom}`, breakdown);
  }
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 24 : filtre-paquet-swipe (src/lib/filtre-paquet-swipe.ts)
// ---------------------------------------------------------------------------
/**
 * Domaine : chaînes de l'alphabet latin (casse par `toLowerCase`, comparaison par unités UTF-16 :
 * une forme décomposée ne correspond pas à la forme composée). Les plannings restent dans le
 * domaine de `planning-candidat` (missions ponctuelles, créneaux explicites, erreur de planning).
 */
function vecteursFiltrePaquetSwipe() {
  const c = new Collecteur('filtre-paquet-swipe');
  const offre = (missionId, extra = {}) => ({
    mission_id: missionId,
    profession_requise: 'IDE',
    etablissement_ville: 'Paris',
    etablissement_code_postal: '75016',
    distance_km: 5,
    taux_horaire_base: 30,
    type_contrat_recherche: 'TOUS',
    est_urgente: false,
    // Mercredi 4 novembre 2026, 8 h → 16 h à Paris.
    debut_le: '2026-11-04T07:00:00Z',
    fin_le: '2026-11-04T15:00:00Z',
    ...extra,
  });
  const filtre = (extra = {}) => ({
    urgentesOnly: false, horaire: 'TOUS', profession: '', ville: '', rayonKm: 50, tauxMin: 0, typeContrat: 'TOUS', ...extra,
  });
  const correspond = (nom, requise, selection, compte, vitest) => {
    const obtenu = filtrePaquetSwipe.missionCorrespondProfessionInscription(requise, selection, compte);
    if (vitest !== undefined) verifieVitest('filtre-paquet-swipe', nom, obtenu, vitest);
    c.ajoute(`missionCorrespondProfessionInscription/${nom}`, { fonction: 'missionCorrespondProfessionInscription', requise, selection, compte }, obtenu);
  };
  const passe = (nom, mission, filtreDeck, professionParcours, vitest) => {
    const obtenu = filtrePaquetSwipe.missionPasseFiltrePaquet(mission, filtreDeck, professionParcours);
    if (vitest !== undefined) verifieVitest('filtre-paquet-swipe', nom, obtenu, vitest);
    c.ajoute(`missionPasseFiltrePaquet/${nom}`, { fonction: 'missionPasseFiltrePaquet', mission, filtre: filtreDeck, professionParcours }, obtenu);
  };
  const filtrer = (nom, paquet, filtreDeck, professionParcours, vitest) => {
    const resultat = filtrePaquetSwipe.filtrerPaquetSwipe(paquet, filtreDeck, professionParcours);
    if (filtreDeck == null && resultat !== paquet) throw new Error(`filtre-paquet-swipe: « ${nom} » : sans filtre, le paquet doit être rendu tel quel.`);
    const obtenu = resultat.map((m) => m.mission_id);
    if (vitest !== undefined) verifieVitest('filtre-paquet-swipe', nom, obtenu, vitest);
    c.ajoute(`filtrerPaquetSwipe/${nom}`, { fonction: 'filtrerPaquetSwipe', paquet, filtre: filtreDeck, professionParcours }, obtenu);
  };

  // --- Issus de filtre-paquet-swipe.test.ts -----------------------------------------
  filtrer('vitest-sans-filtre', [offre('a'), offre('b')], null, null, ['a', 'b']);
  filtrer('vitest-sans-filtre-parcours', [offre('a'), offre('b')], null, 'IDE', ['a', 'b']);
  filtrer('vitest-filtre-neutre-ordre', [offre('b'), offre('a'), offre('c')], filtre(), null, ['b', 'a', 'c']);
  const paquetProfessions = [
    offre('ide', { profession_requise: 'IDE' }), offre('iade', { profession_requise: 'IADE' }),
    offre('ibode', { profession_requise: 'IBODE' }), offre('sf', { profession_requise: 'SAGE_FEMME' }),
  ];
  filtrer('vitest-profession-toutes', paquetProfessions, filtre(), null, ['ide', 'iade', 'ibode', 'sf']);
  filtrer('vitest-profession-exacte', paquetProfessions, filtre({ profession: 'IDE' }), null, ['ide']);
  filtrer('vitest-parcours-iade', paquetProfessions, filtre(), 'IADE', ['ide', 'iade']);
  filtrer('vitest-parcours-ide', paquetProfessions, filtre(), 'IDE', ['ide']);
  filtrer('vitest-parcours-choix-prime', paquetProfessions, filtre({ profession: 'SAGE_FEMME' }), 'IADE', ['sf']);
  filtrer('vitest-parcours-sans-profession', paquetProfessions, filtre(), '', ['ide', 'iade', 'ibode', 'sf']);
  correspond('vitest-ide-compte-iade', 'IDE', '', 'IADE', true);
  correspond('vitest-iade-compte-ide', 'IADE', '', 'IDE', false);
  correspond('vitest-choix-sf-mission-ide', 'IDE', 'SAGE_FEMME', 'IADE', false);
  correspond('vitest-choix-sf-mission-sf', 'SAGE_FEMME', 'SAGE_FEMME', 'IADE', true);
  correspond('vitest-compte-vide', 'KINE', '', '', true);
  const paquetLieux = [
    offre('paris', {}),
    offre('lyon', { etablissement_ville: 'Lyon', etablissement_code_postal: '69003' }),
    offre('sans-lieu', { etablissement_ville: null, etablissement_code_postal: null }),
  ];
  filtrer('vitest-ville-sous-chaine', paquetLieux, filtre({ ville: '  PAR ' }), null, ['paris']);
  filtrer('vitest-ville-code-postal', paquetLieux, filtre({ ville: '690' }), null, ['lyon']);
  filtrer('vitest-ville-pas-milieu-code-postal', paquetLieux, filtre({ ville: '016' }), null, []);
  filtrer('vitest-ville-espaces', paquetLieux, filtre({ ville: '   ' }), null, ['paris', 'lyon', 'sans-lieu']);
  filtrer('vitest-rayon', [offre('inconnue', { distance_km: null }), offre('limite', { distance_km: 10 }), offre('loin', { distance_km: 10.5 })],
    filtre({ rayonKm: 10 }), null, ['inconnue', 'limite']);
  const paquetTaux = [offre('absent', { taux_horaire_base: null }), offre('egal', { taux_horaire_base: 30 }), offre('dessous', { taux_horaire_base: 29.99 })];
  filtrer('vitest-taux-ignore', paquetTaux, filtre({ tauxMin: 0 }), null, ['absent', 'egal', 'dessous']);
  filtrer('vitest-taux-minimum', paquetTaux, filtre({ tauxMin: 30 }), null, ['egal']);
  const paquetContrats = [offre('salarie', { type_contrat_recherche: 'SALARIE' }), offre('liberal', { type_contrat_recherche: 'LIBERAL' }),
    offre('tous', { type_contrat_recherche: 'TOUS' })];
  filtrer('vitest-contrat-cdd', paquetContrats, filtre({ typeContrat: 'CDD' }), null, ['salarie', 'tous']);
  filtrer('vitest-contrat-liberal', paquetContrats, filtre({ typeContrat: 'LIBERAL' }), null, ['liberal', 'tous']);
  filtrer('vitest-contrat-tous', paquetContrats, filtre({ typeContrat: 'TOUS' }), null, ['salarie', 'liberal', 'tous']);
  filtrer('vitest-urgentes', [offre('normale'), offre('urgente', { est_urgente: true })], filtre({ urgentesOnly: true }), null, ['urgente']);
  const jour = offre('jour');
  // Samedi 7 novembre 2026, 21 h → dimanche 7 h à Paris.
  const nuitWeekend = offre('nuit-weekend', { debut_le: '2026-11-07T20:00:00Z', fin_le: '2026-11-08T06:00:00Z' });
  const inexacte = offre('inexacte', { erreur_planning: true });
  const paquetHoraires = [jour, nuitWeekend, inexacte];
  filtrer('vitest-horaire-tous', paquetHoraires, filtre({ horaire: 'TOUS' }), null, ['jour', 'nuit-weekend', 'inexacte']);
  filtrer('vitest-horaire-jour', paquetHoraires, filtre({ horaire: 'JOUR' }), null, ['jour']);
  filtrer('vitest-horaire-nuit', paquetHoraires, filtre({ horaire: 'NUIT' }), null, ['nuit-weekend']);
  filtrer('vitest-horaire-weekend', paquetHoraires, filtre({ horaire: 'WEEKEND' }), null, ['nuit-weekend']);
  passe('vitest-inexacte-nuit', inexacte, filtre({ horaire: 'NUIT' }), null, false);
  filtrer('vitest-cumul', [
    offre('ok', { est_urgente: true, distance_km: 3, taux_horaire_base: 40 }),
    offre('pas-urgente', { distance_km: 3, taux_horaire_base: 40 }),
    offre('trop-loin', { est_urgente: true, distance_km: 30, taux_horaire_base: 40 }),
  ], filtre({ urgentesOnly: true, rayonKm: 10, tauxMin: 35, ville: 'paris' }), null, ['ok']);

  // --- Grille : profession × sélection × compte (exploration avant inscription) ------
  for (const requise of ['IDE', 'IADE', 'IBODE', 'SAGE_FEMME', 'MEDECIN', null]) {
    for (const selection of ['', 'IDE', 'IADE', 'SAGE_FEMME']) {
      for (const compte of ['', 'IDE', 'IADE', 'IBODE', 'SAGE_FEMME', 'MEDECIN']) {
        correspond(`grille/${requise ?? 'null'}/${selection || 'vide'}/${compte || 'vide'}`, requise, selection, compte);
      }
    }
  }
  // --- Grille : profession du filtre × parcours ---------------------------------------
  for (const requise of ['IDE', 'IADE', 'IBODE', 'SAGE_FEMME', null]) {
    for (const profession of ['', 'IDE', 'IADE']) {
      for (const parcours of [null, '', 'IDE', 'IADE', 'IBODE']) {
        const nom = `profession/${requise ?? 'null'}/${profession || 'vide'}/${parcours === null ? 'hors-parcours' : parcours || 'vide'}`;
        passe(nom, offre(nom, { profession_requise: requise }), filtre({ profession }), parcours);
      }
    }
  }
  // --- Grille : ville et code postal --------------------------------------------------
  const LIEUX = [['paris', 'Paris', '75016'], ['lyon', 'Lyon', '69003'], ['saint-etienne', 'Saint-Étienne', '42000'],
    ['l-hay', "L'Haÿ-les-Roses", '94240'], ['evry', 'ÉVRY-COURCOURONNES', '91000'], ['sans-lieu', null, null],
    ['vides', '', ''], ['ville-seule', 'Paris', null], ['code-seul', null, '75001']];
  const VILLES = [['vide', ''], ['espaces', '   '], ['par', 'par'], ['par-espaces-majuscules', ' PAR '], ['paris-majuscules', 'PARIS'],
    ['code-750', '750'], ['code-milieu-016', '016'], ['lyon', 'lyon'], ['saint-e-accent', 'saint-é'], ['saint-e-majuscule', 'SAINT-É'],
    ['etienne-compose', 'étienne'], ['etienne-majuscule', 'ÉTIENNE'], ['etienne-decompose', 'e\u0301tienne'],
    ['etienne-sans-accent', 'etienne'], ['hay-trema', 'haÿ'], ['apostrophe', "l'haÿ"], ['evry-accent', 'évry'],
    ['evry-sans-accent', 'evry'], ['chiffre-9', '9'], ['tabulation-saut', '\tparis\n'], ['insecable', '\u00a0paris\u00a0'],
    ['bom', '\ufeffparis'], ['tiret', '-']];
  for (const [nomLieu, ville, codePostal] of LIEUX) {
    for (const [nomVille, villeFiltre] of VILLES) {
      const nom = `ville/${nomLieu}/${nomVille}`;
      passe(nom, offre(nom, { etablissement_ville: ville, etablissement_code_postal: codePostal }), filtre({ ville: villeFiltre }), null);
    }
  }
  // --- Grille : rayon -------------------------------------------------------------------
  for (const [nomDistance, distance] of [['null', null], ['zero', 0], ['9-99', 9.99], ['10', 10], ['10-0001', 10.0001], ['50', 50], ['51', 51]]) {
    for (const rayonKm of [0, 10, 50, 100]) {
      const nom = `rayon/${nomDistance}/${rayonKm}`;
      passe(nom, offre(nom, { distance_km: distance }), filtre({ rayonKm }), null);
    }
  }
  // --- Grille : taux minimum --------------------------------------------------------------
  for (const [nomTaux, taux] of [['null', null], ['zero', 0], ['29-99', 29.99], ['30', 30], ['30-01', 30.01], ['100', 100]]) {
    for (const tauxMin of [0, 30, 35.5]) {
      const nom = `taux/${nomTaux}/${tauxMin}`;
      passe(nom, offre(nom, { taux_horaire_base: taux }), filtre({ tauxMin }), null);
    }
  }
  // --- Grille : type de contrat -----------------------------------------------------------
  for (const contratMission of ['TOUS', 'SALARIE', 'LIBERAL', 'CDD', 'MIXTE', null]) {
    for (const typeContrat of ['TOUS', 'CDD', 'LIBERAL', 'SALARIE', '']) {
      const nom = `contrat/${contratMission ?? 'null'}/${typeContrat || 'vide'}`;
      passe(nom, offre(nom, { type_contrat_recherche: contratMission }), filtre({ typeContrat }), null);
    }
  }
  // --- Grille : urgence ---------------------------------------------------------------------
  for (const estUrgente of [true, false]) {
    for (const urgentesOnly of [true, false]) {
      const nom = `urgence/${estUrgente ? 'urgente' : 'normale'}/${urgentesOnly ? 'urgentes-seulement' : 'toutes'}`;
      passe(nom, offre(nom, { est_urgente: estUrgente }), filtre({ urgentesOnly }), null);
    }
  }
  // --- Grille : horaires (planning exact, nuit, week-end, créneaux explicites) ---------------
  const creneau = (debut, fin, extra = {}) => ({ debut, fin, est_pause: false, type_creneau: 'PREVISIONNEL', ...extra });
  const PLANNINGS = [
    ['jour-semaine', {}],
    ['nuit-weekend', { debut_le: '2026-11-07T20:00:00Z', fin_le: '2026-11-08T06:00:00Z' }],
    ['nuit-semaine', { debut_le: '2026-11-04T20:00:00Z', fin_le: '2026-11-05T05:00:00Z' }],
    ['samedi-jour', { debut_le: '2026-11-07T08:00:00Z', fin_le: '2026-11-07T16:00:00Z' }],
    ['erreur-planning', { erreur_planning: true }],
    ['deux-creneaux-jour', { nb_creneaux: 2, debut_le: '2026-11-04T07:00:00Z', fin_le: '2026-11-05T15:00:00Z',
      creneaux_planifies: [creneau('2026-11-04T07:00:00Z', '2026-11-04T15:00:00Z'), creneau('2026-11-05T07:00:00Z', '2026-11-05T15:00:00Z')] }],
    ['deux-creneaux-dont-nuit', { nb_creneaux: 2, debut_le: '2026-11-04T07:00:00Z', fin_le: '2026-11-06T05:00:00Z',
      creneaux_planifies: [creneau('2026-11-04T07:00:00Z', '2026-11-04T15:00:00Z'), creneau('2026-11-05T20:00:00Z', '2026-11-06T05:00:00Z')] }],
    ['planning-incomplet', { nb_creneaux: 3, debut_le: '2026-11-04T07:00:00Z', fin_le: '2026-11-06T15:00:00Z',
      creneaux_planifies: [creneau('2026-11-04T07:00:00Z', '2026-11-04T15:00:00Z')] }],
    ['changement-heure', { debut_le: '2026-10-24T20:00:00Z', fin_le: '2026-10-25T06:00:00Z' }],
  ];
  for (const [nomPlanning, planning] of PLANNINGS) {
    for (const horaire of ['TOUS', 'JOUR', 'NUIT', 'WEEKEND']) {
      const nom = `horaire/${nomPlanning}/${horaire.toLowerCase()}`;
      passe(nom, offre(nom, planning), filtre({ horaire }), null);
    }
  }
  // --- Paquets : ordre conservé, cumul ----------------------------------------------------
  filtrer('paquet/vide', [], filtre(), null, []);
  filtrer('paquet/vide-sans-filtre', [], null, null, []);
  filtrer('paquet/cumul-parcours', [
    offre('ide-proche', { profession_requise: 'IDE', distance_km: 2 }),
    offre('iade-loin', { profession_requise: 'IADE', distance_km: 60 }),
    offre('iade-proche-liberal', { profession_requise: 'IADE', distance_km: 2, type_contrat_recherche: 'LIBERAL' }),
    offre('sf-proche', { profession_requise: 'SAGE_FEMME', distance_km: 2 }),
    offre('ide-lyon', { profession_requise: 'IDE', etablissement_ville: 'Lyon', etablissement_code_postal: '69003' }),
  ], filtre({ typeContrat: 'CDD', ville: 'Paris' }), 'IADE');
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 25 : statut-litige (src/lib/statut-litige-regles.ts)
// ---------------------------------------------------------------------------
/** Libellé, icône nommée et groupe (les classes Tailwind ne sont pas portées), prédicats. */
function vecteursStatutLitige() {
  const c = new Collecteur('statut-litige');
  const TABLE = [
    ['OUVERT', 'Ouvert', 'Scale', 'OUVERT'], ['EN_DISCUSSION', 'En discussion', 'MessageSquare', 'OUVERT'],
    ['EN_MEDIATION', 'Médiation', 'AlertTriangle', 'MEDIATION'], ['MEDIATION_EN_COURS', 'Médiation en cours', 'Users', 'MEDIATION'],
    ['REVUE_ADMIN', 'Revue admin', 'Gavel', 'ACTION_ATTENDUE'], ['RESOLU_ACCORD_PARTIES', 'Accord mutuel ✅', 'CheckCircle2', 'RESOLU_ACCORD'],
    ['RESOLU_FAVEUR_SOIGNANT', 'Tranché en faveur soignant', 'Gavel', 'RESOLU_DECISION'],
    ['RESOLU_FAVEUR_ETAB', 'Tranché en faveur étab', 'Gavel', 'RESOLU_DECISION'],
    ['RESOLU_PARTAGE', 'Tranché : décision partagée', 'Gavel', 'RESOLU_DECISION'],
    ['RESOLU_SOIGNANT', 'Résolu (soignant)', 'CheckCircle2', 'RESOLU_DECISION'],
    ['RESOLU_ETABLISSEMENT', 'Résolu (étab)', 'CheckCircle2', 'RESOLU_DECISION'],
    ['RESOLU_ADMIN', 'Résolu admin', 'Gavel', 'FERME'], ['FERME', 'Fermé', 'XCircle', 'FERME'],
  ];
  const regle = (statut) => {
    const { label, icone, groupe } = statutLitigeRegles.statutLitigeRegle(statut);
    return { label, icone, groupe };
  };
  for (const [statut, label, icone, groupe] of TABLE) {
    verifieVitest('statut-litige', `vitest-${statut}`, regle(statut), { label, icone, groupe });
  }
  verifieVitest('statut-litige', 'vitest-inconnu', regle('STATUT_FUTUR'), { label: 'STATUT_FUTUR', icone: 'Scale', groupe: 'OUVERT' });
  const statuts = [...TABLE.map(([statut]) => statut), 'STATUT_FUTUR', '', 'ouvert', ' OUVERT', 'OUVERT ', 'RESOLU', 'Résolu',
    'constructor', 'toString', '__proto__', 'hasOwnProperty'];
  for (const statut of statuts) {
    const nom = statut === '' ? 'vide' : statut.replace(/ /g, '_');
    c.ajoute(`statutLitigeRegle/${nom}`, { fonction: 'statutLitigeRegle', statut }, regle(statut));
    for (const predicat of ['estResolu', 'peutProposerMediation', 'peutConfirmerAccord']) {
      c.ajoute(`${predicat}/${nom}`, { fonction: predicat, statut }, statutLitigeRegles[predicat](statut));
    }
  }
  const vrais = (predicat) => statuts.filter((statut) => statutLitigeRegles[predicat](statut));
  verifieVitest('statut-litige', 'vitest-estResolu', vrais('estResolu'), ['RESOLU_ACCORD_PARTIES', 'RESOLU_FAVEUR_SOIGNANT',
    'RESOLU_FAVEUR_ETAB', 'RESOLU_PARTAGE', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME']);
  verifieVitest('statut-litige', 'vitest-peutProposerMediation', vrais('peutProposerMediation'), ['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION']);
  verifieVitest('statut-litige', 'vitest-peutConfirmerAccord', vrais('peutConfirmerAccord'), ['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS']);
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 26 : alertes-recherche-missions (src/lib/alertes-recherche-missions.ts)
// ---------------------------------------------------------------------------
/**
 * `preparerAlerteMissions` (recherche équivalente à réutiliser, nom libre) et la clé de
 * comparaison qu'elle applique (fonction interne `cle`, recopiée sous garde d'extrait). Domaine de
 * `cleComparaison` : clés dont l'ordre `localeCompare` coïncide avec l'ordre des unités UTF-16 (le
 * port Swift trie par unités UTF-16 ; deux objets aux mêmes clés restent comparés à l'identique) et
 * objets imbriqués d'au plus une clé (un objet JSON relu par Swift ne garde pas l'ordre de ses clés).
 * Le nom est tronqué à 90 unités UTF-16 : aucune troncature ne coupe une paire de substitution.
 */
function vecteursAlertesRecherche() {
  const c = new Collecteur('alertes-recherche-missions');
  const EXTRAIT_CLE = 'const cle = (valeur: Record<string, unknown>) => JSON.stringify(Object.fromEntries(Object.entries(valeur).sort(([a], [b]) => a.localeCompare(b))));';
  exigeExtraits('src/lib/alertes-recherche-missions.ts', [EXTRAIT_CLE, 'cle(recherche.filtres ?? {}) === cle({ ...criteres })'],
    'clé de comparaison recopiée par cleComparaison');
  const cle = (valeur) => JSON.stringify(Object.fromEntries(Object.entries(valeur).sort(([a], [b]) => a.localeCompare(b))));
  const criteres = { profession: '', rayonKm: 25, tauxMin: 30, typeContrat: 'CDD', urgentesOnly: true, horaire: 'NUIT', villeRecherche: 'Paris' };

  const preparer = (nom, criteresVecteur, recherches, nomBase, vitest) => {
    if (!Number.isInteger(criteresVecteur.rayonKm)) throw new Error(`alertes-recherche-missions: « ${nom} » : rayonKm entier attendu (FiltresAlerte.rayonKm).`);
    if (new Set(recherches.map((r) => r.id)).size !== recherches.length) throw new Error(`alertes-recherche-missions: « ${nom} » : identifiants dupliqués.`);
    const tronque = nomBase.slice(0, 90);
    if (/[\ud800-\udbff]$/.test(tronque) && nomBase.length > 90) throw new Error(`alertes-recherche-missions: « ${nom} » : la troncature coupe une paire de substitution (hors domaine).`);
    const resultat = alertesRecherche.preparerAlerteMissions(criteresVecteur, recherches, nomBase);
    const obtenu = { dejaId: resultat.deja?.id ?? null, nom: resultat.nom, filtres: resultat.filtres };
    if (vitest !== undefined) verifieVitest('alertes-recherche-missions', nom, obtenu, vitest, true);
    c.ajoute(`preparerAlerteMissions/${nom}`, { fonction: 'preparerAlerteMissions', criteres: criteresVecteur, recherches, nomBase }, obtenu);
  };
  const recherche = (id, filtres, extra = {}) => ({ id, nom: `Recherche ${id}`, alerte_active: false, filtres, ...extra });

  // --- Issus de alertes-recherche-missions.test.ts -----------------------------------
  preparer('vitest-sept-filtres', criteres, [], 'Alerte missions IADE', { dejaId: null, nom: 'Alerte missions IADE', filtres: criteres });
  const ancien = { id: 'a', nom: 'Alerte missions', alerte_active: false, filtres: { profession: 'IDE', rayonKm: 100 } };
  preparer('vitest-meme-nom-autre-rayon', criteres, [ancien, { ...ancien, id: 'b', nom: 'Alerte missions (2)' }], 'Alerte missions',
    { dejaId: null, nom: 'Alerte missions (3)', filtres: criteres });
  preparer('vitest-equivalente-autre-ordre', criteres, [{ id: 'exacte', nom: 'Ma recherche', alerte_active: false,
    filtres: { villeRecherche: 'Paris', horaire: 'NUIT', urgentesOnly: true, typeContrat: 'CDD', tauxMin: 30, rayonKm: 25, profession: '' } }],
  'Alerte missions', { dejaId: 'exacte' });

  // --- Équivalence des filtres ------------------------------------------------------------
  const ordreJsonb = (objet) => Object.fromEntries(Object.entries(objet).sort(([a], [b]) => (Buffer.byteLength(a) - Buffer.byteLength(b)) || (a < b ? -1 : a > b ? 1 : 0)));
  const VARIANTES = [
    ['identique', { ...criteres }],
    ['ordre-inverse', Object.fromEntries(Object.entries(criteres).reverse())],
    ['ordre-jsonb', ordreJsonb(criteres)],
    ['rayon-texte', { ...criteres, rayonKm: '25' }],
    ['taux-proche', { ...criteres, tauxMin: 30.000000000000004 }],
    ['taux-texte', { ...criteres, tauxMin: '30' }],
    ['urgentes-texte', { ...criteres, urgentesOnly: 'true' }],
    ['urgentes-nombre', { ...criteres, urgentesOnly: 1 }],
    ['cle-en-plus-null', { ...criteres, etablissementId: null }],
    ['cle-en-plus-ville', { ...criteres, ville: 'Paris' }],
    ['cle-manquante', Object.fromEntries(Object.entries(criteres).filter(([k]) => k !== 'villeRecherche'))],
    ['profession-null', { ...criteres, profession: null }],
    ['ville-casse', { ...criteres, villeRecherche: 'paris' }],
    ['ville-espace-final', { ...criteres, villeRecherche: 'Paris ' }],
    ['horaire-imbrique', { ...criteres, horaire: { valeur: 'NUIT' } }],
    ['horaire-tableau', { ...criteres, horaire: ['NUIT'] }],
    ['vide', {}],
    ['null', null],
    ['tableau', [1, 2]],
    ['texte', 'Paris'],
    ['nombre', 25],
  ];
  for (const [nomVariante, filtres] of VARIANTES) {
    for (const alerteActive of [false, true]) {
      preparer(`equivalence/${nomVariante}/${alerteActive ? 'active' : 'inactive'}`, criteres,
        [recherche(`r-${nomVariante}-${alerteActive}`, filtres, { alerte_active: alerteActive })], 'Alerte missions');
    }
  }
  preparer('equivalence/filtres-absents', criteres, [{ id: 'sans-filtres', nom: 'Sans filtres', alerte_active: false }], 'Alerte missions');
  const criteresAccents = { ...criteres, villeRecherche: 'Saint-Étienne' };
  preparer('equivalence/ville-composee', criteresAccents, [recherche('nfc', { ...criteresAccents })], 'Alerte missions');
  preparer('equivalence/ville-decomposee', criteresAccents, [recherche('nfd', { ...criteresAccents, villeRecherche: 'Saint-E\u0301tienne' })], 'Alerte missions');
  const criteresTexte = { ...criteres, profession: 'IDE', villeRecherche: 'L\'Haÿ-les-Roses "centre"\\\n\u2028😀' };
  preparer('equivalence/echappements', criteresTexte, [recherche('echappements', { ...criteresTexte })], 'Alerte missions');
  const criteresDecimaux = { ...criteres, rayonKm: 0, tauxMin: 0.1 + 0.2 };
  preparer('equivalence/decimaux', criteresDecimaux, [recherche('dec', { ...criteresDecimaux, tauxMin: 0.30000000000000004 })], 'Alerte missions');
  preparer('equivalence/decimaux-arrondis', criteresDecimaux, [recherche('arrondi', { ...criteresDecimaux, tauxMin: 0.3 })], 'Alerte missions');
  preparer('equivalence/premiere-retenue', criteres, [
    recherche('autre', { ...criteres, rayonKm: 50 }), recherche('premiere', { ...criteres }), recherche('seconde', ordreJsonb(criteres)),
  ], 'Alerte missions');
  preparer('equivalence/nom-different-meme-filtres', criteres, [{ id: 'renommee', nom: 'Autre nom', alerte_active: true, filtres: { ...criteres } }], 'Alerte missions');
  for (const [nomCritere, extra] of [['profession-ide', { profession: 'IDE' }], ['rayon-zero', { rayonKm: 0 }], ['rayon-grand', { rayonKm: 200 }],
    ['taux-zero', { tauxMin: 0 }], ['taux-decimal', { tauxMin: 32.5 }], ['contrat-tous', { typeContrat: 'TOUS' }], ['contrat-liberal', { typeContrat: 'LIBERAL' }],
    ['urgentes-non', { urgentesOnly: false }], ['horaire-tous', { horaire: 'TOUS' }], ['ville-vide', { villeRecherche: '' }]]) {
    const variante = { ...criteres, ...extra };
    preparer(`criteres/${nomCritere}/meme`, variante, [recherche(`${nomCritere}-meme`, { ...variante })], 'Alerte missions');
    preparer(`criteres/${nomCritere}/base`, variante, [recherche(`${nomCritere}-base`, { ...criteres })], 'Alerte missions');
  }

  // --- Nom libre ---------------------------------------------------------------------------
  const avecNoms = (noms) => noms.map((nomRecherche, i) => ({ id: `n${i}`, nom: nomRecherche, alerte_active: false, filtres: { profession: 'IDE' } }));
  preparer('nom/libre', criteres, avecNoms(['Autre']), 'Alerte missions');
  preparer('nom/pris', criteres, avecNoms(['Alerte missions']), 'Alerte missions');
  preparer('nom/trou-dans-la-suite', criteres, avecNoms(['Alerte missions', 'Alerte missions (3)']), 'Alerte missions');
  preparer('nom/suite-longue', criteres, avecNoms(['Alerte missions', 'Alerte missions (2)', 'Alerte missions (3)', 'Alerte missions (4)']), 'Alerte missions');
  preparer('nom/seulement-suffixe', criteres, avecNoms(['Alerte missions (2)']), 'Alerte missions');
  preparer('nom/casse', criteres, avecNoms(['alerte missions']), 'Alerte missions');
  preparer('nom/espace-final', criteres, avecNoms(['Alerte missions ']), 'Alerte missions');
  // Identifiant distinct : deux entrées qui ne diffèrent que par la normalisation Unicode seraient
  // confondues par le contrôle de doublons Swift (égalité canonique des `String`).
  preparer('nom/decompose-vs-compose', criteres, [{ id: 'nfd', nom: 'Cafe\u0301 du soir', alerte_active: false, filtres: { profession: 'IDE' } }], 'Café du soir');
  preparer('nom/compose-pris', criteres, avecNoms(['Café du soir']), 'Café du soir');
  preparer('nom/vide', criteres, avecNoms(['']), '');
  preparer('nom/vide-libre', criteres, [], '');
  const long95 = `Alerte missions ${'IDE '.repeat(20)}`.slice(0, 95);
  const exactement90 = 'É'.repeat(90);
  preparer('nom/long-95-libre', criteres, [], long95);
  preparer('nom/long-95-tronque-pris', criteres, avecNoms([long95.slice(0, 90)]), long95);
  preparer('nom/long-95-complet-pris', criteres, avecNoms([long95]), long95);
  preparer('nom/exactement-90', criteres, avecNoms([exactement90]), exactement90);
  preparer('nom/91-unites', criteres, [], `${exactement90}x`);
  preparer('nom/emoji-avant-limite', criteres, avecNoms([`${'a'.repeat(86)}😀😀`]), `${'a'.repeat(86)}😀😀`);
  preparer('nom/emoji-apres-limite', criteres, [], `${'a'.repeat(90)}😀`);

  // --- Clé de comparaison (JSON.stringify trié) -----------------------------------------------
  const cleVecteur = (nom, valeur) => {
    if (valeur !== null && typeof valeur === 'object' && !Array.isArray(valeur)) {
      const cles = Object.keys(valeur);
      const parUnites = [...cles].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
      const parLocale = [...cles].sort((a, b) => a.localeCompare(b));
      if (JSON.stringify(parUnites) !== JSON.stringify(parLocale)) throw new Error(`alertes-recherche-missions: « ${nom} » : ordre localeCompare ≠ ordre UTF-16 (hors domaine).`);
      for (const v of Object.values(valeur)) {
        if (v !== null && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length > 1) throw new Error(`alertes-recherche-missions: « ${nom} » : objet imbriqué à plusieurs clés (hors domaine).`);
      }
    }
    c.ajoute(`cleComparaison/${nom}`, { fonction: 'cleComparaison', valeur }, cle(valeur));
  };
  cleVecteur('criteres', criteres);
  cleVecteur('vide', {});
  cleVecteur('imbrique-une-cle', { horaire: { valeur: 'NUIT' }, rayonKm: 25 });
  cleVecteur('tableau-valeur', { horaire: ['NUIT', 'JOUR', 3, null, true] });
  for (const [nomNombre, nombre] of [['zero', 0], ['un', 1], ['vingt-cinq', 25], ['decimal', 30.5], ['dixieme', 0.1], ['somme-flottante', 0.1 + 0.2],
    ['1e21', 1e21], ['1e20', 1e20], ['1e-7', 1e-7], ['1e-6', 0.000001], ['123e-20', 123e-20], ['grand-arrondi', 123456789012345680000],
    ['min-positif', 5e-324], ['max', 1.7976931348623157e308], ['negatif', -3.25], ['2-puissance-53', 2 ** 53], ['2-puissance-53-plus-2', 2 ** 53 + 2],
    ['cent', 100], ['tiers', 1 / 3], ['1-5e-10', 1.5e-10], ['negatif-petit', -1e-7], ['1e300', 1e300]]) {
    cleVecteur(`nombre/${nomNombre}`, { rayonKm: nombre });
  }
  for (const [nomTexte, texte] of [['vide', ''], ['simple', 'Paris'], ['accent', 'é'], ['decompose', 'e\u0301'], ['guillemet', '"'],
    ['barre-inverse', '\\'], ['saut', '\n'], ['nul', '\u0000'], ['controle-1f', '\u001f'], ['controle-10', '\u0010'], ['suppr', '\u007f'],
    ['separateur-ligne', '\u2028'], ['separateur-paragraphe', '\u2029'], ['emoji', '😀'], ['barre', 'a/b'], ['tabulation', '\t'],
    ['retour-arriere', '\b'], ['saut-page', '\f'], ['retour-chariot', '\r'], ['chevrons', '<script>'], ['insecable', '\u00a0'], ['bom', '\ufeff']]) {
    // `profession` porte le nom du cas : « é » composé et décomposé restent deux entrées distinctes
    // pour le contrôle de doublons Swift (égalité canonique des `String`).
    cleVecteur(`texte/${nomTexte}`, { profession: nomTexte, villeRecherche: texte });
  }
  for (const [nomBooleen, valeur] of [['vrai', true], ['faux', false], ['null', null]]) cleVecteur(`valeur/${nomBooleen}`, { urgentesOnly: valeur });
  cleVecteur('cles-hors-criteres', { a: 1, b_c: 2, z: 3, ville: 'Paris' });
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 27 : semaines-disponibilites (grille de src/pages/MesDisponibilites.tsx)
// ---------------------------------------------------------------------------
/**
 * La grille est calculée dans la page (aucun module à importer) : l'exporteur rejoue les mêmes appels
 * date-fns, sous garde d'extraits, dans le fuseau Europe/Paris du processus, et vérifie à la main les
 * semaines des changements d'heure (2026-10-25, 2027-03-28) avant d'écrire les vecteurs.
 */
function vecteursSemainesDisponibilites() {
  const c = new Collecteur('semaines-disponibilites');
  exigeExtraits('src/pages/MesDisponibilites.tsx', [
    "import { format, addDays, startOfWeek } from 'date-fns';",
    'const debut = startOfWeek(new Date(), { weekStartsOn: 1 });',
    'return Array.from({ length: 4 }, (_, s) =>',
    'Array.from({ length: 7 }, (_, j) => addDays(debut, s * 7 + j)),',
    ".gte('jour', format(new Date(), 'yyyy-MM-dd'));",
    "const aujourdHui = format(new Date(), 'yyyy-MM-dd');",
    "const jour = format(jourDate, 'yyyy-MM-dd');",
    'const passe = jour < aujourdHui;',
    "Semaine du {format(semaine[0], 'd MMMM', { locale: fr })}",
    "{format(jourDate, 'EEEE d MMM', { locale: fr })}",
    "{jour === aujourdHui && (",
  ], 'grille des disponibilités recopiée par semainesDisponibilites');
  const grille = (maintenant) => {
    const debut = startOfWeek(maintenant, { weekStartsOn: 1 });
    const semaines = Array.from({ length: 4 }, (_, s) => Array.from({ length: 7 }, (_, j) => addDays(debut, s * 7 + j)));
    const aujourdHui = formatDateFns(maintenant, 'yyyy-MM-dd');
    return {
      aujourdHui,
      semaines: semaines.map((semaine) => ({
        entete: `Semaine du ${formatDateFns(semaine[0], 'd MMMM', { locale: localeFr })}`,
        jours: semaine.map((jourDate) => {
          const jour = formatDateFns(jourDate, 'yyyy-MM-dd');
          return { jour, passe: jour < aujourdHui, estAujourdhui: jour === aujourdHui, libelle: formatDateFns(jourDate, 'EEEE d MMM', { locale: localeFr }) };
        }),
      })),
    };
  };
  const vecteur = (nom, instant, attendu) => {
    const obtenu = grille(new Date(instant));
    if (attendu) {
      const premier = obtenu.semaines[0].jours[0].jour;
      const dernier = obtenu.semaines[3].jours[6].jour;
      verifieVitest('semaines-disponibilites', nom, { aujourdHui: obtenu.aujourdHui, premier, dernier }, attendu);
    }
    c.ajoute(`semainesDisponibilites/${nom}`, { fonction: 'semainesDisponibilites', maintenant: instant }, obtenu);
  };
  // --- Écrits à la main : changements d'heure et bascule de minuit à Paris -------------------
  vecteur('main/2026-10-25-dimanche-midi', '2026-10-25T12:00:00.000Z', { aujourdHui: '2026-10-25', premier: '2026-10-19', dernier: '2026-11-15' });
  vecteur('main/2026-10-25-avant-bascule', '2026-10-25T00:59:59.999Z', { aujourdHui: '2026-10-25', premier: '2026-10-19', dernier: '2026-11-15' });
  vecteur('main/2026-10-25-apres-bascule', '2026-10-25T01:00:00.000Z', { aujourdHui: '2026-10-25', premier: '2026-10-19', dernier: '2026-11-15' });
  vecteur('main/2026-10-25-dernier-instant-dimanche', '2026-10-25T22:59:59.999Z', { aujourdHui: '2026-10-25', premier: '2026-10-19', dernier: '2026-11-15' });
  vecteur('main/2026-10-26-minuit-lundi', '2026-10-25T23:00:00.000Z', { aujourdHui: '2026-10-26', premier: '2026-10-26', dernier: '2026-11-22' });
  vecteur('main/2027-03-28-avant-bascule', '2027-03-28T00:59:59.999Z', { aujourdHui: '2027-03-28', premier: '2027-03-22', dernier: '2027-04-18' });
  vecteur('main/2027-03-28-apres-bascule', '2027-03-28T01:00:00.000Z', { aujourdHui: '2027-03-28', premier: '2027-03-22', dernier: '2027-04-18' });
  vecteur('main/2027-03-28-dernier-instant-dimanche', '2027-03-28T21:59:59.999Z', { aujourdHui: '2027-03-28', premier: '2027-03-22', dernier: '2027-04-18' });
  vecteur('main/2027-03-29-minuit-lundi', '2027-03-28T22:00:00.000Z', { aujourdHui: '2027-03-29', premier: '2027-03-29', dernier: '2027-04-25' });
  vecteur('main/horloge-demo', '2026-11-02T00:00:00.000Z', { aujourdHui: '2026-11-02', premier: '2026-11-02', dernier: '2026-11-29' });
  vecteur('main/dimanche-soir-utc-lundi-paris', '2026-11-01T23:30:00.000Z', { aujourdHui: '2026-11-02', premier: '2026-11-02', dernier: '2026-11-29' });
  vecteur('main/grille-traverse-octobre', '2026-10-05T10:00:00.000Z', { aujourdHui: '2026-10-05', premier: '2026-10-05', dernier: '2026-11-01' });
  vecteur('main/grille-traverse-mars', '2027-03-10T10:00:00.000Z', { aujourdHui: '2027-03-10', premier: '2027-03-08', dernier: '2027-04-04' });
  vecteur('main/nouvel-an-paris', '2026-12-31T23:30:00.000Z', { aujourdHui: '2027-01-01', premier: '2026-12-28', dernier: '2027-01-24' });
  vecteur('main/bissextile', '2028-02-28T12:00:00.000Z', { aujourdHui: '2028-02-28', premier: '2028-02-28', dernier: '2028-03-26' });
  // --- Grille : chaque jour d'une semaine, minuit et dernière milliseconde à Paris -------------
  for (let jour = 2; jour <= 8; jour += 1) {
    const iso = `2026-11-${pad2(jour)}`;
    vecteur(`semaine/${iso}/minuit`, new Date(`${iso}T00:00:00+01:00`).toISOString());
    vecteur(`semaine/${iso}/midi`, new Date(`${iso}T12:00:00+01:00`).toISOString());
    vecteur(`semaine/${iso}/fin`, new Date(new Date(`${iso}T00:00:00+01:00`).getTime() + 86_400_000 - 1).toISOString());
  }
  // --- Grille : fins de mois et d'année, années bissextiles --------------------------------------
  for (const iso of ['2026-01-31T12:00:00.000Z', '2026-02-28T12:00:00.000Z', '2026-03-29T00:30:00.000Z', '2026-03-29T01:30:00.000Z',
    '2026-04-30T21:59:59.999Z', '2026-06-30T22:00:00.000Z', '2026-08-31T12:00:00.000Z', '2026-12-27T22:59:59.999Z', '2026-12-27T23:00:00.000Z',
    '2027-02-28T12:00:00.000Z', '2027-10-31T00:30:00.000Z', '2027-10-31T01:30:00.000Z', '2027-12-31T12:00:00.000Z', '2028-02-29T12:00:00.000Z',
    '2028-12-31T12:00:00.000Z', '2030-01-01T00:00:00.000Z']) {
    vecteur(`dates/${iso}`, iso);
  }
  return c.tries();
}

// ---------------------------------------------------------------------------
// Règle 28 : copie-bulletin-validation (src/lib/copiesBulletins.ts)
// ---------------------------------------------------------------------------
/**
 * Décodage strict de `fn_lister_copies_bulletins` (`validerListeCopiesBulletins`) et
 * `copieBulletinTelechargeable`. Domaine (le port Swift est plus strict au-delà, échec fermé) :
 * `publie_le` au format date-heure ISO d'ECMAScript (`T` majuscule, secondes et fraction
 * facultatives, `Z` ou `±HH:MM`) ou refusé par `Date.parse` — le repli permissif de V8 (espace,
 * `t` minuscule, `+0000`, chiffres non ASCII…) est hors domaine ; `statut` jamais un tableau
 * (`String(['PUBLIEE'])` passerait côté web). Le serveur (`jsonb_build_object`) n'émet ni l'un ni l'autre.
 */
function vecteursCopieBulletinValidation() {
  const c = new Collecteur('copie-bulletin-validation');
  const ISO_ECMASCRIPT = /^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})?)?$/;
  // Réplique JavaScript du contrôle Swift (`CopieBulletinValidation.instantLisible`) : doit coïncider
  // avec `Date.parse` sur tout le domaine ISO (garde ci-dessous sur les vecteurs et une grille).
  const instantLisibleSwift = (s) => {
    const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|[+-](\d{2}):(\d{2}))?)?$/.exec(s);
    if (!m) return false;
    const [, , mois, jour, heure, minute, seconde, fraction, , dh, dm] = m;
    if (+mois < 1 || +mois > 12 || +jour < 1 || +jour > 31) return false;
    if (heure === undefined) return true;
    if (+heure > 24 || +minute > 59 || +(seconde ?? 0) > 59) return false;
    if (+heure === 24 && (+minute !== 0 || +(seconde ?? 0) !== 0 || /[1-9]/.test(fraction ?? ''))) return false;
    if (dh !== undefined && (+dh > 23 || +dm > 59)) return false;
    return true;
  };
  const verifieDomaineInstant = (nom, valeur) => {
    if (typeof valeur !== 'string') return;
    const lisible = !Number.isNaN(Date.parse(valeur));
    if (!ISO_ECMASCRIPT.test(valeur) && lisible) throw new Error(`copie-bulletin-validation: « ${nom} » : « ${valeur} » est lu par le repli V8 de Date.parse (hors domaine).`);
    if (instantLisibleSwift(valeur) !== lisible) throw new Error(`copie-bulletin-validation: « ${nom} » : le contrôle Swift de « ${valeur} » ne suit pas Date.parse.`);
  };
  for (const annee of ['2026', '0000', '2028']) {
    for (const mois of ['00', '01', '02', '12', '13']) {
      for (const jour of ['00', '01', '29', '30', '31', '32']) {
        for (const suffixe of ['', 'T00:00', 'T24:00:00Z', 'T24:00:00.000Z', 'T24:00:00.001Z', 'T23:59:59.999+23:59', 'T12:60:00Z',
          'T12:00:60Z', 'T25:00:00Z', 'T12:00:00+24:00', 'T12:00:00-12:60', 'T12:00:00.5', 'T09:30+01:00']) {
          verifieDomaineInstant('grille-instants', `${annee}-${mois}-${jour}${suffixe}`);
        }
      }
    }
  }

  const uuid = (n) => `10000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
  const copie = {
    id: uuid(1), etablissement_id: uuid(2), soignant_id: uuid(3), etablissement_nom: 'Employeur de test',
    soignant_nom: 'Test', soignant_prenom: 'Salarié', periode_debut: '2026-09-01', periode_fin: '2026-09-30',
    statut: 'PUBLIEE', publie_le: '2026-09-29T12:00:00Z', remplace_id: null, version: 1,
    motif_remplacement: null, mission_ids: [uuid(4)], taille_octets: 256, sha256: 'a'.repeat(64), signalee: false,
  };
  const valider = (nom, data, vitest) => {
    if (Array.isArray(data)) {
      for (const ligne of data) {
        if (ligne && typeof ligne === 'object' && !Array.isArray(ligne)) {
          if (Array.isArray(ligne.statut)) throw new Error(`copie-bulletin-validation: « ${nom} » : statut tableau hors domaine.`);
          verifieDomaineInstant(nom, ligne.publie_le);
        }
      }
    }
    let obtenu;
    try {
      obtenu = { valide: true, ids: copiesBulletins.validerListeCopiesBulletins(data).map((ligne) => ligne.id) };
    } catch (erreur) {
      if (!(erreur instanceof Error) || erreur.constructor !== Error) throw new Error(`copie-bulletin-validation: « ${nom} » lève ${erreur?.name} : hors domaine.`);
      obtenu = { erreur: erreur.message };
    }
    if (vitest !== undefined) verifieVitest('copie-bulletin-validation', nom, obtenu, vitest);
    c.ajoute(`validerListeCopiesBulletins/${nom}`, { fonction: 'validerListeCopiesBulletins', data }, obtenu);
  };
  const REFUS = { erreur: 'La liste des copies ne peut pas être vérifiée. Réessayez.' };
  const sans = (cle) => Object.fromEntries(Object.entries(copie).filter(([k]) => k !== cle));

  // --- Issus de copiesBulletins.test.ts --------------------------------------------------------
  valider('vitest-liste-vide', [], { valide: true, ids: [] });
  valider('vitest-document-complet', [copie], { valide: true, ids: [copie.id] });
  for (const [nom, reponse] of [['null', null], ['objet', {}], ['element-null', [null]], ['statut-PAYE', [{ ...copie, statut: 'PAYE' }]],
    ['missions-vides', [{ ...copie, mission_ids: [] }]], ['mission-autre', [{ ...copie, mission_ids: ['autre'] }]], ['version-0', [{ ...copie, version: 0 }]],
    ['taille-texte', [{ ...copie, taille_octets: '256' }]], ['taille-10485761', [{ ...copie, taille_octets: 10485761 }]],
    ['sha-non-verifiable', [{ ...copie, sha256: 'non-verifiable' }]], ['periode-inconnue', [{ ...copie, periode_debut: 'date inconnue' }]],
    ['publie-null', [{ ...copie, publie_le: null }]], ['periode-inversee', [{ ...copie, periode_fin: '2026-08-01' }]]]) {
    valider(`vitest-refus-${nom}`, reponse, REFUS);
  }

  // --- Grille : une mutation de champ à la fois ---------------------------------------------------
  const MUTATIONS = {
    id: [['majuscules', uuid(1).toUpperCase().replace('10000000', 'ABCDEF00')], ['nil', '00000000-0000-0000-0000-000000000000'], ['null', null],
      ['autre', 'autre'], ['accolades', `{${uuid(1)}}`], ['court', uuid(1).slice(1)], ['non-hexa', uuid(1).replace('1', 'g')], ['nombre', 1],
      ['saut-final', `${uuid(1)}\n`], ['sans-tirets', uuid(1).replace(/-/g, '')]],
    etablissement_id: [['majuscules', uuid(2).toUpperCase()], ['null', null], ['vide', '']],
    soignant_id: [['null', null], ['espace', ` ${uuid(3)}`]],
    etablissement_nom: [['vide', ''], ['null', null], ['nombre', 3]],
    soignant_nom: [['vide', ''], ['null', null]],
    soignant_prenom: [['vide', ''], ['null', null], ['booleen', true]],
    periode_debut: [['bissextile-faux', '2026-02-29'], ['fevrier-28', '2026-02-28'], ['an-zero', '0000-01-01'], ['an-zero-bissextile', '0000-02-29'],
      ['mois-13', '2026-13-01'], ['mois-00', '2026-00-10'], ['jour-00', '2026-01-00'], ['avril-31', '2026-04-31'], ['1900-bissextile', '1900-02-29'],
      ['2000-bissextile', '2000-02-29'], ['un-chiffre', '2026-9-01'], ['compact', '20260901'], ['avec-heure', '2026-09-01T00:00:00Z'],
      ['espace-tete', ' 2026-09-01'], ['saut-final', '2026-09-01\n'], ['chiffres-arabes', '٢٠٢٦-09-01'], ['nombre', 20260901], ['egale-fin', '2026-09-30']],
    periode_fin: [['9999', '9999-12-31'], ['avant-debut', '2026-08-31'], ['egale-debut', '2026-09-01'], ['fevrier-30', '2026-02-30'], ['null', null]],
    publie_le: [['utc', '2026-09-29T12:00:00Z'], ['microsecondes', '2026-09-29T12:00:00.123456+00:00'], ['date-seule', '2026-09-29'],
      ['sans-secondes', '2026-09-29T12:00'], ['sans-fuseau', '2026-09-29T12:00:00'], ['decalage-negatif', '2026-09-29T12:00:00-05:30'],
      ['minuit-24h', '2026-09-29T24:00:00Z'], ['24h-plus-une-seconde', '2026-09-29T24:00:01Z'], ['25h', '2026-09-29T25:00:00Z'],
      ['minute-60', '2026-09-29T12:60:00Z'], ['fevrier-30', '2026-02-30T12:00:00Z'], ['fevrier-32', '2026-02-32T12:00:00Z'],
      ['decalage-24h', '2026-09-29T12:00:00+24:00'], ['decalage-23h59', '2026-09-29T12:00:00+23:59'], ['decalage-minute-60', '2026-09-29T12:00:00+12:60'],
      ['vide', ''], ['texte', 'date inconnue'], ['nombre', 0], ['heure-seule', '2026-09-29T12'], ['fraction-vide', '2026-09-29T12:00:00.Z'],
      ['mois-13', '2026-13-01T00:00:00Z'], ['mois-00', '2026-00-01'], ['demi-seconde-decalee', '2026-09-29T12:00:00.5+01:00'],
      ['fraction-longue', '2026-09-29T12:00:00.1234567890123Z'], ['epoque', '1970-01-01T00:00:00Z']],
    statut: [['REMPLACEE', 'REMPLACEE'], ['RETIREE', 'RETIREE'], ['RESERVEE', 'RESERVEE'], ['minuscules', 'publiee'], ['null', null], ['nombre', 1], ['vide', '']],
    version: [['deux', 2], ['negatif', -1], ['decimal', 1.5], ['texte', '1'], ['null', null], ['max-sur', 9007199254740991], ['au-dela-sur', 9007199254740992]],
    taille_octets: [['un', 1], ['max', 10485760], ['zero', 0], ['decimal', 255.5], ['null', null], ['negatif', -256]],
    sha256: [['majuscules', 'A'.repeat(64)], ['63', 'a'.repeat(63)], ['65', 'a'.repeat(65)], ['non-hexa', 'g'.repeat(64)], ['null', null],
      ['saut-final', `${'a'.repeat(64)}\n`], ['hexa-mixte', '0123456789abcdef'.repeat(4)]],
    mission_ids: [['deux', [uuid(4), uuid(5)]], ['avec-null', [uuid(4), null]], ['texte', uuid(4)], ['null', null], ['majuscules', [uuid(4).toUpperCase()]],
      ['objet', { 0: uuid(4) }]],
    signalee: [['vrai', true], ['texte', 'false'], ['zero', 0], ['null', null]],
    remplace_id: [['uuid', uuid(9)], ['vide', ''], ['autre', 'autre'], ['majuscules', uuid(9).toUpperCase()]],
    motif_remplacement: [['CONTENU', 'CONTENU'], ['AUTRE', 'AUTRE'], ['DESTINATAIRE', 'DESTINATAIRE'], ['minuscules', 'contenu'], ['vide', '']],
  };
  for (const [champ, valeurs] of Object.entries(MUTATIONS)) {
    for (const [nomValeur, valeur] of valeurs) valider(`champ/${champ}/${nomValeur}`, [{ ...copie, [champ]: valeur }]);
    valider(`champ/${champ}/absent`, [sans(champ)]);
  }
  // --- Grille : forme de la liste et des lignes ------------------------------------------------------
  for (const [nom, data] of [['texte', 'liste'], ['nombre', 1], ['vrai', true], ['element-tableau', [[]]], ['element-nombre', [1]],
    ['element-texte', ['x']], ['element-vrai', [true]], ['element-objet-vide', [{}]]]) {
    valider(`forme/${nom}`, data);
  }
  valider('forme/deux-copies', [copie, { ...copie, id: uuid(11), statut: 'REMPLACEE', version: 2, remplace_id: uuid(1), motif_remplacement: 'CONTENU' }]);
  valider('forme/deuxieme-invalide', [copie, { ...copie, id: uuid(12), sha256: 'b'.repeat(63) }]);
  valider('forme/cles-en-plus', [{ ...copie, cle_inconnue: 'x', autre: { y: 1 } }]);

  // --- copieBulletinTelechargeable --------------------------------------------------------------------
  const telechargeable = (nom, statut, vitest) => {
    const obtenu = copiesBulletins.copieBulletinTelechargeable({ statut });
    if (vitest !== undefined) verifieVitest('copie-bulletin-validation', nom, obtenu, vitest);
    c.ajoute(`copieBulletinTelechargeable/${nom}`, { fonction: 'copieBulletinTelechargeable', statut }, obtenu);
  };
  telechargeable('PUBLIEE', 'PUBLIEE', true);
  telechargeable('REMPLACEE', 'REMPLACEE', true);
  telechargeable('RETIREE', 'RETIREE', false);
  for (const statut of ['RESERVEE', 'publiee', '', 'PUBLIEE ']) telechargeable(statut === '' ? 'vide' : statut.replace(/ /g, '_'), statut);
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
  // Lot 5, T3 : dérivation structurelle du planning établissement.
  'planning-derive.json': vecteursPlanningDerive(),
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
  // Lot 3, T2.
  'push-routing.json': vecteursPushRouting(),
  'session-count.json': await vecteursSessionCount(),
  'mission-finance-display.json': vecteursMissionFinance(),
  'paiement-soignant-ui.json': vecteursPaiementUi(),
  'valider-profil-soignant.json': vecteursValidationProfil(),
  'preferences-modes-exercice.json': vecteursModesExercice(),
  'professions-rpps.json': vecteursProfessionsRpps(),
  // Lot 4, T2 : règles extraites par la PR web W0, grille des disponibilités, copies de bulletins.
  'raisons-score-matching.json': vecteursRaisonsScore(),
  'filtre-paquet-swipe.json': vecteursFiltrePaquetSwipe(),
  'statut-litige.json': vecteursStatutLitige(),
  'alertes-recherche-missions.json': vecteursAlertesRecherche(),
  'semaines-disponibilites.json': vecteursSemainesDisponibilites(),
  'copie-bulletin-validation.json': vecteursCopieBulletinValidation(),
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
