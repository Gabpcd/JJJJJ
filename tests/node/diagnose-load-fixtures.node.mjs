import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { configuration, creerManifeste, STAGING_REF, STAGING_URL } from '../../scripts/ci/prepare-load-fixtures.mjs';
import { executerDiagnostic, SEARCH_DEFINITION_MD5, sondesDiagnostic } from '../../scripts/ci/diagnose-load-fixtures.mjs';

const silence = () => {};
function environnement(extra = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-diagnostic-load-'));
  const env = { STAGING_SUPABASE_PROJECT_REF: STAGING_REF, STAGING_SUPABASE_URL: STAGING_URL,
    STAGING_SUPABASE_ACCESS_TOKEN: 'faux-token-prive-du-test', LOAD_TEST_RUN_ID: 'diagnostic-500-1',
    LOAD_FIXTURE_COUNT: '100', LOAD_FIXTURE_MANIFEST: join(dir, 'manifest.json'),
    LOAD_DIAGNOSTICS_PATH: join(dir, 'diagnostic.json'), ...extra };
  // Écrire une fixture connue même pour les tests d'environnement refusé.
  const manifest = creerManifeste({ runId: 'diagnostic-500-1', count: 100 });
  writeFileSync(env.LOAD_FIXTURE_MANIFEST, JSON.stringify({ ...manifest, status: 'prepared', visible: 100 }));
  return env;
}
const metadata = { definition_md5: SEARCH_DEFINITION_MD5, uid_null: true, read_only: 'on', fixture_count: 100,
  role: 'postgres', jit: 'off', tables: [], search_statements: [] };
const tailles = ['sans_filtre','ide_paris','ville_paris'].map((cas, i) => ({ cas, lignes: i === 0 ? 100 : 1, octets_json: 1000, octets_pg: 1004 }));
const plan = [{ 'QUERY PLAN': [{ Plan: { 'Node Type': 'Aggregate', 'Actual Rows': 1 }, 'Execution Time': 1.2 }] }];
const resultats = [[{ metadata }], tailles, plan, plan, plan, plan];
const reponse = value => new Response(JSON.stringify(value), { status: 201 });

test('six sondes bornées, strictement en lecture seule, sans ANALYZE de table ni texte de pg_stat_statements', () => {
  const sondes = sondesDiagnostic(creerManifeste({ runId: 'diagnostic-500-1', count: 100 }));
  assert.equal(sondes.length, 6);
  assert.equal(new Set(sondes.map(s => s.id)).size, 6);
  for (const { query } of sondes) {
    assert.match(query, /^BEGIN READ ONLY;/); assert.match(query, /ROLLBACK;$/);
    assert.match(query, /SET LOCAL statement_timeout = '8s'/); assert.match(query, /SET LOCAL lock_timeout = '2s'/);
    assert.match(query, /SET LOCAL request\.jwt\.claim\.sub = ''/);
    assert.match(query, /IF auth\.uid\(\) IS NOT NULL/);
    assert.match(query, /cron\.job WHERE active/);
    assert.match(query, new RegExp(SEARCH_DEFINITION_MD5));
    assert.doesNotMatch(query, /\b(?:INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|TRUNCATE|COMMIT|VACUUM)\b|^ANALYZE\b|net\.http|http_post|COPY\b/im);
  }
  assert.equal(sondes.filter(s => s.query.includes('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)')).length, 4);
  assert.match(sondes[4].query, /SET LOCAL plan_cache_mode = 'force_custom_plan'/);
  assert.doesNotMatch(sondes[0].query, /SELECT query[, ]/);
  assert.match(sondes[5].query, /NOT false OR public\.fn_soignant_eligible_mission\(NULL::uuid/);
  assert.match(sondes[5].query, /NULL::uuid IS NULL OR NOT public\.fn_est_exclu/);
});

test('production, autre hôte et manifeste non préparé refusés avant tout réseau', async () => {
  for (const extra of [
    { STAGING_SUPABASE_PROJECT_REF: 'flripxtsyegjshnhzjkz' },
    { STAGING_SUPABASE_URL: 'https://flripxtsyegjshnhzjkz.supabase.co' },
    { STAGING_SUPABASE_URL: STAGING_URL + '.evil.invalid' },
    { STAGING_SUPABASE_ACCESS_TOKEN: '' },
    { LOAD_TEST_RUN_ID: "run'; SELECT 1" },
  ]) {
    let appels = 0;
    await assert.rejects(executerDiagnostic({ env: environnement(extra), fetchImpl: () => { appels++; }, log: silence }));
    assert.equal(appels, 0);
  }
  for (const key of ['status','visible','projectRef','missions']) {
    const env = environnement(); const manifest = JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST));
    manifest[key] = key === 'status' ? 'cleaned' : key === 'missions' ? [] : 'incoherent';
    writeFileSync(env.LOAD_FIXTURE_MANIFEST, JSON.stringify(manifest)); let appels = 0;
    await assert.rejects(executerDiagnostic({ env, fetchImpl: () => { appels++; }, log: silence }), /Manifeste/);
    assert.equal(appels, 0);
  }
});

