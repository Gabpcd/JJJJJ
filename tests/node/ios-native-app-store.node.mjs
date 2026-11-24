// Gardes de la soumission App Store de l'app Swift (lot 6)
// (scripts/mobile/ios-native-app-store.mjs, .github/workflows/ios-native-app-store.yml,
// docs/mobile-swift/APP_STORE.md). Sans réseau ni secret : API GitHub et App Store Connect simulées.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  DEMO_WORLD_TESTS, NOTES, NOTES_MAX, PORTS_COEUR, WORKFLOW_TESTFLIGHT, evaluateBuild, evaluateEntrees, evaluateNotes,
  evaluateSource, findProvenance, lireBuild, loadSourceTree, phraseConfirmation, portsEnAttente,
} from '../../scripts/mobile/ios-native-app-store.mjs';
import { APP, GuardFailure, ascClient } from '../../scripts/mobile/ios-native-testflight.mjs';
import { lireConfigLivraison } from '../../scripts/mobile/release-config.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (chemin) => readFileSync(join(root, chemin), 'utf8');
const config = lireConfigLivraison(lire('config/mobile-release.json'));
const { marketingVersion, minimumBuildNumber } = config.ios;
const BUILD = minimumBuildNumber;

function refus(fn, garde, fragment) {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof GuardFailure, `GuardFailure attendue, reçu ${error}`);
    const lignes = error.failures.filter((line) => line.startsWith(`[${garde}]`));
    assert.ok(lignes.length, `garde ${garde} absente de : ${error.failures.join(' | ')}`);
    if (fragment) assert.ok(lignes.some((ligne) => fragment.test(ligne)), `${fragment} absent de : ${lignes.join(' | ')}`);
    for (const ligne of error.failures) assert.match(ligne, /docs\/mobile-swift\/APP_STORE\.md/);
    return true;
  });
}

async function refusAsync(promesse, garde, fragment) {
  let erreur;
  try { await promesse; } catch (error) { erreur = error; }
  refus(() => { if (erreur) throw erreur; }, garde, fragment);
}

// --- Entrées : build, confirmation explicite, publication --------------------------------------

const entrees = (patch = {}) => ({ build: String(BUILD), confirmation: phraseConfirmation(marketingVersion, BUILD), publication: 'automatique', ...patch });

test('une soumission exige un build admis, la phrase exacte et un mode de publication connu', () => {
  assert.equal(phraseConfirmation('2.0.0', 32), 'SOUMETTRE 2.0.0 (32)');
  assert.deepEqual(evaluateEntrees(entrees(), config), { buildNumber: BUILD, marketingVersion, automaticRelease: true });
  assert.equal(evaluateEntrees(entrees({ publication: 'manuelle' }), config).automaticRelease, false);
  const suivant = BUILD + 3;
  assert.equal(evaluateEntrees(entrees({ build: String(suivant), confirmation: phraseConfirmation(marketingVersion, suivant) }), config).buildNumber, suivant);
});

for (const [nom, patch, fragment] of [
  ['un build de la coquille (24)', { build: '24' }, /doit dépasser 24/],
  ['un build TestFlight antérieur au plancher', { build: String(BUILD - 1) }, /premier build admis/],
  ['un numéro qui n\'est pas un entier', { build: '32.0' }, /entier positif/],
  ['un numéro vide', { build: '' }, /entier positif/],
  ['un numéro à zéro initial', { build: `0${BUILD}` }, /entier positif/],
  ['une confirmation absente', { confirmation: '' }, /confirmation absente ou inexacte/],
  ['une confirmation d\'une autre casse', { confirmation: phraseConfirmation(marketingVersion, BUILD).toLowerCase() }, /confirmation absente ou inexacte/],
  ['une confirmation pour un autre build', { confirmation: phraseConfirmation(marketingVersion, BUILD + 1) }, /confirmation absente ou inexacte/],
  ['une confirmation pour une autre version', { confirmation: phraseConfirmation('1.0.7', BUILD) }, /confirmation absente ou inexacte/],
  ['une confirmation avec un espace en trop', { confirmation: `${phraseConfirmation(marketingVersion, BUILD)} ` }, /confirmation absente ou inexacte/],
  ['un simple « oui »', { confirmation: 'oui' }, /confirmation absente ou inexacte/],
  ['un mode de publication inconnu', { publication: 'immediate' }, /mode de publication inconnu/],
  ['un mode de publication absent', { publication: undefined }, /mode de publication inconnu/],
]) {
  test(`la soumission refuse ${nom}`, () => refus(() => evaluateEntrees(entrees(patch), config), 'entrees', fragment));
}

