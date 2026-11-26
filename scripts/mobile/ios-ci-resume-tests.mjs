#!/usr/bin/env node
/**
 * Relevé des tests de chaque éclat XCUITest de la CI iOS (jobs `ui` et `ui-lot1` de
 * `.github/workflows/ios-swift-ci.yml`, étape « Résumé xcresult (assertions, pas de succès fabriqué) »).
 *
 * Pourquoi (run 45239724447, `main` à `f6e6be49`, UI — ipad-portrait, éclat « pointage ») : à la tentative 2, l'éclat a
 * été coupé à sa limite de 30 min. Le `grep … | tail -n 60` de son étape n'a donc jamais tourné, et le résumé du job
 * disait seulement « 8 réussis, 2 échoués » : ni le nom des deux tests, ni leur durée, ni le message d'échec. Le journal
 * xcodebuild de l'éclat et les relevés du veilleur n'étaient lisibles que dans un artefact de 832 Mo.
 *
 * Pour chaque éclat nommé en argument, le script écrit dans le résumé du job, au journal et en annotation :
 *   - les tests échoués : nom, durée, premier message d'échec tronqué (`xcrun xcresulttool get test-results tests`, l'outil
 *     de l'étape ; à défaut d'un arbre lisible, le journal `test-without-building-<éclat>.log`) ;
 *   - les trois tests les plus longs ;
 *   - le temps passé des tests échoués, restés sans conclusion ou de plus de 5 min : marques d'attente d'inactivité de
 *     XCTest comptées dans le journal (« App event loop idle notification not received »…) et plus longs silences entre
 *     deux lignes d'activité, attribués à l'activité qui précède ;
 *   - la garde de repos XCUITest (`ios-native/JoleneUITests/GardeRepos.swift`, « Garde de repos XCUITest — 26/11/2026 »
 *     de `docs/mobile-swift/DECISIONS_LOT2.md`) : lignes « Jolene diagnostic repos-xcuitest » du journal, en
 *     avertissement (attentes des animations expirées puis suspendues pour un processus d'app ; garde non installée) ;
 *   - les relevés du veilleur (`scripts/mobile/ios-ci-gel-simulateur.sh veiller`) : passes, pile la plus fréquente du fil
 *     principal de chaque `sample` ; et les Spindump que XCTest joint à un test qui dépasse son délai d'exécution, copiés
 *     dans `diagnostic/` pour l'artefact léger du job.
 * L'arbre lu est gardé dans `xctest-tests-<éclat>.json` (durée de chaque test), publié par le même artefact léger.
 *
 * Relevé d'information, à une exception près : il ne décide du statut du job que si la garde de repos a absorbé plus de
 * `SEUIL_ABSORPTIONS_PAR_JOB` processus d'app dans le job. Il rend alors
 * `CODE_ABSORPTIONS_EXCESSIVES`, avec une erreur qui nomme les tests (« probable animation sans fin dans l'app ») ;
 * sinon toujours 0. L'étape l'appelle par `trap … EXIT`, pour qu'il tourne quelle que soit l'issue de l'étape (bundle
 * absent, tests en échec) ; le trap ne propage que `CODE_ABSORPTIONS_EXCESSIVES`, et seulement si l'étape réussissait
 * (un test échoué reste échoué dans tous les cas). Garde : `tests/node/ios-swift-ci-eclats.node.mjs` ; tests :
 * `scripts/mobile/ios-ci-resume-tests.test.mjs` (job « Cœur »).
 *
 * Usage : node scripts/mobile/ios-ci-resume-tests.mjs <éclat> [<éclat>…]
 * Environnement : JOLENE_UI_FORMAT, JOLENE_UI_OUTPUT (journaux, pièces jointes, relevés du veilleur), RUNNER_TEMP
 * (bundles `ui-<format>-<éclat>.xcresult`), GITHUB_STEP_SUMMARY. Aucun réseau, aucun secret.
 */
