import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
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
  // Fusion des lots 2 et 3 : les noms d'éclats du lot 3 portent un tiret (`lot3-compte`) ; la forme reste stricte.
  return [...job.matchAll(/\{ nom: "([a-z0-9]+(?:-[a-z0-9]+)*)", code: process\.env\.([A-Z0-9_]+), classes: \[([^\]]*)\] \}/g)]
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
  const boucle = /for eclat in ([a-z0-9 -]+); do/.exec(job)?.[1].trim().split(/\s+/);
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
  // Revue B8 de la vague 5, m1 : le socle aussi. Sans condition, il était sauté dès qu'une étape précédente échouait (la
  // vérification du Package.resolved au run 43948577842), et JoleneCoreTests, JoleneDesignTests et les XCUITest des lots
  // 0 et 1 ne prouvaient plus rien.
  for (const e of parEtape) {
    assert.equal(e.si, "always() && steps.build.outcome == 'success'",
      `éclat ${e.nom} : doit tourner même si un éclat ou une vérification précédents échouent`);
  }
});

test('décision 22 : le plafond du job couvre la somme des éclats plus le build', () => {
  const plafond = Number(/^ {4}timeout-minutes: (\d+)$/m.exec(job)?.[1]);
  const somme = parEtape.reduce((total, e) => total + e.delai, 0);
  assert.ok(plafond >= somme + 15, `plafond du job ${plafond} min < ${somme} min d éclats + 15 min de build`);
});

// Revue fraîche B8 n°1 de L3-T15, m4 : la résolution SPM (faite par build-for-testing, une fois par job) ne réécrit
// jamais le Package.resolved versionné de l'app. Une version de paquet ou un originHash différent ferait tester la CI
// sur un graphe de dépendances que le dépôt ne décrit pas (Sentry Cocoa, supabase-swift épinglés en version exacte).
const PACKAGE_RESOLVED_APP = 'ios-native/Jolene.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved';

test('L3-T15 m4 : Package.resolved de l app inchangé après la résolution SPM, avant le premier éclat', () => {
  assert.ok(read(PACKAGE_RESOLVED_APP).includes('"identity" : "sentry-cocoa"'), `${PACKAGE_RESOLVED_APP} illisible`);
  const iBuild = liste.findIndex(e => e.id === 'build');
  assert.ok(iBuild >= 0 && liste[iBuild].texte.includes('xcodebuild build-for-testing'), 'étape build-for-testing (id build) absente');
  // Revue B8 de la vague 5 : le chemin est porté par la variable `fichier` de l'étape (diff, copie du diagnostic).
  const iGarde = liste.findIndex(e => e.texte.includes(`fichier=${PACKAGE_RESOLVED_APP}\n`)
    && e.texte.includes('if ! git diff --exit-code -- "$fichier"; then'));
  assert.ok(iGarde >= 0, `aucune étape ne vérifie « git diff --exit-code » sur ${PACKAGE_RESOLVED_APP}`);
  assert.equal(iGarde, iBuild + 1, 'la vérification suit immédiatement la résolution SPM (build-for-testing)');
  const premierEclat = liste.findIndex(e => /^test-without-building — éclat /.test(e.nom));
  assert.ok(iGarde < premierEclat, 'la vérification précède les éclats');
  const garde = liste[iGarde];
  assert.equal(garde.si, null, 'la vérification ne tourne qu après un build réussi (condition par défaut)');
  assert.ok(garde.delai <= 2, `délai de la vérification : ${garde.delai} min (au plus 2 : le plafond du job reste tenu)`);
  assert.ok(!/^test-without-building/.test(garde.nom), 'la vérification n est pas un éclat');
});