test('la saisie de confirmation n\'est jamais réaffichée dans le refus', () => {
  try { evaluateEntrees(entrees({ confirmation: 'saisie-qui-ne-doit-pas-fuiter' }), config); assert.fail('refus attendu'); } catch (error) {
    assert.doesNotMatch(error.message, /saisie-qui-ne-doit-pas-fuiter/);
  }
});

test('les notes de version du dépôt annoncent la reconnexion et Face ID, sans texte provisoire', () => {
  const notes = evaluateNotes(lire(NOTES));
  assert.ok([...notes].length <= NOTES_MAX);
  assert.match(notes, /reconnecter/);
  assert.match(notes, /Face ID/);
  // Ton de voix du produit : vouvoiement, pas d'argot.
  assert.match(notes, /\bvous\b/);
  assert.doesNotMatch(notes, /\b(?:tu|ton|ta|tes)\b/i);
  refus(() => evaluateNotes(''), 'notes', /absent ou vide/);
  refus(() => evaluateNotes('Corrections diverses. Face ID.'), 'notes', /reconnexion/);
  refus(() => evaluateNotes('Vous devrez vous reconnecter.'), 'notes', /Face ID/);
  refus(() => evaluateNotes(`Vous devrez vous reconnecter. Face ID. ${'x'.repeat(NOTES_MAX)}`), 'notes', /dépasse/);
  refus(() => evaluateNotes('Vous devrez vous reconnecter. Face ID. [à compléter]'), 'notes', /provisoire/);
});

// --- Provenance : run TestFlight réussi depuis main -------------------------------------------

const SHA = 'a'.repeat(40);
const AUTRE = 'b'.repeat(40);
const run = (id, sha = SHA, patch = {}) => ({
  id, head_sha: sha, head_branch: 'main', event: 'workflow_dispatch', status: 'completed', conclusion: 'success',
  path: WORKFLOW_TESTFLIGHT, repository: { full_name: 'Gabpcd/JJJJJ' }, head_repository: { full_name: 'Gabpcd/JJJJJ' }, ...patch,
});
function github({ runs, artefacts, pageSize = 100, total }) {
  const appels = [];
  const api = async (path) => {
    appels.push(path);
    const liste = path.match(/^actions\/workflows\/ios-native-testflight\.yml\/runs\?(.*)$/);
    if (liste) {
      const query = new URLSearchParams(liste[1]);
      assert.equal(query.get('branch'), 'main');
      assert.equal(query.get('event'), 'workflow_dispatch');
      assert.equal(query.get('status'), 'success');
      const page = Number(query.get('page'));
      return { total_count: total ?? runs.length, workflow_runs: runs.slice((page - 1) * pageSize, page * pageSize) };
    }
    const detail = path.match(/^actions\/runs\/(\d+)\/artifacts\?/);
    if (detail) return { artifacts: (artefacts[detail[1]] ?? []).map((name) => ({ name })) };
    throw new Error(`Appel GitHub inattendu : ${path}`);
  };
  return { api, appels };
}

test('la provenance d\'un build est le commit du run TestFlight dont l\'artefact porte son numéro', async () => {
  const { api, appels } = github({
    runs: [run(3, AUTRE), run(2), run(1, AUTRE)],
    artefacts: { 3: [`ios-native-testflight-${BUILD + 1}-${AUTRE}`], 2: [`ios-native-testflight-${BUILD}-${SHA}`], 1: [`ios-native-testflight-${BUILD - 1}-${AUTRE}`] },
  });
  assert.deepEqual(await findProvenance({ api, build: BUILD }), { sha: SHA, runId: 2 });
  assert.ok(appels.every((path) => !/\b(?:POST|PATCH|DELETE)\b/.test(path)));
});

