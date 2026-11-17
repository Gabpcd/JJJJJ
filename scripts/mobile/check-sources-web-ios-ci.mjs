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
 *   - un chemin de fichier du dépôt hors `ios-native/` écrit dans un littéral (`source("src/…")`,
 *     `static let hub = "src/pages/…"`), préfixes `./`, `../` et `/` ou interpolation de tête (`"\(racine.path)/src/…"`)
 *     compris ;
 *   - une annotation `// source:`, `// source-objet:` ou `// source-ensemble:` (en début ou en fin de ligne) d'un
 *     fichier Swift dont le chemin (depuis la racine, `ios-native/` ou un paquet) figure lui-même dans un littéral :
 *     c'est ainsi que `CompletionVerbatimTests` relit `CompletionProfil.swift` et `InscriptionVerbatimTests` relit
 *     `InscriptionRules.swift`.
 * Les annotations d'un fichier Swift qu'aucun test ne relit sont de la documentation. C'est le cas de
 * `TextesWeb.swift` et `LibellesWeb.swift` : la garde tolérante `check-textes-juridiques-ios.mjs` les relit dans
 * validate-pr (check requis ; texte modifié en erreur, décalage de lignes en avertissement), aucun test Swift. Un test
 * Swift qui se mettrait à les relire rendrait leurs citations obligatoires dans le filtre.
 *
 * Refusés, pour qu'aucune lecture n'échappe en silence :
 *   - un dossier lu (`"src/pages"`, `"src/pages/" + nom`) et un chemin construit (interpolation au fil d'un dossier du
 *     dépôt, segment racine seul passé à `appendingPathComponent` ou `appending(path:|component:)`) : couverture
 *     inconnue ;
 *   - un chemin cité introuvable (fichier d'un sous-dossier existant ou à extension de source, ou annotation d'un
 *     fichier relu) : les tests Swift lèvent `XCTSkip` sur un fichier absent, une PR web qui le renomme ou le supprime
 *     passerait donc en silence.
 * Limite connue : un test qui parcourrait un dossier pour relire les annotations de chaque fichier Swift n'est pas vu ;
 * la convention du dépôt est de citer chaque fichier relu dans un littéral (CompletionVerbatimTests, InscriptionVerbatimTests).
 *
 * Chaque fichier lu doit correspondre à un motif des DEUX filtres (`pull_request` et `push`), lus avec le paquet `yaml`
 * comme GitHub les lit. Seuls `*` et `**` sont interprétés ; `?`, `+`, `[…]` et `!` (quantificateurs et négation chez
 * GitHub), `paths-ignore` et un `paths` qui n'est pas une liste de chaînes sont refusés.
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
import { readFileSync, realpathSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parse } from 'yaml';

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
 * Motifs `paths` des événements `pull_request` et `push`, lus par le paquet `yaml` comme GitHub les lit (commentaires,
 * listes en ligne, ancres, alias, indentation libre). Événement sans `paths` : non filtré (`**`). Refusés : `paths`
 * qui n'est pas une liste non vide de chaînes, `paths-ignore`, événement absent de `on` (revues B8 de #1139).
 */
