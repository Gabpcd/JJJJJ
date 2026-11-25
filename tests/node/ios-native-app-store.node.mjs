// Gardes de la soumission App Store de l'app Swift (lot 6)
// (scripts/mobile/ios-native-app-store.mjs, .github/workflows/ios-native-app-store.yml,
// docs/mobile-swift/APP_STORE.md). Sans réseau ni secret : API GitHub et App Store Connect simulées.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { generateKeyPairSync } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  APP_CONTAINER, DEMO_WORLD_TESTS, ENVIRONNEMENT, ESPACE_RESOLUTION, MODES, NOTES, NOTES_MAX, PORTS_COEUR, RETENTION_PROVENANCE_JOURS, WORKFLOW_CI_IOS, WORKFLOW_TESTFLIGHT,
  evaluateBuild, evaluateCiIos, evaluateEntrees, evaluateNotes, evaluateSource, findProvenance, lireBuild, lirePortsEnAttente,
  lireModes, lireOuvertureEtablissement, loadSourceTree, phraseConfirmation, portsEnAttente, sansCommentaires,
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

const entrees = (patch = {}) => ({ mode: 'soumettre', build: String(BUILD), confirmation: phraseConfirmation(marketingVersion, BUILD), publication: 'automatique', ...patch });

test('une soumission exige un build admis, la phrase exacte et un mode de publication connu', () => {
  assert.equal(phraseConfirmation('2.0.0', 32), 'SOUMETTRE 2.0.0 (32)');
  assert.deepEqual(evaluateEntrees(entrees(), config), { mode: 'soumettre', buildNumber: BUILD, marketingVersion, automaticRelease: true });
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
  ['un mode absent', { mode: undefined }, /mode inconnu/],
  ['un mode inconnu', { mode: 'publier' }, /mode inconnu/],
  ['un mode hérité de l\'objet', { mode: '__proto__' }, /mode inconnu/],
]) {
  test(`la soumission refuse ${nom}`, () => refus(() => evaluateEntrees(entrees(patch), config), 'entrees', fragment));
}

test('mode verifier (revue M3 de #1177) : gardes du build sans phrase de confirmation, mode inconnu refusé', () => {
  assert.deepEqual(Object.keys(MODES), ['verifier', 'soumettre']);
  for (const confirmation of [undefined, '', 'oui', phraseConfirmation(marketingVersion, BUILD)]) {
    assert.equal(evaluateEntrees(entrees({ mode: 'verifier', confirmation }), config).mode, 'verifier');
  }
  // Le mode verifier ne relâche aucune autre garde des entrées.
  refus(() => evaluateEntrees(entrees({ mode: 'verifier', build: '24' }), config), 'entrees', /doit dépasser 24/);
  refus(() => evaluateEntrees(entrees({ mode: 'verifier', publication: 'immediate' }), config), 'entrees', /publication inconnu/);
  refus(() => evaluateEntrees(entrees({ mode: 'soumettre', confirmation: '' }), config), 'entrees', /confirmation absente/);
});

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
    if (detail) return { artifacts: (artefacts[detail[1]] ?? []).map((a) => (typeof a === 'string' ? { name: a, expired: false } : a)) };
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

test('provenance : la fenêtre de 14 jours de l\'artefact est écrite et un artefact expiré est refusé en clair (revue m2 de #1177)', async () => {
  const nom = `ios-native-testflight-${BUILD}-${SHA}`;
  // La constante suit la rétention réelle de l'artefact dans ios-native-testflight.yml.
  const testflight = lire(WORKFLOW_TESTFLIGHT);
  const bloc = testflight.slice(testflight.indexOf('name: ios-native-testflight-${{'));
  assert.ok(bloc.length > 0 && testflight.includes('uses: actions/upload-artifact@'));
  assert.equal(Number(/retention-days: (\d+)/.exec(bloc)?.[1]), RETENTION_PROVENANCE_JOURS);
  for (const expire of [{ name: nom, expired: true }, { name: nom }]) {
    await refusAsync(findProvenance({ ...github({ runs: [run(1)], artefacts: { 1: [expire] } }), build: BUILD }), 'provenance', /a expiré \(run 1\).*conservé 14 jours/);
  }
  await refusAsync(findProvenance({ ...github({ runs: [], artefacts: {} }), build: BUILD }), 'provenance', /conservé 14 jours/);
  assert.match(lire('docs/mobile-swift/APP_STORE.md'), /14 jours/);
});

// --- CI iOS verte sur le commit source (revue M1 de #1177) ---------------------------------------

const runCi = (id, patch = {}) => ({
  id, run_attempt: 1, head_sha: SHA, head_branch: 'main', event: 'push', status: 'completed', conclusion: 'success',
  path: WORKFLOW_CI_IOS, repository: { full_name: 'Gabpcd/JJJJJ' }, head_repository: { full_name: 'Gabpcd/JJJJJ' }, ...patch,
});
const apiCi = (runs, total = runs.length) => {
  const appels = [];
  const api = async (path) => {
    appels.push(path);
    const m = path.match(/^actions\/workflows\/ios-swift-ci\.yml\/runs\?(.*)$/);
    if (!m) throw new Error(`Appel GitHub inattendu : ${path}`);
    const query = new URLSearchParams(m[1]);
    assert.equal(query.get('head_sha'), SHA);
    assert.equal(query.get('branch'), 'main');
    return { total_count: total, workflow_runs: runs };
  };
  return { api, appels };
};

test('ci-ios : le dernier run de ios-swift-ci.yml sur le commit source, réussi, ouvre la garde', async () => {
  assert.equal(WORKFLOW_CI_IOS, '.github/workflows/ios-swift-ci.yml');
  assert.equal((await evaluateCiIos({ ...apiCi([runCi(7)]), sha: SHA })).id, 7);
  // Déclenchement manuel sur main au même commit, plus récent qu'un push annulé : il fait foi.
  assert.equal((await evaluateCiIos({ ...apiCi([runCi(7, { conclusion: 'cancelled' }), runCi(9, { event: 'workflow_dispatch' })]), sha: SHA })).id, 9);
  // Un run d'une autre branche, d'un autre événement ou d'un autre workflow est ignoré, même plus récent.
  assert.equal((await evaluateCiIos({ ...apiCi([runCi(7), runCi(8, { head_branch: 'lot6/preparation', conclusion: 'failure' }),
    runCi(10, { event: 'pull_request', conclusion: 'failure' })]), sha: SHA })).id, 7);
});

