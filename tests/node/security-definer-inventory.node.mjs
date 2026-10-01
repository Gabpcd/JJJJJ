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
const replayEntries = entries.map(entry => entry.signature === suppressionSignature
  ? { ...entry, old_md5: suppressionAvant, definition_md5: suppressionApres }
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

test('seul le successeur suppression vérifié remplace le corps historique après migration', () => {
  const historical = entries.find(entry => entry.signature === suppressionSignature);
  assert.equal(historical.definition_md5, suppressionAvant);
  assert.equal(md5(sourceBody(read('supabase/migrations/20260925150546_suppression_compte_preuve_privee.sql'), 'fn_supprimer_mon_compte')), suppressionAvant);
  assert.equal(md5(sourceBody(suppressionMigration, 'fn_supprimer_mon_compte')), suppressionApres);
  assert.equal(md5(sourceBody(read('supabase/schema/public.sql'), 'fn_supprimer_mon_compte')), suppressionApres);
  assert.ok(suppressionMigration.includes(`('${suppressionSignature}', '${suppressionAvant}', '${suppressionApres}'`));
  assert.deepEqual(replayEntries.filter(entry => entry.signature !== suppressionSignature), entries.filter(entry => entry.signature !== suppressionSignature));
  assert.equal(replayEntries.find(entry => entry.signature === suppressionSignature).definition_md5, suppressionApres);
});

test('le rejeu conserve exactement la logique historique et exige le seul corps courant', () => {
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
