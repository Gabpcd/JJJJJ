import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// Garde de la décision 22 du lot 2 (docs/mobile-swift/DECISIONS_LOT2.md : « Durée de la CI UI ») : les XCUITest
// tournent en éclats successifs dans chaque job de format de `.github/workflows/ios-swift-ci.yml`, chacun borné à
// 30 min. Un éclat est ouvert par domaine dès qu'un format dépasse 20 min mesurées ; l'éclat « contrats »
// (DemoContratsTests + DemoSignatureContratTests) est sorti de « lot2 » par L2-T9b (revue fraîche, M1 : « lot2 »
// mesurait 20,7 min en ipad-landscape au run 42536866359 avant l'ajout de la signature). La garde vérifie que
// chaque éclat est déclaré partout où le job le lit (étape, résumé, boucle xcresult, artefact) et qu'aucune classe
// n'est exécutée deux fois ni oubliée. Aucun réseau, aucun secret : le test ne lit que des fichiers du dépôt.

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = relative => readFileSync(join(root, relative), 'utf8');
const WORKFLOW = '.github/workflows/ios-swift-ci.yml';
const DOSSIER_UI = 'ios-native/JoleneUITests';
const yml = read(WORKFLOW);

/** Corps du job `ui:` (jusqu'au job suivant, indentation de deux espaces). */
function jobUi() {
  const debut = yml.indexOf('\n  ui:\n');
  assert.ok(debut >= 0, `job ui absent de ${WORKFLOW}`);
  const suite = yml.slice(debut + 1);
  const fin = suite.slice(5).search(/\n {2}[A-Za-z0-9_-]+:\n/);
  return fin < 0 ? suite : suite.slice(0, fin + 5);
}

/** Étapes du job `ui` : nom, identifiant, condition, délai et corps (texte brut de l'étape). */
function etapes(job) {
  const morceaux = job.split(/\n {6}- (?=name: |uses: |run: )/).slice(1);
  return morceaux.map(texte => ({
    nom: /^name: (.+)$/m.exec(texte)?.[1] ?? '',
    id: /^ {8}id: (\S+)$/m.exec(texte)?.[1] ?? null,
    si: /^ {8}if: (.+)$/m.exec(texte)?.[1] ?? null,
    delai: Number(/^ {8}timeout-minutes: (\d+)$/m.exec(texte)?.[1] ?? Number.NaN),
    texte,
  }));
}

const options = (texte, option) => [...texte.matchAll(new RegExp(`-${option}:(\\S+)`, 'g'))].map(m => m[1]);

/** Éclats déclarés par les étapes `test-without-building — éclat <nom>`. */
function eclatsDesEtapes(liste) {
  return liste
    .map(e => ({ ...e, eclat: /^test-without-building — éclat (\S+) /.exec(e.nom)?.[1] }))
    .filter(e => e.eclat)
    .map(e => ({
      nom: e.eclat, id: e.id, si: e.si, delai: e.delai,
      seulement: options(e.texte, 'only-testing'), sauf: options(e.texte, 'skip-testing'),
      resultat: /resultat="\$RUNNER_TEMP\/ui-\$JOLENE_UI_FORMAT-(\S+)\.xcresult"/.exec(e.texte)?.[1],
      journal: /test-without-building-(\S+)\.log"/.exec(e.texte)?.[1],
    }));
}

/** Tableau `eclats` du script de résumé : nom, variable du code de sortie, classes exigées. */
function eclatsDuResume(job) {
  return [...job.matchAll(/\{ nom: "([a-z0-9]+)", code: process\.env\.([A-Z0-9_]+), classes: \[([^\]]*)\] \}/g)]
    .map(m => ({ nom: m[1], code: m[2], classes: [...m[3].matchAll(/"([A-Za-z0-9]+)"/g)].map(c => c[1]) }));
}

/**
 * Classes XCUITest finales de la cible JoleneUITests : sous-classes de `JoleneUITestCase`, directes ou par une classe
 * de base intermédiaire sans test (`DemoPointageUITestCase` de L2-T4b, dont héritent `DemoPointageTests` et
 * `DemoPointageEtatsTests` ; intégration du 9 novembre 2026).
 */
function classesUi() {
  const parents = new Map();
  const finales = new Set();
  for (const f of readdirSync(join(root, DOSSIER_UI)).filter(n => n.endsWith('.swift'))) {
    for (const m of read(`${DOSSIER_UI}/${f}`).matchAll(/^(final )?class (\w+): (\w+)/gm)) {
      parents.set(m[2], m[3]);
      if (m[1]) finales.add(m[2]);
    }
  }
  const herite = nom => {
    const vus = new Set();
    for (let c = parents.get(nom); c && !vus.has(c); c = parents.get(c)) {
      if (c === 'JoleneUITestCase') return true;
      vus.add(c);
    }
    return false;
  };
  return [...finales].filter(herite);
}

