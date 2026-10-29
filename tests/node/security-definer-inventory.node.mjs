import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const migration = read('supabase/migrations/20260930090822_inventorier_corps_security_definer_expliques.sql');
const sqlTest = read('tests/security/security-definer-inventory-explicit.test.sql');
const sources = JSON.parse(read('recette/2026-09-30-inventaire-security/sources.json'));
const entries = JSON.parse(migration.split('$entries$')[1]);
const suppressionMigration = read('supabase/migrations/20261001131013_conserver_historique_financier_suppression_soignant.sql');
const suppressionSignature = 'fn_supprimer_mon_compte()';
const suppressionAvant = '71254d2065c67c11ce0460368f20d01f';
const suppressionApres = 'f3af23aeeb4e30aba07e422c0e819aeb';
const avoirsMigration = read('supabase/migrations/20261017191635_exclure_avoirs_des_impayes.sql');
const suppressionEtablissementSignature = 'fn_supprimer_mon_compte_etablissement()';
const suppressionEtablissementAvant = '8d1a6220cdc135d36d2d472fcde230ee';
const suppressionEtablissementApres = '35b630a12ed0f755592fdc431031b8cc';
const imputationMigration = read('supabase/migrations/20261018140952_imputer_avoirs_commission.sql');
const suppressionEtablissementImputation = 'a43978aee09ef1ae4a157dbee9911b2f';
const litigeSalarieSignature = 'fn_admin_resoudre_litige_salarie(uuid,text,text,numeric,numeric,text)';
const litigeSalarieAvant = '139ca12a3fcbff5bd5f65074d3242b53';
const litigeSalarieApres = 'f07f34e05904c5f7c233a9477b6cdd1c';
const internatMigration = read('supabase/migrations/20261029080849_internat_specialite_et_choix_etablissement.sql');
const rechercheSignature = 'fn_rechercher_soignants_etab(text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text,integer,integer)';
const rechercheAvant = '5a1fc4a4651f794ca8d95c3f6885195a';
const rechercheApres = '62d0bf39f1600b82a93a522a411f1bd7';
const successors = new Map([
  [suppressionSignature, { old_md5: suppressionAvant, definition_md5: suppressionApres }],
  [suppressionEtablissementSignature, { old_md5: suppressionEtablissementApres, definition_md5: suppressionEtablissementImputation }],
  [litigeSalarieSignature, { old_md5: litigeSalarieAvant, definition_md5: litigeSalarieApres }],
  [rechercheSignature, { old_md5: rechercheAvant, definition_md5: rechercheApres }],
]);
const replayEntries = entries.map(entry => successors.has(entry.signature)
  ? { ...entry, ...successors.get(entry.signature) }
  : entry);
const md5 = body => createHash('md5').update(body).digest('hex');

function sourceBody(sql, name) {
  const unquoted = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  const start = unquoted >= 0 ? unquoted : sql.indexOf(`CREATE OR REPLACE FUNCTION "public"."${name}"(`);
  assert.ok(start >= 0, `${name}: définition explicite absente`);
  const tail = sql.slice(start);
  const opening = /\bAS\s+(\$[a-zA-Z_0-9]*\$)/i.exec(tail);
  assert.ok(opening, `${name}: corps dollar-quoted absent`);
  const offset = opening.index + opening[0].length;
  const end = tail.indexOf(opening[1], offset);
  assert.ok(end >= 0);
  return tail.slice(offset, end);
}

test('onze fonctions explicites, aucune recapture des deux gardes non validées', () => {
  assert.equal(entries.length, 11);
  assert.equal(new Set(entries.map(e => e.signature)).size, 11);
  assert.deepEqual(entries.map(e => e.signature).sort(), sources.map(e => e.signature).sort());
  assert.ok(entries.every(e => !/fn_terminer_mission|fn_admin_resoudre_litige_intelligent/.test(e.signature)));
  assert.equal(entries.filter(e => e.old_md5 === null).length, 2);
  assert.deepEqual(entries.filter(e => e.anon_execute).map(e => e.signature), ['fn_missions_publiques_recherche(text,text)']);
});

