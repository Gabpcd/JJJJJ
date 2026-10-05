import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { ACCOUNT, PROJECT, EDGES, SQL_FUNCTIONS, QUERIES, collectPreflight, sourceFromGit } from '../../scripts/recette-fournisseurs/collect-preflight.mjs';

import { summarizePreflight } from '../../scripts/recette-fournisseurs/summarize-preflight.mjs';

const secret = 'sk_test_NEVEREXPOSETHIS';
const source = { repository: 'Gabpcd/JJJJJ', sha: 'a'.repeat(40), migrations: ['20260927152738'],
  sourceFiles: EDGES.map(name => ({ path: `supabase/functions/${name}/index.ts`, sha256: 'b'.repeat(64) })) };
function fixture(overrides = {}) {
  const calls = [];
  const responses = {
    migrations: [{ version: '20260927152738', secret }],
    sqlFunctions: SQL_FUNCTIONS.map(name => ({ name, digest: 'c'.repeat(32), secret })),
    vaultNames: [{ name: 'supabase_url', value: secret }, { name: 'service_role_key', value: secret }],
    crons: [{ total: 9, active: 0, command: secret }],
    queues: ['escrow_release_queue', 'stripe_refunds_queue'].map(name => ({ name, total: 2, pending: 1, secret })),
    functions: EDGES.map(slug => ({ slug, version: 3, verify_jwt: false, status: 'ACTIVE', secret })),
    secrets: [{ name: 'STRIPE_SECRET_KEY', value: secret }, { name: secret, value: secret }],
    account: { id: ACCOUNT, email: secret, charges_enabled: true, payouts_enabled: true,
      capabilities: { card_payments: 'active', transfers: 'active' },
      requirements: { past_due: [], disabled_reason: null } }, balance: { livemode: false, available: [{ amount: 987654321 }] },
    webhooks: { data: ['stripe-webhook', 'stripe-connect-webhook'].map((route, i) => ({
      id: `we_example${i}`, url: `https://${PROJECT}.supabase.co/functions/v1/${route}`, livemode: false,
      status: 'enabled', enabled_events: ['*'], secret, description: secret,
    })), has_more: false }, ...overrides,
  };
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    assert.equal(init.redirect, 'error');
    assert.ok(init.signal);
    let key;
    if (url.startsWith('https://api.supabase.com/')) {
      assert.ok(url.startsWith(`https://api.supabase.com/v1/projects/${PROJECT}/`));
      if (url.endsWith('/database/query')) {
        assert.equal(init.method, 'POST');
        const body = JSON.parse(init.body);
        assert.equal(body.read_only, true);
        key = Object.keys(QUERIES).find(name => QUERIES[name] === body.query);
        assert.ok(key, 'only fixed read-only queries permitted');
        assert.match(body.query, /^SELECT /);
        assert.doesNotMatch(body.query, /decrypted_secrets|pg_net|net\.http|INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|fn_\w+\(/i);
      } else {
        assert.equal(init.method, 'GET'); key = url.endsWith('/functions') ? 'functions' : 'secrets';
      }
    } else {
      assert.equal(init.method, 'GET'); assert.ok(url.startsWith('https://api.stripe.com/v1/'));
      key = url.includes('/webhook_endpoints?') ? 'webhooks' : url.split('/').at(-1);
      assert.ok(['account', 'balance', 'webhooks'].includes(key));
    }
    const value = responses[key];
    if (value instanceof Error) throw value;
    if (typeof value === 'function') return value(url, init);
    return { ok: true, json: async () => value };
  };
  return { calls, fetchImpl };
}
const collect = f => collectPreflight({ source, token: 'test-management-header-only', stripeKey: secret, fetchImpl: f.fetchImpl });

test('reads fixed staging + sandbox metadata without any transport and remains explicitly incomplete', async () => {
  const f = fixture(), report = await collect(f);
  assert.equal(report.status, 'NON_PRET');
  assert.equal(report.readyForTransports, false); assert.equal(report.integratedFlowReady, false);
  assert.equal(report.providerMutations, 0); assert.equal(f.calls.length, 10);
  assert.equal(report.checks.migrations.matchesCandidate, true);
  assert.equal(report.checks.edgeFunctions.functions.length, 7);
  assert.equal(report.checks.sqlFunctions.functions.length, 4);
  assert.equal(report.checks.edgeFunctions.deployedContentMatchesCandidate, null);
  assert.equal(report.checks.sqlFunctions.definitionsMatchCandidate, null);
  assert.equal(report.checks.vaultNames.projectUrlMatches, null);
  assert.equal(report.checks.queues.eligibleForeignQueueCount, null);
  assert.equal(report.checks.stripeWebhooks.connectScopeConfirmed, null);
  assert.equal(report.checks.stripeWebhooks.signingSecretMatches, null);
  assert.ok(report.unknowns.includes('COHORT_GUARDS_NOT_ATTESTED'));
  const output = JSON.stringify(report);
  for (const forbidden of [secret, 'test-management-header-only', '987654321', 'we_example']) assert.ok(!output.includes(forbidden));
});

