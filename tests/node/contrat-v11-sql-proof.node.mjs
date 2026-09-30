import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join, dirname } from 'node:path';
import { test } from 'node:test';
import { parse } from 'yaml';
import { assembler, chargerEntrees, contexte, executerPreuve, STAGING_REF, DRAFT_SHA256 } from '../../scripts/ci/contrat-v11-sql-proof.mjs';
import { createHash } from 'node:crypto';

const root = resolve(import.meta.dirname, '../..');
const env = { STAGING_SUPABASE_PROJECT_REF: STAGING_REF, STAGING_SUPABASE_ACCESS_TOKEN: 'CANARI_JETON_prive',
  GITHUB_EVENT_NAME: 'pull_request', BASE_SHA: 'a'.repeat(40), GITHUB_SHA: 'b'.repeat(40), GITHUB_RUN_ID: '36700000000', GITHUB_RUN_ATTEMPT: '1' };
const preuve = [{ preuve: 'CONTRAT_V11_SQL_ROLLBACK', annule: true }];
const workflow = parse(readFileSync(join(root, '.github/workflows/validate-pr.yml'), 'utf8'));
const sqlJob = workflow.jobs['sql-transaction'];
const scope = sqlJob.steps.find(s => s.id === 'migration_scope').run;
const codePrive = 'CANARI_JETON_prive email@prive.invalid https://prive.invalid?jwt=CANARI';
const entrees = () => chargerEntrees();
function transport(entree, override = {}) {
  const appels = [], rapports = [];
  return { appels, rapports, options: { entrees: entree, conserver: r => rapports.push(structuredClone(r)), fetchImpl: async (url, options) => {
    appels.push({ url, options });
    const i = appels.length;
    if (override[i] instanceof Error) throw override[i];
    if (typeof override[i] === 'function') return override[i]();
    return { ok: true, json: async () => override[i] ?? (i === 2 ? preuve : [entree.attendu]) };
  } } };
}
function sansSecret(value) { assert.ok(!JSON.stringify(value).includes('CANARI')); assert.ok(!JSON.stringify(value).includes('prive.invalid')); }

test('destination et contexte refusés avant réseau, sans repli ni sortie sensible', async () => {
  for (const extra of [{ STAGING_SUPABASE_PROJECT_REF: 'flripxtsyegjshnhzjkz' }, { STAGING_SUPABASE_PROJECT_REF: '' },
    { STAGING_SUPABASE_ACCESS_TOKEN: '' }, { GITHUB_EVENT_NAME: 'push' }, { BASE_SHA: '' }, { GITHUB_SHA: codePrive }, { GITHUB_RUN_ATTEMPT: '0' }]) {
    const t = transport(entrees());
    await assert.rejects(executerPreuve({ ...env, ...extra }, t.options), error => { sansSecret(error.message); return true; });
    assert.equal(t.appels.length, 0);
  }
  assert.equal(contexte(env).projet, STAGING_REF);
});

test('assemblage : DDL exact dans savepoint, suite et garde répétée, aucune validation par COMMIT', () => {
  const e = entrees(), sql = assembler(e);
  assert.equal(createHash('sha256').update(e.draft).digest('hex'), DRAFT_SHA256);
  assert.ok(sql.startsWith('BEGIN;\n')); assert.ok(sql.endsWith('ROLLBACK;\n'));
  assert.ok(sql.indexOf(e.draft) > sql.indexOf('SAVEPOINT contrat_v11_draft;'));
  assert.ok(sql.indexOf(e.draft) < sql.indexOf('ROLLBACK TO SAVEPOINT contrat_v11_draft;'));
  assert.equal(sql.split(e.draft).length, 2);
  assert.equal(sql.split(e.catalogueSql.trim().replace(/;$/, '')).length, 3);
  assert.ok(!/^\s*COMMIT;/m.test(sql));
  for (const suite of [e.suite.replace('BEGIN;', ''), e.suite.replace('ROLLBACK;', 'COMMIT;'), e.suite.replace('DO $test$', 'COMMIT;\nDO $test$')]) {
    assert.throws(() => assembler({ ...e, suite }));
  }
  assert.throws(() => assembler({ ...e, draft: e.draft + '\n' }), /draft_altere/);
  assert.throws(() => assembler({ ...e, catalogueSql: 'WITH x AS (SELECT 1) DELETE FROM auth.users;' }), /catalogue_altere/);
  assert.throws(() => assembler({ ...e, attendu: {} }), /catalogue_altere/);
});

