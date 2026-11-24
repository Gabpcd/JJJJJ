#!/usr/bin/env node
// Gardes de la soumission App Store de l'app Swift (ios-native/), lot 6.
// Utilisé par .github/workflows/ios-native-app-store.yml ; mode d'emploi :
// docs/mobile-swift/APP_STORE.md. Tout est en lecture seule : l'unique écriture chez Apple est la
// lane fastlane `ios submit_native`, lancée après ces gardes. Principe CLAUDE.md « un gap connu
// reste verrouillé » : chaque refus nomme sa garde et renvoie à la doc. Aucun secret n'est affiché.
//
// Sous-commandes :
//   entrees            entrées du déclenchement (mode, build, phrase de confirmation, publication) et notes de version
//   provenance <N>     commit dont est issu le build TestFlight N (run GitHub Actions) ; main n'a pas avancé
//   ci <commit>        dernier run de ios-swift-ci.yml sur ce commit de main : réussi (revue M1 de #1177)
//   source <dossier>   arbre source de ce commit : lots 1 à 5 clos, garde Apple 4.2, aucune mise à jour à chaud
//   build <N>          build N dans App Store Connect : VALID, non expiré, bonne version, chiffrement exempté
import { appendFileSync, existsSync, readFileSync, readdirSync } from 'node:fs';
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
/** « verifier » (défaut du workflow) joue toutes les gardes et s'arrête avant la lane et le tag. */
export const MODES = Object.freeze({ verifier: 'verifier', soumettre: 'soumettre' });
/** Rétention de l'artefact de provenance (`retention-days` de ios-native-testflight.yml), en jours. */
export const RETENTION_PROVENANCE_JOURS = 14;
export const WORKFLOW_CI_IOS = '.github/workflows/ios-swift-ci.yml';

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

export function evaluateEntrees({ mode, build, confirmation, publication }, config) {
  const { fail, done } = collector();
  if (!Object.hasOwn(MODES, mode ?? '')) fail('entrees', 'mode inconnu : « verifier » ou « soumettre » exigé.');
  const soumission = mode === MODES.soumettre;
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
  // En mode « verifier », rien n'est soumis : la phrase n'est pas exigée.
  if (soumission && buildNumber !== null && confirmation !== phraseConfirmation(marketingVersion, buildNumber)) {
    fail('entrees', `confirmation absente ou inexacte : écrire exactement « ${phraseConfirmation(marketingVersion, buildNumber)} ».`);
  }
  done();
  return { mode, buildNumber, marketingVersion, automaticRelease: PUBLICATIONS[publication] };
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
  const expires = [];
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
        else if (artefact.expired !== false) expires.push(run.id);
        else trouves.push({ sha, runId: run.id });
      }
    }
    if (lus >= total || reponse.workflow_runs.length === 0) break;
  }
  if (total !== null && lus < total) fail('provenance', 'historique des envois TestFlight trop long pour être relu en entier.');
  // Revue m2 de #1177 : la preuve de provenance est un artefact conservé RETENTION_PROVENANCE_JOURS jours.
  // Au-delà, GitHub le purge : le build ne se soumet plus, même après un refus d'Apple. Jamais de repli.
  const delai = `la provenance repose sur l'artefact du run TestFlight, conservé ${RETENTION_PROVENANCE_JOURS} jours : un build envoyé il y a plus de ${RETENTION_PROVENANCE_JOURS} jours ne se soumet plus`;
  if (trouves.length === 0 && expires.length) {
    fail('provenance', `l'artefact de provenance du build ${build} a expiré (run ${expires.join(', ')}) : ${delai}. Refaire un envoi TestFlight depuis main, puis soumettre le nouveau build.`);
  } else if (trouves.length === 0) {
    fail('provenance', `aucun envoi TestFlight réussi depuis main n'a produit le build ${build} (artefact ios-native-testflight-${build}-<commit> introuvable ; ${delai}) : relancer ios-native-testflight.yml depuis main, puis soumettre le nouveau build.`);
  } else if (trouves.length > 1) {
    fail('provenance', `plusieurs envois TestFlight revendiquent le build ${build} (runs ${trouves.map((t) => t.runId).join(', ')}) : provenance ambiguë.`);
  }
  done();
  return trouves[0];
}

