import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// ---------------------------------------------------------------------------------------------
// Garde du lot 2, tranche T5a : aucune lecture des notes côté natif.
//
// Sources de la règle : `docs/mobile-swift/LOT2_PLAN.md` §5 (ligne de risque « Notation : lecture de
// `notations_missions` qui contournerait le double-aveugle » → « garde : aucun littéral `notations_missions`
// dans `ios-native/` ») et CLAUDE.md, « Publication différée = filtre de visibilité CENTRALISÉ » (un test-garde à
// chaque nouvelle surface ; source canonique : la vue `evaluations_publiees`). Le natif n'écrit qu'une note
// (`fn_creer_notation_mission`) et ne lit jamais une note, publiée ou non (DECISIONS_LOT2.md, « Décisions
// déléguées du 8 novembre 2026 », T5a). Une future lecture des notes reçues passera par une décision et un contrat
// RPC dédiés : cette garde rougit d'abord.
//
// Ce qui rougit, dans tout fichier `.swift` de `ios-native/` (sources, tests, tests UI ; hors `.build`, `DerivedData`
// et dossiers cachés) : un littéral de chaîne qui contient `notations_missions` ou `evaluations_publiees` (chaîne
// simple, multiligne, brute `#"…"#`, interpolation comprise), le même mot écrit en dehors d'une chaîne (identifiant,
// attribut), et tout `from("notations…")` (lecture PostgREST d'une table dont le nom commence par `notations`).
//
// Exclusions, explicites et commentées :
//   1. les commentaires (`//`, `///`, `/* … */` imbriqués) sont IGNORÉS : ils documentent la règle et ne peuvent
//      émettre aucune requête (Lot2Ports.swift, NotationModel.swift, SupabaseNotationGateway.swift, NotationSheet.swift
//      citent la table pour dire qu'elle n'est jamais lue) ;
//   2. les assertions négatives de test listées dans `EXCLUSIONS` (fichier sous `/Tests/`, extrait exact de la ligne,
//      raison) : chacune doit être trouvée exactement une fois, sinon la garde rougit (une exclusion périmée ne
//      couvre jamais une nouvelle ligne).
// Un fichier dont le découpage échoue (chaîne ou commentaire non fermé) fait rougir la garde : jamais un fichier
// ignoré en silence.
// ---------------------------------------------------------------------------------------------

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const IOS = join(root, 'ios-native');

/** Exclusions de test : assertions qui prouvent qu'AUCUNE requête ne vise la table. */
export const EXCLUSIONS = [
  {
    fichier: 'ios-native/Packages/JoleneSupabase/Tests/JoleneSupabaseTests/SupabaseNotationGatewayTests.swift',
    extrait: '!$0.path.contains("notations_missions")',
    raison: 'assertion négative : aucune requête de la gateway de notation ne vise `notations_missions` (écriture seule)',
  },
];

