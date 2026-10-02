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
  GITHUB_EVENT_NAME: 'pull_request', BASE_SHA: 'a'.repeat(40), GITHUB_SHA: 'b'.repeat(40), SOURCE_SHA: 'c'.repeat(40), GITHUB_RUN_ID: '36700000000', GITHUB_RUN_ATTEMPT: '1' };
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
    { STAGING_SUPABASE_ACCESS_TOKEN: '' }, { GITHUB_EVENT_NAME: 'push' }, { BASE_SHA: '' }, { GITHUB_SHA: codePrive }, { SOURCE_SHA: '' }, { SOURCE_SHA: codePrive }, { GITHUB_RUN_ATTEMPT: '0' }]) {
    const t = transport(entrees());
    await assert.rejects(executerPreuve({ ...env, ...extra }, t.options), error => { sansSecret(error.message); return true; });
    assert.equal(t.appels.length, 0);
  }
  assert.equal(contexte(env).projet, STAGING_REF);
  assert.equal(contexte(env).sha, env.SOURCE_SHA);
  assert.equal(contexte(env).eventSha, env.GITHUB_SHA);
  assert.notEqual(contexte(env).sha, contexte(env).eventSha);
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

function scopeAttendu(overrides = {}) {
  return { has_migrations: 'false', has_f1_regression: 'false',
    has_connect_fixture: 'false', has_contract_fixture: 'false', ...overrides };
}
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
function executeCondition(step, outputs, successful = true) {
  if (!step.if) return successful;
  // Une branche OR après un statut explicite doit être interprétée séparément.
  // Ce format est absent du workflow : le refuser plutôt que simuler sa priorité.
  assert.ok(!/^(always|success)\(\) && .* \|\| /.test(step.if), 'condition nouvelle non couverte');
  const status = step.if.startsWith('always() && ') || successful;
  const condition = step.if.replace(/^(always|success)\(\) && /, '');
  const terms = condition.split(' || ').map(group => group.split(' && ').map(term => {
    const match = /^steps\.migration_scope\.outputs\.(has_migrations|has_f1_regression|has_contract_fixture|has_connect_fixture) == '(true|false)'$/.exec(term);
    assert.ok(match, 'condition nouvelle non couverte');
    assert.ok(Object.hasOwn(outputs, match[1]), 'output manquant dans le scénario');
    return outputs[match[1]] === match[2];
  }).every(Boolean));
  return status && terms.some(Boolean);
}
test('le témoin contrôle le SHA de la révision réellement extraite, sans credentials Git persistants', () => {
  const checkout = sqlJob.steps.find(step => step.uses?.startsWith('actions/checkout@'));
  const witness = sqlJob.steps.find(step => step.run === 'node scripts/ci/connect-test-fixture-rollback.mjs');
  assert.equal(checkout.with.ref, '${{ github.event.pull_request.head.sha }}');
  assert.equal(witness.env.SOURCE_SHA, checkout.with.ref);
  assert.equal(checkout.with['persist-credentials'], false);
  assert.equal(checkout.with['fetch-depth'], 0);
  const draft = sqlJob.steps.find(step => step.run === 'node scripts/ci/contrat-v11-sql-proof.mjs');
  assert.equal(draft.env.SOURCE_SHA, checkout.with.ref);
});
test('vrai scope YAML : fixture seule active le runner sans bootstrap, CLI ni régressions migration', t => {
  const s = scopeReel(t, ['tests/fixtures/contrat-service-v11/draft.sql']);
  assert.equal(s.result.status, 0); assert.deepEqual(s.outputs, scopeAttendu({ has_contract_fixture: 'true' }));
  const actifs = sqlJob.steps.filter(step => executeCondition(step, s.outputs));
  assert.ok(actifs.some(step => step.run === 'node scripts/ci/contrat-v11-sql-proof.mjs'));
  assert.ok(!actifs.some(step => step.uses?.startsWith('supabase/') || /supabase (?:link|db push)|CREATE EXTENSION/.test(step.run || '')));
  assert.deepEqual(sqlJob.concurrency, { group: 'jolene-supabase-staging-writes', queue: 'max', 'cancel-in-progress': false });
});
test('scope YAML refuse le mélange fixture/migration avant réseau ; changements ordinaires inchangés', t => {
  const mix = scopeReel(t, ['tests/security/contrat-service-v11.test.sql', 'supabase/migrations/20260930000000_fixture.sql']);
  assert.notEqual(mix.result.status, 0);
  const normal = scopeReel(t, ['docs/fixture.md']);
  assert.equal(normal.result.status, 0); assert.deepEqual(normal.outputs, scopeAttendu());
  const migration = scopeReel(t, ['supabase/migrations/20260930000000_fixture.sql']);
  assert.equal(migration.result.status, 0); assert.deepEqual(migration.outputs, scopeAttendu({ has_migrations: 'true' }));
});
test('le harnais Node reste testé en CI sans déclencher une recette contrat distante', t => {
  const s = scopeReel(t, ['tests/node/contrat-v11-sql-proof.node.mjs']);
  assert.equal(s.result.status, 0);
  assert.deepEqual(s.outputs, scopeAttendu());
  const actifs = sqlJob.steps.filter(step => executeCondition(step, s.outputs));
  assert.ok(!actifs.some(step => step.run === 'node scripts/ci/contrat-v11-sql-proof.mjs'));
  assert.ok(workflow.jobs['typecheck-and-build'].steps.some(step => step.run === 'node --test tests/node/contrat-v11-sql-proof.node.mjs'));
});
test('chaque entrée du seed Connect active seulement sa preuve, sans bootstrap, candidate, F1 ni draft contrat', t => {
  for (const path of ['scripts/ci/connect-test-fixture.mjs', 'scripts/ci/connect-test-fixture-ci.mjs',
    'scripts/ci/connect-test-fixture-rollback.mjs', 'scripts/ci/connect-test-fixture-prepare.sql',
    'tests/node/connect-test-fixture.node.mjs', 'tests/node/connect-test-fixture-ci.node.mjs',
    'tests/node/connect-test-fixture-rollback.node.mjs']) {
    const s = scopeReel(t, [path]);
    assert.equal(s.result.status, 0, path);
    assert.deepEqual(s.outputs, scopeAttendu({ has_connect_fixture: 'true' }), path);
    const actifs = sqlJob.steps.filter(step => step.id !== 'migration_scope' && executeCondition(step, s.outputs));
    assert.ok(actifs.some(step => step.uses?.startsWith('actions/setup-node@')));
    assert.ok(actifs.some(step => step.run === 'node scripts/ci/connect-test-fixture-rollback.mjs'));
    assert.ok(actifs.some(step => step.with?.path === '${{ runner.temp }}/connect-test-fixture-rollback.json'));
    assert.ok(!actifs.some(step => step.uses?.startsWith('supabase/') || step.env?.HAS_MIGRATIONS ||
      /supabase (?:link|db push)|CREATE EXTENSION|contrat-v11-sql-proof|connect-staging-(?:admission-pg17|catalogue-proof)/.test(step.run || '')));
  }
  const horsScope = scopeReel(t, ['docs/connect-test-fixture-ci.md', 'scripts/ci/connect-test-fixture-ci.contract.json',
    'scripts/ci/prepare-staging-api-env.mjs', 'tests/node/fixture-ordinaire.node.mjs']);
  assert.equal(horsScope.result.status, 0); assert.deepEqual(horsScope.outputs, scopeAttendu());
});
test('le seed Connect reste indépendant du draft et conserve seulement son rapport après échec', () => {
  const seed = sqlJob.steps.find(step => step.run === 'node scripts/ci/connect-test-fixture-rollback.mjs');
  const seedArtifact = sqlJob.steps.find(step => step.with?.path === '${{ runner.temp }}/connect-test-fixture-rollback.json');
  const setup = sqlJob.steps.find(step => step.uses?.startsWith('actions/setup-node@'));
  for (const step of [seed, seedArtifact, setup]) assert.ok(step);
  for (const has_connect_fixture of ['true', 'false']) for (const has_contract_fixture of ['true', 'false'])
    for (const successful of [true, false]) {
      const outputs = scopeAttendu({ has_connect_fixture, has_contract_fixture });
      assert.equal(executeCondition(seed, outputs, successful), successful && has_connect_fixture === 'true');
      assert.equal(executeCondition(seedArtifact, outputs, successful), has_connect_fixture === 'true');
      assert.equal(executeCondition(setup, outputs, successful), successful &&
        [has_contract_fixture, has_connect_fixture].includes('true'));
    }
});
test('F1 active sa transaction et son contrôle indépendant, sans activer le draft contrat', t => {
  const s = scopeReel(t, ['tests/security/facturation-remplacement-commission-f1.test.sql']);
  assert.equal(s.result.status, 0);
  assert.deepEqual(s.outputs, scopeAttendu({ has_f1_regression: 'true' }));
  const actifs = sqlJob.steps.filter(step => executeCondition(step, s.outputs));
  assert.ok(actifs.some(step => step.env?.HAS_MIGRATIONS));
  assert.ok(actifs.some(step => step.name === 'F1 — SELECT indépendant après succès ou échec SQL'));
  assert.ok(!actifs.some(step => step.uses?.startsWith('supabase/') || step.run === 'node scripts/ci/contrat-v11-sql-proof.mjs'));
  const mix = scopeReel(t, ['tests/security/facturation-remplacement-commission-f1.test.sql', 'tests/fixtures/contrat-service-v11/draft.sql']);
  assert.notEqual(mix.result.status, 0);
  assert.match(mix.result.stderr + mix.result.stdout, /fixture contrat et la recette F1 doivent rester séparées/);
});
test('le chaînage heures F1 conserve la voie test-only, le contrôle indépendant et le refus du mélange contrat', t => {
  const s = scopeReel(t, ['tests/security/facturation-heures-ajustees-chainage-f1.test.sql']);
  assert.equal(s.result.status, 0);
  assert.deepEqual(s.outputs, scopeAttendu({ has_f1_regression: 'true' }));
  const actifs = sqlJob.steps.filter(step => executeCondition(step, s.outputs));
  assert.ok(actifs.some(step => step.env?.HAS_MIGRATIONS));
  assert.ok(actifs.some(step => step.name === 'F1 — SELECT indépendant après succès ou échec SQL'));
  assert.ok(!actifs.some(step => step.uses?.startsWith('supabase/') || /supabase (?:link|db push)|CREATE EXTENSION/.test(step.run || '') || step.run === 'node scripts/ci/contrat-v11-sql-proof.mjs'));
  const mix = scopeReel(t, ['tests/fixtures/facturation-heures-ajustees-f1/catalogue.sql', 'tests/fixtures/contrat-service-v11/draft.sql']);
  assert.notEqual(mix.result.status, 0);
  assert.match(mix.result.stderr + mix.result.stdout, /fixture contrat et la recette F1 doivent rester séparées/);
});
test('les conditions SQL non reconnues ne sont pas considérées actives par défaut', () => {
  for (const condition of ["success()", "steps.migration_scope.outputs.unknown == 'true'", "always() || true",
    "success() && steps.migration_scope.outputs.has_connect_fixture == 'true' || unknown()",
    "success() && steps.migration_scope.outputs.has_connect_fixture == 'true' || steps.migration_scope.outputs.has_connect_fixture == 'true'",
    "always() && steps.migration_scope.outputs.has_connect_fixture == 'false' || steps.migration_scope.outputs.has_connect_fixture == 'true'",
    "always() && steps.migration_scope.outputs.has_connect_fixture == 'false' && unknown()"])
    for (const successful of [true, false])
      assert.throws(() => executeCondition({ if: condition }, scopeAttendu(), successful), /condition nouvelle non couverte/);
  assert.throws(() => executeCondition({ if: "steps.migration_scope.outputs.has_connect_fixture == 'true'" }, {}), /output manquant/);
});