test('missing secrets and live credentials never trigger a request', async () => {
  for (const stripeKey of [undefined, '', 'sk_live_MUSTNEVERUSE', 'rk_live_NO']) {
    let called = false;
    const report = await collectPreflight({ source, stripeKey, fetchImpl: () => { called = true; } });
    assert.equal(called, false); assert.equal(report.status, 'NON_PRET');
    assert.deepEqual(report.issues, ['STAGING_TOKEN_ABSENT', 'STRIPE_TEST_KEY_ABSENT_OR_INVALID']);
  }
});

test('an authenticated test account with disabled payments is reported as restricted, without identity data', async () => {
  const report = await collect(fixture({ account: { id: ACCOUNT, charges_enabled: false, payouts_enabled: false,
    capabilities: { card_payments: 'inactive', transfers: 'inactive' },
    requirements: { past_due: ['person_PRIVATE.address.city', 'person_PRIVATE.dob.year'], disabled_reason: 'requirements.past_due' },
  } }));
  assert.equal(report.checks.stripeSandbox.accountMatches, true);
  assert.equal(report.checks.stripeSandbox.chargesEnabled, false);
  assert.equal(report.checks.stripeSandbox.payoutsEnabled, false);
  assert.equal(report.checks.stripeSandbox.pastDueCount, 2);
  assert.ok(report.issues.includes('STRIPE_TEST_ACCOUNT_RESTRICTED'));
  assert.ok(!JSON.stringify(report).includes('person_PRIVATE'));
  assert.equal(report.integratedFlowReady, false);
});

test('missing capability information stays unknown; an active account still does not validate the circuit', async () => {
  const unknown = await collect(fixture({ account: { id: ACCOUNT } }));
  assert.equal(unknown.checks.stripeSandbox.chargesEnabled, null);
  assert.equal(unknown.checks.stripeSandbox.transfersActive, null);
  assert.ok(unknown.issues.includes('STRIPE_TEST_CAPABILITIES_UNKNOWN'));
  const active = await collect(fixture());
  assert.equal(active.checks.stripeSandbox.chargesEnabled, true);
  assert.equal(active.checks.stripeSandbox.transfersActive, true);
  assert.ok(!active.issues.includes('STRIPE_TEST_ACCOUNT_RESTRICTED'));
  assert.equal(active.integratedFlowReady, false);
});

test('a wrong account or live balance blocks webhook inspection and redacts provider responses', async () => {
  for (const override of [{ account: { id: 'acct_FOREIGN', secret } }, { balance: { livemode: true, secret } }]) {
    const f = fixture(override), report = await collect(f);
    assert.equal(report.checks.stripeSandbox.status, 'UNKNOWN');
    assert.equal(report.checks.stripeWebhooks, undefined);
    assert.ok(!f.calls.some(call => call.url.includes('webhook_endpoints')));
    assert.ok(!JSON.stringify(report).includes('acct_FOREIGN'));
  }
});

test('permissions, malformed responses and exceptions remain unknown without leaking bodies', async () => {
  const f = fixture({ vaultNames: new Error(secret), sqlFunctions: [], functions: null,
    secrets: () => ({ ok: false, json: () => { throw new Error('error body must not be read'); } }) });
  const report = await collect(f);
  for (const name of ['vaultNames', 'sqlFunctions', 'edgeFunctions', 'edgeSecretNames']) assert.equal(report.checks[name].status, 'UNKNOWN');
  assert.equal(report.checks.crons.active, 0);
  assert.equal(report.checks.stripeSandbox.accountMatches, true);
  assert.ok(!JSON.stringify(report).includes(secret));
});

