#!/usr/bin/env node
/**
 * Garde du filtre de chemins de la CI iOS (incident #1137 du 17 novembre 2026).
 *
 * Les tests Swift de `ios-native/` relisent des fichiers du dépôt hors `ios-native/` (pages et règles web, dump
 * `public.sql`, décisions du lot) : `CompletionVerbatimTests` relit chaque annotation `// source: fichier:ligne` de
 * `CompletionProfil.swift` à la ligne près, `SupabaseRevenusGatewayTests` lit `MesGains.tsx` ligne 95, etc. Une PR web
 * qui décale ou modifie un de ces fichiers casse ces tests ; si le fichier manque au filtre `paths` de
 * `.github/workflows/ios-swift-ci.yml`, la CI iOS ne tourne pas, la PR passe verte et `main` rougit plus tard : #1137
 * a décalé `InscriptionSoignant.tsx` et 50 tests de `CompletionVerbatimTests` ont échoué (corrigés par #1138).
 *
 * Est une lecture, dans tout fichier `.swift` de `ios-native/` :
 *   - un littéral de chaîne égal au chemin d'un fichier du dépôt hors `ios-native/` (`source("src/…")`,
 *     `static let hub = "src/pages/…"`) ;
 *   - une annotation `// source:`, `// source-objet:` ou `// source-ensemble:` (en début ou en fin de ligne) d'un
 *     fichier Swift dont le chemin (depuis la racine ou depuis `ios-native/`) figure lui-même en littéral dans du
 *     Swift : c'est ainsi que `CompletionVerbatimTests`
 *     relit `CompletionProfil.swift` et `InscriptionVerbatimTests` relit `InscriptionRules.swift`.
 * Les annotations d'un fichier Swift qu'aucun test ne relit sont de la documentation. C'est le cas de
 * `TextesWeb.swift` et `LibellesWeb.swift` : la garde tolérante `check-textes-juridiques-ios.mjs` les relit dans
 * validate-pr (check requis ; texte modifié en erreur, décalage de lignes en avertissement), aucun test Swift. Un test
 * Swift qui se mettrait à les relire rendrait leurs citations obligatoires dans le filtre.
 *
 * Les littéraux des commentaires comptent aussi : lecture par excès, un chemin périmé dans une doc est à corriger.
 *
 * Refusés : un littéral égal à un dossier (`"src/pages"`, `"src/pages/" + nom`) ou un chemin construit sous un dossier
 * racine (interpolation `\(…)`, `appendingPathComponent("src")`) : couverture inconnue ; un chemin cité introuvable
 * (littéral dont le dossier existe ou qui porte une extension de source, ou annotation d'un fichier relu) : les tests
 * Swift lèvent `XCTSkip` sur un fichier absent, une PR web qui le renomme ou le supprime passerait donc en silence.
 *
 * Chaque fichier lu doit correspondre à un motif des DEUX filtres (`pull_request` et `push`). Seuls `*` et `**` sont
 * interprétés ; `?`, `+`, `[…]` et `!` (quantificateurs et négation chez GitHub) et `paths-ignore` sont refusés.
 *
 * Coût assumé : élargir le filtre relance la CI iOS (macOS, ~3 h, délai maximal de 6 h pour le job `ui`) sur les PR
 * web qui touchent ces fichiers.
 * C'est le prix d'un couplage déjà présent dans les tests Swift ; le réduire, c'est rendre ces tests tolérants ou
 * les passer par la garde Node, pas retirer le fichier du filtre.
 *
 * Usage :
 *   node scripts/mobile/check-sources-web-ios-ci.mjs          # vérifie, code 1 si un fichier lu manque au filtre
 *   node scripts/mobile/check-sources-web-ios-ci.mjs --liste  # fichiers lus et leurs lecteurs Swift (Markdown)
 *
 * Aucun réseau, aucun secret : le script ne lit que des fichiers du dépôt (et `git ls-files`).
 */
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const SCRIPT = 'scripts/mobile/check-sources-web-ios-ci.mjs';
export const WORKFLOW_IOS = '.github/workflows/ios-swift-ci.yml';
export const TEST_NODE = 'tests/node/sources-web-ios-ci.node.mjs';
export const EVENEMENTS = ['pull_request', 'push'];
const NATIF = 'ios-native/';
/** Extensions d'un fichier source : un tel chemin introuvable est refusé même si son dossier a disparu. */
const EXTENSIONS_SOURCE = /\.(?:tsx?|jsx?|mjs|cjs|sql|md|json|css|html|ya?ml)$/;