for (const source of sources) {
  test(`empreinte issue du corps source : ${source.signature}`, () => {
    assert.equal(source.sources.length, 1);
    const body = sourceBody(read(source.sources[0].path), source.signature.split('(')[0]);
    assert.equal(md5(body), source.definition_md5);
    assert.equal(entries.find(e => e.signature === source.signature).definition_md5, source.definition_md5);
    assert.notEqual(md5(`${body} `), source.definition_md5, 'même une dérive blanche change le verrou');
  });
}

test('aucun DDL, GRANT, recapture globale ou écriture hors inventaire', () => {
  const skeleton = migration.replace(/--[^\n]*/g, '').replace(/\$entries\$[\s\S]*?\$entries\$/g, "'manifest'");
  assert.doesNotMatch(skeleton, /\b(?:CREATE|ALTER|DROP|GRANT|REVOKE|TRUNCATE|DELETE|EXECUTE)\s+(?:FUNCTION|TABLE|ON|FROM|INTO|public\.)/i);
  assert.deepEqual([...skeleton.matchAll(/INSERT\s+INTO\s+([\w.]+)/gi)].map(m => m[1]), ['private.security_definer_inventory']);
  assert.match(skeleton, /md5\(p\.prosrc\) IS DISTINCT FROM r\.definition_md5/);
  assert.match(skeleton, /p\.proconfig IS DISTINCT FROM r\.proconfig/);
  assert.match(skeleton, /a\.grantee = 0 AND a\.privilege_type = 'EXECUTE'/);
  assert.match(skeleton, /definition_md5 = excluded\.definition_md5/);
  assert.ok(skeleton.indexOf('END LOOP;') < skeleton.indexOf('INSERT INTO'));
});

test('le successeur suppression soignant vérifié remplace le corps historique après migration', () => {
  const historical = entries.find(entry => entry.signature === suppressionSignature);
  assert.equal(historical.definition_md5, suppressionAvant);
  assert.equal(md5(sourceBody(read('supabase/migrations/20260925150546_suppression_compte_preuve_privee.sql'), 'fn_supprimer_mon_compte')), suppressionAvant);
  assert.equal(md5(sourceBody(suppressionMigration, 'fn_supprimer_mon_compte')), suppressionApres);
  assert.equal(md5(sourceBody(read('supabase/schema/public.sql'), 'fn_supprimer_mon_compte')), suppressionApres);
  assert.ok(suppressionMigration.includes(`('${suppressionSignature}', '${suppressionAvant}', '${suppressionApres}'`));
  assert.equal(replayEntries.find(entry => entry.signature === suppressionSignature).definition_md5, suppressionApres);
});

test('le successeur avoirs lie exactement les corps suppression établissement avant et après', () => {
  const historical = entries.find(entry => entry.signature === suppressionEtablissementSignature);
  const source = sources.find(entry => entry.signature === suppressionEtablissementSignature);
  assert.equal(historical.definition_md5, suppressionEtablissementAvant);
  assert.equal(md5(sourceBody(read(source.sources[0].path), 'fn_supprimer_mon_compte_etablissement')), suppressionEtablissementAvant);
  assert.equal(md5(sourceBody(avoirsMigration, 'fn_supprimer_mon_compte_etablissement')), suppressionEtablissementApres);
  assert.ok(avoirsMigration.includes(`('${suppressionEtablissementSignature}', '${suppressionEtablissementAvant}', '${suppressionEtablissementApres}'`));
});