export function motifsDuFiltre(yml) {
  let on;
  try {
    on = parse(yml)?.on;
  } catch (erreur) {
    throw new Error(`${WORKFLOW_IOS} : YAML illisible par ${SCRIPT} (${erreur.message}).`);
  }
  const filtres = {};
  for (const evenement of EVENEMENTS) {
    const forme = typeof on === 'string' || Array.isArray(on);
    const present = forme ? [on].flat().includes(evenement) : on !== null && typeof on === 'object' && evenement in on;
    if (!present) throw new Error(`${WORKFLOW_IOS} : événement ${evenement} introuvable dans « on ».`);
    const corps = forme ? null : on[evenement];
    if (corps === null || corps === undefined) { filtres[evenement] = ['**']; continue; }
    if (typeof corps !== 'object' || Array.isArray(corps)) {
      throw new Error(`${WORKFLOW_IOS} : corps de ${evenement} non géré par ${SCRIPT} (objet attendu).`);
    }
    if ('paths-ignore' in corps) throw new Error(`${WORKFLOW_IOS} : paths-ignore (${evenement}) non géré par ${SCRIPT}.`);
    if (!('paths' in corps)) { filtres[evenement] = ['**']; continue; }
    const { paths } = corps;
    if (!Array.isArray(paths) || !paths.length || !paths.every(m => typeof m === 'string')) {
      throw new Error(`${WORKFLOW_IOS} : paths (${evenement}) doit être une liste non vide de chaînes pour ${SCRIPT}.`);
    }
    filtres[evenement] = paths.map(m => verifierMotif(m, evenement));
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
  const racineWeb = racine => racine !== 'ios-native' && racines.has(racine);
  const parent = chemin => chemin.split('/').slice(0, -1).join('/');
  const swiftSuivis = fichiersDepot.filter(f => f.startsWith(NATIF) && f.endsWith('.swift'));
  /** Jeton de chemin sans ses préfixes `./`, `../` et `/` ; `null` s'il contient un segment vide, `.` ou `..`. */
  const normaliser = jeton => {
    const valeur = jeton.replace(/^(?:\.{1,2}\/|\/)+/, '');
    const net = valeur.replace(/\/+$/, '');
    if (!net || net.split('/').some(seg => !seg || seg === '.' || seg === '..')) return null;
    return { net, dossier: valeur.endsWith('/') };
  };
  const conseil = 'si ce n’est pas une lecture (commentaire, préfixe), écrivez le chemin sans guillemets';
  for (const { chemin, texte } of swift) {
    const nom = basename(chemin);
    // Jeton de caractères de chemin ouvert par un guillemet ou par la fin d'une interpolation `\(…)`, fermé par un
    // guillemet : une seule classe répétée (aucun retour arrière exponentiel) ; un guillemet impair plus tôt sur la
    // ligne ne décale pas la lecture, le contenu d'un faux littéral contenant une espace.
    for (const [, jeton] of texte.matchAll(/[")]([\w./-]+)"/g)) {
      const lu = normaliser(jeton);
      if (!lu || (!lu.net.includes('/') && !lu.dossier)) continue;
      const { net, dossier } = lu;
      if (!dossier && net.endsWith('.swift')) {
        const relu = swiftSuivis.filter(f => f === net || f.endsWith(`/${net}`));
        for (const f of relu) ajouter(relus, f, chemin);
        if (relu.length) continue;
      }
      if (!racineWeb(net.split('/')[0])) continue;
      if (!dossier && depot.has(net)) ajouter(lectures, net, nom);
      else if (net.includes('/') && dossiers.has(net)) {
        erreurs.push(`${nom} lit le dossier « ${net}/ » : ${SCRIPT} ne sait pas quels fichiers il couvre ; citez chaque fichier lu en entier (${conseil}).`);
      } else if (!dossier && ((parent(net).includes('/') && dossiers.has(parent(net))) || EXTENSIONS_SOURCE.test(net))) {
        erreurs.push(`${nom} cite « ${net} », introuvable dans le dépôt : le test Swift lèverait XCTSkip et ne vérifierait plus rien ; corrigez le chemin (${conseil}).`);
      }
    }
    // Chemins construits : interpolation au fil d'un dossier du dépôt (`"src/pages/\(nom).tsx"`, pas un message
    // `"src/x introuvable : \(…)"`), ou segment racine seul passé à appendingPathComponent / appending(path:|component:).
    const interpoles = [...texte.matchAll(/[")]([\w./-]*)\\\(/g)].map(m => normaliser(m[1]))
      .filter(lu => lu && lu.net.includes('/') && dossiers.has(lu.net)).map(lu => lu.net.split('/')[0]);
    const segments = [...texte.matchAll(/(?:appendingPathComponent\(|appending\(\s*(?:path|component):)\s*"([^"\n]*)"\s*[,)]/g)]
      .map(m => normaliser(m[1])).filter(lu => lu && !lu.net.includes('/')).map(lu => lu.net);
    for (const racine of [...interpoles, ...segments].filter(racineWeb)) {
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

const lanceDirectement = () => {
  try {
    return Boolean(process.argv[1]) && pathToFileURL(realpathSync(process.argv[1])).href === import.meta.url;
  } catch {
    return false;
  }
};
if (lanceDirectement()) process.exitCode = main();
