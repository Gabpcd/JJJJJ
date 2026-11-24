#!/usr/bin/env node
// Gardes de la soumission App Store de l'app Swift (ios-native/), lot 6.
// Utilisé par .github/workflows/ios-native-app-store.yml ; mode d'emploi :
// docs/mobile-swift/APP_STORE.md. Tout est en lecture seule : l'unique écriture chez Apple est la
// lane fastlane `ios submit_native`, lancée après ces gardes. Principe CLAUDE.md « un gap connu
// reste verrouillé » : chaque refus nomme sa garde et renvoie à la doc. Aucun secret n'est affiché.
//
// Sous-commandes :
//   entrees            entrées du déclenchement (build, phrase de confirmation, publication) et notes de version
//   provenance <N>     commit dont est issu le build TestFlight N (run GitHub Actions) ; main n'a pas avancé
//   source <dossier>   arbre source de ce commit : lots 4 et 5 clos, garde Apple 4.2, aucune mise à jour à chaud
//   build <N>          build N dans App Store Connect : VALID, non expiré, bonne version, chiffrement exempté
import { appendFileSync, existsSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { APP, GuardFailure, ascClient, ascToken, loadSources } from './ios-native-testflight.mjs';
import { COQUILLE_IOS_FIGEE, chargerConfigLivraison, comparerVersions } from './release-config.mjs';

export const DOC = 'docs/mobile-swift/APP_STORE.md';
export const REPO = 'Gabpcd/JJJJJ';
export const WORKFLOW_TESTFLIGHT = '.github/workflows/ios-native-testflight.yml';
export const NOTES = 'config/mobile-release-notes-ios.txt';
/** Limite Apple du champ « Nouveautés » (What's New in This Version). */
export const NOTES_MAX = 4000;
export const PUBLICATIONS = Object.freeze({ automatique: true, manuelle: false });

function collector() {
  const failures = [];
  const fail = (garde, message) => failures.push(`[${garde}] ${message} (voir ${DOC}, garde « ${garde} »)`);
  const done = () => { if (failures.length) throw new GuardFailure(failures); };
  return { fail, done };
}

/** Phrase exacte à saisir pour confirmer : elle nomme la version et le build soumis. */
export const phraseConfirmation = (marketingVersion, buildNumber) => `SOUMETTRE ${marketingVersion} (${buildNumber})`;

// ---------------------------------------------------------------------------------------------
// Garde « entrees » : build, confirmation explicite, mode de publication
// ---------------------------------------------------------------------------------------------

export function evaluateEntrees({ build, confirmation, publication }, config) {
  const { fail, done } = collector();
  const { marketingVersion, minimumBuildNumber } = config.ios;
  const raw = String(build ?? '').trim();
  let buildNumber = null;
  if (!/^[1-9]\d{0,8}$/.test(raw)) fail('entrees', 'numéro de build invalide : entier positif exigé, celui d\'un build déjà envoyé sur TestFlight.');
  else if (Number(raw) <= COQUILLE_IOS_FIGEE.buildNumber) fail('entrees', `build ${raw} refusé : il doit dépasser ${COQUILLE_IOS_FIGEE.buildNumber}, dernier build de la coquille Capacitor.`);
  else if (Number(raw) < minimumBuildNumber) fail('entrees', `build ${raw} refusé : le premier build admis est ${minimumBuildNumber} (ios.minimumBuildNumber de config/mobile-release.json).`);
  else buildNumber = Number(raw);
  if (comparerVersions(marketingVersion, COQUILLE_IOS_FIGEE.marketingVersion) <= 0) {
    fail('entrees', `version ${marketingVersion} refusée : elle doit dépasser ${COQUILLE_IOS_FIGEE.marketingVersion}, la version en vente.`);
  }
  if (!Object.hasOwn(PUBLICATIONS, publication ?? '')) fail('entrees', 'mode de publication inconnu : « automatique » ou « manuelle » exigé.');
  // Comparaison stricte : ni espace en trop, ni autre casse, ni autre numéro. La saisie n'est pas réaffichée.
  if (buildNumber !== null && confirmation !== phraseConfirmation(marketingVersion, buildNumber)) {
    fail('entrees', `confirmation absente ou inexacte : écrire exactement « ${phraseConfirmation(marketingVersion, buildNumber)} ».`);
  }
  done();
  return { buildNumber, marketingVersion, automaticRelease: PUBLICATIONS[publication] };
}

/** Notes de version (« Nouveautés ») : le plan exige d'annoncer la reconnexion et Face ID. */
export function evaluateNotes(text) {
  const { fail, done } = collector();
  const notes = String(text ?? '').trim();
  if (!notes) fail('notes', `${NOTES} absent ou vide.`);
  else {
    if ([...notes].length > NOTES_MAX) fail('notes', `${NOTES} dépasse ${NOTES_MAX} caractères.`);
    if (!/reconnect/i.test(notes)) fail('notes', `${NOTES} doit annoncer la reconnexion après la mise à jour (plan, lot 6).`);
    if (!/Face ID/.test(notes)) fail('notes', `${NOTES} doit annoncer la réactivation de Face ID (plan, lot 6).`);
    if (/\b(?:TODO|TBD|lorem)\b|\[[^\]]*\]/i.test(notes)) fail('notes', `${NOTES} contient un texte provisoire.`);
  }
  done();
  return notes;
}