// ---------------------------------------------------------------------------------------------
// Garde « ci-ios » : la CI de l'app Swift est verte sur le commit dont le build est issu
// ---------------------------------------------------------------------------------------------

/**
 * Revue M1 de #1177 : les listes de ports en attente ne sont vraies que si les tests Swift passent
 * (`testAucunPortNonCable`). Exige que le DERNIER run de ios-swift-ci.yml sur ce commit exact de main
 * (push ou déclenchement manuel ; l'API rend l'état de sa dernière tentative) soit terminé et réussi.
 * Aucun run sur ce commit (filtre de chemins, run annulé puis remplacé) : refus, jamais de repli sur un
 * ancêtre. Lecture seule de l'API GitHub.
 */
export async function evaluateCiIos({ api, sha }) {
  const { fail, done } = collector();
  if (!estSha(sha)) throw new Error('Commit source illisible pour la garde ci-ios');
  const reponse = await api(`actions/workflows/ios-swift-ci.yml/runs?head_sha=${sha}&branch=main&per_page=100`);
  if (!Array.isArray(reponse?.workflow_runs)) throw new Error('Historique de ios-swift-ci.yml illisible');
  if (!Number.isSafeInteger(reponse.total_count) || reponse.total_count > reponse.workflow_runs.length) {
    fail('ci-ios', `historique de ios-swift-ci.yml sur le commit ${sha.slice(0, 12)} incomplet : il ne peut pas être relu en entier.`);
  }
  const runs = reponse.workflow_runs.filter((run) => run?.path === WORKFLOW_CI_IOS && run.head_sha === sha && run.head_branch === 'main'
    && ['push', 'workflow_dispatch'].includes(run.event) && run.repository?.full_name === REPO
    && run.head_repository?.full_name === REPO && Number.isSafeInteger(run.id))
    .sort((a, b) => b.id - a.id);
  const [dernier] = runs;
  if (!dernier) {
    fail('ci-ios', `aucun run de « iOS Swift — socle natif » (ios-swift-ci.yml) sur le commit ${sha.slice(0, 12)} de main : le lancer sur main à ce commit et attendre qu'il soit vert, ou envoyer un nouveau build depuis un commit dont la CI iOS est verte.`);
  } else if (dernier.status !== 'completed' || dernier.conclusion !== 'success') {
    const lu = dernier.status === 'completed' ? `conclusion « ${dernier.conclusion ?? 'inconnue'} »` : `état « ${dernier.status ?? 'inconnu'} »`;
    fail('ci-ios', `le dernier run de ios-swift-ci.yml sur le commit ${sha.slice(0, 12)} (run ${dernier.id}, tentative ${dernier.run_attempt ?? '?'}) a la ${lu}, « success » exigée : les tests Swift, dont testAucunPortNonCable, ne sont pas prouvés pour ce build.`);
  }
  done();
  return dernier;
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
const MISE_A_JOUR_A_CHAUD = /capawesome|live[-_ ]?update|mobile-ota|code[-_ ]?push|hot[-_ ]?update|expo-updates|jspatch|rollout\.io/i;
/** Manifestes de dépendances lus par la garde `ota` en plus des sources Swift (revue m7 de #1177). */
const MANIFESTES = Object.freeze(['Package.swift', 'Package.resolved', 'project.yml']);

/** Retire les commentaires Swift (de ligne, et de bloc même imbriqués) hors des chaînes, sauts de ligne gardés. */
export function sansCommentaires(source) {
  let sortie = '';
  let profondeur = 0;
  let chaine = false;
  for (let i = 0; i < source.length; i += 1) {
    const c = source[i];
    const deux = source.slice(i, i + 2);
    if (profondeur > 0) {
      if (deux === '/*') { profondeur += 1; i += 1; } else if (deux === '*/') { profondeur -= 1; i += 1; } else if (c === '\n') sortie += '\n';
    } else if (chaine) {
      sortie += c;
      if (c === '\\') { sortie += source[i + 1] ?? ''; i += 1; } else if (c === '"' || c === '\n') chaine = false;
    } else if (deux === '//') {
      while (i + 1 < source.length && source[i + 1] !== '\n') i += 1;
    } else if (deux === '/*') {
      profondeur = 1; i += 1;
    } else {
      if (c === '"') chaine = true;
      sortie += c;
    }
  }
  return sortie;
}

/**
 * Liste `portsEnAttenteLotN` de DemoWorldTests.swift : source unique des ports non câblés d'un lot.
 * Lecture stricte (revue m1 de #1177) : commentaires retirés d'abord, une seule déclaration, un littéral
 * de tableau fait uniquement de noms entre guillemets, rien qui le prolonge (`+`, `.`, appel, `as`…).
 * Tout le reste est « illisible » : en cas de doute, la garde `lots` refuse.
 */
export function lirePortsEnAttente(source, lot) {
  if (typeof source !== 'string') return { etat: 'absente' };
  const texte = sansCommentaires(source);
  const declarations = [...texte.matchAll(new RegExp(`\\bstatic\\s+let\\s+portsEnAttenteLot${lot}\\b`, 'g'))];
  if (declarations.length === 0) return { etat: 'absente' };
  if (declarations.length > 1) return { etat: 'illisible', raison: 'déclarée plusieurs fois' };
  const apres = texte.slice(declarations[0].index + declarations[0][0].length);
  const tete = /^\s*(?::\s*\[\s*String\s*\]\s*)?=\s*\[/.exec(apres);
  if (!tete) return { etat: 'illisible', raison: 'pas un littéral de tableau' };
  const corps = apres.slice(tete[0].length);
  const fin = /^((?:[^\]"]|"[^"\n]*")*)\]/.exec(corps);
  if (!fin) return { etat: 'illisible', raison: 'tableau non fermé' };
  const NOM = '"[A-Za-z0-9_.]+"';
  if (!new RegExp(`^\\s*(?:${NOM}\\s*(?:,\\s*${NOM}\\s*)*,?\\s*)?$`).test(fin[1])) return { etat: 'illisible', raison: 'éléments autres que des noms de ports' };
  const suite = corps.slice(fin[0].length);
  // Après le `]` : fin du fichier ou début d'une autre déclaration, jamais un opérateur ni `as`/`is`.
  if (!/^\s*(?:$|[A-Za-z_@#}])/.test(suite) || /^\s*(?:as|is)\b/.test(suite)) return { etat: 'illisible', raison: 'expression prolongée après le tableau' };
  return { etat: 'lue', ports: [...fin[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]) };
}

/** Ports en attente du lot, `null` si la liste est absente ou illisible (la garde `lots` refuse alors). */
export function portsEnAttente(source, lot) {
  const lu = lirePortsEnAttente(source, lot);
  return lu.etat === 'lue' ? lu.ports : null;
}

export function evaluateSource(files) {
  const { fail, done } = collector();
  // Lots clos : AUCUN port en attente, quel que soit le lot (revue M2 de #1177). Pas d'exception en dur :
  // soumettre avec un port non câblé exigerait une décision écrite de la fondatrice et une PR de ce fichier.
  // Au 24/11/2026, portsEnAttenteLot1 = ["recovery"] : réinitialisation native du mot de passe (LOT6_PLAN §2).
  const attente = {};
  for (const lot of [1, 2, 3, 4, 5]) {
    const lu = lirePortsEnAttente(files.demoWorldTests, lot);
    attente[lot] = lu.etat === 'lue' ? lu.ports : null;
    if (lu.etat === 'absente') fail('lots', `liste portsEnAttenteLot${lot} introuvable dans ${DEMO_WORLD_TESTS} : la clôture des lots ne peut pas être établie.`);
    else if (lu.etat === 'illisible') fail('lots', `liste portsEnAttenteLot${lot} illisible dans ${DEMO_WORLD_TESTS} (${lu.raison}) : la clôture des lots ne peut pas être établie.`);
    else if (lu.ports.length) fail('lots', `le lot ${lot} n'est pas clos dans la source de ce build : ports non câblés ${lu.ports.join(', ')}.`);
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
  // Apple 2.5.2 : aucun téléchargement de code qui change l'app. Sources Swift ET manifestes de dépendances.
  const manifestes = Object.keys(files.manifestes ?? {});
  for (const nom of ['Package.swift', 'Package.resolved']) {
    if (!manifestes.some((chemin) => chemin.endsWith(`/${nom}`))) fail('ota', `aucun ${nom} lu sous ios-native/ : les dépendances de l'app ne peuvent pas être contrôlées.`);
  }
  const fautifs = Object.entries({ ...(files.swiftSources ?? {}), ...(files.manifestes ?? {}) })
    .filter(([, texte]) => MISE_A_JOUR_A_CHAUD.test(texte)).map(([chemin]) => chemin);
  if (fautifs.length) fail('ota', `client de mise à jour à chaud détecté (${fautifs.slice(0, 3).join(', ')}) : interdit dans l'app iOS native (Apple 2.5.2).`);
  done();
}

/** Package.swift, Package.resolved et project.yml sous ios-native/ (hors produits de build). */
export function listerManifestes(root) {
  const trouves = {};
  const parcourir = (relatif) => {
    for (const entree of readdirSync(join(root, relatif), { withFileTypes: true })) {
      const chemin = `${relatif}/${entree.name}`;
      if (entree.isDirectory()) {
        if (!['.build', '.swiftpm', 'DerivedData', 'build', 'node_modules', '.git'].includes(entree.name)) parcourir(chemin);
      } else if (MANIFESTES.includes(entree.name)) trouves[chemin] = readFileSync(join(root, chemin), 'utf8');
    }
  };
  if (existsSync(join(root, 'ios-native'))) parcourir('ios-native');
  return trouves;
}

export function loadSourceTree(root) {
  const chemins = [...Object.values(ECRANS_COEUR), ...RACINE_APP];
  const lire = (chemin) => (existsSync(join(root, chemin)) ? readFileSync(join(root, chemin), 'utf8') : undefined);
  return {
    manifestes: listerManifestes(root),
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
      // Tentative du run : le job `soumettre` refuse des gardes d'une autre tentative (revue m5 de #1177).
      const tentative = process.env.GITHUB_RUN_ATTEMPT;
      if (!/^[1-9]\d{0,5}$/.test(tentative ?? '')) throw new Error('GITHUB_RUN_ATTEMPT absent ou illisible');
      const entrees = evaluateEntrees({
        mode: process.env.JOLENE_MODE, build: process.env.JOLENE_BUILD_INPUT,
        confirmation: process.env.JOLENE_CONFIRMATION, publication: process.env.JOLENE_PUBLICATION,
      }, config);
      evaluateNotes(existsSync(join(ROOT, NOTES)) ? readFileSync(join(ROOT, NOTES), 'utf8') : '');
      output({
        mode: entrees.mode, build_number: entrees.buildNumber, marketing_version: entrees.marketingVersion,
        automatic_release: entrees.automaticRelease, run_attempt: tentative,
      });
      summary(entrees.mode === MODES.soumettre
        ? `✓ Entrées : ${APP.bundleId} ${entrees.marketingVersion} (${entrees.buildNumber}), mode soumettre, confirmation exacte, publication ${entrees.automaticRelease ? 'automatique' : 'manuelle'} après approbation, progressive sur sept jours.`
        : `✓ Entrées : ${APP.bundleId} ${entrees.marketingVersion} (${entrees.buildNumber}), mode verifier : gardes seulement, ni soumission ni tag.`);
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
    case 'ci': {
      if (!estSha(args[0])) throw new Error('ci <commit source du build> exigé');
      const run = await evaluateCiIos({ api: githubApi(), sha: args[0] });
      summary(`✓ CI iOS : dernier run de ios-swift-ci.yml sur ${args[0].slice(0, 12)} réussi (run ${run.id}, tentative ${run.run_attempt ?? '?'}).`);
      return;
    }
    case 'source': {
      if (!args[0] || !existsSync(join(args[0], 'ios-native'))) throw new Error('source <dossier contenant ios-native/> exigé');
      evaluateSource(loadSourceTree(args[0]));
      summary('✓ Source du build : lots 1 à 5 clos, tableau de bord, missions et pointage natifs (Apple 4.2), aucune mise à jour à chaud (Apple 2.5.2).');
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