for (const [nom, runs, fragment] of [
  ['aucun run sur ce commit (filtre de chemins)', [], /aucun run de « iOS Swift — socle natif »/],
  ['un dernier run en échec, même après un succès plus ancien', [runCi(7), runCi(8, { conclusion: 'failure', run_attempt: 2 })], /run 8, tentative 2\) a la conclusion « failure »/],
  ['un run annulé (cas du build 31, 95a987f2)', [runCi(7, { conclusion: 'cancelled' })], /conclusion « cancelled »/],
  ['un run encore en cours', [runCi(7, { status: 'in_progress', conclusion: null })], /état « in_progress »/],
  ['un run d\'une autre branche seulement', [runCi(7, { head_branch: 'fix/test' })], /aucun run/],
  ['un run d\'un fork seulement', [runCi(7, { head_repository: { full_name: 'fork/JJJJJ' } })], /aucun run/],
  ['un run d\'un autre commit seulement', [runCi(7, { head_sha: 'b'.repeat(40) })], /aucun run/],
  ['un run d\'un autre workflow seulement', [runCi(7, { path: '.github/workflows/ios-native-testflight.yml' })], /aucun run/],
]) {
  test(`ci-ios refuse ${nom}`, async () => {
    await refusAsync(evaluateCiIos({ ...apiCi(runs), sha: SHA }), 'ci-ios', fragment);
    try { await evaluateCiIos({ ...apiCi(runs), sha: SHA }); } catch (error) { assert.ok(error.failures.some((l) => l.includes(SHA.slice(0, 12))), 'le refus nomme le commit'); }
  });
}

test('ci-ios refuse un historique tronqué ou illisible', async () => {
  await refusAsync(evaluateCiIos({ ...apiCi([runCi(7)], 150), sha: SHA }), 'ci-ios', /incomplet/);
  await assert.rejects(evaluateCiIos({ api: async () => ({}), sha: SHA }), /illisible/);
  await assert.rejects(evaluateCiIos({ ...apiCi([runCi(7)]), sha: 'abc' }), /illisible/);
});

// --- Source du build : lots clos, Apple 4.2, aucune mise à jour à chaud ---------------------

const arbre = () => structuredClone(loadSourceTree(root));
const LOTS = [1, 2, 3, 4, 5];
const clore = (source) => LOTS.reduce((texte, lot) => texte.replace(
  new RegExp(`static let portsEnAttenteLot${lot}(?:\\s*:\\s*\\[String\\])?\\s*=\\s*\\[[^\\]]*\\]`), `static let portsEnAttenteLot${lot}: [String] = []`), source);
const arbreClos = () => { const files = arbre(); files.demoWorldTests = clore(files.demoWorldTests); return files; };

test('les listes de ports en attente se lisent dans DemoWorldTests.swift, commentaires ignorés', () => {
  const source = 'static let portsEnAttenteLot4 = [\n  "litiges", // T8\n  // "score", retiré\n  "messagerie",\n]\nstatic let portsEnAttenteLot5: [String] = []\n';
  assert.deepEqual(portsEnAttente(source, 4), ['litiges', 'messagerie']);
  assert.deepEqual(portsEnAttente(source, 5), []);
  assert.equal(portsEnAttente(source, 3), null);
  const reel = lire(DEMO_WORLD_TESTS);
  for (const lot of LOTS) assert.ok(Array.isArray(portsEnAttente(reel, lot)), `portsEnAttenteLot${lot} lisible dans le dépôt`);
  for (const lot of LOTS) assert.deepEqual(portsEnAttente(clore(reel), lot), [], `clore() vide le lot ${lot}`);
});

test('lecture des listes robuste aux commentaires et aux concaténations : en cas de doute, refus (revue m1 de #1177)', () => {
  const lot4 = (corps) => lirePortsEnAttente(`struct T {\n    static let portsEnAttenteLot4${corps}\n    func test() {}\n}\n`, 4);
  // Les deux contre-exemples du relecteur : un `]` en commentaire, une concaténation.
  assert.deepEqual(lot4(' = [\n        // reste [T7a, T8]\n        "messagerie",\n        "litiges",\n    ]').ports, ['messagerie', 'litiges']);
  assert.deepEqual(lot4(' = [ /* [T7a] */ "messagerie" /* ] */, "litiges" ]').ports, ['messagerie', 'litiges']);
  assert.deepEqual(lot4(' = [ /* imbriqué /* ] */ ] */ "messagerie" ]').ports, ['messagerie']);
  assert.deepEqual(lot4(': [String] = [] // T15 : tout câblé ]').ports, []);
  for (const [corps, raison] of [
    [': [String] = [] + Lot4PortsTests.portsLot4', /prolongée/],
    [': [String] = []\n        + Lot4PortsTests.portsLot4', /prolongée/],
    [': [String] = [].filter { _ in true }', /prolongée/],
    [' = ["a"] as [String]', /prolongée/],
    [' = Lot4PortsTests.portsLot4', /littéral/],
    [': [String] = Array([])', /littéral/],
    [' = ["messagerie", nom]', /noms de ports/],
    [' = ["messa\\"gerie"]', /noms de ports|non fermé/],
    [' = ["mes]sagerie"]', /noms de ports/],
    [' = ["messagerie"', /non fermé/],
  ]) {
    const lu = lot4(corps);
    assert.equal(lu.etat, 'illisible', corps);
    assert.match(lu.raison, raison, corps);
  }
  // Deux déclarations (par exemple sous #if) : illisible ; une déclaration en commentaire ne compte pas.
  assert.equal(lirePortsEnAttente('static let portsEnAttenteLot4: [String] = []\nstatic let portsEnAttenteLot4 = ["x"]\n', 4).raison, 'déclarée plusieurs fois');
  assert.deepEqual(lirePortsEnAttente('// static let portsEnAttenteLot4 = ["x"]\nstatic let portsEnAttenteLot4: [String] = []\n', 4).ports, []);
  assert.equal(lirePortsEnAttente('/* static let portsEnAttenteLot4: [String] = [] */\n', 4).etat, 'absente');
  assert.equal(lirePortsEnAttente(undefined, 4).etat, 'absente');
  // Une chaîne qui contient `//` n'est pas un commentaire.
  assert.equal(sansCommentaires('let u = "https://x" // fin\n'), 'let u = "https://x" \n');
  // Dans la garde : une liste illisible bloque, avec sa raison.
  const files = arbreClos();
  files.demoWorldTests = files.demoWorldTests.replace('static let portsEnAttenteLot4: [String] = []', 'static let portsEnAttenteLot4: [String] = [] + Lot4PortsTests.portsLot4');
  refus(() => evaluateSource(files), 'lots', /portsEnAttenteLot4 illisible .*prolongée/);
});