// ---------------------------------------------------------------------------------------------
// Garde « provenance » : le build soumis vient d'un envoi TestFlight réussi, lancé depuis main
// ---------------------------------------------------------------------------------------------

const estSha = (value) => /^[a-f0-9]{40}$/.test(value ?? '');

/**
 * Retrouve le run de ios-native-testflight.yml qui a envoyé le build N : son artefact s'appelle
 * `ios-native-testflight-<N>-<sha>`. Rend le commit source. Lecture seule de l'API GitHub.
 */
export async function findProvenance({ api, build }) {
  const { fail, done } = collector();
  const motif = new RegExp(`^ios-native-testflight-${build}-([a-f0-9]{40})$`);
  const trouves = [];
  let total = null;
  let lus = 0;
  for (let page = 1; page <= 5; page += 1) {
    const reponse = await api(`actions/workflows/ios-native-testflight.yml/runs?branch=main&event=workflow_dispatch&status=success&per_page=100&page=${page}`);
    if (!Number.isSafeInteger(reponse?.total_count) || !Array.isArray(reponse.workflow_runs)) throw new Error('Historique des envois TestFlight illisible');
    total ??= reponse.total_count;
    for (const run of reponse.workflow_runs) {
      lus += 1;
      // Filtres relus localement : un run d'une autre branche ou d'un autre workflow ne prouve rien.
      if (run.path !== WORKFLOW_TESTFLIGHT || run.head_branch !== 'main' || run.event !== 'workflow_dispatch'
        || run.status !== 'completed' || run.conclusion !== 'success' || run.repository?.full_name !== REPO
        || run.head_repository?.full_name !== REPO || !Number.isSafeInteger(run.id) || !estSha(run.head_sha)) continue;
      const artefacts = await api(`actions/runs/${run.id}/artifacts?per_page=100`);
      if (!Array.isArray(artefacts?.artifacts)) throw new Error('Artefacts du run TestFlight illisibles');
      for (const artefact of artefacts.artifacts) {
        const sha = motif.exec(artefact?.name ?? '')?.[1];
        if (!sha) continue;
        if (sha !== run.head_sha) fail('provenance', `l'artefact du run ${run.id} nomme un autre commit que celui du run : provenance incohérente.`);
        else trouves.push({ sha, runId: run.id });
      }
    }
    if (lus >= total || reponse.workflow_runs.length === 0) break;
  }
  if (total !== null && lus < total) fail('provenance', 'historique des envois TestFlight trop long pour être relu en entier.');
  if (trouves.length === 0) {
    fail('provenance', `aucun envoi TestFlight réussi depuis main n'a produit le build ${build} (artefact ios-native-testflight-${build}-<commit> introuvable) : relancer ios-native-testflight.yml depuis main, puis soumettre le nouveau build.`);
  } else if (trouves.length > 1) {
    fail('provenance', `plusieurs envois TestFlight revendiquent le build ${build} (runs ${trouves.map((t) => t.runId).join(', ')}) : provenance ambiguë.`);
  }
  done();
  return trouves[0];
}

// ---------------------------------------------------------------------------------------------
// Garde « source » : arbre du commit dont le build est issu
// ---------------------------------------------------------------------------------------------

