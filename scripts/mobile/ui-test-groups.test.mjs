// Tests du garde des groupes UI (`node --test scripts/mobile/ui-test-groups.test.mjs`, job « Cœur »
// de ios-swift-ci.yml). Données synthétiques : indépendants des classes présentes dans le dépôt.
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { HORS_GROUPES, argumentsXcodebuild, attendus, classesDeTest, verifier } from './ui-test-groups.mjs';

const GROUPES = [
  { nom: 'socle', cibles: ['JoleneCoreTests'], classes: ['DemoA', 'DemoPrevue'] },
  { nom: 'parcours', cibles: [], classes: ['DemoB'] },
];
const MATRICE = ['socle', 'parcours'];
const CLASSES = { DemoA: ['testUn'], DemoB: ['testDeux', 'testTrois'], StagingConnexionTests: ['testStaging'] };

test('lit les classes de test et leurs méthodes, ignore une classe sans test', () => {
  const dossier = mkdtempSync(join(tmpdir(), 'ui-test-groups-'));
  try {
    writeFileSync(join(dossier, 'Socle.swift'), '@MainActor\nclass JoleneUITestCase: XCTestCase {\n    func tap(_ id: String) {}\n}\n');
    writeFileSync(join(dossier, 'DemoA.swift'), [
      'final class DemoA: JoleneUITestCase {',
      '    func testUn() throws {}',
      '    func testAvecParametre(_ x: Int) {}',
      '    private func texte() {}',
      '}',
      '@MainActor final class DemoB: JoleneUITestCase {',
      '    @MainActor func testDeux() async throws {}',
      '}',
      '',
    ].join('\n'));
    writeFileSync(join(dossier, 'Notes.md'), 'final class Ignoree: JoleneUITestCase { func testX() {} }');
    assert.deepEqual(classesDeTest(dossier), { DemoA: ['testUn'], DemoB: ['testDeux'] });
  } finally {
    rmSync(dossier, { recursive: true, force: true });
  }
});

test('un dépôt rangé ne produit aucune erreur ; STAGING reste hors groupes', () => {
  assert.deepEqual(verifier({ classes: CLASSES, matrice: MATRICE, groupes: GROUPES }), []);
  assert.ok('StagingConnexionTests' in HORS_GROUPES);
});

test('une classe nouvelle non rangée fait échouer le garde', () => {
  const erreurs = verifier({ classes: { ...CLASSES, DemoNouvelle: ['testA'] }, matrice: MATRICE, groupes: GROUPES });
  assert.equal(erreurs.length, 1);
  assert.match(erreurs[0], /DemoNouvelle \(1 test\(s\)\) n'est rangée dans aucun groupe/);
});

test('matrice absente ou divergente, classe en double, groupe sans test', () => {
  assert.match(verifier({ classes: CLASSES, matrice: null, groupes: GROUPES })[0], /introuvable/);
  assert.match(verifier({ classes: CLASSES, matrice: ['parcours', 'socle'], groupes: GROUPES })[0], /Matrice du workflow/);
  const doublon = [...GROUPES, { nom: 'x', cibles: [], classes: ['DemoB'] }];
  assert.ok(verifier({ classes: CLASSES, matrice: [...MATRICE, 'x'], groupes: doublon }).some((e) => /deux groupes/.test(e)));
  const vide = [...GROUPES, { nom: 'vide', cibles: [], classes: ['DemoAbsente'] }];
  assert.ok(verifier({ classes: CLASSES, matrice: [...MATRICE, 'vide'], groupes: vide }).some((e) => /aucun test/.test(e)));
  const horsEtDedans = [{ ...GROUPES[0], classes: [...GROUPES[0].classes, 'StagingConnexionTests'] }, GROUPES[1]];
  assert.ok(verifier({ classes: CLASSES, matrice: MATRICE, groupes: horsEtDedans }).some((e) => /hors groupes/.test(e)));
});

test('sélection xcodebuild et cas attendus : classes présentes seulement, cibles entières', () => {
  assert.deepEqual(argumentsXcodebuild('socle', CLASSES, GROUPES), ['-only-testing:JoleneCoreTests', '-only-testing:JoleneUITests/DemoA']);
  assert.deepEqual(argumentsXcodebuild('parcours', CLASSES, GROUPES), ['-only-testing:JoleneUITests/DemoB']);
  assert.deepEqual(attendus('parcours', CLASSES, GROUPES), {
    groupe: 'parcours', cibles: [], classes: ['DemoB'], cas: ['DemoB/testDeux', 'DemoB/testTrois'],
  });
  // Classe prévue ajoutée plus tard : sélectionnée sans autre modification.
  const avecPrevue = { ...CLASSES, DemoPrevue: ['testQuatre'] };
  assert.deepEqual(argumentsXcodebuild('socle', avecPrevue, GROUPES).at(-1), '-only-testing:JoleneUITests/DemoPrevue');
  assert.throws(() => attendus('inconnu', CLASSES, GROUPES), /Groupe inconnu/);
});