test('la provenance lit toutes les pages de l\'historique', async () => {
  const runs = [run(3, AUTRE), run(2, AUTRE), run(1)];
  const { api, appels } = github({ runs, artefacts: { 1: [`ios-native-testflight-${BUILD}-${SHA}`] }, pageSize: 1 });
  assert.deepEqual(await findProvenance({ api, build: BUILD }), { sha: SHA, runId: 1 });
  assert.ok(appels.some((path) => path.endsWith('page=3')));
});

test('un build sans envoi TestFlight réussi depuis main n\'a pas de provenance', async () => {
  const nom = `ios-native-testflight-${BUILD}-${SHA}`;
  await refusAsync(findProvenance({ ...github({ runs: [], artefacts: {} }), build: BUILD }), 'provenance', /aucun envoi TestFlight réussi/);
  await refusAsync(findProvenance({ ...github({ runs: [run(1)], artefacts: { 1: [`ios-native-testflight-${BUILD}1-${SHA}`] } }), build: BUILD }), 'provenance', /aucun envoi/);
  for (const patch of [{ head_branch: 'lot6/preparation' }, { event: 'push' }, { conclusion: 'failure' }, { status: 'in_progress' },
    { path: '.github/workflows/autre.yml' }, { head_repository: { full_name: 'fork/JJJJJ' } }, { head_sha: 'abc' }]) {
    await refusAsync(findProvenance({ ...github({ runs: [run(1, SHA, patch)], artefacts: { 1: [nom] } }), build: BUILD }), 'provenance', /aucun envoi/);
  }
});

test('une provenance ambiguë ou incohérente est refusée', async () => {
  const nom = `ios-native-testflight-${BUILD}-${SHA}`;
  await refusAsync(findProvenance({ ...github({ runs: [run(1), run(2)], artefacts: { 1: [nom], 2: [nom] } }), build: BUILD }), 'provenance', /ambiguë/);
  await refusAsync(findProvenance({ ...github({ runs: [run(1, AUTRE)], artefacts: { 1: [nom] } }), build: BUILD }), 'provenance', /autre commit/);
  await refusAsync(findProvenance({ ...github({ runs: [run(1)], artefacts: { 1: [nom] }, total: 900, pageSize: 1 }), build: BUILD }), 'provenance', /trop long/);
  await assert.rejects(findProvenance({ api: async () => ({}), build: BUILD }), /illisible/);
});

// --- Source du build : lots clos, Apple 4.2, aucune mise à jour à chaud ---------------------

const arbre = () => structuredClone(loadSourceTree(root));
const clore = (source) => source
  .replace(/static let portsEnAttenteLot4(?:\s*:\s*\[String\])?\s*=\s*\[[^\]]*\]/, 'static let portsEnAttenteLot4: [String] = []')
  .replace(/static let portsEnAttenteLot5(?:\s*:\s*\[String\])?\s*=\s*\[[^\]]*\]/, 'static let portsEnAttenteLot5: [String] = []');
const arbreClos = () => { const files = arbre(); files.demoWorldTests = clore(files.demoWorldTests); return files; };

test('les listes de ports en attente se lisent dans DemoWorldTests.swift, commentaires ignorés', () => {
  const source = 'static let portsEnAttenteLot4 = [\n  "litiges", // T8\n  // "score", retiré\n  "messagerie",\n]\nstatic let portsEnAttenteLot5: [String] = []\n';
  assert.deepEqual(portsEnAttente(source, 4), ['litiges', 'messagerie']);
  assert.deepEqual(portsEnAttente(source, 5), []);
  assert.equal(portsEnAttente(source, 3), null);
  const reel = lire(DEMO_WORLD_TESTS);
  for (const lot of [1, 2, 3, 4, 5]) assert.ok(Array.isArray(portsEnAttente(reel, lot)), `portsEnAttenteLot${lot} lisible dans le dépôt`);
});

test('la source du dépôt, lots 4 et 5 clos, passe la garde Apple 4.2 et la garde OTA', () => {
  assert.doesNotThrow(() => evaluateSource(arbreClos()));
});

