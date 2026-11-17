import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  EVENEMENTS,
  ROOT,
  TEST_NODE,
  WORKFLOW_IOS,
  correspond,
  motifsDuFiltre,
  verifierDepot,
  verifierFiltre,
} from '../../scripts/mobile/check-sources-web-ios-ci.mjs';
import { FICHIERS_SWIFT } from '../../scripts/mobile/check-textes-juridiques-ios.mjs';

// Garde du filtre de chemins de la CI iOS (incident #1137 du 17 novembre 2026) : #1137 a décalé les lignes de
// `src/pages/InscriptionSoignant.tsx`, que `CompletionVerbatimTests` relit à la ligne près ; la CI iOS ne se
// déclenchait pas sur ce fichier, la PR web est passée verte et 50 tests Swift ont rougi ensuite (#1138). Tout fichier
// du dépôt hors `ios-native/` lu par du Swift (littéral de chemin, annotation `// source:`, `// source-objet:`,
// `// source-ensemble:`) doit figurer dans les deux filtres (`pull_request` et `push`) de `ios-swift-ci.yml`, sauf s'il
// n'est lu que par la garde tolérante `check-textes-juridiques-ios.mjs` (annotations de `TextesWeb.swift` et
// `LibellesWeb.swift`, que validate-pr relit en tolérant un décalage). Aucun réseau, aucun secret.

const TEST_SWIFT = 'ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/PageTests.swift';
const REGLE_SWIFT = 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Regles/Regle.swift';
const GARDE_SWIFT = 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Legal/TextesWeb.swift';
const PAGE = 'src/pages/Page.tsx';

/** Un workflow réduit à ses deux filtres de chemins. */
function workflow(pullRequest, push = pullRequest) {
  const liste = motifs => motifs.map(m => `      - '${m}'`).join('\n');
  return [
    'name: iOS', '', 'on:', '  pull_request:', '    branches: [main]', '    paths:', '      # commentaire',
    liste(pullRequest), '  push:', '    branches: [main]', '    paths:', liste(push), '  workflow_dispatch:', '',
    'jobs:', '  coeur:', '    runs-on: ubuntu-latest', '',
  ].join('\n');
}

/** Un test Swift qui relit `PAGE` à la ligne près, comme `SupabaseRevenusGatewayTests`. */
const lecteur = { chemin: TEST_SWIFT, texte: `let web = try source("${PAGE}")\nXCTAssertTrue(web[41].contains("Bonjour"))\n` };

function verifier({ swift = [lecteur], depot = [PAGE], filtre = workflow(['ios-native/**']) } = {}) {
  const fichiersDepot = [...new Set([...depot, ...swift.map(f => f.chemin)])];
  return verifierFiltre({ swift, fichiersDepot, workflow: filtre });
}