test('trois requêtes exactes : préflight, transaction annulée, lecture indépendante ; aucun Auth/CLI', async () => {
  const e = entrees(), t = transport(e), r = await executerPreuve(env, t.options);
  assert.equal(t.appels.length, 3); assert.equal(r.succes, true); assert.equal(r.sentinelle, true); assert.equal(r.controle_independant, true);
  assert.deepEqual(t.appels.map(x => JSON.parse(x.options.body).query), [e.catalogueSql, assembler(e), e.catalogueSql]);
  for (const a of t.appels) {
    assert.equal(a.url, `https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`);
    assert.equal(a.options.method, 'POST'); assert.equal(a.options.redirect, 'error'); assert.ok(a.options.signal instanceof AbortSignal);
    assert.deepEqual(Object.keys(a.options.headers).sort(), ['Authorization', 'Content-Type']);
  }
  sansSecret(r); assert.deepEqual(t.rapports, [r]);
});

test('catalogue/cron/résidu divergent : refus avant transaction', async () => {
  const e = entrees();
  for (const rows of [[], {}, [null], [{ ...e.attendu, crons_actifs: 1 }], [e.attendu, e.attendu], [{ error: codePrive }]]) {
    const t = transport(e, { 1: rows });
    await assert.rejects(executerPreuve(env, t.options), /catalogue_divergent/);
    assert.equal(t.appels.length, 1); assert.equal(t.rapports[0].transaction_tentee, false); sansSecret(t.rapports);
  }
  for (const divergent of [
    { ...e.attendu, collisions: { ...e.attendu.collisions, 'public.soignants': 1 } },
    { ...e.attendu, fonctions_md5: { ...e.attendu.fonctions_md5, 'auth.uid()': '0'.repeat(32) } },
    { ...e.attendu, foreign_keys_unvalidated: 1 }, { ...e.attendu, table_draft_absente: false },
  ]) {
    const t = transport(e, { 1: [divergent] });
    await assert.rejects(executerPreuve(env, t.options), /catalogue_divergent/);
    assert.equal(t.appels.length, 1);
  }
});

test('sentinelle strictement typée : refus reste rouge malgré vérification indépendante propre', async () => {
  const e = entrees();
  for (const rows of [[], {}, [{ preuve: 'CONTRAT_V11_SQL_ROLLBACK', annule: 'true' }],
    [{ preuve: 'CONTRAT_V11_SQL_ROLLBACK', annule: true, extra: 1 }], [...preuve, ...preuve], [{ error: codePrive }]]) {
    const t = transport(e, { 2: rows });
    await assert.rejects(executerPreuve(env, t.options), /sentinelle_invalide/);
    assert.equal(t.appels.length, 3); assert.equal(t.rapports[0].succes, false); assert.equal(t.rapports[0].controle_independant, true); sansSecret(t.rapports);
  }
});

test('erreur HTTP/JSON/timeout/redirect : aucune répétition POST, exception fournisseur jamais publiée', async () => {
  const e = entrees();
  for (const echec of [new Error(codePrive), () => ({ ok: false, json: async () => ({ error: codePrive }) }),
    () => ({ ok: true, json: async () => { throw new Error(codePrive); } })]) {
    const t = transport(e, { 2: echec });
    await assert.rejects(executerPreuve(env, t.options), error => { sansSecret(error.message); return true; });
    assert.equal(t.appels.length, 3); assert.equal(t.rapports[0].succes, false); assert.equal(t.rapports[0].controle_independant, true); sansSecret(t.rapports);
    assert.ok(t.rapports[0].erreur_transaction);
  }
});