test('le témoin avant migration exige migration ET recette F1, jamais un seul des deux', t => {
  const step = sqlJob.steps.find(s => s.name === 'F1 — reproduction exacte avant la migration candidate');
  assert.ok(step);
  for (const has_migrations of ['true', 'false']) {
    for (const has_f1_regression of ['true', 'false']) {
      assert.equal(executeCondition(step, { has_migrations, has_f1_regression }),
        has_migrations === 'true' && has_f1_regression === 'true');
    }
  }
  const s = scopeReel(t, [
    'supabase/migrations/20261001102511_aligner_commissions_pieces_et_estimation.sql',
    'tests/security/facturation-heures-ajustees-chainage-f1.test.sql',
  ]);
  assert.equal(s.result.status, 0);
  assert.deepEqual(s.outputs, scopeAttendu({ has_migrations: 'true', has_f1_regression: 'true' }));
  assert.equal(executeCondition(step, s.outputs), true);
  for (const condition of ["steps.migration_scope.outputs.has_migrations == 'false' && unknown()",
    "steps.migration_scope.outputs.has_migrations == 'true' || unknown()"])
    assert.throws(() => executeCondition({ if: condition }, s.outputs), /condition nouvelle non couverte/);
});

test('double échec garde les deux catégories sans exposer la réponse fournisseur', async () => {
  const t = transport(entrees(), { 2: new Error(codePrive), 3: [] });
  await assert.rejects(executerPreuve(env, t.options), /catalogue_divergent/);
  assert.equal(t.appels.length, 3);
  assert.equal(t.rapports[0].erreur_transaction, 'transport_refuse');
  assert.equal(t.rapports[0].erreur_controle, 'catalogue_divergent');
  assert.equal(t.rapports[0].succes, false); sansSecret(t.rapports);
});
