#!/usr/bin/env node
/**
 * Groupes des tests simulateur du job « UI » de `.github/workflows/ios-swift-ci.yml`.
 *
 * Pourquoi (revue B8 de T5, 2e passe) : chaque XCUITest démo coûte un lancement, une connexion démo
 * et des défilements — de 79 à 222 s par test sur iPad paysage (run 41538145532, 10 XCUITest =
 * 1 280 s, étape à 23,4 min sur un délai de 30). Un seul job par format ne tient pas le lot 1, dont
 * chaque tranche ajoute des XCUITest : le job « UI » est donc une matrice format × groupe, chaque
 * groupe ayant sa propre étape `test-without-building` (délai 30 min) dans son propre job (60 min).
 *
 * Règles (« un gap connu reste verrouillé », CLAUDE.md) :
 *   - toute classe de `ios-native/JoleneUITests` qui déclare au moins un `func test…` est rangée dans
 *     exactement un groupe, ou dans `HORS_GROUPES` avec le workflow qui l'exécute ; sinon
 *     `--verifier` échoue (job « Cœur ») : une nouvelle classe ne peut pas être oubliée par la CI ;
 *   - les classes déjà prévues par `LOT1_PLAN.md` §2.1 sont rangées d'avance ; une classe prévue mais
 *     absente du dépôt n'est simplement pas sélectionnée (aucun `-only-testing` vers rien) ;
 *   - la liste `groupe:` de la matrice du workflow est identique à celle des groupes ci-dessous ;
 *   - le résumé du job exige que les cas exécutés soient exactement ceux du groupe (`--attendus`),
 *     tous réussis, et signale un groupe qui approche du délai de son étape (`JOLENE_UI_BUDGET_ALERTE_S`).
 *
 * Répartition (durées iPad paysage du run 41538145532, +T5) : `socle` ≈ 9 min, `accueil-explorer`
 * ≈ 15 min, `missions` ≈ 13 min ; T4b (`DemoFavorisTests`) et T9 (`DemoSessionTests`) y entrent
 * sans dépasser 20 min. Quand un groupe dépasse l'alerte, on le scinde ici et dans la matrice.
 *
 * Usage :
 *   node scripts/mobile/ui-test-groups.mjs --verifier
 *   node scripts/mobile/ui-test-groups.mjs --arguments <groupe>   # arguments xcodebuild, un par ligne
 *   node scripts/mobile/ui-test-groups.mjs --attendus <groupe>    # JSON { groupe, cibles, cas }
 */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const DOSSIER_UI = join(ROOT, 'ios-native', 'JoleneUITests');
export const WORKFLOW = join(ROOT, '.github', 'workflows', 'ios-swift-ci.yml');
const CIBLE_UI = 'JoleneUITests';

/** Groupes, dans l'ordre de la matrice. `cibles` : bundles de tests exécutés en entier. */
export const GROUPES = [
  {
    nom: 'socle',
    cibles: ['JoleneCoreTests', 'JoleneDesignTests'],
    classes: ['EnvironmentGuardTests', 'DemoConsultationTests', 'DemoCompteTests', 'DemoSessionTests', 'DemoLiensTests'],
  },
  {
    nom: 'accueil-explorer',
    cibles: [],
    classes: ['DemoAccueilTests', 'DemoExplorerTests', 'DemoFavorisTests'],
  },
  {
    nom: 'missions',
    cibles: [],
    classes: ['DemoMesMissionsTests', 'DemoCandidatureTests', 'DemoPresenceTests', 'DemoAnnulationTests'],
  },
];

/** Classes exécutées ailleurs (secrets, STAGING) : jamais dans `ios-swift-ci.yml`. */
export const HORS_GROUPES = {
  StagingConnexionTests: '.github/workflows/ios-swift-staging.yml (STAGING, environnement protégé)',
  StagingParcoursTests: '.github/workflows/ios-swift-lot1-staging.yml (T11, STAGING, environnement protégé)',
};

/**
 * Classes de tests déclarées dans les sources : `{ classe: [tests…] }`. Un `func test…()` appartient
 * à la dernière classe déclarée avant lui ; une classe sans test (socle `JoleneUITestCase`) est omise.
 */
export function classesDeTest(dossier = DOSSIER_UI) {
  const classes = {};
  for (const fichier of readdirSync(dossier).filter((nom) => nom.endsWith('.swift')).sort()) {
    const source = readFileSync(join(dossier, fichier), 'utf8');
    let courante = null;
    for (const ligne of source.split('\n')) {
      const declaration = ligne.match(/^\s*(?:@\w+\s+)*(?:(?:final|public|internal|open|private|fileprivate)\s+)*class\s+(\w+)\s*:\s*(\w+)/);
      if (declaration) {
        courante = declaration[1];
        continue;
      }
      const test = ligne.match(/^\s*(?:@\w+\s+)*func\s+(test\w*)\s*\(\s*\)/);
      if (test && courante) (classes[courante] ??= []).push(test[1]);
    }
  }
  return classes;
}

