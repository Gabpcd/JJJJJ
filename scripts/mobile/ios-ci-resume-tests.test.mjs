// Tests de `ios-ci-resume-tests.mjs` : relevé des tests échoués, des tests les plus longs et du temps passé de chaque
// éclat XCUITest (étape « Résumé xcresult » des jobs `ui` et `ui-lot1` de `.github/workflows/ios-swift-ci.yml`).
// Exécuté par le job « Cœur » de ios-swift-ci.yml : `node --test scripts/mobile/ios-ci-resume-tests.test.mjs`.
// Aucun simulateur, aucun réseau, aucun secret : `xcrun` est simulé, les bundles sont des dossiers vides.
//
// Les deux scénarios reprennent le run 45239724447 (main `f6e6be49`, UI — ipad-portrait, éclat « pointage ») :
// - tentative 1 (job 137920791850) : durées et message d'échec recopiés du journal du job ;
// - tentative 2 (job 138340510274) : éclat coupé à 30 min. Le journal xcodebuild de l'éclat n'a pas été lu (il n'existe
//   que dans l'artefact) : les lignes d'activité du scénario sont RECONSTITUÉES d'après les heures des événements
//   synthétisés relevées dans le journal du job (un événement toutes les 2 min 8 s après la fermeture du pavé). Elles
//   prouvent ce que le relevé sait lire, pas ce que ce journal contenait.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import {
  MARQUE_GARDE_REPOS,
  MARQUES_INACTIVITE,
  SEUIL_SILENCE_S,
  SEUIL_TEST_LONG_S,
  TRONCATURE_MESSAGE,
  collecter,
  dureeDuNoeud,
  formaterDuree,
  lireJournal,
  main,
  parserDuree,
  pileDominante,
  rendre,
  resumerEclat,
  testsDeLArbre,
} from './ios-ci-resume-tests.mjs';

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), 'ios-ci-resume-tests.mjs');

// MARK: - Fixtures

/** Nœud « Test Case » de `xcresulttool get test-results tests` (schéma imprimé par `--help`, Xcode 16.4 et suivants). */
const cas = (suite, nom, resultat, secondes, enfants = []) => ({
  children: enfants,
  duration: secondes === null ? undefined : `${Math.floor(secondes / 60)}m ${Math.round(secondes % 60)}s`,
  durationInSeconds: secondes === null ? undefined : secondes,
  name: `${nom}()`,
  nodeIdentifier: `${suite}/${nom}()`,
  nodeIdentifierURL: `test://com.apple.xcode/Jolene/JoleneUITests/${suite}/${nom}`,
  nodeType: 'Test Case',
  result: resultat,
});
const echec = message => ({ name: message, nodeType: 'Failure Message', result: 'Failed' });
const arbre = (suite, tests, cible = 'JoleneUITests') => ({
  devices: [{ architecture: 'arm64', deviceId: 'UDID', deviceName: 'iPad (A16)', modelName: 'iPad (A16)', osVersion: '26.2', platform: 'iOS Simulator' }],
  testNodes: [{
    name: 'Jolene', nodeType: 'Test Plan', result: 'Failed',
    children: [{ name: cible, nodeType: 'UI test bundle', result: 'Failed', children: [{ name: suite, nodeType: 'Test Suite', result: 'Failed', children: tests }] }],
  }],
  testPlanConfigurations: [{ configurationId: '1', configurationName: 'Test Scheme Action' }],
});

const MESSAGE_T1 = "DemoPointageUITestCase.swift:203: failed - Compteurs relus après l'action — condition fausse à chacune des 14 évaluations sur 15,0 s décomptées";
// Tentative 1 : dix tests, durées du journal du job 137920791850 (ordre d'exécution, alphabétique).
const TESTS_T1 = [
  ['testConsentementAccepteRefusVerbatimPuisOuvertureEtFermeture', 'Passed', 140.070],
  ['testConsentementRefusePointeSansPositionEtAfficheLeBandeau', 'Passed', 62.760],
  ['testConsentementRetireEtReactiveDepuisLeProfil', 'Passed', 124.519],
  ['testHorsLigneDesactiveLePointageSansAucunEnvoi', 'Failed', 92.840],
  ['testLocalisationRefuseeParLAppareilPointeSansCoordonnees', 'Passed', 73.059],
  ['testPrecisionReduiteNEnvoieAucunePositionEtAfficheLEncart', 'Passed', 66.880],
  ['testQRDetecteDeuxFoisNEnvoieQuUnScan', 'Passed', 57.474],
  ['testQRIllisibleGardeLaCameraPuisSaisieManuelle', 'Passed', 45.459],
  ['testRefusDeLaCameraRendLaSaisieManuelle', 'Passed', 83.152],
  ['testScanIncertainReconcilieParRelectureSansSecondScan', 'Passed', 76.478],
];
const ARBRE_T1 = arbre('DemoPointageTests', TESTS_T1.map(([nom, resultat, s]) =>
  cas('DemoPointageTests', nom, resultat, s, resultat === 'Failed' ? [echec(MESSAGE_T1)] : [])));