test('migration drift, inactive edges, active crons and absent routes are explicit, not successful', async () => {
  const f = fixture({ migrations: [{ version: '20260925000000' }], functions: [], crons: [{ total: 9, active: 1 }],
    webhooks: { data: [{ id: 'we_foreign', url: 'https://example.invalid/?token=NEVEREXPOSE', status: 'enabled' }], has_more: false } });
  const report = await collect(f);
  assert.equal(report.checks.migrations.matchesCandidate, false);
  for (const issue of ['MIGRATIONS_MISMATCH', 'EDGE_FUNCTION_MISSING_OR_INACTIVE', 'ACTIVE_CRONS_PRESENT', 'STAGING_WEBHOOK_ROUTE_MISSING']) assert.ok(report.issues.includes(issue));
  assert.ok(!JSON.stringify(report).includes('NEVEREXPOSE'));
});

test('webhook pagination is bounded, complete and refuses repeated cursors or malformed lists', async () => {
  let pages = 0;
  const f = fixture({ webhooks: () => ({ ok: true, json: async () => (++pages === 1
    ? { data: [{ id: 'we_page1', url: 'https://example.invalid' }], has_more: true }
    : { data: [], has_more: false }) }) });
  const report = await collect(f);
  assert.equal(report.checks.stripeWebhooks.total, 1); assert.equal(pages, 2);
  assert.ok(f.calls.at(-1).url.endsWith('starting_after=we_page1'));
  const repeated = await collect(fixture({ webhooks: { data: [{ id: 'we_repeat' }], has_more: true } }));
  assert.equal(repeated.checks.stripeWebhooks.status, 'UNKNOWN');
  const empty = await collect(fixture({ webhooks: { data: [], has_more: true } }));
  assert.equal(empty.checks.stripeWebhooks.status, 'UNKNOWN');
});

test('foreign source and malformed source stop before authentication; unknown source fields are discarded', async () => {
  for (const bad of [null, { ...source, repository: 'other/repo' }, { ...source, sha: '0'.repeat(40) }, { ...source, migrations: [] }]) {
    const report = await collectPreflight({ source: bad, token: secret, stripeKey: secret,
      fetchImpl: () => { throw new Error('must never call'); } });
    assert.equal(report.source, null); assert.deepEqual(report.issues, ['SOURCE_INVALID']);
  }
  const report = await collectPreflight({ source: { ...source, secret }, fetchImpl: () => assert.fail() });
  assert.ok(!JSON.stringify(report).includes(secret));
  const timestamp = await collectPreflight({ source, now: secret, fetchImpl: () => assert.fail() });
  assert.equal(timestamp.observedAt, null);
  assert.deepEqual(timestamp.issues, ['OBSERVATION_TIME_INVALID']);
  assert.ok(!JSON.stringify(timestamp).includes(secret));
});

test('source references come from exact committed checkout and mismatch is rejected', () => {
  const cwd = fileURLToPath(new URL('../..', import.meta.url));
  const sha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd, encoding: 'utf8' }).trim();
  const result = sourceFromGit(sha, cwd);
  assert.equal(result.sha, sha); assert.ok(result.migrations.includes('20260927152738'));
  assert.ok(EDGES.every(name => result.sourceFiles.some(f => f.path === `supabase/functions/${name}/index.ts`)));
  assert.throws(() => sourceFromGit('f'.repeat(40), cwd), /INVALID_METADATA/);
});

test('CLI fails closed without credentials, emits only a static message and refuses report overwrite', () => {
  const cwd = mkdtempSync(join(tmpdir(), 'jolene-preflight-cli-'));
  const script = fileURLToPath(new URL('../../scripts/recette-fournisseurs/collect-preflight.mjs', import.meta.url));
  try {
    const run = () => spawnSync(process.execPath, [script], { cwd, encoding: 'utf8', env: { PATH: process.env.PATH } });
    const first = run(); assert.equal(first.status, 2);
    assert.match(first.stdout, /^NON_PRET :/); assert.equal(first.stderr, '');
    const before = readFileSync(join(cwd, 'recette-fournisseurs-preflight.json'), 'utf8');
    assert.deepEqual(JSON.parse(before).issues, ['COLLECTION_SOURCE_OR_RUNTIME_INVALID']);
    const second = run(); assert.equal(second.status, 2); assert.match(second.stderr, /^RAPPORT_NON_ECRIT/);
    assert.equal(readFileSync(join(cwd, 'recette-fournisseurs-preflight.json'), 'utf8'), before);
  } finally { rmSync(cwd, { recursive: true, force: true }); }
});

