import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
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
