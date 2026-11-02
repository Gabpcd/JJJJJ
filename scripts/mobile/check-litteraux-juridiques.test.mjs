// Test de la garde `check-litteraux-juridiques.mjs` (lot 5, tranche T0, LOT5_PLAN §2.9) : cas
// négatifs (chaque famille de valeur interdite rougit), exceptions exactes (TextesWeb.swift,
// RPCResponse.marqueurCodeDuTravail), commentaires et cibles de test ignorés, dépôt conforme.
// Exécuté par le job « Cœur » de ios-swift-ci.yml : `node --test scripts/mobile/check-litteraux-juridiques.test.mjs`.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import {
  EXCEPTIONS,
  ROOT,
  SCHEMA,
  estLivre,
  fautesLitteraux,
  litterauxSwift,
  main,
  migrationsMatrice,
  valeursInterdites,
} from './check-litteraux-juridiques.mjs';

const schemaSource = readFileSync(join(ROOT, SCHEMA), 'utf8');
const interdits = valeursInterdites({ schemaSource, migrations: migrationsMatrice(ROOT) });
const SOURCE = 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Etablissement/Exemple.swift';
const fautes = (contenu, chemin = SOURCE) => fautesLitteraux({ fichiers: [{ chemin, contenu }], interdits });

test('valeurs lues dans le dump et dans les migrations de la matrice, pas dans une liste du script', () => {
  // CHECK de matrice_modes_exercice (public.sql) : catégories, niveaux, forces de source.
  for (const v of ['cabinet_liberal', 'prive', 'centre_sante', 'public', 'AUTORISE', 'NON_PROPOSE', 'BLOQUE',
    'JUGE', 'DOCTRINE', 'LEGAL', 'CONFORMITE_JOLENE']) {
    assert.ok(interdits.exactes.includes(v), `valeur CHECK ${v} absente`);
  }
  assert.equal(interdits.exactes.length, 11);
  // Toutes les migrations qui écrivent la matrice (corrections de sources comprises).
  const migrations = migrationsMatrice(ROOT).map(m => m.chemin);
  for (const m of ['20260712160000', '20260712161000', '20260712163000', '20260713164844', '20260714053000', '20260803190000']) {
    assert.ok(migrations.some(c => c.includes(m)), `migration ${m} non lue`);
  }
  const urls = interdits.sousChaines.filter(s => s.startsWith('https://'));
  for (const url of [
    'https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546',
    'https://www.fehap.fr/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf',
    'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000033621093',
    'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000047567923',
  ]) assert.ok(urls.includes(url), `source_url ${url} absente`);
  for (const libelle of [
    "L'exercice libéral n'est pas ouvert aux aides-soignants (Conseil d'État, 11/02/2025, n°491128). Mission proposée en salarié.",
    "Au sein d'un centre de santé, les professionnels sont salariés (art. L.6323-1-5 du code de la santé publique).",
    "Jolene propose cette mission en salarié : l'exercice libéral au sein d'un établissement expose à une requalification.",
  ]) assert.ok(interdits.sousChaines.includes(libelle), `source_libelle absent : ${libelle}`);
  // Les littéraux courts d'un WHERE ou d'un unnest(ARRAY[...]) ne sont pas des libellés.
  for (const bruit of ['%L.6323-1-5%', 'AS', 'IBODE', 'MANIPULATEUR_RADIO']) assert.ok(!interdits.sousChaines.includes(bruit), bruit);
  for (const nom of ['fn_mode_exercice', 'matrice_modes_exercice', 'notations_missions', 'evaluations_publiees']) {
    assert.ok(interdits.sousChaines.includes(nom), `${nom} absent`);
  }
});