import { spawnSync } from 'node:child_process';
import { appendFileSync, copyFileSync, existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const RACINE = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Longueur maximale du premier message d'échec recopié (résumé et annotation). */
export const TRONCATURE_MESSAGE = 300;
/** Un test réussi d'au moins cette durée voit son temps passé relevé (délai d'exécution d'un test : 600 s). */
export const SEUIL_TEST_LONG_S = 300;
/** Silence minimal entre deux lignes d'activité du journal pour être relevé. */
export const SEUIL_SILENCE_S = 20;
/**
 * Marques du journal xcodebuild comptées par test : attentes d'inactivité de XCTest restées sans réponse, et les marques
 * de gel de `ios-ci-gel-simulateur.sh`. Comptées sans tenir compte de la casse, une fois par ligne.
 */
export const MARQUES_INACTIVITE = [
  'App event loop idle notification not received',
  'App animations complete notification not received',
  'main thread busy',
  'failed to quiesce',
  'Failed to get launch progress',
  'Timed out while evaluating UI query',
  'exceeded execution time allowance',
];
/** Marque des lignes de la garde de repos XCUITest (`GardeReposDecision.marque`). */
export const MARQUE_GARDE_REPOS = 'Jolene diagnostic repos-xcuitest';
/**
 * Absorptions de la garde tolérées par job (processus d'app suspendus, une ligne chacun), tous éclats du job.
 * Comptage du 26/11/2026 sur les 103 jobs UI terminés des 120 dernières séries : au plus UNE
 * attente des animations expirée par job (5 jobs sur 103, chacun un seul test : `clavier-ok` sur iPad, plus un cas
 * isolé de la messagerie). Une animation sans fin introduite dans l'app frapperait au contraire chaque test qui passe
 * par son écran : au-delà de trois par job, la série doit rougir.
 */
export const SEUIL_ABSORPTIONS_PAR_JOB = 3;
/** Code de sortie du relevé quand le seuil est dépassé (le seul que le trap de l'étape propage). */
export const CODE_ABSORPTIONS_EXCESSIVES = 8;
const MAX_ECHOUES = 40;
const MAX_DETAILS = 15;
const MAX_ANNOTATIONS = 10;
const MAX_CADRES = 8;

// MARK: - Durées

const UNITES = { d: 86_400, h: 3_600, m: 60, s: 1, ms: 0.001 };

/** Durée lisible de xcresulttool (« 1m 33s », « 2h 1m 3s », « 0.25s ») en secondes ; null si elle n'est pas lisible. */
export function parserDuree(texte) {
  if (typeof texte !== 'string') return null;
  let total = 0;
  let lus = 0;
  for (const m of texte.matchAll(/(\d+(?:[.,]\d+)?)\s*(ms|d|h|m|s)(?![a-z])/gi)) {
    total += Number(m[1].replace(',', '.')) * UNITES[m[2].toLowerCase()];
    lus += 1;
  }
  return lus ? total : null;
}

/** Durée d'un nœud de l'arbre : `durationInSeconds` (nombre), à défaut `duration` (texte). */
export function dureeDuNoeud(noeud) {
  if (Number.isFinite(noeud?.durationInSeconds)) return noeud.durationInSeconds;
  return parserDuree(noeud?.duration);
}

const deuxChiffres = n => String(n).padStart(2, '0');
const decimale = n => n.toFixed(1).replace('.', ',');

/** « 45,5 s », « 1 min 33 s », « 1 h 02 min 05 s » ; « durée inconnue » sans nombre. */
export function formaterDuree(secondes) {
  if (!Number.isFinite(secondes)) return 'durée inconnue';
  if (Math.round(secondes * 10) / 10 < 60) return `${decimale(secondes)} s`;
  const total = Math.round(secondes);
  const h = Math.floor(total / 3_600);
  const m = Math.floor((total % 3_600) / 60);
  const s = total % 60;
  return h ? `${h} h ${deuxChiffres(m)} min ${deuxChiffres(s)} s` : `${m} min ${deuxChiffres(s)} s`;
}

// MARK: - Arbre de `xcresulttool get test-results tests`

function premierMessage(noeud) {
  for (const enfant of noeud?.children ?? []) {
    if (enfant?.nodeType === 'Failure Message' && typeof enfant.name === 'string') return enfant.name;
    const plusBas = premierMessage(enfant);
    if (plusBas !== null) return plusBas;
  }
  return null;
}

/**
 * Tests de l'arbre (`testNodes`, nœuds « Test Case ») : clé `Classe.test`, résultat, durée en secondes, premier message
 * d'échec (nœud « Failure Message », y compris sous un nœud d'appareil ou de répétition). Un arbre absent ou étranger
 * rend une liste vide.
 */
export function testsDeLArbre(arbre) {
  const tests = [];
  const parcourir = (noeud, suite, cible) => {
    if (!noeud || typeof noeud !== 'object') return;
    const type = noeud.nodeType;
    if (type === 'Test Case') {
      const nom = String(noeud.name ?? '').replace(/\(\)$/, '');
      const identifiant = typeof noeud.nodeIdentifier === 'string' ? noeud.nodeIdentifier.replace(/\(\)$/, '') : null;
      const classe = identifiant?.includes('/') ? identifiant.slice(0, identifiant.lastIndexOf('/')) : suite ?? '?';
      tests.push({
        cle: `${classe}.${nom}`, classe, nom, cible: cible ?? '?', resultat: noeud.result ?? 'unknown',
        duree: dureeDuNoeud(noeud), message: premierMessage(noeud),
      });
      return;
    }
    const suiteSuivante = type === 'Test Suite' ? noeud.name : suite;
    const cibleSuivante = typeof type === 'string' && / test bundle$/.test(type) ? noeud.name : cible;
    for (const enfant of Array.isArray(noeud.children) ? noeud.children : []) parcourir(enfant, suiteSuivante, cibleSuivante);
  };
  for (const racine of Array.isArray(arbre?.testNodes) ? arbre.testNodes : []) parcourir(racine, null, null);
  return tests;
}

// MARK: - Journal xcodebuild (`test-without-building-<éclat>.log`)

const DEBUT = /^Test Case '-\[(\S+?)\.(\S+) (\S+)\]' started\.\s*$/;
const FIN = /^Test Case '-\[(\S+?)\.(\S+) (\S+)\]' (passed|failed) \(([\d.]+) seconds\)\.\s*$/;
const ACTIVITE = /^\s+t =\s*([\d.]+)s (.*)$/;
const ERREUR = /^(.*?):(\d+): error: -\[(\S+?)\.(\S+) (\S+)\] : (.*)$/;
const MARQUES_MINUSCULES = MARQUES_INACTIVITE.map(m => [m, m.toLowerCase()]);

/**
 * Tests du journal, dans l'ordre : issue (`passed`, `failed` ou null), durée, première erreur, marques d'attente
 * comptées, trois plus longs silences entre deux lignes d'activité « t = …s » (attribués à l'activité qui précède, la
 * fin du test comprise) et nombre de silences d'au moins `SEUIL_SILENCE_S`. Un test démarré sans ligne de conclusion est
 * `sansConclusion` ; s'il est le dernier du journal, `enCoursALaFin` (étape coupée pendant ce test).
 */
export function lireJournal(texte) {
  const tests = new Map();
  const installation = [];
  let courant = null;
  let precedent = null;
  const noter = (info, silence) => {
    if (silence.duree < SEUIL_SILENCE_S) return;
    info.silencesTotal += 1;
    info.silences.push(silence);
    // Tri stable : à durée égale (au millième), le premier silence du test reste devant.
    info.silences.sort((a, b) => Math.round((b.duree - a.duree) * 1000) || a.t - b.t);
    if (info.silences.length > 3) info.silences.length = 3;
  };
  const clore = (info, issue, duree) => {
    info.issue = issue;
    info.duree = duree;
    info.sansConclusion = issue === null;
    if (issue !== null && Number.isFinite(duree) && precedent) {
      noter(info, { duree: duree - precedent.t, apres: precedent.texte, t: precedent.t, fin: true });
    }
  };
  for (const ligne of String(texte ?? '').split('\n')) {
    const debut = DEBUT.exec(ligne);
    if (debut) {
      if (courant) clore(courant, null, null);
      courant = {
        cle: `${debut[2]}.${debut[3]}`, cible: debut[1], classe: debut[2], nom: debut[3], issue: null, duree: null, erreur: null,
        marques: new Map(), silences: [], silencesTotal: 0, activites: 0, dernierT: null, derniereActivite: null,
        sansConclusion: true, enCoursALaFin: false, gardeRepos: [],
      };
      tests.set(courant.cle, courant);
      precedent = null;
      continue;
    }
    if (!courant) continue;
    const fin = FIN.exec(ligne);
    if (fin && `${fin[2]}.${fin[3]}` === courant.cle) {
      clore(courant, fin[4], Number(fin[5]));
      courant = null;
      precedent = null;
      continue;
    }
    const minuscules = ligne.toLowerCase();
    for (const [marque, cherchee] of MARQUES_MINUSCULES) {
      if (minuscules.includes(cherchee)) courant.marques.set(marque, (courant.marques.get(marque) ?? 0) + 1);
    }
    // Ligne de la garde écrite par `print` hors du fil principal (sans « t = … s ») : lue aussi, sans instant.
    if (!ACTIVITE.test(ligne) && ligne.trim().startsWith(MARQUE_GARDE_REPOS)) {
      const libre = ligne.trim();
      if (libre.includes('garde de repos')) installation.push(libre);
      else courant.gardeRepos.push({ t: null, ligne: libre });
      continue;
    }
    const activite = ACTIVITE.exec(ligne);
    if (activite) {
      const t = Number(activite[1]);
      const libelle = activite[2].trim();
      // Garde de repos : une ligne par processus d'app suspendu (attente des animations expirée), et son état de pose
      // au premier test de l'éclat.
      if (libelle.startsWith(MARQUE_GARDE_REPOS)) {
        if (libelle.includes('garde de repos')) installation.push(libelle);
        else courant.gardeRepos.push({ t, ligne: libelle });
      }
      if (precedent) noter(courant, { duree: t - precedent.t, apres: precedent.texte, t: precedent.t, fin: false });
      precedent = { t, texte: libelle };
      courant.activites += 1;
      courant.dernierT = t;
      courant.derniereActivite = libelle;
      continue;
    }
    const erreur = ERREUR.exec(ligne);
    if (erreur && !courant.erreur && `${erreur[4]}.${erreur[5]}` === courant.cle) {
      courant.erreur = { fichier: erreur[1], ligne: Number(erreur[2]), message: erreur[6] };
    }
  }
  if (courant) {
    clore(courant, null, null);
    courant.enCoursALaFin = true;
  }
  return { tests, installation };
}

// MARK: - Relevés du veilleur (`sample`)

/**
 * Pile la plus fréquente du fil principal d'un rapport `sample` : nombre d'échantillons du fil, de la feuille retenue,
 * et cadres « symbole (bibliothèque) », feuille en tête. À chaque niveau du graphe d'appels, la branche la plus lourde
 * est suivie. null si le texte n'est pas un rapport lisible (processus introuvable, `sample` en échec).
 */
export function pileDominante(texte) {
  const lignes = String(texte ?? '').split('\n');
  const tete = lignes.findIndex(l => /^\s+\d+ Thread_\S+.*com\.apple\.main-thread/.test(l));
  if (tete < 0) return null;
  const echantillons = Number(/^\s+(\d+) Thread_/.exec(lignes[tete])[1]);
  const racine = { profondeur: -1, compte: echantillons, enfants: [] };
  const pile = [racine];
  for (const ligne of lignes.slice(tete + 1)) {
    if (/^\s+\d+ Thread_/.test(ligne) || ligne.trim() === '') break;
    const cadre = /^([\s+!:|]*?)(\d+) (.+)$/.exec(ligne);
    if (!cadre) continue;
    const reste = cadre[3];
    const symbole = reste.split('  (in ')[0].trim();
    const bibliotheque = /\(in ([^)]+)\)/.exec(reste)?.[1];
    const noeud = {
      profondeur: cadre[1].length, compte: Number(cadre[2]), enfants: [],
      nom: bibliotheque ? `${symbole} (${bibliotheque})` : symbole,
    };
    while (pile.length > 1 && pile.at(-1).profondeur >= noeud.profondeur) pile.pop();
    pile.at(-1).enfants.push(noeud);
    pile.push(noeud);
  }
  const cadres = [];
  let noeud = racine;
  while (noeud.enfants.length) {
    noeud = noeud.enfants.reduce((lourd, enfant) => (enfant.compte > lourd.compte ? enfant : lourd));
    cadres.unshift(noeud.nom);
  }
  return cadres.length ? { echantillons, feuille: noeud.compte, cadres } : null;
}

