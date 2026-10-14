import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { PROJECT, FUNCTIONS, SECRET_NAMES, checkContext, sourceClosure, compareBody,
  projectDiagnostic, collectPscDiagnostic, checkCanonicalConfig } from '../../scripts/ci/psc-staging-diagnostic.mjs';

const SHA = 'a'.repeat(40), MANAGEMENT = 'MANAGEMENT_SECRET_CANARY';
const SERVICE = 'eyJSERVICE_SECRET_CANARY.PAYLOAD.SIGNATURE';
const CANARY = 'TOKEN_STATE_AUTH_URL_CANARY';
const API = `https://api.supabase.com/v1/projects/${PROJECT}`;
const DIAGNOSTIC = `https://${PROJECT}.supabase.co/functions/v1/psc-test-connexion`;
const env = () => ({ GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'workflow_dispatch',
  GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', GITHUB_REF: 'refs/heads/test/recette-complete-20261014',
  GITHUB_SHA: SHA, PSC_DIAGNOSTIC_EXPECTED_SHA: SHA, STAGING_SUPABASE_ACCESS_TOKEN: MANAGEMENT });
const CONFIG = FUNCTIONS.map(slug => `[functions.${slug}]\nverify_jwt = false\n`).join('\n');
const local = () => ({ sha: SHA, clean: true, config: CONFIG });
const source = slug => new Map([[`supabase/functions/${slug}/index.ts`, 'import { test } from "../_shared/helper.ts";\n'],
  ['supabase/functions/_shared/helper.ts', 'export const test = true;\n']]);
const sources = () => new Map(FUNCTIONS.map(slug => [slug, source(slug)]));
const rows = () => FUNCTIONS.map((slug, i) => ({ slug, version: i + 20, verify_jwt: false,
  status: 'ACTIVE', ezbr_sha256: String(i + 1).repeat(64), opaque: CANARY,
  entrypoint_path: `file:///tmp/opaque/supabase/functions/${slug}/index.ts`, import_map: false, import_map_path: null }));
const diagnostic = () => ({ env: 'sandbox', secrets_ok: true, missing_secrets: [], discovery_ok: true,
  discovery_status: 200, endpoints_match: true, endpoints_diff: [], duration_ms: 25,
  discovery_url: `https://example.invalid?token=${CANARY}`, token: CANARY, state: CANARY });
function harness(options = {}) {
  const calls = []; let metadataReads = 0;
  const response = (value, status = 200) => new Response(typeof value === 'string' ? value : JSON.stringify(value), { status });
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (options.fetch) return options.fetch(url, init, calls);
    if (url === `${API}/secrets`) return response(options.secrets ?? SECRET_NAMES.map(name => ({ name, value: CANARY, digest: CANARY })));
    if (url === `${API}/functions`) {
      metadataReads++;
      return response(metadataReads === 1 ? options.before ?? rows()
        : metadataReads === 2 ? options.beforeKeys ?? options.after ?? rows().reverse() : options.after ?? rows().reverse());
    }
    for (const slug of FUNCTIONS) {
      if (url === `${API}/functions/${slug}/body`) return response(options.body?.(slug)
        ?? { files: [...source(slug)].map(([name, content]) => ({ name: name.replace('supabase/', ''), content })) });
    }
    if (url === `${API}/api-keys?reveal=true`) return response(options.keys ?? [{ name: 'service_role', api_key: SERVICE }, { name: 'anon', api_key: CANARY }]);
    if (url === DIAGNOSTIC) return response(options.diagnostic ?? diagnostic(), options.diagnosticStatus ?? 200);
    throw new Error(CANARY);
  };
  return { calls, run: () => collectPscDiagnostic({ env: options.env ?? env(),
    local: options.local ?? local(), sources: sources(), fetchImpl }) };
}
function safe(report) {
  const out = JSON.stringify(report);
  for (const secret of [MANAGEMENT, SERVICE, CANARY, 'authorization_url', 'discovery_url']) assert.ok(!out.includes(secret), secret);
}