test('manual workflow exposes credentials only to collector and uploads only projected report', () => {
  const workflow = readFileSync(new URL('../../.github/workflows/recette-fournisseurs-preflight.yml', import.meta.url), 'utf8');
  assert.match(workflow, /workflow_dispatch:/); assert.doesNotMatch(workflow, /pull_request:|push:|schedule:|continue-on-error|functions deploy|db push|curl|secrets\.SUPABASE_ACCESS_TOKEN/);
  assert.match(workflow, /contents: read/); assert.match(workflow, /persist-credentials: false/);
  assert.match(workflow, /RECETTE_CANDIDATE_SHA: \$\{\{ github.sha \}\}/);
  assert.match(workflow, /path: recette-fournisseurs-preflight.json/);
});

test('CLI invoked through a symlinked directory still records NON_PRET and exits 2', () => {
  const cwd = mkdtempSync(join(tmpdir(), 'jolene-preflight-symlink-'));
  const script = fileURLToPath(new URL('../../scripts/recette-fournisseurs/collect-preflight.mjs', import.meta.url));
  try {
    const alias = join(cwd, 'alias');
    symlinkSync(dirname(script), alias, 'dir');
    const result = spawnSync(process.execPath, [join(alias, 'collect-preflight.mjs')], {
      cwd, encoding: 'utf8', env: { PATH: process.env.PATH },
    });
    assert.equal(result.status, 2);
    assert.match(result.stdout, /^NON_PRET :/); assert.equal(result.stderr, '');
    const report = JSON.parse(readFileSync(join(cwd, 'recette-fournisseurs-preflight.json'), 'utf8'));
    assert.equal(report.status, 'NON_PRET');
    assert.equal(report.readyForTransports, false);
    assert.deepEqual(report.issues, ['COLLECTION_SOURCE_OR_RUNTIME_INVALID']);
  } finally { rmSync(cwd, { recursive: true, force: true }); }
});


test('platform webhook name is observed separately without reading its value or digest', async () => {
  for (const present of [true,false]) {
    const rows = [{name:'STRIPE_WEBHOOK_SECRET',value:secret},{name:'STRIPE_CONNECT_WEBHOOK_SECRET',digest:secret}];
    if (present) rows.push({name:'STRIPE_PLATFORM_WEBHOOK_SECRET',get value(){assert.fail('must not read value');},get digest(){assert.fail('must not read digest');}});
    const report=await collect(fixture({secrets:rows}));
    assert.equal(report.checks.edgeSecretNames.present.STRIPE_PLATFORM_WEBHOOK_SECRET,present);
    assert.equal(report.checks.edgeSecretNames.present.STRIPE_WEBHOOK_SECRET,true);
    assert.equal(report.checks.edgeSecretNames.present.STRIPE_CONNECT_WEBHOOK_SECRET,true);
    assert.equal(report.checks.edgeSecretNames.valuesVerified,false);
    assert(summarizePreflight(report).includes(present ? '**présent**' : '**absent**'));
    assert(!JSON.stringify(report).includes(secret));
  }
});

test('successful metadata collection may expose blockers and still never qualifies transports', async () => {
  const report=await collect(fixture({migrations:[{version:'20260925000000'}],crons:[{total:9,active:1}],
    account:{id:ACCOUNT,charges_enabled:false,payouts_enabled:false,capabilities:{card_payments:'inactive',transfers:'inactive'},requirements:{past_due:[],disabled_reason:null}}}));
  const summary=summarizePreflight(report);
  assert.match(summary,/Collecte : complète \(9\/9/);
  assert.match(summary,/Migrations différentes/); assert.match(summary,/Crons actifs présents/); assert.match(summary,/Compte Stripe TEST restreint/);
  assert.match(summary,/Qualification : NON PRÊT/); assert.match(summary,/code de sortie 2/);
  assert.equal(report.readyForTransports,false);assert.equal(report.integratedFlowReady,false);
  for (const forbidden of [secret,ACCOUNT,PROJECT,source.sha,'c'.repeat(32)]) assert(!summary.includes(forbidden));
});

test('unavailable names remain unknown, never absence or complete collection', async () => {
  const summary=summarizePreflight(await collect(fixture({secrets:new Error(secret)})));
  assert.match(summary,/incomplète ou non confirmée \(8\/9/);
  assert.match(summary,/signature plateforme : \*\*non observé\*\*/);
  assert(!summary.includes(secret));
});