// MARK: - Relevé d'un éclat

const replier = texte => String(texte).replace(/\s+/g, ' ').trim();
const tronquer = texte => {
  const net = replier(texte);
  return net.length > TRONCATURE_MESSAGE ? `${net.slice(0, TRONCATURE_MESSAGE)}…` : net;
};

/**
 * Relevé d'un éclat. Source : l'arbre xcresult s'il porte au moins un test, sinon le journal xcodebuild (`lecture` dit
 * alors pourquoi l'arbre manque), sinon rien. Les indications du journal (sans conclusion, marques, silences) complètent
 * toujours les tests de l'arbre, et un test resté sans conclusion au journal mais absent de l'arbre est ajouté.
 */
export function resumerEclat({ nom, arbre = null, lecture = null, journal = null, veilleur = null, spindumps = [] }) {
  const lu = journal === null || journal === undefined ? null : lireJournal(journal);
  const duJournal = lu?.tests ?? null;
  const deLArbre = testsDeLArbre(arbre);
  let source = null;
  let motif = lecture;
  let tests = [];
  if (deLArbre.length) {
    source = 'xcresult';
    tests = deLArbre.map(t => {
      const info = duJournal?.get(t.cle) ?? null;
      return { ...t, duree: t.duree ?? info?.duree ?? null, echoue: t.resultat === 'Failed', journal: info };
    });
    const connus = new Set(tests.map(t => t.cle));
    for (const info of duJournal?.values() ?? []) {
      if (info.sansConclusion && !connus.has(info.cle)) {
        tests.push({ cle: info.cle, classe: info.classe, nom: info.nom, cible: info.cible, resultat: 'Sans conclusion',
          duree: null, message: null, echoue: true, journal: info });
      }
    }
  } else if (duJournal?.size) {
    source = 'journal';
    motif = lecture ?? 'aucun test dans l’xcresult';
    tests = [...duJournal.values()].map(info => ({
      cle: info.cle, classe: info.classe, nom: info.nom, cible: info.cible,
      resultat: info.issue === 'passed' ? 'Passed' : info.issue === 'failed' ? 'Failed' : 'Sans conclusion',
      duree: info.duree, message: info.erreur ? `${basename(info.erreur.fichier)}:${info.erreur.ligne}: ${info.erreur.message}` : null,
      echoue: info.issue !== 'passed', journal: info,
    }));
  }
  for (const t of tests) {
    t.message = t.message === null || t.message === undefined ? null : tronquer(t.message);
    t.sansConclusion = t.journal?.sansConclusion ?? false;
    t.enCoursALaFin = t.journal?.enCoursALaFin ?? false;
  }
  const mesures = tests.filter(t => Number.isFinite(t.duree));
  return {
    nom, source, lecture: motif, journalAbsent: duJournal === null,
    total: tests.length,
    dureeTotale: mesures.reduce((somme, t) => somme + t.duree, 0),
    echoues: tests.filter(t => t.echoue),
    plusLongs: [...mesures].sort((a, b) => b.duree - a.duree).slice(0, 3),
    details: tests.filter(t => t.journal && (t.echoue || t.sansConclusion || (Number.isFinite(t.duree) && t.duree >= SEUIL_TEST_LONG_S))),
    veilleur: veilleur ?? { passes: [], piles: [] },
    spindumps,
    gardeRepos: {
      installation: lu?.installation ?? [],
      expirations: [...(duJournal?.values() ?? [])].flatMap(info => info.gardeRepos.map(g => ({ test: info.cle, ...g }))),
    },
  };
}