test('fixed staging reads, shared exact-byte comparison, stable versions and allowlisted diagnostic', async () => {
  const h = harness(), report = await h.run();
  assert.equal(report.status, 'CONFIGURATION_OBSERVED'); assert.equal(report.metadataStable, true);
  assert.equal(report.preKeyMetadataStable, true); assert.equal(report.privilegedInvocationAllowed, true);
  assert.equal(report.diagnosticInvocationAttempted, true); assert.equal(report.diagnosticAttributionConfirmed, true);
  assert.equal(report.authenticationVerified, false); assert.equal(report.frontendVerified, false);
  assert.equal(report.deploymentPerformed, false); assert.equal(report.legacyServiceRoleAvailable, true);
  assert.equal(report.diagnostic.environment, 'sandbox'); assert.equal(report.functions.length, 4);
  assert.ok(report.functions.every(fn => fn.comparison.status === 'MATCH' && fn.comparison.files.length === 2));
  assert.deepEqual(report.secretPresence, Object.fromEntries(SECRET_NAMES.map(name => [name, true])));
  assert.equal(h.calls.length, 10); safe(report);
  const keyIndex = h.calls.findIndex(call => call.url === `${API}/api-keys?reveal=true`);
  assert.equal(h.calls.slice(0, keyIndex).filter(call => call.url === `${API}/functions`).length, 2);
  for (const { url, init } of h.calls) {
    assert.equal(init.method, 'GET'); assert.equal(init.body, undefined);
    assert.equal(init.redirect, 'error'); assert.ok(init.signal instanceof AbortSignal);
    assert.equal(init.headers.Authorization, `Bearer ${url === DIAGNOSTIC ? SERVICE : MANAGEMENT}`);
    assert.equal(init.headers.apikey, url === DIAGNOSTIC ? SERVICE : undefined);
    assert.ok(url.startsWith(API) || url === DIAGNOSTIC);
    assert.ok(!url.includes('/auth/v1/') && !url.includes('/functions/v1/psc-authorize'));
  }
});

test('context mismatches and dirty checkout stop before keys or any request', async () => {
  for (const [field, value] of [['GITHUB_ACTIONS', 'false'], ['GITHUB_EVENT_NAME', 'push'],
    ['GITHUB_EVENT_NAME', 'pull_request_target'], ['GITHUB_REPOSITORY', 'fork/repo'],
    ['GITHUB_REF', 'refs/heads/unreviewed'], ['GITHUB_SHA', 'b'.repeat(40)],
    ['PSC_DIAGNOSTIC_EXPECTED_SHA', 'bad'], ['STAGING_SUPABASE_ACCESS_TOKEN', '']]) {
    const e = env(); e[field] = value;
    const h = harness({ env: e }), r = await h.run();
    assert.equal(h.calls.length, 0); assert.deepEqual(r.issues, ['CONTEXT_REFUSED']); safe(r);
  }
  const h = harness({ local: { sha: SHA, clean: false } });
  assert.deepEqual((await h.run()).issues, ['CONTEXT_REFUSED']); assert.equal(h.calls.length, 0);
  checkContext({ ...env(), GITHUB_REF: 'refs/heads/main' }, local());
});

test('canonical checked-in PSC config requires four false JWT defaults and no alternate entrypoint/import map', async () => {
  checkCanonicalConfig(readFileSync(new URL('../../supabase/config.toml', import.meta.url), 'utf8'));
  for (const config of [CONFIG.replace('verify_jwt = false', 'verify_jwt = true'),
    CONFIG.replace('verify_jwt = false', 'verify_jwt = false\nentrypoint = "other.ts"'),
    CONFIG.replace('verify_jwt = false', 'verify_jwt = false\nimport_map = "map.json"'),
    CONFIG + '\n[functions.psc-authorize]\nverify_jwt = false\n', '']) {
    const h = harness({ local: { ...local(), config } }), r = await h.run();
    assert.equal(h.calls.length, 0); assert.ok(r.issues.includes('LOCAL_CONFIG_REFUSED')); safe(r);
  }
});

