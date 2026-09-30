import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { parse } from 'yaml';
import { configurationPreuveD2, prouverD2 } from '../../scripts/ci/prove-candidatures-rollback.mjs';
import { catalogueD, sqlCatalogueD, STAGING_REF, STAGING_URL } from '../../scripts/ci/candidatures-fixture-contract.mjs';
import { sqlRecetteRollbackD } from '../../scripts/ci/generate-candidatures-rollback.mjs';

const now = Date.parse('2026-09-30T12:00:00Z');
const envValide = () => ({
  GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_REPOSITORY: 'Gabpcd/JJJJJ',
  GITHUB_RUN_ID: '123456', GITHUB_RUN_ATTEMPT: '2', GITHUB_SHA: 'a'.repeat(40),
  LOAD_D_SQL_ONLY: 'true', LOAD_D_SQL_JOUR: '2026-10-07',
  LOAD_TEST_SCENARIO: '04-candidatures-simultanees', DASHBOARD_FIXTURE_ONLY: 'false', DIAGNOSTIC_SQL: 'false',
  STAGING_SUPABASE_PROJECT_REF: STAGING_REF, STAGING_SUPABASE_URL: STAGING_URL,
  STAGING_SUPABASE_ACCESS_TOKEN: 'CANARI-TOKEN-MANAGEMENT',
});
const catalogue = () => [{ ...catalogueD, crons_actifs: 0, audit_fk: 0 }];
const sentinelle = () => [{ preuve: 'D2_SQL_ROLLBACK', annule: true }];
function banc({ env = envValide(), reponses = [catalogue(), sentinelle()], faute } = {}) {
  const appels = [];
  return { appels, run: () => prouverD2({ env, now, fetchImpl: async (url, options) => {
    appels.push({ url, options });
    const n = appels.length;
    if (faute?.appel === n && faute.type === 'timeout') throw new Error('CANARI-ERREUR-RESEAU');
    return { ok: !(faute?.appel === n && faute.type === 'http'), status: 500, json: async () => {
      if (faute?.appel === n && faute.type === 'json') throw new Error('CANARI-CORPS-JSON');
      return reponses[n - 1];
    } };
  } }) };
}

test('succès : seulement catalogue puis SQL exact, preuves filtrées et aucun autre endpoint', async () => {
  const b = banc(); const r = await b.run();
  assert.equal(b.appels.length, 2);
  for (const { url, options } of b.appels) {
    assert.equal(url, `https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`);
    assert.equal(options.method, 'POST'); assert.equal(options.redirect, 'error');
    assert.ok(options.signal instanceof AbortSignal);
    assert.deepEqual(Object.keys(options.headers).sort(), ['Authorization', 'Content-Type']);
  }
  assert.equal(JSON.parse(b.appels[0].options.body).query, sqlCatalogueD);
  const sql = sqlRecetteRollbackD('ci-123456-2', '2026-10-07');
  assert.equal(JSON.parse(b.appels[1].options.body).query, sql);
  assert.match(sql, /ERRCODE='JD201'/); assert.match(sql, /ROLLBACK;\nSELECT 'D2_SQL_ROLLBACK'/);
  assert.match(sql, /Catalogue D non conforme/);
  assert.doesNotMatch(sql, /COMMIT;|DISABLE TRIGGER|session_replication_role|https?:\/\/|encrypted_password|access_token/);
  assert.equal(r.sqlSha256, createHash('sha256').update(sql).digest('hex'));
  assert.equal(r.runId, 'sql-d2-ci-123456-2'); assert.equal(r.annule, true);
  assert.deepEqual([r.authHttp, r.k6, r.frontendReel], [false, false, false]);
  assert.ok(!JSON.stringify(r).includes('CANARI'));
});