const ligneDebut = nom => `Test Case '-[JoleneUITests.DemoPointageTests ${nom}]' started.`;
const ligneFin = (nom, issue, s) => `Test Case '-[JoleneUITests.DemoPointageTests ${nom}]' ${issue} (${s.toFixed(3)} seconds).`;
const activite = (t, texte, retrait = '') => `    t = ${t.toFixed(2).padStart(8)}s ${retrait}${texte}`;
const ERREUR_T1 = "/Users/runner/work/JJJJJ/JJJJJ/ios-native/JoleneUITests/DemoPointageUITestCase.swift:203: error: -[JoleneUITests.DemoPointageTests testHorsLigneDesactiveLePointageSansAucunEnvoi] : failed - Compteurs relus après l'action — condition fausse à chacune des 14 évaluations sur 15,0 s décomptées";
const JOURNAL_T1 = [
  "Test Suite 'Selected tests' started at 2026-11-24 00:50:43.593.",
  "Test Suite 'JoleneUITests.xctest' started at 2026-11-24 00:50:43.593.",
  "Test Suite 'DemoPointageTests' started at 2026-11-24 00:50:43.593.",
  ...TESTS_T1.flatMap(([nom, resultat, s]) => [
    ligneDebut(nom),
    activite(0, 'Start Test at 2026-11-24 00:50:43.594'),
    activite(0.11, 'Set Up'),
    activite(0.12, 'Open app.jolene.ios'),
    activite(2.4, 'Wait for app.jolene.ios to idle', '    '),
    activite(s - 18, 'Tap "pointage-demo-relire" Button'),
    activite(s - 17.9, 'Wait for app.jolene.ios to idle', '    '),
    activite(s - 17.5, 'Synthesize event', '    '),
    activite(s - 1.2, 'Tear Down'),
    ...(resultat === 'Failed' ? [ERREUR_T1] : []),
    ligneFin(nom, resultat === 'Failed' ? 'failed' : 'passed', s),
  ]),
  "Test Suite 'DemoPointageTests' failed at 2026-11-24 01:04:26.313.",
  '** TEST EXECUTE FAILED **',
].join('\n');

// Tentative 2 : huit réussis, deux échoués ; le premier a épuisé son délai d'exécution de 10 min, le dernier était en
// cours quand l'étape a été coupée. Lignes d'activité reconstituées (voir l'en-tête).
const IDLE = 'App event loop idle notification not received, will attempt to continue.';
const lent = debut => [
  activite(debut, 'Tap "pointage-submit-demo-presence-a" Button'),
  activite(debut + 0.1, 'Wait for app.jolene.ios to idle', '    '),
  activite(debut + 60.1, IDLE, '        '),
  activite(debut + 60.4, 'Find the "pointage-submit-demo-presence-a" Button', '    '),
  activite(debut + 61.0, 'Synthesize event', '    '),
  activite(debut + 61.3, 'Wait for app.jolene.ios to idle', '    '),
  activite(debut + 121.3, IDLE, '        '),
];
const TESTS_T2 = TESTS_T1.map(([nom], i) => [nom, i === 0 || i === 9 ? 'Failed' : 'Passed', i === 0 ? 600.9 : i === 9 ? null : 90 + i]);
const MESSAGE_DELAI = 'Test exceeded execution time allowance of 10 minutes';
const ARBRE_T2 = arbre('DemoPointageTests', TESTS_T2.map(([nom, resultat, s], i) =>
  cas('DemoPointageTests', nom, resultat, s, i === 0 ? [echec(MESSAGE_DELAI)] : [])));
const JOURNAL_T2 = [
  "Test Suite 'DemoPointageTests' started at 2026-11-24 09:57:29.100.",
  ligneDebut(TESTS_T2[0][0]),
  activite(0, 'Start Test at 2026-11-24 09:57:29.101'),
  activite(90.2, 'Tap "OK" Button'),
  activite(90.9, 'Synthesize event', '    '),
  ...lent(92), ...lent(220), ...lent(348),
  activite(600.2, `Test exceeded execution time allowance of 10 minutes`),
  ligneFin(TESTS_T2[0][0], 'failed', 600.9),
  ...TESTS_T2.slice(1, 9).flatMap(([nom, , s]) => [ligneDebut(nom), activite(0, 'Start Test'), activite(s - 1, 'Tear Down'), ligneFin(nom, 'passed', s)]),
  ligneDebut(TESTS_T2[9][0]),
  activite(0, 'Start Test at 2026-11-24 10:25:40.000'),
  activite(71.4, 'Tap "pointage-code-demo-presence-a" TextField'),
].join('\n');

// `sample` réel (macOS 26.5, `sample <pid> 1`) réduit à ses premières lignes, puis un graphe à deux branches à la
// forme des piles relevées au gel du 16/11/2026 (DECISIONS_LOT2, « Gel iPhone CI — 16/11/2026 »).
const SAMPLE_REEL = `Analysis of sampling sleep (pid 34405) every 1 millisecond
Process:         sleep [34405]
Path:            /bin/sleep

Call graph:
    821 Thread_50487846   DispatchQueue_1: com.apple.main-thread  (serial)
      821 start  (in dyld) + 6992  [0x18ac13e00]
        821 ???  (in sleep)  load address 0x104184000 + 0x740  [0x104184740]
          821 nanosleep  (in libsystem_c.dylib) + 220  [0x18ae6dcc0]
            821 __semwait_signal  (in libsystem_kernel.dylib) + 8  [0x18af91308]

Total number in stack (recursive counted multiple, when >=5):

Sort by top of stack, same collapsed (when >= 5):
        __semwait_signal  (in libsystem_kernel.dylib)        821
`;
const SAMPLE_GEL = `Analysis of sampling Jolene (pid 4242) every 1 millisecond
Process:         Jolene [4242]

Call graph:
    4118 Thread_812345   DispatchQueue_1: com.apple.main-thread  (serial)
    + 4118 start  (in dyld) + 6076  [0x1801d5d3c]
    +   4118 main  (in Jolene) + 120  [0x104a0c0f8]
    +     4118 UIApplicationMain  (in UIKitCore) + 148  [0x185b6e6d0]
    +       310 __CFRunLoopRun  (in CoreFoundation) + 1208  [0x18041b7e0]
    +       ! 310 mach_msg2_trap  (in libsystem_kernel.dylib) + 8  [0x1804d0b18]
    +       3808 _UIUpdateCycleNotifyIdle  (in UIKitCore) + 92  [0x1852a0f1c]
    +         3808 CA::Transaction::commit()  (in QuartzCore) + 1152  [0x18b0b4a40]
    +           3808 CA::Render::Message::send_message()  (in QuartzCore) + 40  [0x18b0f2c08]
    +             3808 mach_msg2_trap  (in libsystem_kernel.dylib) + 8  [0x1804d0b18]
    4118 Thread_812377
    + 4118 start_wqthread  (in libsystem_pthread.dylib) + 8  [0x18050a0bc]
    +   4118 __workq_kernreturn  (in libsystem_kernel.dylib) + 8  [0x1804d2a5c]

Total number in stack (recursive counted multiple, when >=5):
`;