test('chaque famille interdite rougit dans un fichier Swift livré', () => {
  assert.equal(fautes('let n = "BLOQUE"').length, 1, 'valeur CHECK exacte');
  assert.equal(fautes('let s = "public"').length, 1, 'valeur CHECK courte exacte');
  assert.equal(fautes('let u = "https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546"').length, 1, 'source_url');
  assert.equal(fautes('let t = "Note : Au sein d\'un centre de santé, les professionnels sont salariés (art. L.6323-1-5 du code de la santé publique). Fin"').length, 1, 'source_libelle contenu');
  assert.equal(fautes('let f = "fn_mode_exercice"').length, 1, 'fonction de la matrice');
  assert.equal(fautes('let t = "evaluations_publiees"').length, 1, 'vue des évaluations');
  assert.equal(fautes('let x = "Maximum légal : Code du travail"').length, 1, 'Code du travail');
  assert.equal(fautes('let x = "[CODE DU TRAVAIL] refus"').length, 1, 'Code du travail, casse ignorée');
  assert.equal(fautes('let x = "voir Légifrance"').length, 1, 'Légifrance');
  assert.equal(fautes('let x = "48 h (Art. L3121-20)"').length, 1, 'art. suivi d un numéro');
  assert.equal(fautes('let x = "CGV art. 8"').length, 1, 'art. 8');
  assert.equal(fautes('let m = """\n  Repos 11 h, article 3\n  """').length, 1, 'chaîne multiligne');
  assert.equal(fautes('let r = #"Code du travail"#').length, 1, 'chaîne brute');
  assert.match(fautes('let n = "BLOQUE"')[0], /Exemple\.swift:1/);
});

test('aucune fausse alerte : sous-chaîne d une valeur courte, commentaires, cibles de test', () => {
  assert.deepEqual(fautes('let c = "est_secteur_public"'), [], 'valeur courte : égalité exacte seulement');
  assert.deepEqual(fautes('let c = "BLOQUE_AUTO"'), []);
  assert.deepEqual(fautes('let r = "fn_creer_notation_mission"'), [], 'notation_mission ≠ notations_missions');
  assert.deepEqual(fautes('// "Code du travail" en commentaire\nlet x = 1 // art. 8'), []);
  assert.deepEqual(fautes('/* "BLOQUE"\n /* imbriqué */ "Légifrance" */\nlet y = 2'), []);
  assert.deepEqual(fautes('/// Doc : `[CODE DU TRAVAIL]`, art. L.1242-12\nlet z = "départ 2"'), []);
  const test = 'ios-native/Packages/JoleneSupabase/Tests/JoleneSupabaseTests/RPCResponseTests.swift';
  assert.equal(estLivre(test), false);
  assert.equal(estLivre('ios-native/JoleneUITests/DemoEtabTests.swift'), false);
  assert.equal(estLivre('ios-native/Jolene/Screens/RootView.swift'), true);
  assert.equal(estLivre(SOURCE), true);
  assert.deepEqual(fautes('let x = "[CODE DU TRAVAIL] Art. L3121-20"', test), []);
});

test('exceptions exactes : TextesWeb.swift (TL du lot 2) et RPCResponse.marqueurCodeDuTravail (lot 1)', () => {
  assert.deepEqual(EXCEPTIONS.map(e => e.fichier), [
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Legal/TextesWeb.swift',
    'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/RPC/RPCResponse.swift',
  ]);
  assert.deepEqual(fautes('public static let x = "Conforme art. 1366-1367 Code civil."', EXCEPTIONS[0].fichier), []);
  const rpc = EXCEPTIONS[1].fichier;
  assert.deepEqual(fautes('    public static let marqueurCodeDuTravail = "[CODE DU TRAVAIL]"', rpc), []);
  // L'exception vaut pour cette constante seulement, pas pour tout le fichier.
  assert.equal(fautes('    static let autre = "[CODE DU TRAVAIL]"', rpc).length, 1);
  assert.equal(fautes('    public static let marqueurCodeDuTravail = "[CODE DU TRAVAIL] art. 8"', rpc).length, 1);
});

test('lecteur de littéraux Swift : échappements, interpolation, lignes', () => {
  assert.deepEqual(litterauxSwift('let a = "x\\"y"; let b = "z"'), [{ valeur: 'x"y', ligne: 1 }, { valeur: 'z', ligne: 1 }]);
  assert.deepEqual(litterauxSwift('let a = "n \\(f("art. 9")) m"').map(l => l.ligne), [1]);
  assert.ok(litterauxSwift('let a = "n \\(f("art. 9")) m"')[0].valeur.includes('art. 9'));
  assert.deepEqual(litterauxSwift('\n\nlet m = """\nA\nB\n"""').map(l => [l.valeur.trim(), l.ligne]), [['A\nB', 3]]);
});

test('dépôt conforme : aucun littéral juridique dans le Swift livré', () => {
  assert.equal(main([]), 0);
});