test('contrôle indépendant divergent après sentinelle : aucun succès ni nettoyage compensatoire', async () => {
  const t = transport(entrees(), { 3: [] });
  await assert.rejects(executerPreuve(env, t.options), /catalogue_divergent/);
  assert.equal(t.appels.length, 3); assert.equal(t.rapports[0].sentinelle, true); assert.equal(t.rapports[0].succes, false);
});

function scopeReel(t, changes) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-contrat-v11-scope-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init', '-q'); git('config', 'user.name', 'Fixture'); git('config', 'user.email', 'fixture@example.invalid');
  writeFileSync(join(dir, 'base.txt'), 'base'); git('add', '.'); git('commit', '-qm', 'base'); const base = git('rev-parse', 'HEAD');
  for (const name of changes) { mkdirSync(dirname(join(dir, name)), { recursive: true }); writeFileSync(join(dir, name), 'fixture'); }
  git('add', '.'); git('commit', '-qm', 'test');
  const output = join(dir, 'output'); writeFileSync(output, '');
  const result = spawnSync('bash', ['-c', scope], { cwd: dir, env: { ...process.env, BASE_SHA: base, GITHUB_OUTPUT: output }, encoding: 'utf8' });
  return { result, outputs: Object.fromEntries(readFileSync(output, 'utf8').trim().split('\n').filter(Boolean).map(l => l.split('='))) };
}
function executeCondition(step, outputs) {
  if (!step.if) return true;
  const match = /^steps\.migration_scope\.outputs\.(\w+) == '(true|false)'$/.exec(step.if);
  assert.ok(match, 'condition nouvelle non couverte');
  return outputs[match[1]] === match[2];
}
test('vrai scope YAML : fixture seule active le runner sans bootstrap, CLI ni régressions migration', t => {
  const s = scopeReel(t, ['tests/fixtures/contrat-service-v11/draft.sql']);
  assert.equal(s.result.status, 0); assert.deepEqual(s.outputs, { has_migrations: 'false', has_contract_fixture: 'true' });
  const actifs = sqlJob.steps.filter(step => executeCondition(step, s.outputs));
  assert.ok(actifs.some(step => step.run === 'node scripts/ci/contrat-v11-sql-proof.mjs'));
  assert.ok(!actifs.some(step => step.uses?.startsWith('supabase/') || /supabase (?:link|db push)|CREATE EXTENSION/.test(step.run || '')));
  assert.deepEqual(sqlJob.concurrency, { group: 'jolene-supabase-staging-writes', 'cancel-in-progress': false });
});
test('scope YAML refuse le mélange fixture/migration avant réseau ; changements ordinaires inchangés', t => {
  const mix = scopeReel(t, ['tests/security/contrat-service-v11.test.sql', 'supabase/migrations/20260930000000_fixture.sql']);
  assert.notEqual(mix.result.status, 0);
  const normal = scopeReel(t, ['docs/fixture.md']);
  assert.equal(normal.result.status, 0); assert.deepEqual(normal.outputs, { has_migrations: 'false', has_contract_fixture: 'false' });
  const migration = scopeReel(t, ['supabase/migrations/20260930000000_fixture.sql']);
  assert.equal(migration.result.status, 0); assert.deepEqual(migration.outputs, { has_migrations: 'true', has_contract_fixture: 'false' });
});

test('double échec garde les deux catégories sans exposer la réponse fournisseur', async () => {
  const t = transport(entrees(), { 2: new Error(codePrive), 3: [] });
  await assert.rejects(executerPreuve(env, t.options), /catalogue_divergent/);
  assert.equal(t.appels.length, 3);
  assert.equal(t.rapports[0].erreur_transaction, 'transport_refuse');
  assert.equal(t.rapports[0].erreur_controle, 'catalogue_divergent');
  assert.equal(t.rapports[0].succes, false); sansSecret(t.rapports);
});