test('la source actuelle du dépôt n\'échoue, au plus, que sur la clôture des lots', () => {
  // Ce test reste vrai avant et après la clôture des lots 4 et 5 : jamais de refus 4.2 ni OTA sur main.
  try { evaluateSource(arbre()); } catch (error) {
    assert.ok(error instanceof GuardFailure);
    assert.deepEqual(error.failures.filter((ligne) => !ligne.startsWith('[lots]')), []);
  }
});

test('un lot 4 ou 5 non clos dans la source du build bloque la soumission', () => {
  for (const lot of [4, 5]) {
    const files = arbreClos();
    files.demoWorldTests = files.demoWorldTests.replace(`static let portsEnAttenteLot${lot}: [String] = []`, `static let portsEnAttenteLot${lot} = ["messagerie", "realtime"]`);
    refus(() => evaluateSource(files), 'lots', new RegExp(`lot ${lot} n'est pas clos .* messagerie, realtime`));
  }
  const illisible = arbreClos();
  illisible.demoWorldTests = illisible.demoWorldTests.replace('portsEnAttenteLot5', 'portsRestantsLot5');
  refus(() => evaluateSource(illisible), 'lots', /portsEnAttenteLot5 introuvable/);
  const absent = arbreClos();
  absent.demoWorldTests = undefined;
  refus(() => evaluateSource(absent), 'lots', /introuvable/);
});

test('garde Apple 4.2 : tableau de bord, missions et pointage natifs, jamais un site réemballé', () => {
  assert.deepEqual([...PORTS_COEUR], ['dashboard', 'mesMissions', 'presence', 'pointage']);
  for (const port of PORTS_COEUR) {
    const files = arbreClos();
    files.demoWorldTests = files.demoWorldTests.replace(/static let portsEnAttenteLot2: \[String\] = \[\]/, `static let portsEnAttenteLot2: [String] = ["${port}"]`);
    refus(() => evaluateSource(files), 'apple-4.2', new RegExp(`port cœur « ${port} »`));
  }
  for (const chemin of ['ios-native/Jolene/Screens/Accueil/AccueilScreen.swift', 'ios-native/Jolene/Screens/MesMissions/MesMissionsScreen.swift', 'ios-native/Jolene/Screens/Presences/PointageCodeView.swift']) {
    const files = arbreClos();
    files.present[chemin] = false;
    refus(() => evaluateSource(files), 'apple-4.2', /écran natif/);
  }
  const onglet = arbreClos();
  onglet.textes['ios-native/Jolene/Screens/MainTabView.swift'] = onglet.textes['ios-native/Jolene/Screens/MainTabView.swift'].replace('MesMissionsScreen(', 'PlaceholderScreen(');
  refus(() => evaluateSource(onglet), 'apple-4.2', /tab-missions ne monte pas MesMissionsScreen/);
  for (const rpc of ['fn_dashboard_soignant_complet', 'fn_scanner_code_pointage']) {
    const files = arbreClos();
    for (const chemin of Object.keys(files.swiftSources)) files.swiftSources[chemin] = files.swiftSources[chemin].replaceAll(`"${rpc}"`, '"fn_autre"');
    refus(() => evaluateSource(files), 'apple-4.2', new RegExp(rpc));
  }
  const web = arbreClos();
  web.textes['ios-native/Jolene/Screens/RootView.swift'] += '\nstruct Coquille { let vue = WKWebView() }\n';
  refus(() => evaluateSource(web), 'apple-4.2', /site réemballé/);
  const commentaire = arbreClos();
  commentaire.textes['ios-native/Jolene/Screens/RootView.swift'] += '\n// Pas de WKWebView à la racine.\n';
  assert.doesNotThrow(() => evaluateSource(commentaire));
});

test('un client de mise à jour à chaud dans l\'app Swift bloque la soumission (Apple 2.5.2)', () => {
  const files = arbreClos();
  files.swiftSources['ios-native/Jolene/Composition/MiseAJour.swift'] = 'import CapawesomeLiveUpdate\n';
  refus(() => evaluateSource(files), 'ota', /2\.5\.2/);
});