test('transitive shared imports are included, cycles deduplicated and escapes rejected', () => {
  const blobs = {
    'supabase/functions/psc-authorize/index.ts': 'import { x } from "../_shared/first.ts";',
    'supabase/functions/_shared/first.ts': 'export { x } from "./second.ts";',
    'supabase/functions/_shared/second.ts': 'import "./first.ts"; import { npm } from "npm:example@1.0.0";',
  };
  const files = sourceClosure('psc-authorize', path => blobs[path]); assert.equal(files.size, 3);
  assert.throws(() => sourceClosure('psc-authorize', () => 'import "../../../../outside.ts";'), /SOURCE_REFUSED/);
  assert.throws(() => sourceClosure('psc-authorize', () => 'import "bare-import-map-name";'), /SOURCE_IMPORT_UNSUPPORTED/);
});

test('shared mismatch and missing dependency never qualify exact source', () => {
  const expected = source('psc-authorize');
  const files = [...expected].map(([name, content]) => ({ name, content }));
  files[1].content += ' ';
  assert.equal(compareBody('psc-authorize', { files }, expected).status, 'DIFFERENT');
  assert.equal(compareBody('psc-authorize', files.slice(0, 1), expected).status, 'INCOMPLETE');
  for (const name of ['functions/psc-authorize/../index.ts', 'functions/psc-authorize/index.ts?token=' + CANARY,
    'functions/other/index.ts', 'file:///opaque/../../functions/psc-authorize/index.ts']) {
    assert.throws(() => compareBody('psc-authorize', [{ name, content: 'x' }], expected), /BODY_FORMAT_UNSUPPORTED/);
  }
  assert.throws(() => compareBody('psc-authorize', [files[0], files[0]], expected), /BODY_FORMAT_UNSUPPORTED/);
});

test('unsupported downloaded bundle format preserves inventory and blocks even API-key retrieval', async () => {
  const h = harness({ body: () => 'ESZIP_OPAQUE_' + CANARY }), r = await h.run();
  assert.equal(r.status, 'NON_PRET'); assert.equal(r.functions[0].comparison.status, 'UNKNOWN');
  assert.ok(r.issues.includes('RESPONSE_INVALID')); assert.ok(r.issues.includes('PSC_SOURCE_NOT_FULLY_MATCHED'));
  assert.equal(r.diagnostic, null); assert.equal(r.privilegedInvocationAllowed, false);
  assert.ok(h.calls.every(call => !call.url.includes('/api-keys') && call.url !== DIAGNOSTIC));
  assert.equal(r.functions.length, 4); assert.ok(Object.values(r.secretPresence).every(Boolean)); safe(r);
});

test('each incomplete or different source, including a shared dependency, blocks keys and invocation', async () => {
  for (const slug of FUNCTIONS) {
    for (const change of ['missing-shared', 'changed-shared', 'changed-index']) {
      const h = harness({ body: name => {
        const files = [...source(name)].map(([path, content]) => ({ name: path, content }));
        if (name === slug) {
          if (change === 'missing-shared') files.pop();
          else files[change === 'changed-shared' ? 1 : 0].content += ' ';
        }
        return { files };
      } }), r = await h.run();
      assert.equal(r.status, 'NON_PRET'); assert.equal(r.privilegedInvocationAllowed, false);
      assert.equal(r.diagnosticInvocationAttempted, false);
      assert.ok(h.calls.every(call => !call.url.includes('/api-keys') && call.url !== DIAGNOSTIC));
      assert.equal(r.functions.length, 4); safe(r);
    }
  }
});