/** Bac à sable : `xcrun` simulé en tête du PATH, sortie et bundles temporaires. */
function bac({ arbres = {}, journaux = {}, fichiers = {}, xcrun } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-resume-'));
  const bin = join(dir, 'bin');
  const sortie = join(dir, 'sortie');
  const bundles = join(dir, 'runner-temp');
  const reponses = join(dir, 'reponses');
  for (const d of [bin, sortie, bundles, reponses]) mkdirSync(d);
  for (const [eclat, contenu] of Object.entries(arbres)) {
    mkdirSync(join(bundles, `ui-ipad-portrait-${eclat}.xcresult`));
    if (contenu !== null) writeFileSync(join(reponses, `ui-ipad-portrait-${eclat}.json`), typeof contenu === 'string' ? contenu : JSON.stringify(contenu));
  }
  for (const [eclat, texte] of Object.entries(journaux)) writeFileSync(join(sortie, `test-without-building-${eclat}.log`), texte);
  for (const [chemin, texte] of Object.entries(fichiers)) {
    mkdirSync(dirname(join(sortie, chemin)), { recursive: true });
    writeFileSync(join(sortie, chemin), texte);
  }
  // `xcrun xcresulttool get test-results tests --path <bundle>` : rend le JSON préparé pour ce bundle, sinon échoue.
  const corps = xcrun ?? [
    'chemin=""; while [ $# -gt 0 ]; do if [ "$1" = --path ]; then chemin="$2"; fi; shift; done',
    `reponse="${reponses}/$(basename "$chemin" .xcresult).json"`,
    'if [ -f "$reponse" ]; then cat "$reponse"; else echo "Error: illisible" >&2; exit 1; fi',
  ].join('\n');
  writeFileSync(join(bin, 'xcrun'), `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> '${join(dir, 'appels.log')}'\n${corps}\n`);
  chmodSync(join(bin, 'xcrun'), 0o755);
  const resume = join(dir, 'resume.md');
  const env = { PATH: `${bin}:${process.env.PATH}`, JOLENE_UI_FORMAT: 'ipad-portrait', JOLENE_UI_OUTPUT: sortie, RUNNER_TEMP: bundles, GITHUB_STEP_SUMMARY: resume };
  return {
    dir, sortie, bundles, env,
    lancer: (eclats, surcharge = {}) => spawnSync(process.execPath, [SCRIPT, ...eclats], { encoding: 'utf8', timeout: 60_000, env: { ...env, ...surcharge } }),
    resume: () => (existsSync(resume) ? readFileSync(resume, 'utf8') : ''),
    appels: () => (existsSync(join(dir, 'appels.log')) ? readFileSync(join(dir, 'appels.log'), 'utf8').trim().split('\n') : []),
    nettoyer: () => rmSync(dir, { recursive: true, force: true }),
  };
}

// MARK: - Durées

test('durées : secondes de l xcresult, sinon durée lisible ; format français', () => {
  assert.equal(parserDuree('1m 33s'), 93);
  assert.equal(parserDuree('2h 1m 3s'), 7263);
  assert.equal(parserDuree('45s'), 45);
  assert.equal(parserDuree('0.25s'), 0.25);
  assert.equal(parserDuree('0,5s'), 0.5);
  assert.equal(parserDuree('1d 2h'), 93600);
  assert.equal(parserDuree(''), null);
  assert.equal(parserDuree(undefined), null);
  assert.equal(parserDuree('bientôt'), null);
  assert.equal(dureeDuNoeud({ durationInSeconds: 92.84, duration: '9m 99s' }), 92.84, 'le nombre prime');
  assert.equal(dureeDuNoeud({ duration: '2m 20s' }), 140);
  assert.equal(dureeDuNoeud({}), null);
  assert.equal(formaterDuree(92.84), '1 min 33 s');
  assert.equal(formaterDuree(600.9), '10 min 01 s');
  assert.equal(formaterDuree(45.459), '45,5 s');
  assert.equal(formaterDuree(0.004), '0,0 s');
  assert.equal(formaterDuree(3725), '1 h 02 min 05 s');
  assert.equal(formaterDuree(null), 'durée inconnue');
});

// MARK: - Arbre xcresult