/** Motifs interdits dans le code Swift sans commentaires (chaînes conservées telles quelles). */
const MOTIFS = [
  { nom: 'notations_missions', re: /notations_missions/g },
  { nom: 'evaluations_publiees', re: /evaluations_publiees/g },
  { nom: 'from("notations…")', re: /\bfrom\s*\(\s*#*"{1,3}notations/g },
];

/**
 * Découpe lexicale minimale du Swift : rend le texte où chaque commentaire est remplacé par des espaces (les sauts de
 * ligne sont conservés, les numéros de ligne restent exacts) et où chaque chaîne est conservée telle quelle. Gère les
 * commentaires imbriqués, les chaînes simples, multilignes (`"""`), brutes (`#"…"#`, `##"…"##`) et les interpolations
 * `\( … )` (qui peuvent contenir d'autres chaînes et des parenthèses). Lève une erreur sur une chaîne ou un commentaire
 * non fermé.
 */
export function sansCommentaires(src) {
  let i = 0;
  let out = '';
  const n = src.length;
  const blanc = (texte) => texte.replace(/[^\n]/g, ' ');

  function commentaireBloc() {
    const debut = i;
    let profondeur = 0;
    while (i < n) {
      if (src.startsWith('/*', i)) { profondeur += 1; i += 2; continue; }
      if (src.startsWith('*/', i)) { profondeur -= 1; i += 2; if (profondeur === 0) break; continue; }
      i += 1;
    }
    if (profondeur !== 0) throw new Error(`commentaire /* non fermé (position ${debut})`);
    out += blanc(src.slice(debut, i));
  }

  function chaine() {
    const debut = i;
    let dieses = 0;
    while (src[i] === '#') { dieses += 1; i += 1; }
    const multiligne = src.startsWith('"""', i);
    i += multiligne ? 3 : 1;
    const fin = (multiligne ? '"""' : '"') + '#'.repeat(dieses);
    const echappement = '\\' + '#'.repeat(dieses);
    out += src.slice(debut, i);
    while (i < n) {
      if (src.startsWith(fin, i)) { out += fin; i += fin.length; return; }
      if (src.startsWith(echappement, i)) {
        out += echappement;
        i += echappement.length;
        if (src[i] === '(') { out += '('; i += 1; code(true); out += ')'; i += 1; continue; }
        out += src[i] ?? '';
        i += 1;
        continue;
      }
      if (!multiligne && src[i] === '\n') throw new Error(`chaîne non fermée en fin de ligne (position ${debut})`);
      out += src[i];
      i += 1;
    }
    throw new Error(`chaîne non fermée (position ${debut})`);
  }

  // Code jusqu'à la parenthèse fermante de l'interpolation (`interpolation`) ou jusqu'à la fin du fichier.
  function code(interpolation) {
    let profondeur = 0;
    while (i < n) {
      const c = src[i];
      if (src.startsWith('//', i)) {
        const fin = src.indexOf('\n', i);
        const stop = fin < 0 ? n : fin;
        out += blanc(src.slice(i, stop));
        i = stop;
        continue;
      }
      if (src.startsWith('/*', i)) { commentaireBloc(); continue; }
      if (c === '"' || (c === '#' && /^#+"/.test(src.slice(i, i + 8)))) { chaine(); continue; }
      if (interpolation) {
        if (c === '(') profondeur += 1;
        if (c === ')') {
          if (profondeur === 0) return;
          profondeur -= 1;
        }
      }
      out += c;
      i += 1;
    }
    if (interpolation) throw new Error('interpolation \\( non fermée');
  }

  code(false);
  return out;
}

/** Fautes d'un fichier : `{ ligne, motif, texte }` (texte = ligne d'origine, commentaires compris). */
export function fautesLectureNotes(src) {
  const code = sansCommentaires(src);
  const lignes = src.split('\n');
  const fautes = [];
  for (const { nom, re } of MOTIFS) {
    for (const m of code.matchAll(re)) {
      const ligne = code.slice(0, m.index).split('\n').length;
      fautes.push({ ligne, motif: nom, texte: lignes[ligne - 1].trim() });
    }
  }
  return fautes.sort((a, b) => a.ligne - b.ligne || a.motif.localeCompare(b.motif));
}

/** Fichiers `.swift` sous un dossier, hors `.build`, `DerivedData` et dossiers cachés. */
function swiftFiles(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    if (name === '.build' || name === 'DerivedData' || name.startsWith('.')) continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...swiftFiles(full));
    else if (name.endsWith('.swift')) out.push(full);
  }
  return out;
}

/** Fautes de tout `ios-native/`, exclusions appliquées ; rend aussi l'usage de chaque exclusion. */
export function auditer(fichiers) {
  const fautes = [];
  const usages = new Map(EXCLUSIONS.map(e => [e, 0]));
  for (const file of fichiers) {
    const rel = relative(root, file).split('\\').join('/');
    let trouvees;
    try {
      trouvees = fautesLectureNotes(readFileSync(file, 'utf8'));
    } catch (erreur) {
      fautes.push(`${rel} : découpage impossible (${erreur.message}) — la garde ne peut pas prouver l'absence de lecture`);
      continue;
    }
    for (const f of trouvees) {
      const exclusion = EXCLUSIONS.find(e => e.fichier === rel && f.texte.includes(e.extrait));
      if (exclusion) { usages.set(exclusion, usages.get(exclusion) + 1); continue; }
      fautes.push(`${rel}:${f.ligne} : ${f.motif} — ${f.texte}`);
    }
  }
  return { fautes, usages };
}

// --- Le découpage : chaque forme de chaîne est vue, chaque commentaire ignoré --------------------------------------

test('découpage : commentaires ignorés, numéros de ligne conservés', () => {
  const src = [
    '/// Aucune lecture de `notations_missions` (filtre `evaluations_publiees`).',
    'let a = 1 // notations_missions',
    '/* bloc /* imbriqué notations_missions */ toujours commentaire evaluations_publiees */',
    'let url = "https://jolene.app/x" // from("notations_missions")',
  ].join('\n');
  assert.deepEqual(fautesLectureNotes(src), []);
  assert.equal(sansCommentaires(src).split('\n').length, 4);
  assert.ok(sansCommentaires(src).includes('"https://jolene.app/x"'), 'une URL dans une chaîne n est pas un commentaire');
});

test('découpage : chaque forme de littéral est une faute, à la bonne ligne', () => {
  const cas = [
    ['let t = "notations_missions"', 'notations_missions'],
    ['let t = #"evaluations_publiees"#', 'evaluations_publiees'],
    ['let t = ##"a "#" notations_missions"##', 'notations_missions'],
    ['let t = """\nselect * from notations_missions\n"""', 'notations_missions'],
    ['let t = "\\(cond ? "evaluations_publiees" : "x")"', 'evaluations_publiees'],
    ['let notations_missions = 1', 'notations_missions'],
    ['client.from("notations")', 'from("notations…")'],
    ['client.from( "notations_v2" ).select()', 'from("notations…")'],
  ];
  for (const [src, motif] of cas) {
    const fautes = fautesLectureNotes(`import Foundation\n${src}\n`);
    assert.ok(fautes.some(f => f.motif === motif && f.ligne >= 2), `non détecté : ${src} → ${JSON.stringify(fautes)}`);
  }
  // Une interpolation qui contient une URL ne fait pas d'un `//` un commentaire.
  assert.equal(fautesLectureNotes('let u = "\\(f("http://x"))"; let t = "notations_missions"').length, 1);
});

test('découpage : chaîne ou commentaire non fermé → erreur (jamais un fichier ignoré en silence)', () => {
  assert.throws(() => sansCommentaires('let t = "ouverte\nlet u = 1'), /chaîne non fermée/);
  assert.throws(() => sansCommentaires('/* jamais fermé'), /commentaire/);
  assert.throws(() => sansCommentaires('let t = """\nsans fin'), /chaîne non fermée/);
});

// --- La garde sur le dépôt -----------------------------------------------------------------------------------------

test('ios-native : aucun littéral notations_missions / evaluations_publiees / from("notations…") (double-aveugle)', () => {
  const fichiers = swiftFiles(IOS);
  assert.ok(fichiers.length > 100, `ios-native : ${fichiers.length} fichiers Swift seulement`);
  const { fautes, usages } = auditer(fichiers);
  assert.deepEqual(fautes, [], 'lecture de note côté natif : interdite (CLAUDE.md « Publication différée », LOT2_PLAN §5)');
  for (const [exclusion, nombre] of usages) {
    assert.ok(exclusion.fichier.includes('/Tests/'), `exclusion hors des tests : ${exclusion.fichier}`);
    assert.ok(exclusion.raison.length > 20, `exclusion sans raison : ${exclusion.extrait}`);
    assert.equal(nombre, 1, `exclusion périmée ou trop large (${nombre} usage(s)) : ${exclusion.fichier} « ${exclusion.extrait} »`);
  }
});

test('mutation : un from("notations_missions") ajouté à la gateway de notation fait rougir la garde', () => {
  const gateway = join(IOS, 'Packages/JoleneSupabase/Sources/JoleneSupabase/Pointage/SupabaseNotationGateway.swift');
  const src = readFileSync(gateway, 'utf8');
  assert.deepEqual(fautesLectureNotes(src), [], 'la gateway d origine ne lit aucune note');
  const mutee = `${src}\nfunc lireNotes(client: SupabaseClient) async throws { _ = try await client.from("notations_missions").select().execute() }\n`;
  const fautes = fautesLectureNotes(mutee);
  assert.deepEqual(fautes.map(f => f.motif).sort(), ['from("notations…")', 'notations_missions']);
  // Même mutation dans un test, hors exclusion : rouge aussi.
  const test = join(IOS, 'Packages/JoleneSupabase/Tests/JoleneSupabaseTests/SupabaseNotationGatewayTests.swift');
  assert.equal(fautesLectureNotes(`${readFileSync(test, 'utf8')}\nlet table = "evaluations_publiees"\n`)
    .filter(f => f.motif === 'evaluations_publiees').length, 1);
});

test('validate-pr : la garde tourne dans « Garde de livraison mobile » et est consignée dans DECISIONS_LOT2', () => {
  const workflow = readFileSync(join(root, '.github/workflows/validate-pr.yml'), 'utf8');
  const etape = workflow.split('- name: ').find(bloc => bloc.startsWith('Garde de livraison mobile'));
  assert.ok(etape, 'étape « Garde de livraison mobile » absente');
  assert.ok(etape.includes('tests/node/lecture-notes-ios.node.mjs'), 'garde non lancée par validate-pr');
  const decisions = readFileSync(join(root, 'docs/mobile-swift/DECISIONS_LOT2.md'), 'utf8');
  assert.ok(decisions.includes('`tests/node/lecture-notes-ios.node.mjs`'), 'garde non consignée dans DECISIONS_LOT2.md');
});