// MARK: - Rendu (résumé du job, journal, annotations)

// Échappements des commandes de workflow GitHub (message, puis propriétés) et des cellules Markdown : mêmes règles
// que l'étape « Attentes bloquées absorbées » du workflow.
const esc = v => String(v).replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
const prop = v => esc(v).replace(/:/g, '%3A').replace(/,/g, '%2C');
const cell = v => String(v).replace(/\|/g, '\\|').replace(/\s+/g, ' ');
const instant = t => `t = ${decimale(t)} s`;

function dureeAffichee(t) {
  const duree = formaterDuree(t.duree);
  if (t.enCoursALaFin) {
    const derniere = Number.isFinite(t.journal?.dernierT) ? ` (dernière activité à ${instant(t.journal.dernierT)})` : '';
    return `${duree} ; en cours quand le journal de l’éclat s’arrête${derniere}`;
  }
  return t.sansConclusion ? `${duree} ; sans conclusion au journal de l’éclat` : duree;
}

/** Fichier et ligne de l'annotation : l'erreur du journal, sinon le préfixe « Fichier.swift:N: » d'un fichier du dépôt. */
function cibleAnnotation(t, racine) {
  const erreur = t.journal?.erreur;
  if (erreur) {
    const i = erreur.fichier.lastIndexOf('/ios-native/');
    if (i >= 0) return { fichier: erreur.fichier.slice(i + 1), ligne: erreur.ligne };
  }
  const prefixe = /^([\w+-]+\.swift):(\d+):/.exec(t.message ?? '');
  if (prefixe && existsSync(join(racine, 'ios-native/JoleneUITests', prefixe[1]))) {
    return { fichier: `ios-native/JoleneUITests/${prefixe[1]}`, ligne: Number(prefixe[2]) };
  }
  return null;
}