test('imputation : la chaîne suppression établissement conserve le prédécesseur PR1071', () => {
  const name = 'fn_supprimer_mon_compte_etablissement';
  assert.equal(md5(sourceBody(avoirsMigration, name)), suppressionEtablissementApres);
  assert.ok(imputationMigration.includes(`('public.${suppressionEtablissementSignature}','${suppressionEtablissementApres}','${suppressionEtablissementImputation}'`));
  assert.equal(md5(sourceBody(imputationMigration, name)), suppressionEtablissementImputation);
  assert.equal(md5(sourceBody(read('supabase/schema/public.sql'), name)), suppressionEtablissementImputation);
  assert.deepEqual(successors.get(suppressionEtablissementSignature), {
    old_md5: suppressionEtablissementApres, definition_md5: suppressionEtablissementImputation,
  });
});

test('imputation : le successeur litige salarié reste lié à sa preuve historique', () => {
  const historical = entries.find(entry => entry.signature === litigeSalarieSignature);
  const source = sources.find(entry => entry.signature === litigeSalarieSignature);
  const name = 'fn_admin_resoudre_litige_salarie';
  assert.equal(historical.definition_md5, litigeSalarieAvant);
  assert.equal(md5(sourceBody(read(source.sources[0].path), name)), litigeSalarieAvant);
  assert.ok(imputationMigration.includes(`('public.${litigeSalarieSignature}','${litigeSalarieAvant}','${litigeSalarieApres}'`));
  assert.equal(md5(sourceBody(imputationMigration, name)), litigeSalarieApres);
  assert.equal(md5(sourceBody(read('supabase/schema/public.sql'), name)), litigeSalarieApres);
});

test('la projection internat reste liée au corps LIVE de recherche et à son successeur exact', () => {
  const name = 'fn_rechercher_soignants_etab';
  const live = JSON.parse(read('tests/fixtures/internat-live-full-closure-20261029.json')).routines
    .find(row => row.signature === rechercheSignature);
  assert.equal(entries.find(entry => entry.signature === rechercheSignature).definition_md5, rechercheAvant);
  assert.equal(md5(sourceBody(live.definition, name)), rechercheAvant);
  assert.equal(md5(sourceBody(internatMigration, name)), rechercheApres);
  assert.ok(internatMigration.includes(`oid='public.${rechercheSignature}'::regprocedure`));
});

test('seuls les quatre successeurs explicites changent le manifeste historique', () => {
  assert.deepEqual([...successors.keys()].sort(), [suppressionSignature, suppressionEtablissementSignature, litigeSalarieSignature, rechercheSignature].sort());
  assert.deepEqual(replayEntries.filter(entry => !successors.has(entry.signature)), entries.filter(entry => !successors.has(entry.signature)));
  for (const entry of entries.filter(entry => successors.has(entry.signature))) {
    assert.deepEqual(replayEntries.find(replayed => replayed.signature === entry.signature), {
      ...entry, ...successors.get(entry.signature),
    });
  }
});

test('le rejeu conserve exactement la logique historique et exige chaque corps courant explicite', () => {
  const body = migration.split('DO $inventory$')[1].split('$inventory$;')[0];
  const replay = sqlTest.split('AS $replay$\n')[1].split('$replay$;')[0];
  const historiqueSansManifeste = body.replace(/\$entries\$[\s\S]*?\$entries\$/, '$entries$MANIFESTE$entries$');
  const rejeuSansManifeste = replay.replace(/\$entries\$[\s\S]*?\$entries\$/, '$entries$MANIFESTE$entries$');
  assert.equal(rejeuSansManifeste, historiqueSansManifeste);
  assert.deepEqual(JSON.parse(sqlTest.split('$entries$')[1]), replayEntries);
  assert.deepEqual(JSON.parse(sqlTest.split('$expected$')[1]), replayEntries);
  assert.match(sqlTest, /SET definition_md5 = repeat\('0',32\)/);
  assert.match(sqlTest, /ROLLBACK;\s*$/);
  const workflow = read('.github/workflows/validate-pr.yml');
  assert.ok(workflow.includes('tests/security/security-definer-inventory-explicit.test.sql'));
  assert.ok(workflow.includes('node --test tests/node/security-definer-inventory.node.mjs'));
});