test('la source du dépôt, lots 1 à 5 clos, passe la garde Apple 4.2 et la garde OTA', () => {
  assert.doesNotThrow(() => evaluateSource(arbreClos()));
});

test('la source actuelle du dépôt n\'échoue, au plus, que sur la clôture des lots', () => {
  // Ce test reste vrai avant et après la clôture des lots : jamais de refus 4.2 ni OTA sur main.
  try { evaluateSource(arbre()); } catch (error) {
    assert.ok(error instanceof GuardFailure);
    assert.deepEqual(error.failures.filter((ligne) => !ligne.startsWith('[lots]')), []);
  }
});

test('revue M2 de #1177 : recovery, en attente au lot 1, bloque aujourd\'hui la soumission', () => {
  const reel = lire(DEMO_WORLD_TESTS);
  if (!portsEnAttente(reel, 1)?.includes('recovery')) return; // Câblé depuis : le test générique ci-dessous suffit.
  refus(() => evaluateSource(arbre()), 'lots', /lot 1 n'est pas clos .*recovery/);
  for (const doc of ['docs/mobile-swift/LOT6_PLAN.md', 'docs/mobile-swift/APP_STORE.md']) assert.match(lire(doc), /`recovery`/, `${doc} écrit le manque`);
});

test('un port en attente de n\'importe quel lot, 1 à 5, bloque la soumission', () => {
  for (const lot of LOTS) {
    const files = arbreClos();
    files.demoWorldTests = files.demoWorldTests.replace(`static let portsEnAttenteLot${lot}: [String] = []`, `static let portsEnAttenteLot${lot} = ["messagerie", "realtime"]`);
    refus(() => evaluateSource(files), 'lots', new RegExp(`lot ${lot} n'est pas clos .* messagerie, realtime`));
  }
  // Les compositions que le relecteur a fait passer : lot 3 et lot 2 non vides, hors ports cœur.
  for (const [lot, ports] of [[3, ['paiements', 'stripeConnect', 'inscription']], [2, ['documents', 'contrats', 'notation']], [1, ['recovery']]]) {
    const files = arbreClos();
    files.demoWorldTests = files.demoWorldTests.replace(`static let portsEnAttenteLot${lot}: [String] = []`, `static let portsEnAttenteLot${lot} = [${ports.map((p) => `"${p}"`).join(', ')}]`);
    refus(() => evaluateSource(files), 'lots', new RegExp(`lot ${lot} n'est pas clos .*${ports.join(', ')}`));
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

test('la garde OTA lit aussi Package.swift, Package.resolved et project.yml de la source du build (revue m7 de #1177)', () => {
  const lus = Object.keys(arbre().manifestes).sort();
  for (const chemin of ['ios-native/Jolene.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
    'ios-native/Packages/JoleneCore/Package.swift', 'ios-native/Packages/JoleneSupabase/Package.resolved',
    'ios-native/Packages/JoleneSupabase/Package.swift', 'ios-native/project.yml']) assert.ok(lus.includes(chemin), `${chemin} lu`);
  for (const [chemin, texte] of [
    ['ios-native/Packages/JoleneSupabase/Package.resolved', '{ "pins": [ { "identity": "capawesome-live-update", "location": "https://github.com/x/capawesome-live-update" } ] }'],
    ['ios-native/Packages/JoleneCore/Package.swift', '.package(url: "https://github.com/microsoft/code-push", from: "1.0.0")'],
    ['ios-native/project.yml', 'packages:\n  Mises:\n    url: https://github.com/x/hot-update\n'],
  ]) {
    const files = arbreClos();
    files.manifestes[chemin] = `${files.manifestes[chemin] ?? ''}\n${texte}\n`;
    refus(() => evaluateSource(files), 'ota', new RegExp(chemin.replaceAll('.', '\\.')));
  }
  for (const nom of ['Package.resolved', 'Package.swift']) {
    const files = arbreClos();
    for (const chemin of Object.keys(files.manifestes)) if (chemin.endsWith(`/${nom}`)) delete files.manifestes[chemin];
    refus(() => evaluateSource(files), 'ota', new RegExp(`aucun ${nom.replace('.', '\\.')} lu`));
  }
});

// --- Espace établissement ouvert en production (lot 5, T14) ---------------------------------

const PRODUCTION_OUVERTE = 'case .production: return .ouvert';
/** Arbre clos dont la table d'ouverture de l'espace établissement est réécrite par `remplacer`. */
const arbreEspace = (remplacer) => {
  const files = arbreClos();
  const avant = files.swiftSources[ESPACE_RESOLUTION];
  files.swiftSources[ESPACE_RESOLUTION] = remplacer(avant);
  assert.notEqual(files.swiftSources[ESPACE_RESOLUTION], avant, 'la mutation doit changer la source');
  return files;
};

test('etablissement : la table du dépôt est lue depuis la source Swift, production ouverte (T14)', () => {
  const sources = arbre().swiftSources;
  assert.deepEqual(lireModes(sources[ENVIRONNEMENT]), ['demo', 'staging', 'production'], 'JoleneMode lu dans Environment.swift');
  const lu = lireOuvertureEtablissement(sources[ESPACE_RESOLUTION], lireModes(sources[ENVIRONNEMENT]));
  assert.equal(lu.etat, 'lue', lu.raison);
  assert.equal(lu.cas.production, 'ouvert', 'T14 : production ouverte dans la source du dépôt');
  assert.ok(sources[ESPACE_RESOLUTION].includes(PRODUCTION_OUVERTE), 'ligne de production attendue par les mutations ci-dessous');
});

test('etablissement : un build dont l espace établissement est fermé en production est refusé', () => {
  refus(() => evaluateSource(arbreEspace((s) => s.replace(PRODUCTION_OUVERTE, 'case .production: return .ferme'))),
    'etablissement', /fermé en production .*return \.ferme.*DECISIONS_LOT5\.md/);
  // Production regroupée avec un autre mode : même lecture.
  refus(() => evaluateSource(arbreEspace((s) => s.replace('        case .staging: return .ouvert\n', '')
    .replace(PRODUCTION_OUVERTE, 'case .staging, .production: return .ferme'))), 'etablissement', /fermé en production/);
  // Une ligne commentée ne rouvre rien : la ligne réelle compte.
  refus(() => evaluateSource(arbreEspace((s) => s.replace(PRODUCTION_OUVERTE, '// case .production: return .ouvert\n        case .production: return .ferme'))),
    'etablissement', /fermé en production/);
});

test('etablissement : en cas de doute sur la table, refus (default, #if, mode manquant ou doublé, table absente)', () => {
  for (const [mutation, raison] of [
    [(s) => s.replace(PRODUCTION_OUVERTE, 'default: return .ouvert'), /default/],
    [(s) => s.replace(PRODUCTION_OUVERTE, '#if DEBUG\n        case .production: return .ouvert\n        #else\n        case .production: return .ferme\n        #endif'), /compilation conditionnelle/],
    [(s) => s.replace(`        ${PRODUCTION_OUVERTE}\n`, ''), /manquants : production/],
    [(s) => s.replace(PRODUCTION_OUVERTE, `${PRODUCTION_OUVERTE}\n        case .production: return .ferme`), /production décidé deux fois/],
    [(s) => s.replace(PRODUCTION_OUVERTE, 'case .production: return ouvertureProduction'), /ligne inattendue/],
    [(s) => s.replace(PRODUCTION_OUVERTE, 'case .production: return Bool.random() ? .ouvert : .ferme'), /ligne inattendue/],
  ]) refus(() => evaluateSource(arbreEspace(mutation)), 'etablissement', raison);
  const absente = arbreClos();
  delete absente.swiftSources[ESPACE_RESOLUTION];
  refus(() => evaluateSource(absente), 'etablissement', /introuvable/);
  const modes = arbreClos();
  modes.swiftSources[ENVIRONNEMENT] = modes.swiftSources[ENVIRONNEMENT].replace('case demo, staging, production', 'case demo, staging, production, recette');
  refus(() => evaluateSource(modes), 'etablissement', /manquants : recette/);
  assert.equal(lireOuvertureEtablissement(undefined, ['production']).etat, 'absente');
  assert.equal(lireModes('public enum JoleneMode { case demo; static let x = 1 }'), null, 'JoleneMode illisible : refus');
});

test('etablissement : AppContainer câble la table sur le mode de lancement, sans ouverture forcée', () => {
  for (const [avant, apres, fragment] of [
    ['espaceEtablissement: .pour(mode: environment.mode))', 'espaceEtablissement: .ferme)', /force l'ouverture .*\.ferme|ne câble pas/],
    ['espaceEtablissement: .pour(mode: environment.mode), // lot 5, T2b', 'espaceEtablissement: .ouvert, // lot 5, T2b', /force l'ouverture .*\.ouvert/],
    ['espaceEtablissement: .pour(mode: environment.mode))', 'espaceEtablissement: .pour(mode: .staging))', /force l'ouverture .*\.pour\(mode: \.staging\)/],
  ]) {
    const files = arbreClos();
    assert.ok(files.swiftSources[APP_CONTAINER].includes(avant), `${avant} attendu dans AppContainer.swift`);
    files.swiftSources[APP_CONTAINER] = files.swiftSources[APP_CONTAINER].replace(avant, apres);
    refus(() => evaluateSource(files), 'etablissement', fragment);
  }
  const sansApp = arbreClos();
  delete sansApp.swiftSources[APP_CONTAINER];
  refus(() => evaluateSource(sansApp), 'etablissement', /AppContainer\.swift absent/);
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

test('le mode verifier est le défaut ; la confirmation, exigée en mode soumettre, nomme la version configurée', () => {
  assert.match(workflow, /\n {6}mode:\n {8}description: '[^\n]+'\n {8}type: choice\n {8}options: \[verifier, soumettre\]\n {8}default: verifier\n/);
  assert.match(workflow, /\n {6}build_number:\n {8}description: '[^\n]+'\n {8}type: string\n {8}required: true\n/);
  assert.match(workflow, /\n {6}confirmation:\n {8}description: '[^\n]+'\n {8}type: string\n {8}required: false\n/);
  assert.ok(workflow.includes(`écrire exactement SOUMETTRE ${marketingVersion} (N)`), 'la description cite la version de config/mobile-release.json');
  assert.match(workflow, /\n {6}publication:\n {8}description: '[^\n]+'\n {8}type: choice\n {8}options: \[automatique, manuelle\]\n/);
  assert.doesNotMatch(actif, /default: (?:SOUMETTRE|soumettre|true|'?\d)/, 'aucune valeur par défaut ne soumet, ne confirme ni ne choisit le build');
});

// --- Câblage du workflow, lu structure par structure (revue M3 de #1177) ----------------------
// Ces tests résistent aux mutations essayées par le relecteur : retrait d'un appel de garde, `if: false`,
// `continue-on-error`, job de soumission qui ne dépend plus des gardes, build lu dans les entrées brutes.

/** Découpe le workflow (commentaires retirés) en jobs, clés de job et étapes, par indentation. */
function lireJobs(texte) {
  const lignes = texte.split('\n');
  const jobs = {};
  let jobCourant = null;
  let etape = null;
  let dansEtapes = false;
  for (const ligne of lignes.slice(lignes.indexOf('jobs:') + 1)) {
    const nomJob = /^ {2}([a-z_-]+):$/.exec(ligne);
    if (nomJob) {
      jobCourant = { nom: nomJob[1], cles: {}, etapes: [], texte: '' };
      jobs[nomJob[1]] = jobCourant;
      etape = null;
      dansEtapes = false;
      continue;
    }
    if (!jobCourant) continue;
    jobCourant.texte += `${ligne}\n`;
    const cleJob = /^ {4}([a-z-]+):(?: (.*))?$/.exec(ligne);
    if (cleJob) {
      jobCourant.cles[cleJob[1]] = cleJob[2] ?? '';
      dansEtapes = cleJob[1] === 'steps';
      etape = null;
      continue;
    }
    if (!dansEtapes) continue;
    const debut = /^ {6}- ([a-z-]+):(?: (.*))?$/.exec(ligne);
    if (debut) {
      etape = { cles: { [debut[1]]: debut[2] ?? '' }, env: {}, texte: `${ligne}\n` };
      jobCourant.etapes.push(etape);
      continue;
    }
    if (!etape) continue;
    etape.texte += `${ligne}\n`;
    const cle = /^ {8}([a-z-]+):(?: (.*))?$/.exec(ligne);
    if (cle) etape.cles[cle[1]] = cle[2] ?? '';
    const variable = /^ {10}([A-Z_]+): (.+)$/.exec(ligne);
    if (variable && etape.texte.includes('\n        env:\n')) etape.env[variable[1]] = variable[2];
  }
  return jobs;
}
const jobs = lireJobs(actif);
const scriptDe = (etape) => {
  if (etape.cles.run && etape.cles.run !== '|') return etape.cles.run;
  const bloc = /\n {8}run: \|\n((?: {10}.*\n|\n)+)/.exec(etape.texte);
  return bloc ? bloc[1].replace(/^ {10}/gm, '') : undefined;
};

test('câblage : exactement trois jobs, et seules trois conditions `if:` dans tout le workflow', () => {
  assert.deepEqual(Object.keys(jobs), ['gardes', 'soumettre', 'consigner']);
  const conditions = [...actif.matchAll(/^\s*if: (.*)$/gm)].map((m) => m[1]);
  const condition = "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main' && needs.gardes.outputs.mode == 'soumettre' && needs.gardes.outputs.verdict == 'ok'";
  assert.deepEqual(conditions, [condition, 'always()', condition], 'aucun `if: false`, aucune étape de garde conditionnelle');
  assert.equal(jobs.soumettre.cles.if, condition);
  assert.equal(jobs.consigner.cles.if, condition);
  assert.ok(!('if' in jobs.gardes.cles));
  // `continue-on-error` est interdit partout : un refus doit arrêter le run.
  assert.doesNotMatch(workflow, /continue-on-error/);
  for (const [nom, j] of Object.entries(jobs)) {
    assert.deepEqual(Object.keys(j.cles).filter((cle) => !['name', 'needs', 'if', 'runs-on', 'timeout-minutes', 'outputs', 'env', 'permissions', 'steps'].includes(cle)), [], `${nom} : clé de job inattendue`);
    for (const etape of j.etapes) {
      assert.deepEqual(Object.keys(etape.cles).filter((cle) => !['name', 'id', 'uses', 'with', 'env', 'run', 'if'].includes(cle)), [], `${nom} : clé d'étape inattendue dans ${etape.texte}`);
    }
  }
});

test('câblage : le job des gardes appelle chaque garde, dans l\'ordre, sans condition, et ne pose le verdict qu\'à la fin', () => {
  const { gardes } = jobs;
  for (const etape of gardes.etapes) assert.ok(!('if' in etape.cles), `étape conditionnelle dans les gardes : ${etape.texte}`);
  const commandes = gardes.etapes.map(scriptDe).filter((script) => script?.startsWith('node '));
  assert.deepEqual(commandes, [
    'node scripts/mobile/ios-native-app-store.mjs entrees',
    'node scripts/mobile/ios-native-testflight.mjs depot',
    'node scripts/mobile/ios-native-app-store.mjs provenance "$BUILD_NUMBER"',
    'node scripts/mobile/ios-native-app-store.mjs ci "$SOURCE_SHA"',
    'node scripts/mobile/ios-native-app-store.mjs source "$RUNNER_TEMP/source-build"',
    'node scripts/mobile/delivery-plan-backend.mjs',
    'node scripts/mobile/ios-native-app-store.mjs build "$BUILD_NUMBER"',
  ]);
  const etape = (fragment) => gardes.etapes.find((e) => scriptDe(e)?.includes(fragment));
  assert.equal(etape('mjs entrees').cles.id, 'entrees');
  assert.deepEqual(etape('mjs entrees').env, {
    JOLENE_MODE: '${{ inputs.mode }}', JOLENE_BUILD_INPUT: '${{ inputs.build_number }}',
    JOLENE_CONFIRMATION: '${{ inputs.confirmation }}', JOLENE_PUBLICATION: '${{ inputs.publication }}',
  });
  assert.equal(etape('mjs provenance').cles.id, 'provenance');
  assert.equal(etape('mjs provenance').env.BUILD_NUMBER, '${{ steps.entrees.outputs.build_number }}');
  assert.equal(etape('mjs ci').env.SOURCE_SHA, '${{ steps.provenance.outputs.source_sha }}');
  assert.equal(etape('git archive').env.SOURCE_SHA, '${{ steps.provenance.outputs.source_sha }}');
  assert.equal(etape('mjs build').env.BUILD_NUMBER, '${{ steps.entrees.outputs.build_number }}');
  // La première étape refuse tout autre déclenchement que manuel sur main ; la dernière pose le verdict.
  assert.match(scriptDe(gardes.etapes[0]), /GITHUB_EVENT_NAME/);
  const derniere = gardes.etapes.at(-1);
  assert.equal(derniere.cles.id, 'verdict');
  assert.match(scriptDe(derniere), /^echo "verdict=ok" >> "\$GITHUB_OUTPUT"\n/);
  assert.equal([...actif.matchAll(/verdict=ok/g)].length, 1, 'le verdict n\'est posé qu\'à un seul endroit');
  assert.match(gardes.texte, /\n {6}verdict: \$\{\{ steps\.verdict\.outputs\.verdict \}\}\n/);
  assert.match(gardes.texte, /\n {6}mode: \$\{\{ steps\.entrees\.outputs\.mode \}\}\n/);
  assert.match(gardes.texte, /\n {6}run_attempt: \$\{\{ steps\.entrees\.outputs\.run_attempt \}\}\n/);
  assert.match(gardes.texte, /\n {6}build_number: \$\{\{ steps\.entrees\.outputs\.build_number \}\}\n/);
  assert.match(gardes.texte, /\n {6}source_sha: \$\{\{ steps\.provenance\.outputs\.source_sha \}\}\n/);
});

test('câblage : la soumission et le tag dépendent du job des gardes et ne lisent que ses sorties', () => {
  assert.equal(jobs.soumettre.cles.needs, 'gardes');
  assert.equal(jobs.consigner.cles.needs, '[gardes, soumettre]');
  for (const variable of ['MODE: ${{ needs.gardes.outputs.mode }}', 'GARDES: ${{ needs.gardes.outputs.verdict }}',
    'GARDES_ATTEMPT: ${{ needs.gardes.outputs.run_attempt }}', 'BUILD_NUMBER: ${{ needs.gardes.outputs.build_number }}',
    'AUTOMATIC_RELEASE: ${{ needs.gardes.outputs.automatic_release }}']) {
    assert.ok(jobs.soumettre.texte.includes(`\n      IOS_NATIVE_${variable}\n`), variable);
  }
  // Les entrées brutes ne sont lues que par l'étape `entrees`, et la phrase par la lane qui la recompare.
  const lectures = [...actif.matchAll(/^\s*([A-Z_]+): \$\{\{ inputs\.(\w+) \}\}$/gm)].map((m) => `${m[1]}=${m[2]}`);
  assert.deepEqual(lectures, ['JOLENE_MODE=mode', 'JOLENE_BUILD_INPUT=build_number', 'JOLENE_CONFIRMATION=confirmation',
    'JOLENE_PUBLICATION=publication', 'IOS_NATIVE_CONFIRMATION=confirmation']);
  assert.doesNotMatch(actif.replace(/^\s*[A-Z_]+: \$\{\{ inputs\.\w+ \}\}$/gm, ''), /inputs\./);
  const lane = jobs.soumettre.etapes.find((e) => scriptDe(e)?.includes('fastlane ios submit_native'));
  assert.equal(lane.env.IOS_NATIVE_CONFIRMATION, '${{ inputs.confirmation }}');
  assert.ok(!('if' in lane.cles));
});

test('câblage : une relance partielle de la soumission ou du tag est refusée (revue m5 de #1177)', () => {
  for (const [nom, variable] of [['soumettre', 'IOS_NATIVE_GARDES_ATTEMPT'], ['consigner', 'GARDES_ATTEMPT']]) {
    const [premiere] = jobs[nom].etapes;
    const script = scriptDe(premiere);
    assert.match(premiere.cles.name, /relance partielle/i, `${nom} : la première étape refuse une relance partielle`);
    assert.ok(!('if' in premiere.cles));
    // Le script de l'étape est exécuté tel qu'écrit dans le workflow.
    const lancer = (gardes, tentative) => spawnSync('bash', ['-c', script], {
      encoding: 'utf8', env: { PATH: process.env.PATH, [variable]: gardes, GITHUB_RUN_ATTEMPT: tentative } });
    assert.equal(lancer('1', '1').status, 0);
    assert.equal(lancer('3', '3').status, 0);
    for (const [gardes, tentative] of [['1', '2'], ['', '1'], ['2', '1']]) {
      const resultat = lancer(gardes, tentative);
      assert.notEqual(resultat.status, 0, `${nom} : gardes ${gardes}, tentative ${tentative}`);
      assert.match(resultat.stdout, /Relancer le workflow entier/i);
    }
  }
  assert.match(jobs.consigner.etapes[0].env.GARDES_ATTEMPT, /^\$\{\{ needs\.gardes\.outputs\.run_attempt \}\}$/);
});

test('câblage : la première étape des gardes refuse tout déclenchement hors manuel sur main', () => {
  const script = scriptDe(jobs.gardes.etapes[0]);
  const lancer = (event, ref) => spawnSync('bash', ['-c', script], { encoding: 'utf8', env: { PATH: process.env.PATH, GITHUB_EVENT_NAME: event, GITHUB_REF: ref } });
  assert.equal(lancer('workflow_dispatch', 'refs/heads/main').status, 0);
  for (const [event, ref] of [['push', 'refs/heads/main'], ['workflow_dispatch', 'refs/heads/lot6/preparation'], ['workflow_dispatch', 'refs/tags/main']]) {
    assert.notEqual(lancer(event, ref).status, 0, `${event} ${ref}`);
  }
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
  // Revue m4 de #1177 : les deux autres workflows de livraison touchés par la PR aussi, avec leur version
  // en commentaire, et sans jeton persistant dans les checkouts de mobile-delivery.yml.
  for (const fichier of ['.github/workflows/mobile-delivery.yml', '.github/workflows/ios-native-testflight.yml']) {
    const lignes = lire(fichier).split('\n').filter((ligne) => /^\s*(?:- )?uses: /.test(ligne));
    assert.ok(lignes.length >= 5, fichier);
    for (const ligne of lignes) assert.match(ligne, /uses: [\w.-]+\/[\w./-]+@[a-f0-9]{40} # v\d+\.\d+\.\d+$/, `${fichier} : ${ligne.trim()}`);
  }
  const livraison = lire('.github/workflows/mobile-delivery.yml');
  assert.equal([...livraison.matchAll(/uses: actions\/checkout@/g)].length, [...livraison.matchAll(/persist-credentials: false/g)].length);
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
  // Revue m8 de #1177 : contexte du workflow, verdict des gardes et phrase exacte avant toute lecture chez Apple.
  const contexte = lane.indexOf('IosReviewSubmission.exiger_contexte_workflow!(env: ENV, marketing: marketing, number: number)');
  assert.ok(contexte > 0, 'la lane contrôle son contexte');
  for (const suite of ['app_store_connect_api_key(', 'guard.prepare!', 'upload_to_app_store(']) assert.ok(contexte < lane.indexOf(suite), suite);
  assert.match(lane, /rescue IosReviewSubmission::Failure => error\n\s+UI\.user_error!\(error\.message\)/);
});

test('la coquille Capacitor iOS n\'a plus de lane de soumission', () => {
  const coquille = fastfile.slice(fastfile.indexOf('lane :submit do'), fastfile.indexOf('lane :submit_native'));
  assert.match(coquille, /UI\.user_error!/);
  assert.doesNotMatch(coquille, /upload_to_app_store|upload_to_testflight|deliver/);
  assert.match(coquille, /ios-native-app-store\.yml/);
});

test('le mode d\'emploi existe et nomme chaque garde', () => {
  const doc = lire('docs/mobile-swift/APP_STORE.md');
  for (const garde of ['entrees', 'notes', 'provenance', 'ci-ios', 'lots', 'etablissement', 'apple-4.2', 'ota', 'build']) assert.ok(doc.includes(`\`${garde}\``), `garde ${garde} absente du mode d'emploi`);
  assert.ok(doc.includes(phraseConfirmation(marketingVersion, 'N')));
  // Revue m6 de #1177 : documents alignés sur le code.
  assert.doesNotMatch(doc, /montés par les onglets/, 'le montage du pointage n\'est pas contrôlé');
  assert.match(doc, /PENDING_DEVELOPER_RELEASE|Pending Developer\s+Release/);
  assert.match(doc, /Re-run all jobs/);
  const readme = lire('fastlane/README-ios-review.md');
  assert.match(readme, /`ios submit_native` never uploads a binary/);
  assert.doesNotMatch(readme, /`ios submit` uploads/);
});

// --- Interface en ligne de commande, en sous-processus (revue M3 de #1177) ---------------------
// Le vrai script tourne avec un `fetch` simulé (aucun réseau, aucun secret réel, aucune écriture) :
// retirer un appel de garde de main(), ou un contrôle d'événement, de branche, de main, d'ascendance,
// rend ces tests rouges.

const SCRIPT = join(root, 'scripts/mobile/ios-native-app-store.mjs');
const GITHUB = 'https://api.github.com/repos/Gabpcd/JJJJJ/';
const ASC = 'https://api.appstoreconnect.apple.com/v1/';
const TETE = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
const ETRANGER = 'c'.repeat(40);

const FAUX_FETCH = `
import { appendFileSync, readFileSync } from 'node:fs';
const routes = JSON.parse(readFileSync(process.env.JOLENE_ROUTES, 'utf8'));
globalThis.fetch = async (url, init = {}) => {
  const cible = decodeURIComponent(new URL(String(url)).href);
  const method = init.method ?? 'GET';
  appendFileSync(process.env.JOLENE_REQUETES, JSON.stringify({ method, url: cible }) + '\\n');
  if (method !== 'GET') return new Response('{}', { status: 405 });
  const route = routes.find((r) => cible.startsWith(r.prefixe));
  if (!route) return Response.json({ message: 'route simulée absente' }, { status: 404 });
  return Response.json(route.corps, { status: route.statut ?? 200 });
};
`;

function cli(t, { args, env = {}, routes = [], script = SCRIPT }) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-app-store-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  for (const fichier of ['output', 'summary', 'requetes']) writeFileSync(join(dir, fichier), '');
  writeFileSync(join(dir, 'routes.json'), JSON.stringify(routes));
  writeFileSync(join(dir, 'fetch.mjs'), FAUX_FETCH);
  const resultat = spawnSync(process.execPath, ['--import', join(dir, 'fetch.mjs'), script, ...args], {
    cwd: dir, encoding: 'utf8',
    env: { PATH: process.env.PATH, GITHUB_OUTPUT: join(dir, 'output'), GITHUB_STEP_SUMMARY: join(dir, 'summary'),
      JOLENE_ROUTES: join(dir, 'routes.json'), JOLENE_REQUETES: join(dir, 'requetes'), ...env },
  });
  const requetes = readFileSync(join(dir, 'requetes'), 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l));
  // Lecture seule : aucune requête autre que GET, vers GitHub ou App Store Connect seulement.
  for (const requete of requetes) {
    assert.equal(requete.method, 'GET');
    assert.ok(requete.url.startsWith(GITHUB) || requete.url.startsWith(ASC), requete.url);
  }
  return { ...resultat, requetes, sortie: readFileSync(join(dir, 'output'), 'utf8') };
}
const refuseCli = (resultat, motif) => {
  assert.notEqual(resultat.status, 0, `refus attendu, sortie : ${resultat.stdout}`);
  assert.match(resultat.stderr, motif);
  assert.equal(resultat.sortie, '', 'aucune sortie de garde après un refus');
};

const ENTREES = {
  GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_REF: 'refs/heads/main', GITHUB_RUN_ATTEMPT: '1', JOLENE_MODE: 'soumettre',
  JOLENE_BUILD_INPUT: String(BUILD), JOLENE_CONFIRMATION: phraseConfirmation(marketingVersion, BUILD), JOLENE_PUBLICATION: 'automatique',
};

test('cli entrees : mode, build, confirmation, publication et tentative sortent seulement après toutes les gardes', (t) => {
  const ok = cli(t, { args: ['entrees'], env: ENTREES });
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(ok.sortie, `mode=soumettre\nbuild_number=${BUILD}\nmarketing_version=${marketingVersion}\nautomatic_release=true\nrun_attempt=1\n`);
  const verifier = cli(t, { args: ['entrees'], env: { ...ENTREES, JOLENE_MODE: 'verifier', JOLENE_CONFIRMATION: '', GITHUB_RUN_ATTEMPT: '2' } });
  assert.equal(verifier.status, 0, verifier.stderr);
  assert.match(verifier.sortie, /^mode=verifier\n.*run_attempt=2\n$/s);
  for (const [patch, motif] of [
    [{ GITHUB_EVENT_NAME: 'push' }, /déclenchement manuel sur main/],
    [{ GITHUB_REF: 'refs/heads/lot6/preparation' }, /déclenchement manuel sur main/],
    [{ GITHUB_REF: 'refs/tags/main' }, /déclenchement manuel sur main/],
    [{ GITHUB_RUN_ATTEMPT: '' }, /GITHUB_RUN_ATTEMPT/],
    [{ JOLENE_MODE: '' }, /\[entrees\] mode inconnu/],
    [{ JOLENE_CONFIRMATION: 'saisie-secrete' }, /\[entrees\] confirmation absente ou inexacte/],
    [{ JOLENE_BUILD_INPUT: '24' }, /\[entrees\] build 24 refusé/],
  ]) {
    const resultat = cli(t, { args: ['entrees'], env: { ...ENTREES, ...patch } });
    refuseCli(resultat, motif);
    assert.doesNotMatch(resultat.stderr + resultat.stdout, /saisie-secrete/);
  }
});

test('cli entrees : des notes de version non conformes arrêtent les gardes', (t) => {
  // Copie minimale du dépôt : le script lit ses notes à la racine de sa propre copie.
  // Chemin réel : sous macOS, le dossier temporaire est un lien, et le script ne se lance que s'il est
  // appelé par son propre chemin.
  const copie = realpathSync(mkdtempSync(join(tmpdir(), 'jolene-app-store-racine-')));
  t.after(() => rmSync(copie, { recursive: true, force: true }));
  mkdirSync(join(copie, 'scripts/mobile'), { recursive: true });
  mkdirSync(join(copie, 'config'));
  for (const fichier of ['ios-native-app-store.mjs', 'ios-native-testflight.mjs', 'release-config.mjs']) cpSync(join(root, 'scripts/mobile', fichier), join(copie, 'scripts/mobile', fichier));
  cpSync(join(root, 'config/mobile-release.json'), join(copie, 'config/mobile-release.json'));
  const script = join(copie, 'scripts/mobile/ios-native-app-store.mjs');
  writeFileSync(join(copie, NOTES), lire(NOTES));
  const ok = cli(t, { args: ['entrees'], env: ENTREES, script });
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.sortie, /^mode=soumettre\n/, 'la copie exécute bien ses gardes');
  writeFileSync(join(copie, NOTES), 'Corrections diverses.\n');
  refuseCli(cli(t, { args: ['entrees'], env: ENTREES, script }), /\[notes\]/);
  rmSync(join(copie, NOTES));
  refuseCli(cli(t, { args: ['entrees'], env: ENTREES, script }), /\[notes\] .*absent ou vide/);
  assert.ok(!existsSync(join(copie, NOTES)));
});

const routesProvenance = ({ main = TETE, source = TETE } = {}) => [
  { prefixe: `${GITHUB}git/ref/heads/main`, corps: { object: { sha: main } } },
  { prefixe: `${GITHUB}actions/workflows/ios-native-testflight.yml/runs?`, corps: { total_count: 1, workflow_runs: [run(4242, source)] } },
  { prefixe: `${GITHUB}actions/runs/4242/artifacts?`, corps: { artifacts: [{ name: `ios-native-testflight-${BUILD}-${source}`, expired: false }] } },
];
const PROVENANCE = { GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', GITHUB_TOKEN: 'jeton-de-test', GITHUB_SHA: TETE };

test('cli provenance : main inchangé, run TestFlight de main, commit dans l\'historique de main', (t) => {
  const ok = cli(t, { args: ['provenance', String(BUILD)], env: PROVENANCE, routes: routesProvenance() });
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(ok.sortie, `source_sha=${TETE}\n`);
  assert.ok(ok.requetes.some((r) => r.url === `${GITHUB}git/ref/heads/main`), 'la tête de main est relue');
  refuseCli(cli(t, { args: ['provenance', String(BUILD)], env: PROVENANCE, routes: routesProvenance({ main: ETRANGER }) }), /\[provenance\] main a avancé/);
  refuseCli(cli(t, { args: ['provenance', String(BUILD)], env: PROVENANCE, routes: routesProvenance({ source: ETRANGER }) }), /\[provenance\] le commit c{12} .*n'appartient pas à l'historique de main/);
  refuseCli(cli(t, { args: ['provenance', String(BUILD)], env: PROVENANCE, routes: routesProvenance().slice(0, 2) }), /GitHub 404|\[provenance\]/);
  refuseCli(cli(t, { args: ['provenance', String(BUILD)], env: { ...PROVENANCE, GITHUB_REPOSITORY: 'fork/JJJJJ' }, routes: routesProvenance() }), /Dépôt inattendu/);
});

test('cli ci : le dernier run de ios-swift-ci.yml sur le commit source doit être réussi (revue M1 de #1177)', (t) => {
  const routes = (runs) => [{ prefixe: `${GITHUB}actions/workflows/ios-swift-ci.yml/runs?head_sha=${TETE}&branch=main`, corps: { total_count: runs.length, workflow_runs: runs } }];
  const ci = (patch = {}) => ({ ...runCi(51, patch), head_sha: TETE });
  const ok = cli(t, { args: ['ci', TETE], env: PROVENANCE, routes: routes([ci()]) });
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.stdout, /CI iOS .*run 51/);
  refuseCli(cli(t, { args: ['ci', TETE], env: PROVENANCE, routes: routes([ci({ conclusion: 'failure' })]) }), new RegExp(`\\[ci-ios\\] .*${TETE.slice(0, 12)} .*conclusion « failure »`));
  refuseCli(cli(t, { args: ['ci', TETE], env: PROVENANCE, routes: routes([]) }), /\[ci-ios\] aucun run/);
  refuseCli(cli(t, { args: ['ci', 'abc'], env: PROVENANCE, routes: routes([ci()]) }), /ci <commit source du build> exigé/);
});

function arbreSurDisque(t, modifier = () => {}) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-app-store-source-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  cpSync(join(root, 'ios-native'), join(dir, 'ios-native'), { recursive: true, filter: (chemin) => !/\/(?:\.build|DerivedData)(?:\/|$)/.test(chemin) });
  const chemin = join(dir, DEMO_WORLD_TESTS);
  writeFileSync(chemin, clore(readFileSync(chemin, 'utf8')));
  modifier(dir);
  return dir;
}

test('cli source : la garde rejoue lots, établissement, Apple 4.2 et OTA sur l\'arbre extrait', (t) => {
  const ok = cli(t, { args: ['source', arbreSurDisque(t)] });
  assert.equal(ok.status, 0, ok.stderr);
  const lot3 = arbreSurDisque(t, (dir) => {
    const chemin = join(dir, DEMO_WORLD_TESTS);
    writeFileSync(chemin, readFileSync(chemin, 'utf8').replace('static let portsEnAttenteLot3: [String] = []', 'static let portsEnAttenteLot3 = ["paiements"]'));
  });
  refuseCli(cli(t, { args: ['source', lot3] }), /\[lots\] le lot 3 n'est pas clos .*paiements/);
  const ota = arbreSurDisque(t, (dir) => {
    const chemin = join(dir, 'ios-native/Packages/JoleneSupabase/Package.resolved');
    writeFileSync(chemin, `${readFileSync(chemin, 'utf8')}\n// capawesome-live-update\n`);
  });
  refuseCli(cli(t, { args: ['source', ota] }), /\[ota\] .*Package\.resolved/);
  // Lot 5, T14 : l'espace établissement refermé en production dans l'arbre extrait bloque la soumission.
  const ferme = arbreSurDisque(t, (dir) => {
    const chemin = join(dir, ESPACE_RESOLUTION);
    writeFileSync(chemin, readFileSync(chemin, 'utf8').replace('case .production: return .ouvert', 'case .production: return .ferme'));
  });
  refuseCli(cli(t, { args: ['source', ferme] }), /\[etablissement\] espace établissement fermé en production/);
  if (portsEnAttente(lire(DEMO_WORLD_TESTS), 1)?.length) refuseCli(cli(t, { args: ['source', root] }), /\[lots\] le lot 1 n'est pas clos/);
});

test('cli build : lecture seule d\'App Store Connect, refus d\'un build non VALID ou sans secret', (t) => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const secrets = { ASC_KEY_ID: 'CLE-TEST', ASC_ISSUER_ID: 'emetteur-test',
    ASC_PRIVATE_KEY_BASE64: Buffer.from(privateKey.export({ type: 'pkcs8', format: 'pem' })).toString('base64') };
  const routes = (corps) => [
    { prefixe: `${ASC}apps/${APP.appleId}?`, corps: { data: { attributes: { bundleId: APP.bundleId } } } },
    { prefixe: `${ASC}builds?filter[app]=${APP.appleId}&filter[version]=${BUILD}&`, corps },
  ];
  const ok = cli(t, { args: ['build', String(BUILD)], env: secrets, routes: routes(reponse()) });
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(ok.requetes.length, 2);
  refuseCli(cli(t, { args: ['build', String(BUILD)], env: secrets, routes: routes(reponse({ processingState: 'PROCESSING' })) }), /\[build\] .*PROCESSING/);
  refuseCli(cli(t, { args: ['build', String(BUILD)], env: secrets, routes: routes(reponse({}, { version: '1.0.7' })) }), /\[build\] .*1\.0\.7/);
  const sansSecret = cli(t, { args: ['build', String(BUILD)], env: { ...secrets, ASC_PRIVATE_KEY_BASE64: '' }, routes: routes(reponse()) });
  refuseCli(sansSecret, /Secrets App Store Connect manquants/);
  assert.equal(sansSecret.requetes.length, 0, 'aucun appel sans secret');
  assert.doesNotMatch(ok.stdout + ok.stderr, /BEGIN PRIVATE KEY|CLE-TEST/);
});