function tempsPasse(t) {
  const morceaux = [];
  const info = t.journal;
  if (info.marques.size) {
    morceaux.push(`attentes expirées au journal : ${[...info.marques].map(([marque, n]) => `« ${marque} » × ${n}`).join(', ')}`);
  }
  if (info.silences.length) {
    const plusLongs = info.silences.map(s => `${decimale(s.duree)} s après « ${s.apres} » (${instant(s.t)}${s.fin ? ', jusqu’à la fin du test' : ''})`);
    const nombre = `${info.silencesTotal} silence${info.silencesTotal > 1 ? 's' : ''} d’au moins ${SEUIL_SILENCE_S} s`;
    morceaux.push(`${nombre}${info.silencesTotal > plusLongs.length ? ', les plus longs' : ''} : ${plusLongs.join(', ')}`);
  }
  if (!morceaux.length) {
    morceaux.push(info.activites
      ? `aucune attente expirée ni silence d’au moins ${SEUIL_SILENCE_S} s au journal (${info.activites} lignes d’activité)`
      : 'aucune ligne d’activité au journal pour ce test');
  }
  return morceaux.join(' ; ');
}

const etat = t => (t.enCoursALaFin ? 'en cours à la fin du journal' : t.sansConclusion ? 'sans conclusion' : t.echoue ? 'échoué' : 'réussi');