test('rouge : un fichier web lu par un test Swift, absent du filtre et hors garde, fait échouer la garde', () => {
  const { erreurs, lectures } = verifier();
  assert.deepEqual([...lectures.keys()], [PAGE]);
  assert.equal(erreurs.length, 1, erreurs.join('\n'));
  assert.match(erreurs[0], /src\/pages\/Page\.tsx/);
  assert.match(erreurs[0], /PageTests\.swift/);
  assert.match(erreurs[0], /pull_request et push/);
  assert.match(erreurs[0], /#1137/);
});

test('vert : le fichier figure aux deux filtres, en chemin exact ou par un motif', () => {
  assert.deepEqual(verifier({ filtre: workflow(['ios-native/**', PAGE]) }).erreurs, []);
  assert.deepEqual(verifier({ filtre: workflow(['ios-native/**', 'src/pages/**']) }).erreurs, []);
  assert.deepEqual(verifier({ filtre: workflow(['ios-native/**', 'src/pages/*.tsx']) }).erreurs, []);
});

test('un fichier absent d’un seul filtre est signalé pour cet événement seulement', () => {
  const { erreurs } = verifier({ filtre: workflow(['ios-native/**', PAGE], ['ios-native/**']) });
  assert.equal(erreurs.length, 1, erreurs.join('\n'));
  assert.match(erreurs[0], /filtre push /);
  assert.doesNotMatch(erreurs[0], /pull_request/);
});

test('les trois annotations d’un fichier Swift relu par un test sont des lectures', () => {
  const regle = {
    chemin: REGLE_SWIFT,
    texte: [
      '// source: src/lib/regle.ts:12',
      'static let titre = "Titre"',
      '// source-objet: src/lib/statuts.ts:40 STATUT_CONFIG.label',
      '// source-ensemble: src/lib/ensembles.ts:3-9',
      'case "X": return "Y" // source: src/lib/fin-de-ligne.ts:7',
    ].join('\n'),
  };
  const relecteur = { chemin: TEST_SWIFT, texte: `private static let fichierSwift = "${REGLE_SWIFT}"\n` };
  const depot = ['src/lib/regle.ts', 'src/lib/statuts.ts', 'src/lib/ensembles.ts', 'src/lib/fin-de-ligne.ts'];
  const { erreurs, lectures } = verifier({ swift: [regle, relecteur], depot });
  assert.deepEqual([...lectures.keys()].sort(), [...depot].sort());
  assert.equal(erreurs.length, 4, erreurs.join('\n'));
  assert.ok(erreurs.every(e => e.includes('PageTests.swift (annotations de Regle.swift)')), erreurs.join('\n'));
});

test('les annotations d’un fichier Swift qu’aucun test ne relit restent de la documentation', () => {
  const regle = { chemin: REGLE_SWIFT, texte: 'case "X": return "Y" // source: src/lib/regle.ts:7\n' };
  const { erreurs, lectures } = verifier({ swift: [regle], depot: ['src/lib/regle.ts'] });
  assert.deepEqual(erreurs, []);
  assert.equal(lectures.size, 0);
});

test('garde tolérante : un fichier cité seulement par TextesWeb.swift, que seule validate-pr relit, reste hors filtre', () => {
  const garde = { chemin: GARDE_SWIFT, texte: '// source: src/components/Consentement.tsx:30 [juridique]\nstatic let a = "A"\n' };
  const depot = ['src/components/Consentement.tsx'];
  assert.deepEqual(verifier({ swift: [garde], depot }).erreurs, []);
  // Un test Swift qui relirait TextesWeb.swift à la ligne près rendrait ses citations obligatoires dans le filtre.
  const relecteur = { chemin: TEST_SWIFT, texte: `let lignes = try source("${GARDE_SWIFT}")\n` };
  const { erreurs } = verifier({ swift: [garde, relecteur], depot });
  assert.equal(erreurs.length, 1, erreurs.join('\n'));
  assert.match(erreurs[0], /Consentement\.tsx/);
});

test('un chemin cité introuvable est refusé : le test Swift sauterait sa vérification (XCTSkip)', () => {
  // Littéral d'un test : fichier web renommé ou supprimé par une PR web.
  const disparu = { chemin: TEST_SWIFT, texte: 'let web = try source("src/pages/Disparue.tsx")\n' };
  const litteral = verifier({ swift: [disparu] });
  assert.equal(litteral.erreurs.length, 1, litteral.erreurs.join('\n'));
  assert.match(litteral.erreurs[0], /src\/pages\/Disparue\.tsx/);
  assert.match(litteral.erreurs[0], /introuvable/);
  // Annotation d'un fichier relu, au nom court ou au chemin périmé.
  const court = { chemin: REGLE_SWIFT, texte: '// source: Page.tsx:71\nstatic let a = "A"\n' };
  const relecteur = { chemin: TEST_SWIFT, texte: `let lignes = try source("${REGLE_SWIFT}")\n` };
  const annotation = verifier({ swift: [court, relecteur], filtre: workflow(['ios-native/**', PAGE]) });
  assert.equal(annotation.erreurs.length, 1, annotation.erreurs.join('\n'));
  assert.match(annotation.erreurs[0], /« Page\.tsx »/);
  assert.match(annotation.erreurs[0], /introuvable/);
  // Une chaîne qui ne commence par aucun dossier du dépôt n'est pas un chemin (type MIME, identifiant).
  const mime = { chemin: TEST_SWIFT, texte: 'let type = "application/json"\n' };
  assert.deepEqual(verifier({ swift: [mime] }).erreurs, []);
});

test('un dossier lu par du Swift est refusé : la garde ne sait pas quels fichiers il couvre', () => {
  const dossier = { chemin: TEST_SWIFT, texte: 'let base = racine.appendingPathComponent("src/pages")\n' };
  const { erreurs } = verifier({ swift: [dossier], depot: [PAGE], filtre: workflow(['ios-native/**', PAGE]) });
  assert.equal(erreurs.length, 1, erreurs.join('\n'));
  assert.match(erreurs[0], /dossier/);
});

test('motifs : seuls * et ** sont lus ; une syntaxe non gérée lève une erreur', () => {
  assert.ok(correspond('ios-native/**', 'ios-native/Packages/A.swift'));
  assert.ok(correspond('src/**/geo.ts', 'src/lib/geo.ts'));
  assert.ok(correspond('src/**/geo.ts', 'src/geo.ts'));
  assert.ok(correspond('src/lib/*.ts', 'src/lib/geo.ts'));
  assert.ok(!correspond('src/lib/*.ts', 'src/lib/sous/geo.ts'));
  assert.ok(!correspond('src/lib/geo.ts', 'src/lib/geo.tsx'));
  assert.ok(!correspond('src/lib/geo.ts', 'src/lib/geoXts'));
  // GitHub lit `?` et `+` comme des quantificateurs du caractère précédent, `!` comme une négation : refusés.
  assert.throws(() => motifsDuFiltre(workflow(['!src/lib/geo.ts'])), /non gérée/);
  assert.throws(() => motifsDuFiltre(workflow(['src/lib/ge?.ts'])), /non gérée/);
  assert.throws(() => motifsDuFiltre(workflow(['src/lib/g+.ts'])), /non gérée/);
  assert.throws(() => motifsDuFiltre(workflow(['src/[ab].ts'])), /non gérée/);
  assert.throws(() => motifsDuFiltre(workflow(['ios-native/**']).replace(/    paths:\n/, '    paths-ignore:\n')), /paths-ignore/);
});

/** Workflow écrit à la main : blocs `paths` bruts des deux événements, puis un job. */
const brut = (pr, push, jobs = '  coeur:\n    runs-on: ubuntu-latest\n') =>
  `on:\n  pull_request:\n    branches: [main]\n${pr}${push === null ? '' : `  push:\n    branches: [main]\n${push}`}`
  + `  workflow_dispatch:\n\njobs:\n${jobs}`;
const LISTE = "    paths:\n      - 'ios-native/**'\n";

test('revue B8 (B1) : le filtre est lu comme GitHub le lit, jamais pris pour « aucun filtre » par erreur', () => {
  const lu = { pull_request: ['ios-native/**'], push: ['ios-native/**'] };
  // Formes YAML valides que GitHub applique : commentaire, liste en ligne, ancre et alias, élément ancré, indentation libre.
  assert.deepEqual(motifsDuFiltre(brut("    paths: # filtre iOS\n      - 'ios-native/**'\n", LISTE)), lu);
  assert.deepEqual(motifsDuFiltre(brut("    paths: ['ios-native/**']\n", LISTE)), lu);
  assert.deepEqual(motifsDuFiltre(brut("    paths: &chemins\n      - 'ios-native/**'\n", '    paths: *chemins\n')), lu);
  assert.deepEqual(motifsDuFiltre(brut("    paths:\n      - &a 'ios-native/**'\n", LISTE)), lu);
  assert.deepEqual(motifsDuFiltre(brut("    paths:\n        - 'ios-native/**'\n", LISTE)), lu);
  assert.deepEqual(motifsDuFiltre(brut("    'paths':\n      - 'ios-native/**'\n", LISTE)), lu);
  // Seconde revue : corps de `push:` ré-indenté, clé entre guillemets ; le fichier absent est vu.
  const reindente = "  push:\n      branches: [main]\n      paths:\n        - 'ios-native/**'\n";
  const yml = `on:\n  pull_request:\n    branches: [main]\n    paths:\n      - 'ios-native/**'\n      - '${PAGE}'\n${reindente}`;
  const { erreurs } = verifier({ filtre: yml });
  assert.equal(erreurs.length, 1, erreurs.join('\n'));
  assert.match(erreurs[0], /filtre push /);
  // Clé sans valeur, valeur qui n'est pas une liste de chaînes, paths-ignore : refusés.
  assert.throws(() => motifsDuFiltre(brut('    paths:\n', LISTE)), /liste/);
  assert.throws(() => motifsDuFiltre(brut('    paths: ios-native/**\n', LISTE)), /liste/);
  assert.throws(() => motifsDuFiltre(brut('    paths:\n      - [a]\n', LISTE)), /liste/);
  assert.throws(() => motifsDuFiltre(brut("    paths-ignore:\n      - 'docs/**'\n", LISTE)), /paths-ignore/);
  // Événement sans corps, ou forme courte `on: [push, pull_request]` : non filtré.
  assert.deepEqual(motifsDuFiltre('on: [push, pull_request]\n'), { pull_request: ['**'], push: ['**'] });
  assert.deepEqual(motifsDuFiltre(`on:\n  pull_request:\n${LISTE}  push:\n`).push, ['**']);
});

test('revue B8 : les événements sont cherchés dans le bloc « on: », pas parmi les jobs', () => {
  assert.throws(() => motifsDuFiltre(brut(LISTE, null, `  push:\n    runs-on: ubuntu-latest\n${LISTE}`)), /push introuvable/);
});

test('revue B8 : un chemin construit (interpolation, concaténation, segments) est refusé', () => {
  const cas = [
    ['let web = try source("src/pages/\\(nom).tsx")', /construit/],
    ['let web = try source("src/pages/" + nom)', /dossier/],
    ['let web = racine.appendingPathComponent("src").appendingPathComponent("pages/Page.tsx")', /construit/],
    ['let web = racine.appendingPathComponent("src", isDirectory: true)', /construit/],
    ['let web = racine.appending(path: "src")', /construit/],
    ['let web = racine.appending(component: "../src")', /construit/],
  ];
  for (const [ligne, attendu] of cas) {
    const { erreurs } = verifier({ swift: [{ chemin: TEST_SWIFT, texte: `${ligne}\n` }], filtre: workflow(['ios-native/**', PAGE]) });
    assert.equal(erreurs.length, 1, `${ligne}\n${erreurs.join('\n')}`);
    assert.match(erreurs[0], attendu);
  }
});

test('revue B8 : préfixes ./, ../, / et interpolation en tête ne masquent pas le chemin lu', () => {
  for (const ligne of [
    'let w = try lire("../src/pages/Page.tsx")',
    'let w = racine.appendingPathComponent("../../../../../src/pages/Page.tsx")',
    'let w = try source("./src/pages/Page.tsx")',
    'let w = try String(contentsOfFile: "\\(racine.path)/src/pages/Page.tsx")',
    'let w = try String(contentsOfFile: racine.path + "/src/pages/Page.tsx")',
    'XCTAssertTrue(l.contains(#"say "hi"#)); let w = try source("src/pages/Page.tsx")',
  ]) {
    const { lectures, erreurs } = verifier({ swift: [{ chemin: TEST_SWIFT, texte: `${ligne}\n` }] });
    assert.deepEqual([...lectures.keys()], [PAGE], ligne);
    assert.equal(erreurs.length, 1, `${ligne}\n${erreurs.join('\n')}`);
  }
});

test('revue B8 : un fichier Swift relu par un chemin relatif (ios-native/, paquet) compte aussi', () => {
  const regle = { chemin: REGLE_SWIFT, texte: '// source: src/lib/regle.ts:12\nstatic let a = "A"\n' };
  for (const relatif of ['Packages/JoleneCore/Sources/JoleneCore/Regles/Regle.swift', 'Sources/JoleneCore/Regles/Regle.swift']) {
    const relecteur = { chemin: TEST_SWIFT, texte: `let lignes = try lire("${relatif}")\n` };
    const { lectures } = verifier({ swift: [regle, relecteur], depot: ['src/lib/regle.ts'] });
    assert.deepEqual([...lectures.keys()], ['src/lib/regle.ts'], relatif);
  }
});

test('revue B8 : pas de faux positif sur une clé de stockage, un préfixe ou un segment court', () => {
  const depot = [PAGE, 'public/robots.txt', 'tests/a/b.ts', 'ios/App/x.swift'];
  for (const ligne of [
    'let cle = "public/avatars/x.jpg"', 'let cle = "public/u-1.jpg"', 'let cle = "public/avatars"',
    'let d = "tests/unitaires"', 'XCTAssertTrue(chemin.hasPrefix("src/"))', 'let v = "ios/\\(version)"',
  ]) {
    assert.deepEqual(verifier({ swift: [{ chemin: TEST_SWIFT, texte: `${ligne}\n` }], depot }).erreurs, [], ligne);
  }
  // Un message qui commence par un chemin puis interpole autre chose n'est pas un chemin construit (JoleneDesignLot1Tests).
  const message = { chemin: TEST_SWIFT, texte: 'throw XCTSkip("src/pages/Page.tsx introuvable : \\(fichier.path)")\n' };
  assert.deepEqual(verifier({ swift: [message], filtre: workflow(['ios-native/**', PAGE]) }).erreurs, []);
  // Un fichier supprimé dont le dossier existe encore reste refusé (XCTSkip).
  const aasa = { chemin: TEST_SWIFT, texte: 'let f = "public/.well-known/apple-app-site-association"\n' };
  const supprime = verifier({ swift: [aasa], depot: [PAGE, 'public/.well-known/assetlinks.json'] });
  assert.equal(supprime.erreurs.length, 1, supprime.erreurs.join('\n'));
  assert.match(supprime.erreurs[0], /introuvable/);
});

test('revue B8 : la CLI tourne aussi lancée à travers un lien symbolique', () => {
  const dossier = mkdtempSync(join(tmpdir(), 'sources-web-ios-ci-'));
  try {
    const lien = join(dossier, 'garde.mjs');
    symlinkSync(join(ROOT, 'scripts/mobile/check-sources-web-ios-ci.mjs'), lien);
    const sortie = spawnSync(process.execPath, [lien], { cwd: ROOT, encoding: 'utf8' });
    assert.equal(sortie.status, 0, sortie.stderr);
    assert.match(sortie.stdout, /fichiers hors ios-native\/ lus par du Swift/);
  } finally {
    rmSync(dossier, { recursive: true, force: true });
  }
});

test('dépôt réel : chaque fichier lu par du Swift hors garde figure aux deux filtres de ios-swift-ci.yml', () => {
  const { erreurs, lectures } = verifierDepot();
  assert.deepEqual(erreurs, []);
  // Le cas de l'incident : relu à la ligne près par CompletionVerbatimTests.
  assert.ok(lectures.has('src/pages/InscriptionSoignant.tsx'));
  // Cité seulement par TextesWeb.swift : relu par la garde tolérante de validate-pr, pas par un test Swift.
  assert.ok(!lectures.has('src/components/ConsentementGPS.tsx'));
  const filtres = motifsDuFiltre(readFileSync(join(ROOT, WORKFLOW_IOS), 'utf8'));
  assert.deepEqual(Object.keys(filtres), EVENEMENTS);
});

test('garde tolérante : aucun test Swift ne relit TextesWeb.swift ni LibellesWeb.swift', () => {
  const { relus } = verifierDepot();
  for (const { chemin } of FICHIERS_SWIFT) assert.ok(!relus.has(chemin), `${chemin} relu par ${[...(relus.get(chemin) ?? [])]}`);
  // Les fichiers dont les annotations sont relues à la ligne près (incident #1137 : CompletionProfil.swift).
  assert.ok(relus.has('ios-native/Packages/JoleneCore/Sources/JoleneCore/Inscription/CompletionProfil.swift'));
});

test('la garde tourne dans le job requis « Typecheck + build » de validate-pr', () => {
  const yml = readFileSync(join(ROOT, '.github/workflows/validate-pr.yml'), 'utf8');
  const debut = yml.indexOf('\n  typecheck-and-build:\n');
  assert.ok(debut >= 0, 'job typecheck-and-build absent de validate-pr.yml');
  const suite = yml.slice(debut + 1);
  const fin = suite.slice(1).search(/\n {2}[a-z0-9_-]+:\n/);
  const job = fin < 0 ? suite : suite.slice(0, fin + 1);
  const lancements = job.split('\n').filter(l => /^\s+run: node --test /.test(l));
  assert.ok(lancements.some(l => l.split(/\s+/).includes(TEST_NODE)), `${TEST_NODE} absent du job typecheck-and-build`);
});