test('nonactive function, JWT true, alternate entrypoint/import-map or unknown bundle pin prevents privileged access', async () => {
  for (const slug of FUNCTIONS) {
    for (const mutate of [row => row.status = 'THROTTLED', row => row.verify_jwt = true,
      row => row.entrypoint_path = `file:///tmp/supabase/functions/${slug}/other.ts`,
      row => row.entrypoint_path = 'file:///tmp/supabase/functions/another/index.ts',
      row => row.entrypoint_path = `https://evil.invalid/functions/${slug}/index.ts`,
      row => delete row.entrypoint_path, row => row.import_map = true,
      row => delete row.import_map, row => row.import_map_path = 'file:///tmp/import_map.json',
      row => row.ezbr_sha256 = null]) {
      const changed = rows(); mutate(changed.find(row => row.slug === slug));
      const h = harness({ before: changed, beforeKeys: changed, after: changed }), r = await h.run();
      assert.equal(r.status, 'NON_PRET'); assert.equal(r.privilegedInvocationAllowed, false);
      assert.equal(r.diagnosticInvocationAttempted, false); assert.equal(r.legacyServiceRoleAvailable, false);
      assert.ok(h.calls.every(call => !call.url.includes('/api-keys') && call.url !== DIAGNOSTIC));
      assert.equal(r.functions.length, 4); assert.ok(r.issues.includes('PSC_DEPLOYED_CONFIG_NOT_CANONICAL')); safe(r);
    }
  }
});

test('missing secret name is reported only as presence, no value or digest', async () => {
  const r = await harness({ secrets: SECRET_NAMES.slice(1).map(name => ({ name, value: CANARY })) }).run();
  assert.equal(r.secretPresence.PSC_ENVIRONMENT, false); assert.equal(r.status, 'NON_PRET'); safe(r);
});

test('wrong or duplicate service key is never used; secret keys are not substituted', async () => {
  for (const keys of [[], [{ name: 'service_role', api_key: 'sb_secret_' + CANARY }],
    [{ name: 'service_role', api_key: SERVICE }, { name: 'service_role', api_key: SERVICE }]]) {
    const h = harness({ keys }), r = await h.run();
    assert.equal(h.calls.some(call => call.url === DIAGNOSTIC), false);
    assert.equal(r.legacyServiceRoleAvailable, false); safe(r);
  }
});

test('401 diagnostic is recorded without retaining its body, retry or minting user session', async () => {
  const h = harness({ diagnosticStatus: 401, diagnostic: { error: CANARY, token: SERVICE } }), r = await h.run();
  assert.equal(r.diagnosticHttpStatus, 401); assert.equal(r.diagnostic, null);
  assert.ok(r.issues.includes('DIAGNOSTIC_HTTP_REFUSED')); assert.equal(h.calls.filter(call => call.url === DIAGNOSTIC).length, 1); safe(r);
});

test('production PSC configuration cannot qualify sandbox; raw endpoint URLs are discarded', async () => {
  const d = diagnostic(); d.env = 'production'; d.endpoints_match = false;
  d.endpoints_diff = ['issuer: hardcoded="https://example.invalid/' + CANARY + '" discovered="https://another.invalid"'];
  const r = await harness({ diagnostic: d }).run();
  assert.equal(r.status, 'NON_PRET'); assert.deepEqual(r.diagnostic.endpointDifferenceFields, ['issuer']); safe(r);
});

test('untrusted diagnostic fields cannot become secret names, status, differences or environment', () => {
  for (const change of [d => d.env = CANARY, d => d.missing_secrets = [CANARY],
    d => d.endpoints_diff = [CANARY + ': value'], d => d.discovery_status = CANARY,
    d => d.duration_ms = CANARY, d => d.secrets_ok = false,
    d => { d.endpoints_diff = ['issuer: x']; }, d => { d.discovery_status = 503; }]) {
    const d = diagnostic(); change(d); assert.throws(() => projectDiagnostic(d), /DIAGNOSTIC_SCHEMA_REFUSED/);
  }
});

test('metadata drift prevents source attribution, and malformed fields never enter report', async () => {
  const after = rows(); after[0].version++;
  const r = await harness({ after }).run(); assert.equal(r.metadataStable, false); assert.equal(r.status, 'NON_PRET'); safe(r);
  const bad = rows(); bad[0].status = CANARY;
  const malformed = await harness({ after: bad }).run(); assert.ok(malformed.issues.includes('FUNCTION_METADATA_REFUSED')); safe(malformed);
});