/** Lignes Markdown du relevé et annotations `::error` des tests échoués (dix au plus, la suite est dans le résumé). */
export function rendre({ format, eclats, racine = RACINE }) {
  const lignes = ['', `#### Tests échoués et tests les plus longs — ${format}`, '',
    '| Éclat | Tests | Durée cumulée des tests | Échoués | Trois tests les plus longs | Source |', '| --- | --- | --- | --- | --- | --- |'];
  for (const e of eclats) {
    if (!e.source) {
      const journal = e.journalAbsent ? 'journal absent' : 'journal sans test';
      lignes.push(`| ${cell(e.nom)} | — | — | — | — | ${cell(`aucun test lu (${e.lecture ?? 'xcresult sans test'} ; ${journal})`)} |`);
      continue;
    }
    const plusLongs = e.plusLongs.map(t => `\`${cell(t.cle)}\` ${formaterDuree(t.duree)}`).join(' ; ') || '—';
    const source = e.source === 'xcresult' ? 'xcresult' : `journal xcodebuild (${e.lecture})`;
    lignes.push(`| ${cell(e.nom)} | ${e.total} | ${formaterDuree(e.dureeTotale)} | ${e.echoues.length} | ${plusLongs} | ${cell(source)} |`);
  }

  const echoues = eclats.flatMap(e => e.echoues.map(t => ({ e, t })));
  const annotations = [];
  lignes.push('');
  if (!echoues.length) {
    lignes.push(eclats.some(e => e.source) ? 'Aucun test échoué dans les éclats lus.' : 'Aucun éclat lu : tests échoués NON relevés par ce run.');
  } else {
    lignes.push(`**Tests échoués : ${echoues.length}**`, '', '| Éclat | Test | Durée | Premier message d’échec |', '| --- | --- | --- | --- |');
    for (const { e, t } of echoues.slice(0, MAX_ECHOUES)) {
      const message = t.message ?? (e.source === 'xcresult' ? 'aucun message d’échec dans l’xcresult' : 'aucune ligne d’erreur au journal');
      lignes.push(`| ${cell(e.nom)} | \`${cell(t.cle)}\` | ${cell(dureeAffichee(t))} | ${cell(message)} |`);
      if (annotations.length < MAX_ANNOTATIONS) {
        const cible = cibleAnnotation(t, racine);
        const proprietes = cible ? ` file=${prop(cible.fichier)},line=${prop(cible.ligne)}` : '';
        annotations.push(`::error${proprietes}::${esc(`Test échoué (${format}, éclat ${e.nom}) : ${t.cle}, ${dureeAffichee(t)} — ${message}`)}`);
      }
    }
    if (echoues.length > MAX_ECHOUES) lignes.push('', `… et ${echoues.length - MAX_ECHOUES} autres tests échoués (voir l’artefact xcresult).`);
  }

  const details = eclats.flatMap(e => e.details.map(t => ({ e, t })));
  if (details.length) {
    lignes.push('', `**Où le temps est passé** (tests échoués, sans conclusion ou d’au moins ${SEUIL_TEST_LONG_S / 60} min ; journal xcodebuild de l’éclat)`, '');
    for (const { e, t } of details.slice(0, MAX_DETAILS)) {
      lignes.push(`- ${e.nom} — \`${t.cle}\` (${formaterDuree(t.duree)}, ${etat(t)}) : ${replier(tempsPasse(t))}`);
    }
    if (details.length > MAX_DETAILS) lignes.push(`- … et ${details.length - MAX_DETAILS} autres tests (journaux des éclats dans l’artefact léger du job).`);
  }

  // Garde de repos XCUITest : avertissements, jamais une erreur (on doit voir la fréquence, pas masquer un échec).
  const garde = eclats.flatMap(e => (e.gardeRepos?.expirations ?? []).map(g => ({ e, g })));
  const nonPosee = eclats.flatMap(e => (e.gardeRepos?.installation ?? []).filter(l => l.includes('non installée')).map(l => ({ e, l })));
  if (garde.length || nonPosee.length) {
    const tests = [...new Set(garde.map(({ g }) => g.test))];
    lignes.push('', `**Garde de repos XCUITest** : ${garde.length} attente${garde.length > 1 ? 's' : ''} des animations expirée${garde.length > 1 ? 's' : ''} puis suspendue${garde.length > 1 ? 's' : ''} pour le processus d’app${tests.length ? ` (${tests.length} test${tests.length > 1 ? 's' : ''})` : ''}`, '');
    for (const { e, g } of garde.slice(0, MAX_DETAILS)) {
      lignes.push(`- ${e.nom} — \`${cell(g.test)}\`${Number.isFinite(g.t) ? ` (${instant(g.t)})` : ''} : ${replier(g.ligne)}`);
    }
    if (garde.length > MAX_DETAILS) lignes.push(`- … et ${garde.length - MAX_DETAILS} autres (journaux des éclats dans l’artefact léger du job).`);
    for (const { e, l } of nonPosee) lignes.push(`- ${e.nom} — ${replier(l)}`);
    for (const { e, g } of garde.slice(0, MAX_ANNOTATIONS)) {
      annotations.push(`::warning::${esc(`Garde de repos (${format}, éclat ${e.nom}) : ${g.test} — ${replier(g.ligne)}`)}`);
    }
    for (const { e, l } of nonPosee.slice(0, MAX_ANNOTATIONS)) annotations.push(`::warning::${esc(`Garde de repos (${format}, éclat ${e.nom}) : ${replier(l)}`)}`);
  }
  // Absorption bornée : au-delà du seuil, erreur nette et code de sortie non nul.
  const absorptions = garde;
  const excessif = absorptions.length > SEUIL_ABSORPTIONS_PAR_JOB;
  if (excessif) {
    const noms = [...new Set(absorptions.map(({ g }) => g.test))];
    const message = `Garde de repos (${format}) : ${absorptions.length} processus d’app absorbés dans ce job, au-delà de ${SEUIL_ABSORPTIONS_PAR_JOB} — `
      + `probable animation sans fin dans l’app, la garde ne doit pas l’absorber. Tests : ${noms.join(', ')}`;
    lignes.push('', `**${message}**`);
    annotations.unshift(`::error::${esc(message)}`);
  }

  const releves = eclats.flatMap(e => [
    ...e.veilleur.passes.map(passe => `- ${e.nom} — ${replier(passe)}`),
    ...e.veilleur.piles.map(({ fichier, pile }) => `- ${e.nom} — \`${fichier}\`, fil principal : ${pile.feuille} échantillons sur ${pile.echantillons} dans ${pile.cadres.slice(0, MAX_CADRES).join(' ← ')}`),
    ...e.spindumps.map(s => `- ${e.nom} — Spindump de XCTest (délai d’exécution dépassé) joint à \`${s.test}\` : \`${s.copie ?? s.fichier}\``),
  ]);
  if (releves.length) lignes.push('', '**Relevés du veilleur et de XCTest** (fichiers dans l’artefact léger du job)', '', ...releves);
  return { lignes, annotations, code: excessif ? CODE_ABSORPTIONS_EXCESSIVES : 0 };
}