test('destination, déclenchement, run/SHA et combinaisons invalides refusent avant le réseau', async () => {
  const mutations = [
    { STAGING_SUPABASE_PROJECT_REF: 'production' }, { STAGING_SUPABASE_URL: 'https://production.invalid' },
    { GITHUB_ACTIONS: '' }, { GITHUB_EVENT_NAME: 'push' }, { GITHUB_REPOSITORY: 'autre/projet' },
    { GITHUB_RUN_ID: '' }, { GITHUB_RUN_ID: '1;echo CANARI' }, { GITHUB_RUN_ATTEMPT: '0' }, { GITHUB_SHA: '' },
    { LOAD_D_SQL_ONLY: 'false' }, { LOAD_TEST_SCENARIO: 'all' }, { LOAD_TEST_SCENARIO: '05-dashboard-concurrent' },
    { DASHBOARD_FIXTURE_ONLY: 'true' }, { DIAGNOSTIC_SQL: 'true' }, { LOAD_TEST_VUS: '2' },
    { LOAD_TEST_DURATION: '1s' }, { LOAD_FIXTURE_COUNT: '3' }, { STAGING_SUPABASE_ACCESS_TOKEN: '' },
    { STAGING_SUPABASE_SERVICE_ROLE_KEY: 'CANARI-service' }, { STAGING_SUPABASE_ANON_KEY: 'CANARI-anon' },
    { LOAD_CANDIDATURES_JSON: 'CANARI-identites' }, { LOAD_D_EXECUTION_APPROUVEE: 'DEUX_PROFILS' },
  ];
  for (const mutation of mutations) {
    const b = banc({ env: { ...envValide(), ...mutation } });
    await assert.rejects(b.run()); assert.equal(b.appels.length, 0, JSON.stringify(mutation));
  }
});

test('jour explicite et bornes réelles refusés avant le réseau, pas de normalisation silencieuse', async () => {
  for (const jour of ['', '2026-02-31', '2026-09-30', '2026-10-01', '2026-11-01', '2026-10-07;SELECT 1', '07/10/2026']) {
    const b = banc({ env: { ...envValide(), LOAD_D_SQL_JOUR: jour } });
    await assert.rejects(b.run(), /JOUR_FUTUR/); assert.equal(b.appels.length, 0);
  }
  assert.equal(configurationPreuveD2({ ...envValide(), LOAD_D_SQL_JOUR: '2026-10-02' }, now).jour, '2026-10-02');
});

test('empreintes, cron, FK et catalogue incomplet bloquent avant la recette SQL', async () => {
  const r = catalogue()[0];
  for (const reponse of [null, {}, [], [r, r], [{ ...r, schema: 'autre' }], [{ ...r, fonctions: null }],
    [{ ...r, triggers: 'autre' }], [{ ...r, crons_actifs: 1 }], [{ ...r, audit_fk: 1 }]]) {
    const b = banc({ reponses: [reponse] });
    await assert.rejects(b.run(), /CATALOGUE_/); assert.equal(b.appels.length, 1);
  }
});

test('sentinelle strictement typée et unique : HTTP 200 ne suffit jamais', async () => {
  const r = sentinelle()[0];
  for (const reponse of [null, {}, [], [r, r], [{ annule: true }], [{ ...r, annule: 'true' }],
    [{ ...r, annule: false }], [{ ...r, preuve: 'autre' }], [{ ...r, error: 'CANARI-provider' }]]) {
    const b = banc({ reponses: [catalogue(), reponse] });
    await assert.rejects(b.run(), /SENTINELLE_ROLLBACK_ABSENTE/); assert.equal(b.appels.length, 2);
  }
});

for (const appel of [1, 2]) for (const type of ['http', 'timeout', 'json']) {
  test(`refus ${type} étape ${appel} : aucun retry ni corps fournisseur dans l'erreur`, async () => {
    const b = banc({ faute: { appel, type } });
    await assert.rejects(b.run(), e => !e.message.includes('CANARI') && /CATALOGUE_|ROLLBACK_/.test(e.message));
    assert.equal(b.appels.length, appel);
  });
}

test('catalogue fournisseur enrichi ne fuit pas de champs inattendus dans le résultat', async () => {
  const b = banc({ reponses: [[{ ...catalogue()[0], secret: 'CANARI-FOURNISSEUR' }], sentinelle()] });
  assert.ok(!JSON.stringify(await b.run()).includes('CANARI'));
});