const job = jobUi();
const liste = etapes(job);
const parEtape = eclatsDesEtapes(liste);
const parResume = eclatsDuResume(job);
const classes = classesUi();
const socle = parEtape.find(e => e.nom === 'socle');
const domaines = parEtape.filter(e => e.nom !== 'socle');
const classesDe = e => e.seulement.map(c => c.replace(/^JoleneUITests\//, ''));

// À l'intégration du 9 novembre 2026, l'éclat « lot2 » n'existe plus : L2-T4b l'a découpé par domaine (« presences »,
// « pointage », « documents », « contrats »). La garde exige donc que les deux classes des contrats ne tournent dans
// aucun autre éclat, au lieu de les chercher hors de « lot2 ».
test('décision 22 : un éclat « contrats » porte DemoContratsTests et DemoSignatureContratTests, et eux seuls', () => {
  const contrats = parEtape.find(e => e.nom === 'contrats');
  assert.ok(contrats, `aucune étape « test-without-building — éclat contrats » dans ${WORKFLOW}`);
  assert.deepEqual(classesDe(contrats).sort(), ['DemoContratsTests', 'DemoSignatureContratTests']);
  const autres = domaines.filter(e => e.nom !== 'contrats');
  assert.ok(autres.length >= 1, 'aucun autre éclat de domaine du lot 2');
  for (const e of autres) {
    for (const c of ['DemoContratsTests', 'DemoSignatureContratTests']) {
      assert.ok(!classesDe(e).includes(c), `${c} est aussi dans l'éclat « ${e.nom} »`);
    }
  }
});

test('décision 22 : les XCUITest du pointage (classe de base intermédiaire) sont reconnus et rangés dans un éclat', () => {
  for (const c of ['DemoPointageTests', 'DemoPointageEtatsTests', 'DemoPresenceDetailTests']) {
    assert.ok(classes.includes(c), `${c} n est pas reconnue comme classe XCUITest`);
    assert.equal(domaines.filter(e => classesDe(e).includes(c)).length, 1, `${c} doit tourner dans un seul éclat de domaine`);
  }
  assert.ok(!classes.includes('DemoPointageUITestCase'), 'la classe de base sans test n est pas une classe XCUITest');
});

test('décision 22 : chaque éclat est déclaré par son étape, le résumé, la boucle xcresult et l artefact', () => {
  const noms = parEtape.map(e => e.nom);
  assert.ok(noms[0] === 'socle' && noms.length >= 3, `éclats lus : ${noms.join(', ')}`);
  assert.equal(new Set(noms).size, noms.length, 'nom d éclat en double');
  assert.deepEqual(parResume.map(e => e.nom), noms, 'tableau `eclats` du résumé ≠ étapes');
  const boucle = /for eclat in ([a-z0-9 ]+); do/.exec(job)?.[1].trim().split(/\s+/);
  assert.deepEqual(boucle, noms, 'boucle xcresult du résumé ≠ étapes');
  const resume = liste.find(e => e.nom.startsWith('Résumé xcresult'));
  assert.ok(resume, 'étape de résumé absente');
  const artefact = liste.find(e => e.nom.startsWith('Conserver xcresult'));
  assert.ok(artefact, 'étape d artefact absente');
  for (const e of parEtape) {
    assert.equal(e.resultat, e.nom, `éclat ${e.nom} : bundle xcresult mal nommé`);
    assert.equal(e.journal, e.nom, `éclat ${e.nom} : journal mal nommé`);
    assert.ok(e.id, `éclat ${e.nom} : étape sans id`);
    assert.equal(e.delai, 30, `éclat ${e.nom} : délai de l étape ≠ 30 min`);
    const code = parResume.find(r => r.nom === e.nom).code;
    assert.ok(resume.texte.includes(`${code}: \${{ steps.${e.id}.outputs.code }}`), `éclat ${e.nom} : ${code} non relié à steps.${e.id}`);
    assert.ok(artefact.texte.includes(`ui-\${{ matrix.format }}-${e.nom}.xcresult`), `éclat ${e.nom} : xcresult non conservé`);
  }
  for (const e of domaines) {
    assert.equal(e.si, "always() && steps.build.outcome == 'success'", `éclat ${e.nom} : doit tourner même si un éclat précédent échoue`);
  }
});

test('décision 22 : le plafond du job couvre la somme des éclats plus le build', () => {
  const plafond = Number(/^ {4}timeout-minutes: (\d+)$/m.exec(job)?.[1]);
  const somme = parEtape.reduce((total, e) => total + e.delai, 0);
  assert.ok(plafond >= somme + 15, `plafond du job ${plafond} min < ${somme} min d éclats + 15 min de build`);
});

test('décision 22 : chaque XCUITest tourne dans un seul éclat, les classes STAGING jamais', () => {
  assert.ok(socle, 'éclat socle absent');
  assert.deepEqual(socle.seulement.sort(), ['JoleneCoreTests', 'JoleneDesignTests', 'JoleneUITests']);
  const staging = classes.filter(c => c.startsWith('Staging'));
  assert.ok(staging.includes('StagingConnexionTests'), 'StagingConnexionTests attendue');
  const vues = new Map();
  for (const e of domaines) {
    assert.ok(e.seulement.length >= 1 && e.sauf.length === 0, `éclat ${e.nom} : -only-testing seulement`);
    const resume = parResume.find(r => r.nom === e.nom);
    assert.deepEqual([...resume.classes].sort(), [...classesDe(e)].sort(), `éclat ${e.nom} : classes exigées par le résumé ≠ -only-testing`);
    for (const c of e.seulement) {
      assert.match(c, /^JoleneUITests\/Demo\w+Tests$/, `éclat ${e.nom} : ${c} n est pas une classe démo`);
      const nom = c.replace(/^JoleneUITests\//, '');
      assert.ok(classes.includes(nom), `éclat ${e.nom} : ${nom} n existe pas dans ${DOSSIER_UI}`);
      assert.ok(!vues.has(nom), `${nom} dans les éclats ${vues.get(nom)} et ${e.nom}`);
      vues.set(nom, e.nom);
    }
  }
  const attendu = [...staging, ...vues.keys()].map(c => `JoleneUITests/${c}`).sort();
  assert.deepEqual([...socle.sauf].sort(), attendu, 'le socle doit exclure les classes STAGING et celles des autres éclats, rien d autre');
  assert.deepEqual(parResume.find(r => r.nom === 'socle').classes, [], 'le socle n exige aucune classe nommée');
});