test('arbre xcresult : chaque Test Case avec sa classe, son résultat, sa durée et son premier message d échec', () => {
  const tests = testsDeLArbre(ARBRE_T1);
  assert.equal(tests.length, 10);
  const horsLigne = tests.find(t => t.nom === 'testHorsLigneDesactiveLePointageSansAucunEnvoi');
  assert.deepEqual(horsLigne, {
    cle: 'DemoPointageTests.testHorsLigneDesactiveLePointageSansAucunEnvoi', classe: 'DemoPointageTests',
    nom: 'testHorsLigneDesactiveLePointageSansAucunEnvoi', cible: 'JoleneUITests', resultat: 'Failed', duree: 92.84, message: MESSAGE_T1,
  });
  assert.equal(tests.filter(t => t.resultat === 'Failed').length, 1);
  assert.equal(tests[0].message, null, 'un test réussi n a pas de message');
});

test('arbre xcresult : message d échec sous un nœud de répétition, identifiant absent, arbre vide ou étranger', () => {
  const repete = arbre('DemoPointageTests', [{
    name: 'testX()', nodeType: 'Test Case', result: 'Failed', duration: '1m 2s',
    children: [{ name: 'iPad (A16)', nodeType: 'Device', children: [
      { name: 'Run 1', nodeType: 'Repetition', result: 'Failed', children: [echec('premier message'), echec('second message')] }] }],
  }]);
  assert.deepEqual(testsDeLArbre(repete), [{ cle: 'DemoPointageTests.testX', classe: 'DemoPointageTests', nom: 'testX', cible: 'JoleneUITests',
    resultat: 'Failed', duree: 62, message: 'premier message' }]);
  assert.deepEqual(testsDeLArbre({ testNodes: [] }), []);
  assert.deepEqual(testsDeLArbre(null), []);
  assert.deepEqual(testsDeLArbre({ autre: 1 }), []);
  assert.deepEqual(testsDeLArbre('texte'), []);
});

// MARK: - Journal xcodebuild

test('journal : issue, durée, première erreur et test resté sans conclusion', () => {
  const { tests } = lireJournal(JOURNAL_T1);
  assert.equal(tests.size, 10);
  const horsLigne = tests.get('DemoPointageTests.testHorsLigneDesactiveLePointageSansAucunEnvoi');
  assert.equal(horsLigne.issue, 'failed');
  assert.equal(horsLigne.duree, 92.84);
  assert.equal(horsLigne.sansConclusion, false);
  assert.deepEqual(horsLigne.erreur, {
    fichier: '/Users/runner/work/JJJJJ/JJJJJ/ios-native/JoleneUITests/DemoPointageUITestCase.swift', ligne: 203,
    message: "failed - Compteurs relus après l'action — condition fausse à chacune des 14 évaluations sur 15,0 s décomptées",
  });
  assert.equal(tests.get('DemoPointageTests.testQRDetecteDeuxFoisNEnvoieQuUnScan').issue, 'passed');

  const coupe = lireJournal(JOURNAL_T2).tests;
  const dernier = coupe.get('DemoPointageTests.testScanIncertainReconcilieParRelectureSansSecondScan');
  assert.equal(dernier.issue, null);
  assert.equal(dernier.sansConclusion, true);
  assert.equal(dernier.enCoursALaFin, true, 'le journal s arrête pendant ce test');
  assert.equal(dernier.dernierT, 71.4);
  assert.equal(dernier.derniereActivite, 'Tap "pointage-code-demo-presence-a" TextField');
});

test('journal : marques d attente d inactivité comptées par test, silences attribués à l activité qui précède', () => {
  const premier = lireJournal(JOURNAL_T2).tests.get(`DemoPointageTests.${TESTS_T2[0][0]}`);
  assert.equal(premier.marques.get('App event loop idle notification not received'), 6);
  assert.equal(premier.marques.get('exceeded execution time allowance'), 1);
  assert.equal(premier.marques.size, 2);
  // Six silences de 60 s après « Wait for … to idle », un de 89,3 s avant la fermeture du pavé, un de 130,9 s avant la fin.
  assert.equal(premier.silences.length, 3, 'les trois plus longs');
  assert.deepEqual(premier.silences.map(s => [Math.round(s.duree * 10) / 10, s.apres]), [
    [130.9, IDLE], [90.2, 'Start Test at 2026-11-24 09:57:29.101'], [60, 'Wait for app.jolene.ios to idle'],
  ]);
  assert.equal(premier.silences[0].t, 469.3);
  assert.equal(premier.silencesTotal, 8, 'huit silences d au moins 20 s');
  // Un test sans blocage : aucun silence au-delà du seuil, aucune marque.
  const sain = lireJournal(JOURNAL_T1).tests.get('DemoPointageTests.testQRIllisibleGardeLaCameraPuisSaisieManuelle');
  assert.equal(sain.marques.size, 0);
  assert.deepEqual(sain.silences.map(s => Math.round(s.duree)), [25], 'seul le trajet entre 2,4 s et 27,5 s dépasse 20 s');
  assert.ok(SEUIL_SILENCE_S === 20 && MARQUES_INACTIVITE.includes('App animations complete notification not received'));
});

test('journal : un test relancé ou jamais conclu ne décale pas les suivants ; texte vide ou sans test', () => {
  const texte = [ligneDebut('testA'), activite(1, 'Set Up'), ligneDebut('testB'), activite(2, 'Set Up'), ligneFin('testB', 'passed', 3)].join('\n');
  const { tests } = lireJournal(texte);
  assert.equal(tests.get('DemoPointageTests.testA').sansConclusion, true);
  assert.equal(tests.get('DemoPointageTests.testA').enCoursALaFin, false, 'un autre test a démarré ensuite');
  assert.equal(tests.get('DemoPointageTests.testB').issue, 'passed');
  assert.equal(lireJournal('').tests.size, 0);
  assert.equal(lireJournal('** TEST EXECUTE SUCCEEDED **\n').tests.size, 0);
});