// Motif GitHub → expression régulière : `*` hors `/`, `**/` zéro ou plusieurs dossiers, `**` tout le reste.
export function correspond(motif, chemin) {
  let re = '';
  for (let i = 0; i < motif.length; i += 1) {
    if (motif.startsWith('**/', i)) {
      re += '(?:.*/)?';
      i += 2;
    } else if (motif.startsWith('**', i)) {
      re += '.*';
      i += 1;
    } else if (motif[i] === '*') {
      re += '[^/]*';
    } else {
      re += motif[i].replace(/[.^$|?+()[\]{}\\]/g, '\\$&');
    }
  }
  return new RegExp(`^${re}$`).test(chemin);
}

function verifierMotif(motif, evenement) {
  if (/^!|[?+[\]]/.test(motif)) {
    throw new Error(`${WORKFLOW_IOS} : motif « ${motif} » (${evenement}) à syntaxe non gérée par ${SCRIPT} (seuls * et ** sont lus).`);
  }
  return motif;
}

/**
 * Motifs `paths` des événements `pull_request` et `push`, cherchés dans le bloc `on:` (absent : l'événement n'est pas
 * filtré, `**`). Seule la forme « `paths:` puis un `- 'motif'` par ligne » est lue ; toute autre écriture (liste en
 * ligne, ancre, alias, liste vide, élément inconnu) lève une erreur au lieu d'être lue comme « aucun filtre » ou
 * comme une liste tronquée (revue B8 de #1139).
 */