// MARK: - Lecture des fichiers de l'étape

const lire = chemin => {
  try { return readFileSync(chemin, 'utf8'); } catch { return null; }
};

/**
 * `xcrun xcresulttool get test-results tests --path <bundle>` : l'arbre, ou la raison pour laquelle il manque. La sortie
 * lisible est gardée dans `copie` (`xctest-tests-<éclat>.json`, à côté de `xctest-summary-<éclat>.json`) : durée de
 * chaque test de l'éclat, lisible dans l'artefact léger sans le bundle.
 */
function lireArbre(bundle, env, copie) {
  if (!existsSync(bundle)) return { arbre: null, lecture: 'bundle xcresult absent' };
  // 90 s par bundle : la lecture prend quelques secondes ; un outil bloqué ne retient pas l'étape (repli sur le journal).
  const delai = Number(env.JOLENE_RESUME_DELAI_XCRESULTTOOL_MS) > 0 ? Number(env.JOLENE_RESUME_DELAI_XCRESULTTOOL_MS) : 90_000;
  const r = spawnSync('xcrun', ['xcresulttool', 'get', 'test-results', 'tests', '--path', bundle],
    { encoding: 'utf8', env, timeout: delai, maxBuffer: 512 * 1024 * 1024 });
  if (r.error?.code === 'ETIMEDOUT' || r.signal) return { arbre: null, lecture: `xcresulttool interrompu après ${decimale(delai / 1000)} s` };
  if (r.error) return { arbre: null, lecture: `xcresulttool non lancé (${r.error.code ?? r.error.message})` };
  if (r.status !== 0) return { arbre: null, lecture: `xcresulttool a échoué (code ${r.status})` };
  let arbre = null;
  try { arbre = JSON.parse(r.stdout); } catch { return { arbre: null, lecture: 'sortie de xcresulttool illisible' }; }
  try { writeFileSync(copie, r.stdout); } catch { /* copie de confort : son échec ne change pas le relevé */ }
  return { arbre, lecture: null };
}