// MARK: - Relevé d'un éclat

test('tentative 1 : le test échoué est nommé avec sa durée et son message, les trois plus longs sont classés', () => {
  const eclat = resumerEclat({ nom: 'pointage', arbre: ARBRE_T1, journal: JOURNAL_T1 });
  assert.equal(eclat.source, 'xcresult');
  assert.equal(eclat.total, 10);
  assert.equal(Math.round(eclat.dureeTotale), 823);
  assert.deepEqual(eclat.echoues.map(t => [t.cle, t.duree, t.message]), [
    ['DemoPointageTests.testHorsLigneDesactiveLePointageSansAucunEnvoi', 92.84, MESSAGE_T1]]);
  assert.deepEqual(eclat.plusLongs.map(t => [t.nom, t.duree]), [
    ['testConsentementAccepteRefusVerbatimPuisOuvertureEtFermeture', 140.07],
    ['testConsentementRetireEtReactiveDepuisLeProfil', 124.519],
    ['testHorsLigneDesactiveLePointageSansAucunEnvoi', 92.84]]);
  const { lignes, annotations } = rendre({ format: 'ipad-portrait', eclats: [eclat] });
  const texte = lignes.join('\n');
  assert.match(texte, /#### Tests échoués et tests les plus longs — ipad-portrait/);
  assert.match(texte, /\| pointage \| 10 \| 13 min 43 s \| 1 \| `DemoPointageTests\.testConsentementAccepteRefusVerbatimPuisOuvertureEtFermeture` 2 min 20 s ; /);
  assert.match(texte, /\| pointage \| `DemoPointageTests\.testHorsLigneDesactiveLePointageSansAucunEnvoi` \| 1 min 33 s \| DemoPointageUITestCase\.swift:203: failed - Compteurs relus après l'action/);
  assert.equal(annotations.length, 1);
  assert.match(annotations[0], /^::error file=ios-native\/JoleneUITests\/DemoPointageUITestCase\.swift,line=203::Test échoué \(ipad-portrait, éclat pointage\) : DemoPointageTests\.testHorsLigneDesactiveLePointageSansAucunEnvoi, 1 min 33 s — /);
});

test('tentative 2 : éclat coupé — les deux tests échoués sont nommés, avec le temps passé du premier', () => {
  const eclat = resumerEclat({ nom: 'pointage', arbre: ARBRE_T2, journal: JOURNAL_T2 });
  assert.deepEqual(eclat.echoues.map(t => t.nom), [TESTS_T2[0][0], TESTS_T2[9][0]]);
  assert.equal(eclat.echoues[0].duree, 600.9);
  assert.equal(eclat.echoues[1].duree, null, 'aucune durée pour le test coupé');
  assert.equal(eclat.echoues[1].enCoursALaFin, true);
  const { lignes, annotations } = rendre({ format: 'ipad-portrait', eclats: [eclat] });
  const texte = lignes.join('\n');
  assert.match(texte, new RegExp(`\\| pointage \\| \`DemoPointageTests\\.${TESTS_T2[0][0]}\` \\| 10 min 01 s \\| Test exceeded execution time allowance of 10 minutes \\|`));
  assert.match(texte, new RegExp(`\\| pointage \\| \`DemoPointageTests\\.${TESTS_T2[9][0]}\` \\| durée inconnue ; en cours quand le journal de l’éclat s’arrête \\(dernière activité à t = 71,4 s\\) \\| aucun message d’échec dans l’xcresult \\|`));
  assert.match(texte, /Où le temps est passé/);
  assert.match(texte, /« App event loop idle notification not received » × 6/);
  assert.match(texte, /« exceeded execution time allowance » × 1/);
  assert.match(texte, /130,9 s après « App event loop idle notification not received, will attempt to continue\. » \(t = 469,3 s\)/);
  assert.match(texte, /8 silences d’au moins 20 s/);
  assert.equal(annotations.length, 2);
  assert.ok(annotations.every(a => a.startsWith('::error')));
});

test('test réussi mais long : son temps passé est relevé, sans annotation', () => {
  const nom = 'testPreferencesDemoModifieesEnregistreesPuisRelues';
  const long = arbre('DemoPreferencesTests', [cas('DemoPreferencesTests', nom, 'Passed', 441), cas('DemoPreferencesTests', 'testCourt', 'Passed', 12)]);
  const journal = [`Test Case '-[JoleneUITests.DemoPreferencesTests ${nom}]' started.`, activite(0, 'Start Test'),
    activite(40, 'Tap "prefs" Switch'), activite(75, 'Find the "prefs" Switch', '    '),
    `Test Case '-[JoleneUITests.DemoPreferencesTests ${nom}]' passed (441.000 seconds).`].join('\n');
  const eclat = resumerEclat({ nom: 'lot3-notifications', arbre: long, journal });
  assert.equal(SEUIL_TEST_LONG_S, 300);
  assert.deepEqual(eclat.echoues, []);
  const { lignes, annotations } = rendre({ format: 'iphone', eclats: [eclat] });
  assert.deepEqual(annotations, []);
  const texte = lignes.join('\n');
  assert.match(texte, /Aucun test échoué dans les éclats lus\./);
  assert.match(texte, /lot3-notifications — `DemoPreferencesTests\.testPreferencesDemoModifieesEnregistreesPuisRelues` \(7 min 21 s, réussi\)/);
  assert.match(texte, /366,0 s après « Find the "prefs" Switch » \(t = 75,0 s, jusqu’à la fin du test\)/);
  assert.doesNotMatch(texte, /testCourt` \(/, 'un test court et réussi n est pas détaillé');
});

test('xcresult illisible ou absent : repli sur le journal, jamais une exception', () => {
  const repli = resumerEclat({ nom: 'pointage', arbre: null, lecture: 'xcresulttool a échoué (code 1)', journal: JOURNAL_T1 });
  assert.equal(repli.source, 'journal');
  assert.equal(repli.total, 10);
  assert.deepEqual(repli.echoues.map(t => [t.nom, t.duree]), [['testHorsLigneDesactiveLePointageSansAucunEnvoi', 92.84]]);
  assert.match(repli.echoues[0].message, /^DemoPointageUITestCase\.swift:203: failed - Compteurs relus/);
  const vide = resumerEclat({ nom: 'documents', arbre: null, lecture: 'bundle xcresult absent', journal: null });
  assert.equal(vide.source, null);
  const { lignes, annotations } = rendre({ format: 'ipad-portrait', eclats: [repli, vide] });
  const texte = lignes.join('\n');
  assert.match(texte, /\| pointage \| 10 \| 13 min 43 s \| 1 \| .* \| journal xcodebuild \(xcresulttool a échoué \(code 1\)\) \|/);
  assert.match(texte, /\| documents \| — \| — \| — \| — \| aucun test lu \(bundle xcresult absent ; journal absent\) \|/);
  assert.equal(annotations.length, 1);
  // Arbre lisible mais sans aucun test (éclat coupé avant le premier test) : le journal reste la source.
  const sansTest = resumerEclat({ nom: 'pointage', arbre: { testNodes: [] }, journal: JOURNAL_T2 });
  assert.equal(sansTest.source, 'journal');
  assert.deepEqual(sansTest.echoues.map(t => t.nom), [TESTS_T2[0][0], TESTS_T2[9][0]], 'échoué au journal, puis sans conclusion');
});

test('message d échec : espaces repliés, tronqué, barres verticales et retours à la ligne neutralisés', () => {
  const long = `Fichier.swift:12: failed - ${'a|b\n'.repeat(200)}`;
  const eclat = resumerEclat({ nom: 'socle', arbre: arbre('XTests', [cas('XTests', 'testY', 'Failed', 1, [echec(long)])]), journal: '' });
  assert.equal(eclat.echoues[0].message.length, TRONCATURE_MESSAGE + 1, 'tronqué, puis « … »');
  assert.ok(eclat.echoues[0].message.endsWith('…'));
  const { lignes, annotations } = rendre({ format: 'iphone', eclats: [eclat] });
  const ligne = lignes.find(l => l.startsWith('| socle | `XTests.testY`'));
  assert.ok(ligne && !ligne.includes('\n') && ligne.includes('a\\|b a\\|b'), ligne);
  assert.ok(!annotations[0].includes('\n'));
  // Fichier inconnu du dépôt : annotation sans cible plutôt qu une cible fausse.
  assert.match(annotations[0], /^::error::Test échoué \(iphone, éclat socle\) : XTests\.testY, 1,0 s — /);
});

// MARK: - Relevés du veilleur

test('sample : pile la plus fréquente du fil principal, feuille en tête', () => {
  const reel = pileDominante(SAMPLE_REEL);
  assert.equal(reel.echantillons, 821);
  assert.equal(reel.feuille, 821);
  assert.deepEqual(reel.cadres, ['__semwait_signal (libsystem_kernel.dylib)', 'nanosleep (libsystem_c.dylib)', '??? (sleep)', 'start (dyld)']);
  const gel = pileDominante(SAMPLE_GEL);
  assert.equal(gel.echantillons, 4118);
  assert.equal(gel.feuille, 3808, 'la branche la plus lourde, pas la première');
  assert.deepEqual(gel.cadres.slice(0, 4), ['mach_msg2_trap (libsystem_kernel.dylib)', 'CA::Render::Message::send_message() (QuartzCore)',
    'CA::Transaction::commit() (QuartzCore)', '_UIUpdateCycleNotifyIdle (UIKitCore)']);
  assert.ok(!gel.cadres.some(c => c.includes('start_wqthread')), 'le fil suivant n est pas lu');
  assert.equal(pileDominante('app Jolene : processus introuvable (2026-11-24T10:00:00Z)'), null);
  assert.equal(pileDominante(''), null);
});

test('veilleur : passes, piles relevées et Spindump de XCTest nommés dans le résumé, puis copiés pour l artefact léger', () => {
  const b = bac({
    arbres: { pointage: ARBRE_T2 },
    journaux: { pointage: JOURNAL_T2 },
    fichiers: {
      'gel-pointage-veilleur.log': 'Passe 1 du veilleur (pointage) : 2026-11-24T10:04:31Z — test en cours depuis plus de 420 s\nPasse 1 terminée : 2026-11-24T10:05:02Z\n',
      'gel-pointage-sample-1.txt': SAMPLE_GEL,
      'gel-pointage-backboardd-sample-1.txt': 'backboardd : processus introuvable (2026-11-24T10:04:40Z)\n',
      'attachments/pointage/manifest.json': JSON.stringify([{ testIdentifier: `DemoPointageTests/${TESTS_T2[0][0]}()`, attachments: [
        { exportedFileName: 'EBCE3E60.txt', suggestedHumanReadableName: '2026-11-24 100730 +0000-Spindump_0_161A8C81.txt' },
        { exportedFileName: 'AAAA.png', suggestedHumanReadableName: 'ipad-portrait-pointage-refus_0_0EC4.png' }] }]),
      'attachments/pointage/EBCE3E60.txt': 'Date/Time: 2026-11-24 10:07:30 +0000\n',
    },
  });
  try {
    const [eclat] = collecter({ eclats: ['pointage'], format: 'ipad-portrait', sortie: b.sortie, bundles: b.bundles, env: b.env });
    assert.deepEqual(eclat.veilleur.passes, ['Passe 1 du veilleur (pointage) : 2026-11-24T10:04:31Z — test en cours depuis plus de 420 s']);
    assert.equal(eclat.veilleur.piles.length, 1, 'un relevé sans pile lisible n est pas inventé');
    assert.deepEqual(eclat.spindumps, [{ test: `DemoPointageTests/${TESTS_T2[0][0]}()`, fichier: 'attachments/pointage/EBCE3E60.txt', copie: 'diagnostic/spindump-pointage-1.txt' }]);
    assert.equal(readFileSync(join(b.sortie, 'diagnostic/spindump-pointage-1.txt'), 'utf8'), 'Date/Time: 2026-11-24 10:07:30 +0000\n');
    const texte = rendre({ format: 'ipad-portrait', eclats: [eclat] }).lignes.join('\n');
    assert.match(texte, /Relevés du veilleur et de XCTest/);
    assert.match(texte, /pointage — Passe 1 du veilleur \(pointage\) : 2026-11-24T10:04:31Z — test en cours depuis plus de 420 s/);
    assert.match(texte, /pointage — `gel-pointage-sample-1\.txt`, fil principal : 3808 échantillons sur 4118 dans mach_msg2_trap \(libsystem_kernel\.dylib\) ← CA::Render::Message::send_message\(\) \(QuartzCore\) ← /);
    assert.match(texte, /pointage — Spindump de XCTest \(délai d’exécution dépassé\) joint à `DemoPointageTests\/testConsentementAccepteRefusVerbatimPuisOuvertureEtFermeture\(\)` : `diagnostic\/spindump-pointage-1\.txt`/);
  } finally { b.nettoyer(); }
});

// MARK: - Ligne de commande

test('commande : résumé du job, journal et annotations pour chaque éclat ; code 0', () => {
  const b = bac({ arbres: { presences: arbre('DemoPresencesTests', [cas('DemoPresencesTests', 'testOnglets', 'Passed', 61)]), pointage: ARBRE_T1 },
    journaux: { pointage: JOURNAL_T1 } });
  try {
    const r = b.lancer(['presences', 'pointage', 'documents']);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(b.appels(), [
      `xcresulttool get test-results tests --path ${join(b.bundles, 'ui-ipad-portrait-presences.xcresult')}`,
      `xcresulttool get test-results tests --path ${join(b.bundles, 'ui-ipad-portrait-pointage.xcresult')}`,
    ], 'un appel par bundle présent, aucun pour un bundle absent');
    const resume = b.resume();
    assert.match(resume, /\| presences \| 1 \| 1 min 01 s \| 0 \| `DemoPresencesTests\.testOnglets` 1 min 01 s \| xcresult \|/);
    assert.match(resume, /\| pointage \| 10 \| 13 min 43 s \| 1 \|/);
    assert.match(resume, /\| documents \| — \| — \| — \| — \| aucun test lu \(bundle xcresult absent ; journal absent\) \|/);
    assert.match(resume, /testHorsLigneDesactiveLePointageSansAucunEnvoi` \| 1 min 33 s \| DemoPointageUITestCase\.swift:203: failed - Compteurs relus/);
    assert.ok(r.stdout.includes(resume.trim()), 'le résumé est aussi imprimé au journal du job');
    // L'arbre lu est gardé à côté des résumés xcresult, pour l'artefact léger (durée de chaque test, sans le bundle).
    assert.deepEqual(JSON.parse(readFileSync(join(b.sortie, 'xctest-tests-pointage.json'), 'utf8')), ARBRE_T1);
    assert.ok(!existsSync(join(b.sortie, 'xctest-tests-documents.json')), 'rien n est écrit pour un bundle absent');
    assert.equal(r.stdout.split('\n').filter(l => l.startsWith('::error')).length, 1);
    assert.match(r.stdout, /::error file=ios-native\/JoleneUITests\/DemoPointageUITestCase\.swift,line=203::Test échoué \(ipad-portrait, éclat pointage\)/);
  } finally { b.nettoyer(); }
});

test('commande : xcresulttool en échec, JSON illisible ou outil absent — repli sur le journal, code 0', () => {
  for (const xcrun of ['echo "Error: bundle tronqué" >&2; exit 64', 'echo "{ pas du JSON"', 'sleep 30']) {
    const b = bac({ arbres: { pointage: null }, journaux: { pointage: JOURNAL_T2 }, xcrun });
    try {
      const r = b.lancer(['pointage'], { JOLENE_RESUME_DELAI_XCRESULTTOOL_MS: '1500' });
      assert.equal(r.status, 0, r.stderr);
      const resume = b.resume();
      assert.match(resume, /\| pointage \| 10 \| .* \| 2 \| .* \| journal xcodebuild \(/, xcrun);
      assert.match(resume, new RegExp(`DemoPointageTests\\.${TESTS_T2[9][0]}`), 'le test en cours à la coupure est nommé');
      assert.equal(r.stdout.split('\n').filter(l => l.startsWith('::error')).length, 2);
    } finally { b.nettoyer(); }
  }
});

test('commande : sans éclat, sans environnement ou sur une erreur interne — avertissement, code 0, rien d autre', () => {
  const b = bac();
  try {
    const sansEclat = b.lancer([]);
    assert.equal(sansEclat.status, 0);
    assert.match(sansEclat.stdout, /^::warning::Résumé des tests par éclat non établi/);
    assert.equal(b.resume(), '');
    const sansSortie = b.lancer(['pointage'], { JOLENE_UI_OUTPUT: '' });
    assert.equal(sansSortie.status, 0);
    assert.match(sansSortie.stdout, /^::warning::Résumé des tests par éclat non établi/);
    // Résumé du job impossible à écrire (dossier à la place du fichier) : avertissement, jamais un échec.
    const illisible = b.lancer(['pointage'], { GITHUB_STEP_SUMMARY: b.dir });
    assert.equal(illisible.status, 0, illisible.stderr);
    assert.match(illisible.stdout, /::warning::Résumé des tests par éclat non établi/);
  } finally { b.nettoyer(); }
  assert.equal(main([], {}), 0);
});

// Garde de repos XCUITest (`ios-native/JoleneUITests/GardeRepos.swift`) : journal RECONSTITUÉ au format des lignes
// d'activité « t = …s » (aucun run de la garde n'existe encore au moment de ce test). Il prouve la lecture, pas la garde.
const JOURNAL_GARDE = [
  "Test Case '-[JoleneUITests.DemoGardeReposTests testAnimationOuverteUneSeuleAttenteExpireePuisGestesRapides]' started.",
  '    t =     0.00s Start Test at 2026-11-26 10:00:00.000',
  '    t =     0.01s Jolene diagnostic repos-xcuitest : garde de repos installée sur waitForQuiescenceIncludingAnimationsIdle:usingActivity:isPreEvent: v28@0:8B16B20B24',
  '    t =     1.05s     Launch app.jolene',
  '    t =    19.10s     Wait for app.jolene to idle',
  '    t =    79.20s App animations complete notification not received, will attempt to continue.',
  '    t =    79.80s Jolene diagnostic repos-xcuitest : attente des animations expirée (60 s) pendant -[DemoGardeReposTests testAnimationOuverteUneSeuleAttenteExpireePuisGestesRapides] ; attente des animations suspendue pour ce processus',
  '    t =    80.10s Press Target Application',
  "Test Case '-[JoleneUITests.DemoGardeReposTests testAnimationOuverteUneSeuleAttenteExpireePuisGestesRapides]' passed (95.210 seconds).",
  "Test Case '-[JoleneUITests.DemoGardeReposTests testSansAnimationOuverteLaGardeNeChangeRien]' started.",
  '    t =     0.00s Start Test at 2026-11-26 10:01:40.000',
  "Test Case '-[JoleneUITests.DemoGardeReposTests testSansAnimationOuverteLaGardeNeChangeRien]' passed (30.100 seconds).",
].join('\n');

test('garde de repos : expirations relevées par test, en avertissement ; pose et non-pose lues', () => {
  assert.equal(MARQUE_GARDE_REPOS, 'Jolene diagnostic repos-xcuitest', 'GardeReposDecision.marque');
  const { tests, installation } = lireJournal(JOURNAL_GARDE);
  const lent = tests.get('DemoGardeReposTests.testAnimationOuverteUneSeuleAttenteExpireePuisGestesRapides');
  assert.equal(lent.gardeRepos.length, 1);
  assert.equal(lent.gardeRepos[0].t, 79.8);
  assert.equal(tests.get('DemoGardeReposTests.testSansAnimationOuverteLaGardeNeChangeRien').gardeRepos.length, 0);
  assert.equal(installation.length, 1, 'la ligne de pose n est pas une expiration');

  const eclat = resumerEclat({ nom: 'socle', journal: JOURNAL_GARDE });
  const { lignes, annotations } = rendre({ format: 'ipad-portrait', eclats: [eclat] });
  const texte = lignes.join('\n');
  assert.match(texte, /\*\*Garde de repos XCUITest\*\* : 1 attente des animations expirée puis suspendue pour le processus d’app \(1 test\)/);
  assert.match(texte, /- socle — `DemoGardeReposTests\.testAnimationOuverteUneSeuleAttenteExpireePuisGestesRapides` \(t = 79,8 s\) : Jolene diagnostic/);
  assert.equal(annotations.filter(a => a.startsWith('::warning::Garde de repos (ipad-portrait, éclat socle)')).length, 1);
  assert.ok(!annotations.some(a => a.startsWith('::error')), 'jamais une erreur');

  const nonPosee = JOURNAL_GARDE.replace(/garde de repos installée sur .*/, 'garde de repos non installée : waitForQuiescenceIncludingAnimationsIdle:isPreEvent: B24@0:8B16B20')
    .split('\n').filter(l => !l.includes('attente des animations expirée')).join('\n');
  const rendu = rendre({ format: 'iphone', eclats: [resumerEclat({ nom: 'socle', journal: nonPosee })] });
  assert.ok(rendu.lignes.some(l => l.includes('garde de repos non installée')), 'non-pose visible au résumé');
  assert.equal(rendu.annotations.filter(a => a.startsWith('::warning::Garde de repos (iphone, éclat socle) : Jolene diagnostic repos-xcuitest : garde de repos non installée')).length, 1);

  const sans = rendre({ format: 'iphone', eclats: [resumerEclat({ nom: 'socle', journal: JOURNAL_T1 })] });
  assert.ok(!sans.lignes.some(l => l.includes('Garde de repos')), 'aucune section sans ligne de la garde');
});