export function motifsDuFiltre(yml) {
  const lignes = yml.split('\n');
  const debutOn = lignes.findIndex(l => /^on:\s*(#.*)?$/.test(l));
  if (debutOn < 0) throw new Error(`${WORKFLOW_IOS} : bloc « on: » introuvable (seule la forme bloc est lue par ${SCRIPT}).`);
  let finOn = debutOn + 1;
  while (finOn < lignes.length && (lignes[finOn] === '' || /^[ #]/.test(lignes[finOn]))) finOn += 1;
  const blocOn = lignes.slice(debutOn + 1, finOn);
  const refus = (evenement, ligne, quoi) => new Error(`${WORKFLOW_IOS} : « ${ligne.trim()} » (${evenement}) : ${quoi} `
    + `non gérée par ${SCRIPT} ; écrivez « paths: » puis un « - 'chemin' » par ligne.`);
  const filtres = {};
  for (const evenement of EVENEMENTS) {
    const debut = blocOn.findIndex(l => new RegExp(`^ {2}${evenement}:\\s*(#.*)?$`).test(l));
    if (debut < 0) throw new Error(`${WORKFLOW_IOS} : événement ${evenement} introuvable dans « on: ».`);
    let fin = debut + 1;
    while (fin < blocOn.length && (blocOn[fin] === '' || /^ {3,}/.test(blocOn[fin]) || /^\s*#/.test(blocOn[fin]))) fin += 1;
    const bloc = blocOn.slice(debut + 1, fin);
    if (bloc.some(l => /^ {4}paths-ignore\s*:/.test(l))) {
      throw new Error(`${WORKFLOW_IOS} : paths-ignore (${evenement}) non géré par ${SCRIPT}.`);
    }
    const cles = bloc.flatMap((l, i) => (/^ {4}paths\s*:/.test(l) ? [i] : []));
    if (!cles.length) { filtres[evenement] = ['**']; continue; }
    if (cles.length > 1 || !/^ {4}paths:\s*(#.*)?$/.test(bloc[cles[0]])) {
      throw refus(evenement, bloc[cles.at(-1)], 'syntaxe (liste en ligne, ancre, alias ou clé répétée)');
    }
    const motifs = [];
    for (const ligne of bloc.slice(cles[0] + 1)) {
      if (/^\s*(#.*)?$/.test(ligne)) continue;
      if (/^ {4}\S/.test(ligne)) break;
      const item = /^ {6}- (?:'([^']*)'|"([^"]*)"|([^\s'"&*#!][^\s#]*))\s*(?:#.*)?$/.exec(ligne);
      if (!item) throw refus(evenement, ligne, 'syntaxe d’élément');
      motifs.push(verifierMotif(item[1] ?? item[2] ?? item[3], evenement));
    }
    if (!motifs.length) throw new Error(`${WORKFLOW_IOS} : paths (${evenement}) vide, non géré par ${SCRIPT}.`);
    filtres[evenement] = motifs;
  }
  return filtres;
}

const ajouter = (carte, cle, valeur) => {
  if (!carte.has(cle)) carte.set(cle, new Set());
  carte.get(cle).add(valeur);
};

/**
 * Fichiers hors `ios-native/` lus par du Swift. `swift` : `[{ chemin, texte }]` ; `fichiersDepot` : chemins suivis
 * du dépôt. Retourne `lectures` (fichier lu → lecteurs), `relus` (fichier Swift relu → lecteurs) et `erreurs`.
 */
export function lecturesDuSwift({ swift, fichiersDepot }) {
  const depot = new Set(fichiersDepot);
  const dossiers = new Set(fichiersDepot.flatMap(f => {
    const parties = f.split('/');
    return parties.slice(1).map((_, i) => parties.slice(0, i + 1).join('/'));
  }));
  const racines = new Set(fichiersDepot.filter(f => f.includes('/')).map(f => f.split('/')[0]));
  const lectures = new Map();
  const relus = new Map();
  const erreurs = [];
  const racineWeb = valeur => valeur !== 'ios-native' && racines.has(valeur);
  const parent = valeur => valeur.split('/').slice(0, -1).join('/');
  for (const { chemin, texte } of swift) {
    const nom = basename(chemin);
    // Contenu réduit à des caractères de chemin : un guillemet impair plus tôt sur la ligne ne décale pas la lecture.
    for (const [, brut] of texte.matchAll(/"([\w.-]+(?:\/[\w.-]+)+\/?|[\w.-]+\/)"/g)) {
      const valeur = brut.replace(/\/$/, '');
      const dossier = brut.endsWith('/');
      const natif = valeur.startsWith(NATIF) ? valeur : `${NATIF}${valeur}`;
      if (!dossier && natif.endsWith('.swift') && depot.has(natif)) { ajouter(relus, natif, chemin); continue; }
      if (!racineWeb(valeur.split('/')[0])) continue;
      if (!dossier && depot.has(valeur)) ajouter(lectures, valeur, nom);
      else if (dossiers.has(valeur)) {
        erreurs.push(`${nom} lit le dossier « ${brut} » : ${SCRIPT} ne sait pas quels fichiers il couvre ; citez chaque fichier lu en entier.`);
      } else if (dossiers.has(parent(valeur)) || EXTENSIONS_SOURCE.test(valeur)) {
        erreurs.push(`${nom} cite « ${valeur} », introuvable dans le dépôt : le test Swift lèverait XCTSkip et ne vérifierait plus rien ; corrigez le chemin.`);
      }
    }
    const construits = [
      // Interpolation au fil du chemin (`"src/pages/\(nom).tsx"`), pas après une espace (message d'XCTSkip).
      ...[...texte.matchAll(/"([\w.-]+)\/[\w.\/-]*\\\(/g)].map(m => m[1]),
      ...[...texte.matchAll(/appendingPathComponent\(\s*"([\w.-]+)"\s*\)/g)].map(m => m[1]),
    ].filter(racineWeb);
    for (const racine of construits) {
      erreurs.push(`${nom} lit un chemin construit sous « ${racine}/ » (interpolation ou segments) : ${SCRIPT} ne peut pas savoir quel fichier est lu ; écrivez le chemin en entier dans un seul littéral.`);
    }
  }
  const textes = new Map(swift.map(f => [f.chemin, f.texte]));
  for (const [relu, lecteurs] of relus) {
    const noms = [...lecteurs].map(l => basename(l)).sort();
    for (const [, cite] of (textes.get(relu) ?? '').matchAll(/\/\/ source(?:-objet|-ensemble)?: ([^\s:`]+):\d/g)) {
      if (cite.startsWith(NATIF)) continue;
      if (!depot.has(cite)) {
        erreurs.push(`${basename(relu)}, relu par ${noms.join(', ')}, cite « ${cite} », introuvable dans le dépôt : citez le chemin complet depuis la racine (sinon XCTSkip).`);
        continue;
      }
      for (const nom of noms) ajouter(lectures, cite, `${nom} (annotations de ${basename(relu)})`);
    }
  }
  return { lectures: new Map([...lectures].sort(([a], [b]) => a.localeCompare(b))), relus, erreurs };
}

/** Lectures du Swift confrontées aux deux filtres du workflow iOS. */
export function verifierFiltre({ swift, fichiersDepot, workflow }) {
  const filtres = motifsDuFiltre(workflow);
  const { lectures, relus, erreurs } = lecturesDuSwift({ swift, fichiersDepot });
  for (const [fichier, lecteurs] of lectures) {
    const absents = EVENEMENTS.filter(e => !filtres[e].some(m => correspond(m, fichier)));
    if (!absents.length) continue;
    const noms = [...lecteurs].sort().join(', ');
    erreurs.push(`${fichier} — lu par ${noms} ; absent du filtre ${absents.join(' et ')} de ${WORKFLOW_IOS} : une PR qui `
      + `le modifie ne relance pas ces tests Swift (incident #1137). Ajoutez-le aux paths de ${absents.join(' et ')}.`);
  }
  return { lectures, relus, erreurs };
}

function fichiersSuivis(racine) {
  const git = spawnSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], { cwd: racine, encoding: 'utf8' });
  if (git.status !== 0) throw new Error(`${SCRIPT} : git ls-files a échoué (${git.stderr || git.error?.message}).`);
  return git.stdout.split('\0').filter(Boolean);
}

/** Vérification sur le dépôt : Swift de `ios-native/`, fichiers suivis (`git ls-files`), workflow iOS. */
export function verifierDepot(racine = ROOT) {
  const fichiersDepot = fichiersSuivis(racine);
  const swift = fichiersDepot.filter(f => f.startsWith(NATIF) && f.endsWith('.swift'))
    .map(chemin => ({ chemin, texte: readFileSync(join(racine, chemin), 'utf8') }));
  const workflow = readFileSync(join(racine, WORKFLOW_IOS), 'utf8');
  return verifierFiltre({ swift, fichiersDepot, workflow });
}

export function main(argv = process.argv.slice(2)) {
  const { lectures, erreurs } = verifierDepot();
  if (argv.includes('--liste')) {
    console.log(`| Fichier lu | Lecteurs Swift |\n| --- | --- |`);
    for (const [fichier, lecteurs] of lectures) console.log(`| \`${fichier}\` | ${[...lecteurs].sort().join(', ')} |`);
  }
  for (const e of erreurs) console.error(`✖ ${e}`);
  if (erreurs.length) return 1;
  console.log(`✔ ${lectures.size} fichiers hors ios-native/ lus par du Swift, tous dans les filtres pull_request et push de ${WORKFLOW_IOS}.`);
  return 0;
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  process.exitCode = main();
}