function lireVeilleur(sortie, eclat) {
  const journal = lire(join(sortie, `gel-${eclat}-veilleur.log`)) ?? '';
  const passes = journal.split('\n').filter(l => /^Passe \d+ du veilleur/.test(l)).slice(0, 6);
  const piles = [];
  for (const n of [1, 2, 3]) {
    for (const genre of ['sample', 'backboardd-sample', 'springboard-sample']) {
      const fichier = `gel-${eclat}-${genre}-${n}.txt`;
      const pile = pileDominante(lire(join(sortie, fichier)));
      if (pile) piles.push({ fichier, pile });
    }
  }
  return { passes, piles };
}

/** Spindump joints par XCTest (manifest.json des pièces jointes exportées), copiés dans `diagnostic/`. */
function lireSpindumps(sortie, eclat) {
  let manifeste = null;
  try { manifeste = JSON.parse(readFileSync(join(sortie, 'attachments', eclat, 'manifest.json'), 'utf8')); } catch { manifeste = null; }
  const spindumps = [];
  for (const t of Array.isArray(manifeste) ? manifeste : []) {
    for (const a of t?.attachments ?? []) {
      if (!/spindump/i.test(a?.suggestedHumanReadableName ?? '') || !a.exportedFileName) continue;
      const fichier = `attachments/${eclat}/${a.exportedFileName}`;
      let copie = `diagnostic/spindump-${eclat}-${spindumps.length + 1}.txt`;
      try {
        mkdirSync(join(sortie, 'diagnostic'), { recursive: true });
        copyFileSync(join(sortie, fichier), join(sortie, copie));
      } catch { copie = null; }
      spindumps.push({ test: t.testIdentifier ?? '?', fichier, copie });
    }
  }
  return spindumps;
}

/** Relevé de chaque éclat, lu dans les fichiers de l'étape ; une lecture en échec n'en empêche aucune autre. */
export function collecter({ eclats, format, sortie, bundles, env = process.env }) {
  return eclats.map(nom => {
    const { arbre, lecture } = lireArbre(join(bundles, `ui-${format}-${nom}.xcresult`), env, join(sortie, `xctest-tests-${nom}.json`));
    return resumerEclat({
      nom, arbre, lecture, journal: lire(join(sortie, `test-without-building-${nom}.log`)),
      veilleur: lireVeilleur(sortie, nom), spindumps: lireSpindumps(sortie, nom),
    });
  });
}

const AVERTISSEMENT = 'Résumé des tests par éclat non établi';

/**
 * Rend 0, sauf absorptions de la garde au-delà du seuil (`CODE_ABSORPTIONS_EXCESSIVES`) : un relevé manquant reste un
 * avertissement, jamais un échec de l'étape.
 */
export function main(argv = process.argv.slice(2), env = process.env) {
  let code = 0;
  try {
    const eclats = argv.filter(a => !a.startsWith('-'));
    const { JOLENE_UI_OUTPUT: sortie, RUNNER_TEMP: bundles } = env;
    if (!eclats.length || !sortie || !bundles) {
      console.log(`::warning::${AVERTISSEMENT} : éclats, JOLENE_UI_OUTPUT ou RUNNER_TEMP manquants (scripts/mobile/ios-ci-resume-tests.mjs).`);
      return 0;
    }
    const format = env.JOLENE_UI_FORMAT || '?';
    const rendu = rendre({ format, eclats: collecter({ eclats, format, sortie, bundles, env }) });
    const { lignes, annotations } = rendu;
    code = rendu.code;
    console.log(lignes.join('\n'));
    for (const annotation of annotations) console.log(annotation);
    if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${lignes.join('\n')}\n`);
  } catch (erreur) {
    console.log(`::warning::${esc(`${AVERTISSEMENT} : ${erreur?.message ?? erreur} (scripts/mobile/ios-ci-resume-tests.mjs).`)}`);
  }
  return code;
}

const lanceDirectement = () => {
  try {
    return Boolean(process.argv[1]) && pathToFileURL(realpathSync(process.argv[1])).href === import.meta.url;
  } catch {
    return false;
  }
};
if (lanceDirectement()) process.exitCode = main();