export const DEMO_WORLD_TESTS = 'ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/DemoWorldTests.swift';
/** Ports cœur que la garde Apple 4.2 exige câblés : tableau de bord, missions, présence, pointage. */
export const PORTS_COEUR = Object.freeze(['dashboard', 'mesMissions', 'presence', 'pointage']);
const ECRANS_COEUR = Object.freeze({
  'tableau de bord': 'ios-native/Jolene/Screens/Accueil/AccueilScreen.swift',
  missions: 'ios-native/Jolene/Screens/MesMissions/MesMissionsScreen.swift',
  pointage: 'ios-native/Jolene/Screens/Presences/PointageCodeView.swift',
});
const RACINE_APP = Object.freeze(['ios-native/Jolene/JoleneApp.swift', 'ios-native/Jolene/Screens/RootView.swift', 'ios-native/Jolene/Screens/MainTabView.swift']);
const MISE_A_JOUR_A_CHAUD = /capawesome|live[-_ ]?update|mobile-ota|codepush|hot[-_ ]?update/i;

/** Liste `portsEnAttenteLotN` de DemoWorldTests.swift : source unique des ports non câblés d'un lot. */
export function portsEnAttente(source, lot) {
  const declaration = new RegExp(`static let portsEnAttenteLot${lot}(?:\\s*:\\s*\\[String\\])?\\s*=\\s*\\[([^\\]]*)\\]`).exec(source ?? '');
  if (!declaration) return null;
  return [...declaration[1].replace(/\/\/.*$/gm, '').matchAll(/"([^"]+)"/g)].map((match) => match[1]);
}

export function evaluateSource(files) {
  const { fail, done } = collector();
  // Lots clos : décision du 24/11/2026, la soumission part dès que les lots 4 et 5 sont sur main.
  const attente = {};
  for (const lot of [1, 2, 3, 4, 5]) {
    attente[lot] = portsEnAttente(files.demoWorldTests, lot);
    if (attente[lot] === null) fail('lots', `liste portsEnAttenteLot${lot} introuvable dans ${DEMO_WORLD_TESTS} : la clôture des lots ne peut pas être établie.`);
  }
  for (const lot of [4, 5]) {
    if (attente[lot]?.length) fail('lots', `le lot ${lot} n'est pas clos dans la source de ce build : ports non câblés ${attente[lot].join(', ')}.`);
  }
  // Apple 4.2 : jamais de soumission sans tableau de bord, missions et pointage natifs.
  const enAttente = Object.values(attente).flatMap((ports) => ports ?? []);
  for (const port of PORTS_COEUR) {
    if (enAttente.includes(port)) fail('apple-4.2', `le port cœur « ${port} » n'est pas câblé dans la source de ce build.`);
  }
  for (const [nom, chemin] of Object.entries(ECRANS_COEUR)) {
    if (!files.present?.[chemin]) fail('apple-4.2', `écran natif « ${nom} » absent (${chemin}).`);
  }
  const onglets = files.textes?.['ios-native/Jolene/Screens/MainTabView.swift'] ?? '';
  for (const [appel, identifiant] of [['AccueilScreen(', 'tab-accueil'], ['MesMissionsScreen(', 'tab-missions']]) {
    if (!onglets.includes(appel) || !onglets.includes(`"${identifiant}"`)) fail('apple-4.2', `l'onglet ${identifiant} ne monte pas ${appel.slice(0, -1)} dans MainTabView.swift.`);
  }
  const supabase = Object.entries(files.swiftSources ?? {}).filter(([chemin]) => chemin.startsWith('ios-native/Packages/JoleneSupabase/')).map(([, texte]) => texte).join('\n');
  for (const rpc of ['fn_dashboard_soignant_complet', 'fn_scanner_code_pointage']) {
    if (!supabase.includes(`"${rpc}"`)) fail('apple-4.2', `la RPC ${rpc} n'est pas appelée par le client Swift.`);
  }
  for (const chemin of RACINE_APP) {
    const texte = files.textes?.[chemin];
    if (texte === undefined) fail('apple-4.2', `${chemin} absent : la racine de l'app ne peut pas être contrôlée.`);
    else if (/\bWKWebView\b|\bSFSafariViewController\b/.test(texte.replace(/\/\/.*$/gm, ''))) fail('apple-4.2', `${chemin} monte une vue web à la racine : l'app ne doit pas être un site réemballé.`);
  }
  // Apple 2.5.2 : aucun téléchargement de code qui change l'app.
  const fautifs = Object.entries(files.swiftSources ?? {}).filter(([, texte]) => MISE_A_JOUR_A_CHAUD.test(texte)).map(([chemin]) => chemin);
  if (fautifs.length) fail('ota', `client de mise à jour à chaud détecté (${fautifs.slice(0, 3).join(', ')}) : interdit dans l'app iOS native (Apple 2.5.2).`);
  done();
}