// Revue B8 de la vague 5, M1 : l'étape a échoué sous Xcode 26.4.1 (iPad portrait et paysage, run 43948577842) et ses
// journaux ont été perdus à l'annulation du run. Elle doit désormais se diagnostiquer seule, sans être affaiblie : diff
// imprimé, fichier résolu copié puis publié aussitôt en artefact, et échec de l'étape dans tous les cas.
test('revue B8 vague 5, M1 : une dérive du Package.resolved échoue toujours et publie aussitôt le fichier résolu', () => {
  const iGarde = liste.findIndex(e => e.texte.includes(`git diff --exit-code -- "$fichier"`));
  assert.ok(iGarde >= 0, 'vérification du Package.resolved absente');
  const garde = liste[iGarde];
  assert.equal(garde.id, 'package_resolved', 'la vérification porte un id, lu par l étape de l artefact');
  assert.ok(garde.texte.includes(`fichier=${PACKAGE_RESOLVED_APP}\n`), 'la vérification porte sur le Package.resolved de l app');
  // Jamais affaiblie : pas de continue-on-error, et la branche de dérive se termine par un échec.
  assert.doesNotMatch(garde.texte, /^ {8}continue-on-error:/m, 'la vérification ne doit jamais être tolérée');
  const derive = /if ! git diff --exit-code -- "\$fichier"; then\n([\s\S]*?)\n {10}fi(?:\n|$)/.exec(garde.texte)?.[1];
  assert.ok(derive, 'branche de dérive (if ! git diff --exit-code …; then … fi) absente');
  const lignes = derive.trim().split('\n').map(l => l.trim());
  assert.equal(lignes.at(-1), 'exit 1', 'la branche de dérive échoue toujours, en dernier');
  assert.ok(!lignes.slice(0, -1).some(l => /^exit\b/.test(l)), 'aucune sortie anticipée avant la copie du diagnostic');
  // Diagnostic : diff (imprimé par git diff --exit-code, puis conservé), fichier résolu et toolchain copiés.
  assert.ok(derive.includes('diagnostic="$JOLENE_UI_OUTPUT/package-resolved"'), 'dossier de diagnostic sous $JOLENE_UI_OUTPUT');
  assert.ok(derive.includes('git diff -- "$fichier" > "$diagnostic/Package.resolved.diff"'), 'diff conservé dans le diagnostic');
  assert.ok(derive.includes('cp "$fichier" "$diagnostic/Package.resolved"'), 'fichier résolu copié dans le diagnostic');
  assert.ok(derive.includes('xcodebuild -version'), 'version d Xcode consignée (la résolution en dépend)');
  assert.match(derive, /::error::[^\n]*committer tel quel le Package\.resolved de l'artefact package-resolved-/,
    'le message d erreur donne le correctif');
  // Artefact publié IMMÉDIATEMENT après, sur échec de la vérification seulement.
  const artefact = liste[iGarde + 1];
  assert.ok(artefact, 'étape d artefact absente après la vérification');
  assert.match(artefact.texte, /^uses: actions\/upload-artifact@[0-9a-f]{40} # v4$|\n {8}uses: actions\/upload-artifact@[0-9a-f]{40} # v4\n/,
    'l étape suivant la vérification publie un artefact (actions/upload-artifact v4 épinglé)');
  assert.equal(artefact.si, "failure() && steps.package_resolved.outcome == 'failure'",
    'artefact publié sur échec de la vérification seulement');
  assert.match(artefact.texte, /\n {10}name: package-resolved-\$\{\{ matrix\.format \}\}-\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}\n/,
    'artefact nommé package-resolved-<format>-<sha>');
  assert.match(artefact.texte, /\n {10}path: ios-native\/test-results\/\$\{\{ matrix\.format \}\}\/package-resolved\/\n/,
    'artefact = dossier de diagnostic ($JOLENE_UI_OUTPUT/package-resolved)');
  assert.match(yml, /\n {6}JOLENE_UI_OUTPUT: \$\{\{ github\.workspace \}\}\/ios-native\/test-results\/\$\{\{ matrix\.format \}\}\n/,
    'JOLENE_UI_OUTPUT et le chemin de l artefact désignent le même dossier');
  assert.doesNotMatch(artefact.texte, /^ {8}continue-on-error:/m);
  assert.ok(artefact.delai <= 1, `délai de l artefact : ${artefact.delai} min`);
  // Les éclats tournent quand même (m1) : le premier suit l'artefact.
  assert.match(liste[iGarde + 2]?.nom ?? '', /^test-without-building — éclat socle /, 'le socle suit l artefact');
  // Plafond : build, vérification, artefact et éclats tiennent sous le plafond du job (360 min).
  const plafond = Number(/^ {4}timeout-minutes: (\d+)$/m.exec(job)?.[1]);
  const bornees = liste.filter(e => Number.isFinite(e.delai));
  const somme = bornees.reduce((total, e) => total + e.delai, 0);
  assert.ok(somme <= plafond && plafond <= 360, `délais des étapes : ${somme} min pour un plafond de ${plafond} min`);
  assert.equal(somme, 357, '25 (build) + 1 (vérification) + 1 (artefact) + 11 × 30 (éclats) : marge de 3 min inchangée');
});