test('complete metadata drift, including unknown fields, is detected before keys and checked again afterwards', async () => {
  const changed = rows(); changed[3].extra_runtime_option = { unknown: CANARY };
  const before = harness({ beforeKeys: changed, after: changed }), r = await before.run();
  assert.equal(r.preKeyMetadataStable, false); assert.equal(r.privilegedInvocationAllowed, false);
  assert.ok(before.calls.every(call => !call.url.includes('/api-keys') && call.url !== DIAGNOSTIC)); safe(r);
  const post = harness({ beforeKeys: rows(), after: changed }), after = await post.run();
  assert.equal(after.preKeyMetadataStable, true); assert.equal(after.diagnosticInvocationAttempted, true);
  assert.equal(after.metadataStable, false); assert.equal(after.diagnosticAttributionConfirmed, false);
  assert.equal(after.status, 'NON_PRET'); safe(after);
  const orderOnly = harness({ beforeKeys: rows().reverse().map(row => Object.fromEntries(Object.entries(row).reverse())) });
  assert.equal((await orderOnly.run()).status, 'CONFIGURATION_OBSERVED');
});

test('transport, redirects, JSON and oversized errors are expurgated without retry', async () => {
  for (const fetch of [() => { throw new Error('https://user:' + CANARY + '@host?token=' + MANAGEMENT); },
    () => new Response(CANARY, { status: 403 }), () => new Response(CANARY, { status: 200 }),
    () => new Response('x'.repeat(2 * 1024 * 1024 + 1) + CANARY, { status: 200 })]) {
    const h = harness({ fetch }), r = await h.run(); assert.equal(r.status, 'NON_PRET'); safe(r);
    assert.ok(h.calls.length <= 4); assert.equal(h.calls.some(call => call.url === DIAGNOSTIC), false);
  }
});

test('workflow validates exact SHA and trusted branch before checkout or staging secret use', () => {
  const text = readFileSync(new URL('../../.github/workflows/psc-staging-diagnostic.yml', import.meta.url), 'utf8');
  assert.equal((text.match(/secrets\./g) ?? []).length, 1); assert.ok(!text.includes('npm ci'));
  const gate = text.split('        run: |\n')[1].split('      - uses:')[0].replace(/^ {10}/gm, '');
  const base = { ...env(), EXPECTED_SHA: SHA, PATH: process.env.PATH }; delete base.STAGING_SUPABASE_ACCESS_TOKEN;
  assert.equal(spawnSync('bash', ['-c', gate], { env: base, encoding: 'utf8' }).status, 0);
  for (const [key, value] of [['GITHUB_REF', 'refs/heads/elsewhere'], ['GITHUB_REPOSITORY', 'fork/repo'],
    ['GITHUB_EVENT_NAME', 'pull_request'], ['EXPECTED_SHA', CANARY]]) {
    const r = spawnSync('bash', ['-c', gate], { env: { ...base, [key]: value }, encoding: 'utf8' });
    assert.equal(r.status, 1); assert.equal(r.stdout, 'PSC_DIAGNOSTIC_CONTEXT_REFUSED\n'); assert.equal(r.stderr, '');
  }
});

test('existing provider workflow runs PSC guards first and preserves a distinct report on NON_PRET', () => {
  const text = readFileSync(new URL('../../.github/workflows/recette-fournisseurs-preflight.yml', import.meta.url), 'utf8');
  const guard = text.indexOf('run: node --test tests/node/psc-staging-diagnostic.node.mjs');
  const psc = text.indexOf('run: node scripts/ci/psc-staging-diagnostic.mjs');
  const providers = text.indexOf('run: node scripts/recette-fournisseurs/collect-preflight.mjs');
  assert.ok(guard >= 0 && guard < psc && psc < providers);
  assert.equal((text.match(/continue-on-error: true/g) ?? []).length, 1);
  assert.ok(text.slice(guard, psc).includes('continue-on-error: true'));
  const artifact = text.slice(text.indexOf('- name: Conserver séparément le diagnostic PSC expurgé'));
  assert.ok(artifact.includes('if: always()')); assert.ok(artifact.includes('path: psc-staging-diagnostic.json'));
  assert.ok(artifact.includes('if-no-files-found: error'));
});