test('six appels séquentiels au seul endpoint Management, rapport sans token et rollback demandé', async () => {
  const env = environnement(); const urls = []; const logs = []; let actifs = 0; let maxActifs = 0;
  const report = await executerDiagnostic({ env, log: message => logs.push(message), fetchImpl: async (url, options) => {
    actifs++; maxActifs = Math.max(maxActifs, actifs); urls.push(url);
    assert.equal(url, `https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`);
    assert.equal(options.redirect, 'error'); assert.equal(options.method, 'POST');
    assert.equal(options.headers.Authorization, `Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`);
    assert.ok(options.signal instanceof AbortSignal);
    const body = JSON.parse(options.body); assert.deepEqual(Object.keys(body), ['query']);
    assert.match(body.query, /^BEGIN READ ONLY;/); assert.match(body.query, /ROLLBACK;$/);
    await Promise.resolve(); actifs--;
    return reponse(resultats[urls.length - 1]);
  } });
  assert.equal(urls.length, 6); assert.equal(maxActifs, 1); assert.equal(report.status, 'completed');
  assert.deepEqual(JSON.parse(readFileSync(env.LOAD_DIAGNOSTICS_PATH)), report);
  assert.doesNotMatch(JSON.stringify(report) + JSON.stringify(logs), /faux-token-prive|Bearer/);
  assert.equal(JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST)).status, 'prepared');
});

test('contexte réel incohérent bloque les cinq autres sondes', async () => {
  for (const wrong of [{ uid_null: false }, { read_only: 'off' }, { fixture_count: 0 }, { definition_md5: 'different' }]) {
    const env = environnement(); let calls = 0;
    await assert.rejects(executerDiagnostic({ env, log: silence, fetchImpl: async () => {
      calls++; return reponse([{ metadata: { ...metadata, ...wrong } }]);
    } }), /Contexte/);
    assert.equal(calls, 1); assert.equal(JSON.parse(readFileSync(env.LOAD_DIAGNOSTICS_PATH)).status, 'failed');
  }
});

test('erreur réseau ou HTTP : aucun corps ni secret affiché, aucun retry caché', async () => {
  for (const mode of ['network','http']) {
    const env = environnement(); let calls = 0; let lu = false;
    const error = await executerDiagnostic({ env, log: silence, fetchImpl: async () => {
      calls++;
      if (mode === 'network') throw new Error(`Détail privé ${env.STAGING_SUPABASE_ACCESS_TOKEN}`);
      return { ok: false, status: 503, text: () => { lu = true; return env.STAGING_SUPABASE_ACCESS_TOKEN; } };
    } }).then(() => null, e => e);
    assert.ok(error); assert.doesNotMatch(error.message, /Détail privé|faux-token-prive/);
    assert.equal(calls, 1); assert.equal(lu, false);
    assert.equal(JSON.parse(readFileSync(env.LOAD_DIAGNOSTICS_PATH)).status, 'failed');
  }
});

test('JSON invalide, réponse trop volumineuse et plan absent échouent sans exporter le corps', async () => {
  for (const body of ['not-json-secret', JSON.stringify({ secret: 'x'.repeat(600_000) }), JSON.stringify({ unexpected: [] })]) {
    const env = environnement();
    await assert.rejects(executerDiagnostic({ env, log: silence, fetchImpl: async () => new Response(body) }));
    assert.doesNotMatch(readFileSync(env.LOAD_DIAGNOSTICS_PATH, 'utf8'), /not-json-secret|unexpected|xxxxxx/);
  }
  const env = environnement(); let calls = 0;
  await assert.rejects(executerDiagnostic({ env, log: silence, fetchImpl: async () => reponse(calls++ < 2 ? resultats[calls - 1] : []) }), /Plan/);
  assert.equal(calls, 3);
  assert.equal(JSON.parse(readFileSync(env.LOAD_DIAGNOSTICS_PATH)).probes.length, 2);
});

test('budget global arrête avant une sonde supplémentaire et conserve les mesures terminées', async () => {
  const env = environnement(); let now = 0; let calls = 0;
  await assert.rejects(executerDiagnostic({ env, log: silence, maintenant: () => now,
    fetchImpl: async () => { calls++; now += 76_000; return reponse(resultats[0]); } }), /Budget global/);
  assert.equal(calls, 1);
  assert.equal(JSON.parse(readFileSync(env.LOAD_DIAGNOSTICS_PATH)).probes.length, 1);
});

test('workflow diagnostic facultatif entre préparation et k6, nettoyage et upload toujours conservés', () => {
  const workflow = readFileSync(new URL('../../.github/workflows/load-tests.yml', import.meta.url), 'utf8');
  const prepare = workflow.indexOf('run: node scripts/ci/prepare-load-fixtures.mjs prepare');
  const diagnostic = workflow.indexOf('run: node scripts/ci/diagnose-load-fixtures.mjs');
  assert.ok(prepare < diagnostic && diagnostic < workflow.indexOf('- name: Run scenario'));
  assert.match(workflow, /if: inputs\.diagnostic_sql && \(inputs\.scenario == '03-recherche-missions' \|\| inputs\.scenario == 'all'\)/);
  assert.match(workflow, /diagnostic_sql:[\s\S]*?type: boolean[\s\S]*?default: false/);
  assert.match(workflow, /name: Nettoyer exclusivement[\s\S]*?if: always\(\)/);
  assert.match(workflow, /name: Upload k6 results\s+if: always\(\)/);
  assert.match(readFileSync(new URL('../../.github/workflows/validate-pr.yml', import.meta.url), 'utf8'), /tests\/node\/diagnose-load-fixtures\.node\.mjs/);
});