test('CLI check invalide : sortie/rapport fermés, aucun succès ni canari', t => {
  const cwd = mkdtempSync(join(tmpdir(), 'jolene-D2-sql-check-')); t.after(() => rmSync(cwd, { recursive: true, force: true }));
  const r = spawnSync(process.execPath, [resolve('scripts/ci/prove-candidatures-rollback.mjs'), 'check'], {
    cwd, encoding: 'utf8', env: { ...envValide(), LOAD_TEST_SCENARIO: 'CANARI-MODE' },
  });
  assert.equal(r.status, 1); assert.doesNotMatch(r.stdout + r.stderr, /CANARI/);
  const report = JSON.parse(readFileSync(join(cwd, 'tests/load/results/d2-sql-rollback.json')));
  assert.deepEqual(report, { version: 1, mode: 'D2_SQL_ROLLBACK', status: 'failed', code: 'MODE_SQL_D2_EXCLUSIF_REQUIS' });
});

const workflow = parse(readFileSync('.github/workflows/load-tests.yml', 'utf8'));
const baseInputs = Object.fromEntries(Object.entries(workflow.on.workflow_dispatch.inputs).map(([k, v]) => [k, v.default]));
const selection = inputs => Object.entries(workflow.jobs).filter(([, job]) => {
  const expression = job.if.replace(/^\$\{\{\s*|\s*\}\}$/g, '');
  return Function('inputs', `return (${expression});`)(inputs);
}).map(([id]) => id);
test('routage exclusif : modes D2 valides ou malformés ne lancent jamais C/E/k6', () => {
  assert.deepEqual(Object.keys(workflow.on), ['workflow_dispatch']);
  assert.deepEqual(workflow.concurrency, { group: 'jolene-supabase-staging-writes', 'cancel-in-progress': false });
  assert.deepEqual(selection(baseInputs), ['load-tests']);
  assert.deepEqual(selection({ ...baseInputs, scenario: '05-dashboard-concurrent', dashboard_fixture_only: true }), ['dashboard-frontend']);
  for (const scenario of ['all', '03-recherche-missions', '04-candidatures-simultanees', '05-dashboard-concurrent']) {
    for (const flags of [{ candidatures_sql_only: true }, { candidatures_sql_date: '2026-10-07' },
      { candidatures_sql_only: true, dashboard_fixture_only: true, diagnostic_sql: true }]) {
      assert.deepEqual(selection({ ...baseInputs, scenario, ...flags }), ['candidatures-sql']);
    }
  }
});
test('job SQL : uniquement runner fermé, token Management après check, artefact exact', () => {
  const job = workflow.jobs['candidatures-sql'];
  assert.deepEqual(job.permissions, { contents: 'read' });
  assert.equal(job.env.STAGING_SUPABASE_URL, STAGING_URL);
  assert.equal(job.env.LOAD_D_SQL_ONLY, '${{ inputs.candidatures_sql_only }}');
  assert.equal(job.env.LOAD_D_SQL_JOUR, '${{ inputs.candidatures_sql_date }}');
  assert.equal(job.steps[0].with.ref, '${{ github.sha }}');
  assert.equal(job.steps[0].with['persist-credentials'], false);
  const commands = job.steps.filter(s => s.run);
  assert.deepEqual(commands.map(s => s.run), ['node scripts/ci/prove-candidatures-rollback.mjs check', 'node scripts/ci/prove-candidatures-rollback.mjs run']);
  assert.equal(commands[0].env, undefined);
  assert.deepEqual(commands[1].env, { STAGING_SUPABASE_ACCESS_TOKEN: '${{ secrets.STAGING_SUPABASE_ACCESS_TOKEN }}' });
  assert.doesNotMatch(JSON.stringify(job), /SERVICE_ROLE|ANON_KEY|prepare-staging-api-env|npm ci|k6 run|db push|migrations|auth\/v1/);
  const upload = job.steps.at(-1); assert.equal(upload.if, 'always()');
  assert.equal(upload.with.path, 'tests/load/results/d2-sql-rollback.json');
  assert.equal(upload.with['if-no-files-found'], 'error');
});