export function loadSourceTree(root) {
  const chemins = [...Object.values(ECRANS_COEUR), ...RACINE_APP];
  const lire = (chemin) => (existsSync(join(root, chemin)) ? readFileSync(join(root, chemin), 'utf8') : undefined);
  return {
    demoWorldTests: lire(DEMO_WORLD_TESTS),
    present: Object.fromEntries(chemins.map((chemin) => [chemin, existsSync(join(root, chemin))])),
    textes: Object.fromEntries(chemins.map((chemin) => [chemin, lire(chemin)]).filter(([, texte]) => texte !== undefined)),
    swiftSources: loadSources(root).swiftSources,
  };
}

// ---------------------------------------------------------------------------------------------
// Garde « build » : état du build dans App Store Connect (lecture seule)
// ---------------------------------------------------------------------------------------------

export function evaluateBuild(reponse, { buildNumber, marketingVersion }) {
  const { fail, done } = collector();
  const builds = (reponse?.data ?? []).filter((build) => build?.attributes?.version === String(buildNumber));
  if (builds.length === 0) {
    fail('build', `build ${buildNumber} absent d'App Store Connect : l'envoyer d'abord par ios-native-testflight.yml.`);
  } else if (builds.length > 1) {
    fail('build', `plusieurs builds ${buildNumber} dans App Store Connect : provenance ambiguë.`);
  } else {
    const [build] = builds;
    const { processingState, expired, usesNonExemptEncryption } = build.attributes;
    if (processingState !== 'VALID') fail('build', `build ${buildNumber} en état ${processingState ?? 'inconnu'} : seul un build VALID se soumet.`);
    if (expired !== false) fail('build', `build ${buildNumber} expiré ou d'expiration inconnue : en envoyer un nouveau.`);
    if (usesNonExemptEncryption !== false) fail('build', `build ${buildNumber} sans conformité export « false » (chiffrement non exempté non exclu).`);
    const id = build.relationships?.preReleaseVersion?.data?.id;
    const version = (reponse.included ?? []).find((row) => row?.type === 'preReleaseVersions' && row.id === id)?.attributes;
    if (!version) fail('build', `version du build ${buildNumber} illisible dans App Store Connect.`);
    else {
      if (version.platform !== 'IOS') fail('build', `build ${buildNumber} de plateforme ${version.platform}, IOS exigé.`);
      if (version.version !== marketingVersion) fail('build', `build ${buildNumber} en version ${version.version}, ${marketingVersion} attendue (config/mobile-release.json).`);
    }
  }
  if (comparerVersions(marketingVersion, COQUILLE_IOS_FIGEE.marketingVersion) <= 0) fail('build', `version ${marketingVersion} : elle doit dépasser ${COQUILLE_IOS_FIGEE.marketingVersion}.`);
  if (!(buildNumber > COQUILLE_IOS_FIGEE.buildNumber)) fail('build', `build ${buildNumber} : il doit dépasser ${COQUILLE_IOS_FIGEE.buildNumber}.`);
  done();
}

export async function lireBuild(get, buildNumber) {
  const app = await get(`/v1/apps/${APP.appleId}?fields[apps]=bundleId`);
  if (app?.data?.attributes?.bundleId !== APP.bundleId) throw new Error(`L'app App Store Connect ${APP.appleId} ne correspond pas au bundle ${APP.bundleId}.`);
  return get(`/v1/builds?filter[app]=${APP.appleId}&filter[version]=${buildNumber}&include=preReleaseVersion`
    + '&fields[builds]=version,processingState,expired,usesNonExemptEncryption,preReleaseVersion&fields[preReleaseVersions]=version,platform&limit=10');
}

// ---------------------------------------------------------------------------------------------
// Interface en ligne de commande
// ---------------------------------------------------------------------------------------------

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');

function output(values) {
  if (!process.env.GITHUB_OUTPUT) return;
  appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(values).map(([key, value]) => `${key}=${value}\n`).join(''));
}