// --- Build dans App Store Connect ------------------------------------------------------------

const reponse = (attributs = {}, version = {}) => ({
  data: [{ id: 'b1', attributes: { version: String(BUILD), processingState: 'VALID', expired: false, usesNonExemptEncryption: false, ...attributs },
    relationships: { preReleaseVersion: { data: { type: 'preReleaseVersions', id: 'v1' } } } }],
  included: [{ type: 'preReleaseVersions', id: 'v1', attributes: { version: marketingVersion, platform: 'IOS', ...version } }],
});
const cible = { buildNumber: BUILD, marketingVersion };

test('seul un build VALID, non expiré, exempté de chiffrement et de la bonne version se soumet', () => {
  assert.doesNotThrow(() => evaluateBuild(reponse(), cible));
  refus(() => evaluateBuild({ data: [], included: [] }, cible), 'build', /absent d'App Store Connect/);
  refus(() => evaluateBuild(reponse({ version: String(BUILD + 1) }), cible), 'build', /absent/);
  refus(() => evaluateBuild(reponse({ processingState: 'PROCESSING' }), cible), 'build', /PROCESSING/);
  refus(() => evaluateBuild(reponse({ processingState: 'INVALID' }), cible), 'build', /INVALID/);
  refus(() => evaluateBuild(reponse({ expired: true }), cible), 'build', /expiré/);
  refus(() => evaluateBuild(reponse({ usesNonExemptEncryption: null }), cible), 'build', /conformité export/);
  refus(() => evaluateBuild(reponse({ usesNonExemptEncryption: true }), cible), 'build', /conformité export/);
  refus(() => evaluateBuild(reponse({}, { version: '1.0.7' }), cible), 'build', /en version 1\.0\.7/);
  refus(() => evaluateBuild(reponse({}, { platform: 'MAC_OS' }), cible), 'build', /IOS exigé/);
  refus(() => evaluateBuild({ ...reponse(), included: [] }, cible), 'build', /illisible/);
  const double = reponse();
  double.data.push({ ...double.data[0], id: 'b2' });
  refus(() => evaluateBuild(double, cible), 'build', /plusieurs builds/);
});

test('les gardes du plan : version supérieure à 1.0.7 et build supérieur à 24', () => {
  refus(() => evaluateBuild(reponse({ version: '24' }), { buildNumber: 24, marketingVersion }), 'build', /doit dépasser 24/);
  refus(() => evaluateBuild(reponse({}, { version: '1.0.7' }), { buildNumber: BUILD, marketingVersion: '1.0.7' }), 'build', /doit dépasser 1\.0\.7/);
});

test('la lecture du build vérifie l\'app et n\'émet que des GET vers App Store Connect', async () => {
  const appels = [];
  const fetchImpl = async (url, init) => {
    appels.push({ url: url.toString(), method: init?.method ?? 'GET' });
    if (url.pathname === `/v1/apps/${APP.appleId}`) return Response.json({ data: { attributes: { bundleId: APP.bundleId } } });
    return Response.json(reponse());
  };
  const lu = await lireBuild(ascClient({ fetchImpl, token: () => 'jeton' }), BUILD);
  assert.doesNotThrow(() => evaluateBuild(lu, cible));
  assert.ok(appels.every((appel) => appel.method === 'GET' && appel.url.startsWith('https://api.appstoreconnect.apple.com/v1/')));
  assert.match(decodeURIComponent(appels[1].url), new RegExp(`filter\\[app\\]=${APP.appleId}&filter\\[version\\]=${BUILD}&include=preReleaseVersion`));
  const autre = async (url) => Response.json(url.pathname.startsWith('/v1/apps/') ? { data: { attributes: { bundleId: 'app.autre' } } } : reponse());
  await assert.rejects(lireBuild(ascClient({ fetchImpl: autre, token: () => 'jeton' }), BUILD), /ne correspond pas au bundle/);
});

// --- Workflow et lane ------------------------------------------------------------------------

const workflow = lire('.github/workflows/ios-native-app-store.yml');
const actif = workflow.split('\n').filter((line) => !/^\s*#/.test(line)).join('\n');
const fastfile = lire('fastlane/Fastfile');
const lane = fastfile.slice(fastfile.indexOf('lane :submit_native'), fastfile.indexOf('lane :testflight_native'));
const job = (nom) => {
  const debut = actif.indexOf(`\n  ${nom}:\n`);
  assert.ok(debut >= 0, `job ${nom} absent`);
  const fin = actif.slice(debut + 1).search(/\n {2}[a-z_-]+:\n/);
  return fin < 0 ? actif.slice(debut) : actif.slice(debut, debut + 1 + fin);
};

test('la soumission ne se déclenche qu\'à la main, depuis main, une à la fois', () => {
  assert.match(workflow, /^on:\n {2}workflow_dispatch:\n {4}inputs:\n/m);
  assert.doesNotMatch(workflow, /^ {2}(push|pull_request|pull_request_target|schedule|workflow_run|workflow_call|release|status|repository_dispatch):/m);
  assert.match(workflow, /concurrency:\n {2}group: ios-native-app-store\n {2}cancel-in-progress: false/);
  assert.match(workflow, /"\$GITHUB_EVENT_NAME" != workflow_dispatch \] \|\| \[ "\$GITHUB_REF" != refs\/heads\/main/);
  for (const nom of ['soumettre', 'consigner']) {
    assert.ok(job(nom).includes("if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'"), nom);
  }
  assert.match(job('soumettre'), /needs: gardes\n/);
  assert.match(job('consigner'), /needs: \[gardes, soumettre\]\n/);
});

test('la confirmation est une entrée obligatoire qui nomme la version configurée', () => {
  for (const entree of ['build_number', 'confirmation']) {
    assert.match(workflow, new RegExp(`\\n {6}${entree}:\\n {8}description: '[^\\n]+'\\n {8}type: string\\n {8}required: true\\n`), entree);
  }
  assert.ok(workflow.includes(`écrire exactement SOUMETTRE ${marketingVersion} (N)`), 'la description cite la version de config/mobile-release.json');
  assert.match(workflow, /\n {6}publication:\n {8}description: '[^\n]+'\n {8}type: choice\n {8}options: \[automatique, manuelle\]\n/);
  assert.doesNotMatch(actif, /default: (?:SOUMETTRE|true|'?\d)/, 'aucune valeur par défaut ne confirme ni ne choisit le build');
});

test('les entrées passent par l\'environnement, jamais par interpolation dans un script', () => {
  const scripts = [...actif.matchAll(/\n( +)run: \|\n((?:\1 {2}.*\n|\n)+)/g)].map((m) => m[2]).concat([...actif.matchAll(/\n +run: (?!\|)(.+)/g)].map((m) => m[1]));
  assert.ok(scripts.length >= 8, `scripts trouvés : ${scripts.length}`);
  for (const script of scripts) assert.doesNotMatch(script, /\$\{\{/, script);
  assert.doesNotMatch(actif, /set -x|echo "\$\{?(?:ASC_|JOLENE_CONFIRMATION)/);
});

test('droits minimaux : lecture partout, écriture du seul tag de soumission', () => {
  assert.match(workflow, /^permissions:\n {2}contents: read\n {2}actions: read\n\n/m);
  assert.equal([...actif.matchAll(/contents: write/g)].length, 1);
  assert.match(job('consigner'), /permissions:\n {6}contents: write\n/);
  assert.doesNotMatch(job('gardes') + job('soumettre'), /permissions:|contents: write/);
  assert.match(job('consigner'), /RELEASE_SHA: \$\{\{ needs\.gardes\.outputs\.source_sha \}\}\n {10}RELEASE_BUILD_NUMBER: \$\{\{ needs\.gardes\.outputs\.build_number \}\}\n {8}run: node scripts\/mobile\/release-state\.mjs record ios\n/);
});

test('seuls les trois secrets App Store Connect sont lus, jamais le matériel de signature', () => {
  const secrets = [...new Set([...actif.matchAll(/secrets\.(\w+)/g)].map((m) => m[1]))].sort();
  assert.deepEqual(secrets, ['ASC_ISSUER_ID', 'ASC_KEY_ID', 'ASC_PRIVATE_KEY_BASE64']);
  assert.doesNotMatch(actif, /xcodebuild|\.ipa\b|keychain|IOS_DISTRIBUTION|IOS_PROFILE|upload_to_testflight|testflight_native/);
  assert.match(job('soumettre'), /if: always\(\)\n {8}run: rm -rf "\$HOME\/\.appstoreconnect\/private_keys"/);
});

test('chaque action est épinglée par son commit', () => {
  const actions = [...actif.matchAll(/uses: (\S+)/g)].map((m) => m[1]);
  assert.ok(actions.length >= 5);
  for (const action of actions) assert.match(action, /^[\w.-]+\/[\w.-]+@[a-f0-9]{40}$/, action);
  const testflight = lire('.github/workflows/ios-native-testflight.yml');
  for (const nom of ['actions/checkout', 'actions/setup-node']) {
    const epingle = (texte) => new RegExp(`uses: ${nom}@([a-f0-9]{40})`).exec(texte)?.[1];
    assert.equal(epingle(actif), epingle(testflight), `${nom} : même commit que ios-native-testflight.yml`);
  }
});

test('toutes les gardes passent avant l\'unique écriture chez Apple', () => {
  const etapes = ['ios-native-app-store.mjs entrees', 'ios-native-testflight.mjs depot', 'ios-native-app-store.mjs provenance', 'git archive "$SOURCE_SHA" ios-native',
    'ios-native-app-store.mjs source', 'delivery-plan-backend.mjs', 'ios-native-app-store.mjs build', 'bundle exec fastlane ios submit_native', 'release-state.mjs record ios'];
  const positions = etapes.map((etape) => actif.indexOf(etape));
  assert.ok(positions.every((p) => p >= 0), `étape manquante : ${etapes[positions.indexOf(-1)]}`);
  assert.deepEqual([...positions].sort((a, b) => a - b), positions, 'ordre des gardes');
  const appels = [...actif.matchAll(/\bfastlane[^\S\n]+(\S+[^\S\n]+\S+)/g)].map((m) => m[1]);
  assert.deepEqual(appels, ['ios submit_native'], 'une seule lane, celle de la soumission native');
  assert.ok(job('gardes').includes('fetch-depth: 0'));
  assert.doesNotMatch(job('gardes'), /fastlane|contents: write/);
});

test('la lane soumet un build existant, avec publication progressive, sans rien envoyer ni toucher aux captures', () => {
  assert.ok(lane.length > 0);
  for (const option of ['skip_binary_upload: true', 'skip_screenshots: true', 'submit_for_review: true', 'phased_release: true',
    'reject_if_possible: false', "release_config('ios')", "ENV.fetch('IOS_NATIVE_BUILD_NUMBER')", 'IosReviewSubmission::Guard.new']) {
    assert.ok(lane.includes(option), option);
  }
  assert.doesNotMatch(lane, /upload_to_testflight|\bipa:|IOS_IPA_PATH|skip_binary_upload: false|phased_release: false/);
  assert.match(lane, /automatic_release: automatic\b/);
  assert.match(lane, /guard\.prepare! do\n\s+raise IosReviewSubmission::Failure/, 'un build absent arrête la lane : aucun envoi depuis ici');
  assert.ok(lane.includes(NOTES));
});

test('la coquille Capacitor iOS n\'a plus de lane de soumission', () => {
  const coquille = fastfile.slice(fastfile.indexOf('lane :submit do'), fastfile.indexOf('lane :submit_native'));
  assert.match(coquille, /UI\.user_error!/);
  assert.doesNotMatch(coquille, /upload_to_app_store|upload_to_testflight|deliver/);
  assert.match(coquille, /ios-native-app-store\.yml/);
});

test('le mode d\'emploi existe et nomme chaque garde', () => {
  const doc = lire('docs/mobile-swift/APP_STORE.md');
  for (const garde of ['entrees', 'notes', 'provenance', 'lots', 'apple-4.2', 'ota', 'build']) assert.ok(doc.includes(`\`${garde}\``), `garde ${garde} absente du mode d'emploi`);
  assert.ok(doc.includes(phraseConfirmation(marketingVersion, 'N')));
});