// Revue B8 de la vague 5, M1 : sentry-cocoa 9.32.0 déclare KSCrash à une révision fixe dans Package@swift-6.2.swift
// (et Package@swift-6.1.swift) ; SwiftPM 6.2 (Xcode 26.4.1, CI et TestFlight) l'épingle même sous le trait V10
// désactivé, Xcode 16.4 non. Le Package.resolved versionné est celui d'Xcode 26.4.1 (docs/mobile-swift/SENTRY_IOS.md §1).
test('revue B8 vague 5, M1 : le Package.resolved de l app épingle KSCrash à la révision déclarée par sentry-cocoa 9.32.0', () => {
  const resolu = JSON.parse(read(PACKAGE_RESOLVED_APP));
  const pin = identite => resolu.pins.find(p => p.identity === identite);
  assert.equal(pin('sentry-cocoa')?.state.version, '9.32.0', 'révision de KSCrash relue pour sentry-cocoa 9.32.0 seulement');
  assert.deepEqual(pin('kscrash'), {
    identity: 'kscrash',
    kind: 'remoteSourceControl',
    location: 'https://github.com/getsentry/KSCrash.git',
    state: { revision: '18a633dec20c265f03386294f9d82d208bb13094' },
  });
  const identites = resolu.pins.map(p => p.identity);
  assert.deepEqual(identites, [...identites].sort(), 'pins dans l ordre alphabétique des identités, comme Xcode les écrit');
  assert.equal(read(PACKAGE_RESOLVED_APP), `${JSON.stringify(resolu, null, 2).replace(/": /g, '" : ')}\n`,
    'format d Xcode : deux espaces, « " : », saut de ligne final');
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

// Gel iPhone CI — 16/11/2026 (docs/mobile-swift/DECISIONS_LOT2.md, section du même nom ; run 43889328109) : le fil
// principal de l'app attend le serveur de rendu du simulateur (`CA::Render::Message::send_message`) après un glissement
// qui ferme le pavé numérique ; le simulateur ne relance plus l'app et les éclats suivants meurent à 30 min sans preuve.
// Résilience : au début de chaque éclat après le socle, `relancer-si-gel` redémarre le simulateur si l'éclat précédent a
// gelé ou dépassé son délai, en 2 min au plus, DANS les 30 min de l'éclat (aucune étape, aucune minute de plus au plafond
// du job). L'éclat gelé reste en échec : le résumé exige toujours chaque éclat vert. Instrumentation : le veilleur des
// éclats presences et pointage relève l'app, backboardd, SpringBoard, l'écran, le journal du simulateur, les .ips et la
// mémoire de l'hôte. Les deux sous-commandes sont exécutées ici avec des outils simulés (aucun simulateur, aucun réseau).
const SCRIPT_GEL = 'scripts/mobile/ios-ci-gel-simulateur.sh';
const MARQUES_GEL = ['main thread busy', 'failed to quiesce', 'Failed to get launch progress', 'exceeded execution time allowance'];

test('gel iPhone : chaque éclat après le socle relance le simulateur si l éclat précédent a gelé, avant son xcodebuild', () => {
  assert.ok(parEtape.length >= 3, 'éclats non lus');
  for (let i = 1; i < parEtape.length; i += 1) {
    const e = parEtape[i];
    const precedent = parEtape[i - 1];
    const texte = liste.find(x => x.id === e.id).texte;
    assert.ok(texte.includes(`\n          ECLAT_PRECEDENT: ${precedent.nom}\n`), `éclat ${e.nom} : ECLAT_PRECEDENT ≠ ${precedent.nom}`);
    assert.ok(texte.includes(`\n          ECLAT_PRECEDENT_ISSUE: \${{ steps.${precedent.id}.outcome }}\n`),
      `éclat ${e.nom} : issue de steps.${precedent.id} non transmise`);
    assert.ok(texte.includes(`\n          ECLAT_PRECEDENT_CODE: \${{ steps.${precedent.id}.outputs.code }}\n`),
      `éclat ${e.nom} : code de steps.${precedent.id} non transmis`);
    const appel = texte.indexOf(`\n          bash ${SCRIPT_GEL} relancer-si-gel ${e.nom} || `);
    assert.ok(appel >= 0, `éclat ${e.nom} : aucun « bash ${SCRIPT_GEL} relancer-si-gel ${e.nom} || … » (jamais un échec d étape)`);
    assert.ok(appel < texte.indexOf('xcodebuild test-without-building'), `éclat ${e.nom} : le contrôle du gel précède xcodebuild`);
    assert.equal(texte.split('relancer-si-gel').length - 1, 1, `éclat ${e.nom} : un seul contrôle du gel`);
  }
  const texteSocle = liste.find(x => x.id === socle.id).texte;
  assert.ok(!texteSocle.includes('relancer-si-gel') && !texteSocle.includes('ECLAT_PRECEDENT'), 'le socle suit le build : aucun éclat précédent');
  for (const e of liste.filter(x => x.texte.includes('relancer-si-gel'))) {
    assert.ok(parEtape.some(p => p.id === e.id), `étape « ${e.nom} » : le redémarrage n a lieu que dans un éclat`);
  }
  // Le script est dans les filtres de chemins (pull_request et push) : le modifier relance la CI iOS.
  assert.equal(yml.split(`\n      - '${SCRIPT_GEL}'\n`).length - 1, 2, `${SCRIPT_GEL} absent des filtres de chemins pull_request et push`);
});

test('gel iPhone : le redémarrage est borné à 2 min dans l éclat suivant, le plafond du job est inchangé', () => {
  const script = read(SCRIPT_GEL);
  assert.ok(script.includes('borne_s="${JOLENE_RELANCE_BORNE_S:-120}"'), 'borne par défaut du redémarrage ≠ 120 s');
  for (const commande of ['xcrun simctl shutdown "$UDID"', 'xcrun simctl boot "$UDID"', 'xcrun simctl bootstatus "$UDID" -b']) {
    assert.ok(script.includes(`borne_restante "$fin" ${commande}`), `redémarrage : « ${commande} » non borné par l échéance commune`);
  }
  for (const marque of MARQUES_GEL) assert.ok(script.toLowerCase().includes(marque.toLowerCase()), `marque de gel « ${marque} » absente`);
  // Aucune étape n'est ajoutée pour le redémarrage : le plafond reste la somme des éclats plus le build.
  assert.equal(liste.filter(e => /simulateur/i.test(e.nom) && /red[ée]marr/i.test(e.nom)).length, 0, 'aucune étape de redémarrage hors éclat');
  for (const e of parEtape) assert.equal(e.delai, 30, `éclat ${e.nom} : délai ≠ 30 min (le redémarrage s y loge)`);
  const plafond = Number(/^ {4}timeout-minutes: (\d+)$/m.exec(job)?.[1]);
  assert.ok(plafond <= 360, `plafond du job au-delà de celui de GitHub : ${plafond} min`);
  assert.ok(job.includes('borné à 2 min') && job.includes('aucune étape ni minute'), 'budget du redémarrage non documenté dans le commentaire du job');
  const syntaxe = spawnSync('bash', ['-n', join(root, SCRIPT_GEL)], { encoding: 'utf8' });
  assert.equal(syntaxe.status, 0, `bash -n ${SCRIPT_GEL} : ${syntaxe.stderr}`);
});

test('gel iPhone : les éclats presences et pointage lancent le veilleur instrumenté, arrêté après xcodebuild', () => {
  for (const nom of ['presences', 'pointage']) {
    const e = parEtape.find(x => x.nom === nom);
    assert.ok(e, `éclat ${nom} absent`);
    const texte = liste.find(x => x.id === e.id).texte;
    assert.ok(texte.includes(`journal="$JOLENE_UI_OUTPUT/test-without-building-${nom}.log"`), `éclat ${nom} : journal du veilleur`);
    const lancement = `bash ${SCRIPT_GEL} veiller ${nom} "$journal" > "$JOLENE_UI_OUTPUT/gel-${nom}-veilleur.log" 2>&1 &\n          veilleur=$!`;
    assert.ok(texte.includes(lancement), `éclat ${nom} : veilleur non lancé en tâche de fond (sortie dans l artefact)`);
    const iXcode = texte.indexOf('xcodebuild test-without-building');
    assert.ok(texte.indexOf(lancement) < iXcode, `éclat ${nom} : veilleur lancé avant xcodebuild`);
    const arret = texte.indexOf('kill "$veilleur" 2>/dev/null || true');
    assert.ok(arret > iXcode && texte.indexOf('pkill -P "$veilleur" 2>/dev/null || true') > iXcode, `éclat ${nom} : veilleur arrêté après xcodebuild`);
    assert.ok(!/\bsample "\$pid"/.test(texte), `éclat ${nom} : l ancien veilleur en ligne est remplacé par le script`);
  }
  const script = read(SCRIPT_GEL);
  for (const attendu of ['borne 30 xcrun simctl io "$UDID" screenshot', 'xcrun simctl spawn "$UDID" launchctl list',
    'xcrun simctl spawn "$UDID" log show --last 10m', 'RuntimeRoot/usr/libexec/backboardd', 'SpringBoard.app/SpringBoard',
    'vm_stat', 'sysctl vm.swapusage', 'top -l 1', '*.ips']) {
    assert.ok(script.includes(attendu), `veilleur : « ${attendu} » absent`);
  }
});

// Bac à sable : outils simulés en tête du PATH (chaque appel est journalisé), sortie et HOME temporaires.
function bac(outils) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-gel-'));
  const bin = join(dir, 'bin');
  const sortie = join(dir, 'sortie');
  mkdirSync(bin);
  mkdirSync(sortie);
  const appels = join(dir, 'appels.log');
  for (const [nom, corps] of Object.entries(outils)) {
    writeFileSync(join(bin, nom), `#!/usr/bin/env bash\nprintf '%s\\n' "${nom} $*" >> '${appels}'\n${corps}\n`);
    chmodSync(join(bin, nom), 0o755);
  }
  return {
    dir, sortie,
    appels: () => (existsSync(appels) ? readFileSync(appels, 'utf8').trim().split('\n').filter(Boolean) : []),
    lancer: (args, env = {}) => spawnSync('bash', [join(root, SCRIPT_GEL), ...args], {
      encoding: 'utf8', timeout: 60_000,
      env: { PATH: `${bin}:${process.env.PATH}`, HOME: dir, UDID: 'UDID-TEST', JOLENE_UI_OUTPUT: sortie, ...env },
    }),
    nettoyer: () => rmSync(dir, { recursive: true, force: true }),
  };
}

const XCRUN_REDEMARRAGE = 'exit 0';
const REDEMARRAGE = ['xcrun simctl shutdown UDID-TEST', 'xcrun simctl boot UDID-TEST', 'xcrun simctl bootstatus UDID-TEST -b'];

function relancer(b, { issue = 'success', code = '0', journal = null, precedent = 'pointage', env = {} } = {}) {
  if (journal !== null) writeFileSync(join(b.sortie, `test-without-building-${precedent}.log`), journal);
  const resume = join(b.dir, 'resume.md');
  const r = b.lancer(['relancer-si-gel', 'documents'], {
    ECLAT_PRECEDENT: precedent, ECLAT_PRECEDENT_ISSUE: issue, ECLAT_PRECEDENT_CODE: code, GITHUB_STEP_SUMMARY: resume, ...env,
  });
  return { ...r, resume: existsSync(resume) ? readFileSync(resume, 'utf8') : '' };
}

test('gel iPhone : chaque marque de gel du journal précédent redémarre le simulateur (shutdown, boot, bootstatus -b)', () => {
  for (const ligne of ['t = 312.07s Wait for app.jolene.ios to idle: main thread busy for 60.0s',
    'App failed to quiesce within 60s', 'Failed to get launch progress for app.jolene.ios',
    "Test Case '-[JoleneUITests.DemoPointageTests testX]' exceeded execution time allowance of 10 minutes",
    'MAIN THREAD BUSY']) {
    const b = bac({ xcrun: XCRUN_REDEMARRAGE });
    try {
      const r = relancer(b, { issue: 'success', code: '65', journal: `Test Suite 'DemoPointageTests' started\n${ligne}\n** TEST FAILED **\n` });
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(b.appels(), REDEMARRAGE, `« ${ligne} » : redémarrage attendu`);
      assert.match(r.stdout, /::warning::Éclat pointage : gel ou dépassement constaté/);
      assert.match(r.stdout, /l'éclat pointage reste en échec/);
      assert.match(r.resume, /éclat pointage .* simulateur redémarré avant l'éclat documents/);
      assert.ok(existsSync(join(b.sortie, 'relance-simulateur-avant-documents.txt')), 'trace du redémarrage dans l artefact');
    } finally { b.nettoyer(); }
  }
});

test('gel iPhone : une étape interrompue (délai dépassé) ou un xcodebuild tué redémarre aussi le simulateur', () => {
  for (const [issue, code] of [['failure', ''], ['cancelled', ''], ['success', '137'], ['success', '143'], ['success', '124']]) {
    const b = bac({ xcrun: XCRUN_REDEMARRAGE });
    try {
      const r = relancer(b, { issue, code, journal: "Test Suite 'DemoPointageTests' started\n" });
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(b.appels(), REDEMARRAGE, `issue ${issue}, code ${code || 'absent'} : redémarrage attendu`);
    } finally { b.nettoyer(); }
  }
});

test('gel iPhone : un éclat vert, un échec d assertion ordinaire ou un éclat sauté ne redémarre rien', () => {
  // Un éclat vert dont le journal garde une attente absorbée (« main thread busy » passager) n'est pas un éclat en échec.
  for (const [issue, code, journal] of [['success', '0', '** TEST SUCCEEDED **\n'], ['success', '65', 'XCTAssertEqual failed\n** TEST FAILED **\n'],
    ['skipped', '', null], ['success', '0', null], ['success', '0', 'Wait for app to idle: main thread busy for 3.1s\n** TEST SUCCEEDED **\n']]) {
    const b = bac({ xcrun: XCRUN_REDEMARRAGE });
    try {
      const r = relancer(b, { issue, code, journal });
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(b.appels(), [], `issue ${issue}, code ${code || 'absent'} : aucun redémarrage`);
      assert.doesNotMatch(r.stdout, /::warning::/);
      assert.equal(r.resume, '', 'rien au résumé sans gel');
    } finally { b.nettoyer(); }
  }
});

test('gel iPhone : un redémarrage bloqué est coupé à sa borne et ne fait jamais échouer l étape', () => {
  const bloque = bac({ xcrun: 'case "$*" in *bootstatus*) sleep 30 ;; esac' });
  try {
    const debut = Date.now();
    const r = relancer(bloque, { issue: 'failure', code: '', env: { JOLENE_RELANCE_BORNE_S: '2' } });
    const duree = (Date.now() - debut) / 1000;
    assert.equal(r.status, 0, r.stderr);
    assert.ok(duree < 12, `redémarrage coupé à sa borne (2 s + grâce), mesuré ${duree} s`);
    assert.deepEqual(bloque.appels(), REDEMARRAGE);
    assert.match(r.stdout, /redémarrage non abouti/);
  } finally { bloque.nettoyer(); }
  const enEchec = bac({ xcrun: 'echo "simctl indisponible" >&2; exit 1' });
  try {
    const r = relancer(enEchec, { issue: 'failure', code: '' });
    assert.equal(r.status, 0, 'un simctl en échec ne fait pas échouer l étape');
    assert.match(r.stdout, /redémarrage non abouti/);
  } finally { enEchec.nettoyer(); }
  const borne = bac({});
  try {
    const debut = Date.now();
    const r = borne.lancer(['borne', '1', 'sleep', '30']);
    assert.ok((Date.now() - debut) / 1000 < 8, 'borne : commande coupée');
    assert.equal(r.status, 143, 'borne : code de la commande coupée (SIGTERM)');
    assert.equal(borne.lancer(['borne', '5', 'true']).status, 0, 'borne : code de la commande terminée');
  } finally { borne.nettoyer(); }
});

const OUTILS_VEILLEUR = {
  pgrep: 'case "$*" in *Jolene.app*) echo 4242 ;; *backboardd*) echo 5151 ;; *SpringBoard*) echo 6161 ;; esac',
  sample: 'while [ $# -gt 0 ]; do if [ "$1" = -file ]; then echo "pile $*" > "$2"; fi; shift; done',
  sudo: 'exit 1',
  vm_stat: 'echo "Pages free: 1"',
  sysctl: 'echo "vm.swapusage: total = 1024.00M"',
  top: 'echo "Processes: 1 total"',
  xcrun: [
    'case "$*" in',
    '  *"launchctl list"*) printf "PID\\tStatus\\tLabel\\n111\\t0\\tcom.apple.backboardd\\n222\\t0\\tcom.apple.SpringBoard\\n" ;;',
    '  *"io UDID-TEST screenshot"*) for d; do :; done; printf "PNG" > "$d" ;;',
    '  *"log show"*) echo "journal du simulateur" ;;',
    'esac',
  ].join('\n'),
};

test('gel iPhone : le veilleur relève l app, backboardd, SpringBoard, l écran, le journal, les .ips et la mémoire, trois fois', () => {
  const b = bac(OUTILS_VEILLEUR);
  try {
    const journal = join(b.sortie, 'test-without-building-pointage.log');
    writeFileSync(journal, 't = 120.00s Wait for app.jolene.ios to idle: main thread busy\n');
    const rapports = join(b.dir, 'Library/Logs/DiagnosticReports');
    mkdirSync(rapports, { recursive: true });
    writeFileSync(join(rapports, 'Jolene-2026-11-16.ips'), '{}');
    const r = b.lancer(['veiller', 'pointage', journal],
      { JOLENE_VEILLEUR_PAS_S: '0', JOLENE_VEILLEUR_PAUSE_S: '0', JOLENE_IPS_HOTE: rapports });
    assert.equal(r.status, 0, r.stderr);
    const fichiers = readdirSync(b.sortie);
    for (const n of [1, 2, 3]) {
      for (const f of [`gel-pointage-sample-${n}.txt`, `gel-pointage-backboardd-sample-${n}.txt`, `gel-pointage-springboard-sample-${n}.txt`,
        `gel-pointage-ecran-${n}.png`, `gel-pointage-memoire-${n}.txt`]) assert.ok(fichiers.includes(f), `${f} absent : ${fichiers.join(', ')}`);
    }
    for (const n of [1, 3]) assert.ok(fichiers.includes(`gel-pointage-journal-simulateur-${n}.txt`), `journal du simulateur, passe ${n}`);
    const memoire = readFileSync(join(b.sortie, 'gel-pointage-memoire-1.txt'), 'utf8');
    for (const t of ['vm_stat', 'Pages free', 'vm.swapusage', 'top -l 1', 'Processes']) assert.ok(memoire.includes(t), `mémoire : « ${t} »`);
    assert.ok(existsSync(join(b.sortie, 'gel-pointage-ips/hote/Jolene-2026-11-16.ips')), '.ips récent de l hôte copié');
    const appels = b.appels();
    assert.ok(appels.includes(`sample 4242 5 -file ${join(b.sortie, 'gel-pointage-sample-1.txt')}`), 'sample de l app Jolene');
    assert.ok(appels.includes(`sample 111 5 -file ${join(b.sortie, 'gel-pointage-backboardd-sample-1.txt')}`), 'sample de backboardd (pid du simulateur)');
    assert.ok(appels.includes(`sample 222 5 -file ${join(b.sortie, 'gel-pointage-springboard-sample-1.txt')}`), 'sample de SpringBoard (pid du simulateur)');
    const logShow = appels.find(a => a.includes('log show'));
    assert.ok(logShow?.startsWith('xcrun simctl spawn UDID-TEST log show --last 10m'), `log show : ${logShow}`);
    for (const t of ['backboardd', 'SpringBoard', 'UIKit', 'coreanimation']) assert.ok(logShow.toLowerCase().includes(t.toLowerCase()), `prédicat : ${t}`);
    assert.ok(appels.includes(`xcrun simctl io UDID-TEST screenshot ${join(b.sortie, 'gel-pointage-ecran-1.png')}`), 'capture de l écran du simulateur');
  } finally { b.nettoyer(); }
});

test('gel iPhone : un veilleur dont chaque outil échoue reste muet pour l étape (code 0, traces dans l artefact)', () => {
  const b = bac({ pgrep: 'case "$*" in *backboardd*) echo 5151 ;; esac; exit 0', sample: 'exit 1', sudo: 'exit 1', vm_stat: 'exit 1',
    sysctl: 'exit 1', top: 'exit 1', xcrun: 'exit 1' });
  try {
    const journal = join(b.sortie, 'test-without-building-presences.log');
    writeFileSync(journal, 'Failed to get launch progress\n');
    const r = b.lancer(['veiller', 'presences', journal], { JOLENE_VEILLEUR_PAS_S: '0', JOLENE_VEILLEUR_PAUSE_S: '0', JOLENE_IPS_HOTE: join(b.dir, 'absent') });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(b.appels().includes('pgrep -n -f RuntimeRoot/usr/libexec/backboardd'), 'repli pgrep sur le chemin du runtime');
    assert.ok(b.appels().some(a => a.startsWith('sample 5151 5 -file ')), 'sample du pid trouvé par pgrep');
    assert.match(readFileSync(join(b.sortie, 'gel-presences-springboard-sample-1.txt'), 'utf8'), /processus introuvable/);
    assert.match(readFileSync(join(b.sortie, 'gel-presences-sample-1.txt'), 'utf8'), /processus introuvable/);
    assert.match(readFileSync(join(b.sortie, 'gel-presences-backboardd-sample-1.txt'), 'utf8'), /sample a échoué/);
    assert.ok(existsSync(join(b.sortie, 'gel-presences-ecran-1.txt')), 'capture en échec consignée');
  } finally { b.nettoyer(); }
});