function summary(line) {
  console.log(line);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${line}\n`);
}

function exigerBuild(value, config) {
  if (!/^[1-9]\d{0,8}$/.test(value ?? '') || Number(value) < config.ios.minimumBuildNumber) throw new Error('<numéro de build> exigé, au moins ios.minimumBuildNumber');
  return Number(value);
}

function githubApi() {
  if (process.env.GITHUB_REPOSITORY !== REPO) throw new Error('Dépôt inattendu');
  return async (path) => {
    const response = await fetch(`https://api.github.com/repos/${REPO}/${path}`, {
      headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json' },
    });
    if (!response.ok) throw new Error(`GitHub ${response.status} : ${path.split('?')[0]}`);
    return response.json();
  };
}

async function main(command, args) {
  const config = chargerConfigLivraison(join(ROOT, 'config/mobile-release.json'));
  switch (command) {
    case 'entrees': {
      if (process.env.GITHUB_EVENT_NAME !== 'workflow_dispatch' || process.env.GITHUB_REF !== 'refs/heads/main') {
        throw new GuardFailure([`[entrees] la soumission ne part que d'un déclenchement manuel sur main (voir ${DOC}, garde « entrees »)`]);
      }
      const entrees = evaluateEntrees({
        build: process.env.JOLENE_BUILD_INPUT, confirmation: process.env.JOLENE_CONFIRMATION, publication: process.env.JOLENE_PUBLICATION,
      }, config);
      evaluateNotes(existsSync(join(ROOT, NOTES)) ? readFileSync(join(ROOT, NOTES), 'utf8') : '');
      output({ build_number: entrees.buildNumber, marketing_version: entrees.marketingVersion, automatic_release: entrees.automaticRelease });
      summary(`✓ Entrées : ${APP.bundleId} ${entrees.marketingVersion} (${entrees.buildNumber}), confirmation exacte, publication ${entrees.automaticRelease ? 'automatique' : 'manuelle'} après approbation, progressive sur sept jours.`);
      return;
    }
    case 'provenance': {
      const build = exigerBuild(args[0], config);
      const api = githubApi();
      const sha = process.env.GITHUB_SHA;
      if (!estSha(sha)) throw new Error('GITHUB_SHA absent');
      if ((await api('git/ref/heads/main'))?.object?.sha !== sha) {
        throw new GuardFailure([`[provenance] main a avancé depuis le déclenchement : relancer la soumission depuis le main courant (voir ${DOC}, garde « provenance »)`]);
      }
      const origine = await findProvenance({ api, build });
      try { execFileSync('git', ['merge-base', '--is-ancestor', origine.sha, sha], { cwd: ROOT, stdio: 'ignore' }); } catch {
        throw new GuardFailure([`[provenance] le commit ${origine.sha.slice(0, 12)} du build ${build} n'appartient pas à l'historique de main (voir ${DOC}, garde « provenance »)`]);
      }
      output({ source_sha: origine.sha });
      summary(`✓ Provenance : build ${build} envoyé par le run TestFlight ${origine.runId}, depuis le commit ${origine.sha.slice(0, 12)} de main.`);
      return;
    }
    case 'source': {
      if (!args[0] || !existsSync(join(args[0], 'ios-native'))) throw new Error('source <dossier contenant ios-native/> exigé');
      evaluateSource(loadSourceTree(args[0]));
      summary('✓ Source du build : lots 4 et 5 clos, tableau de bord, missions et pointage natifs (Apple 4.2), aucune mise à jour à chaud (Apple 2.5.2).');
      return;
    }
    case 'build': {
      const buildNumber = exigerBuild(args[0], config);
      const token = () => ascToken({ keyId: process.env.ASC_KEY_ID, issuerId: process.env.ASC_ISSUER_ID, privateKeyBase64: process.env.ASC_PRIVATE_KEY_BASE64 });
      token(); // Échoue tôt, sans rien afficher de la clé, si un secret manque.
      evaluateBuild(await lireBuild(ascClient({ token }), buildNumber), { buildNumber, marketingVersion: config.ios.marketingVersion });
      summary(`✓ Build ${config.ios.marketingVersion} (${buildNumber}) : VALID, non expiré, chiffrement exempté, version supérieure à ${COQUILLE_IOS_FIGEE.marketingVersion} (${COQUILLE_IOS_FIGEE.buildNumber}).`);
      return;
    }
    default:
      throw new Error(`Sous-commande inconnue : ${command ?? 'absente'}`);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const [command, ...args] = process.argv.slice(2);
  main(command, args).catch((error) => {
    const prefix = process.env.GITHUB_ACTIONS ? '::error::' : '✗ ';
    for (const line of error.failures ?? [error.message]) console.error(`${prefix}${line}`);
    process.exit(1);
  });
}