/** Noms de la ligne `groupe: [ … ]` de la matrice du workflow, ou `null`. */
export function groupesDeLaMatrice(workflow = WORKFLOW) {
  const ligne = readFileSync(workflow, 'utf8').match(/^\s*groupe:\s*\[([^\]]*)\]/m);
  return ligne ? ligne[1].split(',').map((nom) => nom.trim()).filter(Boolean) : null;
}

/** Erreurs de cohérence entre sources, groupes et matrice (vide si tout est rangé). */
export function verifier({ classes = classesDeTest(), matrice = groupesDeLaMatrice(), groupes = GROUPES } = {}) {
  const erreurs = [];
  const rangement = new Map();
  for (const groupe of groupes) {
    for (const classe of groupe.classes) {
      if (rangement.has(classe)) erreurs.push(`${classe} est rangée dans deux groupes (${rangement.get(classe)}, ${groupe.nom}).`);
      rangement.set(classe, groupe.nom);
    }
  }
  for (const classe of Object.keys(HORS_GROUPES)) {
    if (rangement.has(classe)) erreurs.push(`${classe} est à la fois hors groupes et dans le groupe ${rangement.get(classe)}.`);
  }
  for (const classe of Object.keys(classes)) {
    if (!rangement.has(classe) && !(classe in HORS_GROUPES)) {
      erreurs.push(`${classe} (${classes[classe].length} test(s)) n'est rangée dans aucun groupe : ajoutez-la à GROUPES de scripts/mobile/ui-test-groups.mjs (budget CI par groupe).`);
    }
  }
  for (const groupe of groupes) {
    if (groupe.cibles.length === 0 && !groupe.classes.some((classe) => classe in classes)) {
      erreurs.push(`Le groupe ${groupe.nom} n'exécuterait aucun test (aucune cible, aucune de ses classes n'existe).`);
    }
  }
  const noms = groupes.map((groupe) => groupe.nom);
  if (!matrice) {
    erreurs.push('Ligne « groupe: [ … ] » introuvable dans la matrice de .github/workflows/ios-swift-ci.yml.');
  } else if (matrice.join(',') !== noms.join(',')) {
    erreurs.push(`Matrice du workflow (${matrice.join(', ')}) différente des groupes du script (${noms.join(', ')}).`);
  }
  return erreurs;
}

function groupeNomme(nom, groupes = GROUPES) {
  const groupe = groupes.find((candidat) => candidat.nom === nom);
  if (!groupe) throw new Error(`Groupe inconnu : « ${nom ?? ''} » (attendu : ${groupes.map((g) => g.nom).join(', ')}).`);
  return groupe;
}

/** Cibles et cas `Classe/test` attendus pour un groupe (classes présentes dans les sources seulement). */
export function attendus(nom, classes = classesDeTest(), groupes = GROUPES) {
  const groupe = groupeNomme(nom, groupes);
  const presentes = groupe.classes.filter((classe) => classe in classes);
  return {
    groupe: groupe.nom,
    cibles: [...groupe.cibles],
    classes: presentes,
    cas: presentes.flatMap((classe) => classes[classe].map((test) => `${classe}/${test}`)),
  };
}

/** Arguments `-only-testing` de `xcodebuild test-without-building` pour un groupe. */
export function argumentsXcodebuild(nom, classes = classesDeTest(), groupes = GROUPES) {
  const { cibles, classes: presentes } = attendus(nom, classes, groupes);
  return [...cibles.map((cible) => `-only-testing:${cible}`), ...presentes.map((classe) => `-only-testing:${CIBLE_UI}/${classe}`)];
}

function main(argv) {
  const [option, valeur] = argv;
  if (option === '--verifier') {
    const classes = classesDeTest();
    const erreurs = verifier({ classes });
    if (erreurs.length) {
      for (const erreur of erreurs) console.error(`::error::${erreur}`);
      process.exit(1);
    }
    for (const groupe of GROUPES) {
      const { classes: presentes, cas } = attendus(groupe.nom, classes);
      const prevues = groupe.classes.filter((classe) => !presentes.includes(classe));
      console.log(`${groupe.nom} : ${[...groupe.cibles, ...presentes].join(', ')} — ${cas.length} XCUITest`
        + (prevues.length ? ` (prévues, absentes du dépôt : ${prevues.join(', ')})` : ''));
    }
    console.log(`Hors groupes : ${Object.keys(HORS_GROUPES).filter((classe) => classe in classes).join(', ') || 'aucune classe présente'}.`);
    return;
  }
  if (option === '--arguments') {
    const lignes = argumentsXcodebuild(valeur);
    if (!lignes.length) throw new Error(`Le groupe ${valeur} n'a aucun test à exécuter.`);
    process.stdout.write(`${lignes.join('\n')}\n`);
    return;
  }
  if (option === '--attendus') {
    process.stdout.write(`${JSON.stringify(attendus(valeur), null, 2)}\n`);
    return;
  }
  console.error('Usage : ui-test-groups.mjs --verifier | --arguments <groupe> | --attendus <groupe>');
  process.exit(2);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main(process.argv.slice(2));
  } catch (erreur) {
    console.error(`::error::${erreur.message}`);
    process.exit(1);
  }
}
