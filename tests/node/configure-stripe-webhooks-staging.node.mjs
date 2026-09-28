import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { ACCOUNT, PROJECT, API_VERSION, ROUTES, FUNCTIONS, endpointMatches, configureTestWebhooks } from '../../scripts/recette-fournisseurs/configure-stripe-webhooks-test.mjs';

const key = 'sk_test_NoOutput123';
const token = 'management-no-output';
function fixture(overrides = {}) {
  const calls = [], checkpoints = [];
  const secrets = ['whsec_NoOutputPlatform', 'whsec_NoOutputConnect'];
  let written = false, created = 0;
  const response = (data, status = 200) => ({ ok: status >= 200 && status < 300, status, json: async () => data });
  const fetchImpl = async (url, options) => {
    calls.push({ url, ...options });
    assert.equal(options.redirect, 'error'); assert.ok(options.signal);
    if (url.includes('.supabase.co/functions/')) {
      const routeIndex = ROUTES.findIndex(route => url === `https://${PROJECT}.supabase.co/functions/v1/${route.slug}`);
      assert.ok(routeIndex >= 0);
      assert.equal(options.method, 'POST');
      assert.equal(options.headers.Authorization, undefined);
      const event = JSON.parse(options.body);
      assert.equal(event.livemode, false);
      assert.equal(event.type, 'jolene.configuration_probe');
      assert.equal(Boolean(event.account), ROUTES[routeIndex].connect);
      const header = options.headers['stripe-signature'];
      const timestamp = header.match(/^t=(\d+),/)[1];
      const correct = header.endsWith(createHmac('sha256', secrets[routeIndex]).update(`${timestamp}.${options.body}`).digest('hex'));
      if (overrides.probeFailure) return response({ error: 'Webhook configuration invalid' }, 503);
      return correct ? response({ received: true, skipped: 'source_event_not_allowed' }) : response({ error: 'Invalid signature' }, 400);
    }
    if (url === 'https://api.stripe.com/v1/account') return response(overrides.account ?? {
      id: ACCOUNT, charges_enabled: true, payouts_enabled: true, capabilities: { card_payments: 'active', transfers: 'active' } });
    if (url === 'https://api.stripe.com/v1/balance') return response(overrides.balance ?? { livemode: false });
    if (/webhook_endpoints\/we_/.test(url)) return response(overrides.existing);
    if (url.includes('webhook_endpoints?')) return response(overrides.list ?? { data: [], has_more: false });
    if (url === 'https://api.stripe.com/v1/webhook_endpoints') {
      const route = ROUTES[created], index = created++;
      assert.equal(options.headers.Authorization, `Bearer ${key}`);
      assert.equal(options.headers['Idempotency-Key'], `jolene-staging-webhooks/${overrides.setupRunId ?? '123456789'}/${route.slug}`);
      const form = new URLSearchParams(options.body);
      assert.equal(form.get('connect'), String(route.connect));
      assert.equal(form.get('metadata[jolene_project]'), PROJECT);
      assert.equal(form.get('metadata[setup_run]'), overrides.setupRunId ?? '123456789');
      assert.deepEqual(form.getAll('enabled_events[]'), route.events);
      if (overrides.createFailure) throw new Error(`ambiguous provider body ${key}`);
      return response({ id: `we_fixture${index}`, livemode: false, url: form.get('url'), status: 'enabled',
        api_version: API_VERSION, enabled_events: route.events, secret: secrets[index], ...overrides.endpoint, ...overrides.endpoints?.[index] });
    }
    assert.ok(url.startsWith(`https://api.supabase.com/v1/projects/${PROJECT}/`));
    assert.equal(options.headers.Authorization, `Bearer ${token}`);
    if (url.endsWith('/database/query')) {
      const body = JSON.parse(options.body); assert.equal(body.read_only, true);
      assert.doesNotMatch(body.query, /vault|DELETE|INSERT|UPDATE|ALTER/i);
      return response(overrides.queues ?? [{ active_crons: 0, releases: 0, refunds: 0 }]);
    }
    if (url.endsWith('/functions')) return response(overrides.functions ?? FUNCTIONS.map(slug => ({ slug, status: 'ACTIVE', verify_jwt: false })));
    assert.ok(url.endsWith('/secrets'));
    if (options.method === 'POST') {
      assert.deepEqual(JSON.parse(options.body), ROUTES.map((route, i) => ({ name: route.secretName, value: secrets[i] })));
      written = true;
      if (overrides.secretFailure) throw new Error(token);
      return response({});
    }
    return response(written ? [{ name: 'STRIPE_SECRET_KEY' }, ...ROUTES.map(route => ({ name: route.secretName }))]
      : overrides.names ?? [{ name: 'STRIPE_SECRET_KEY' }]);
  };
  return { calls, checkpoints, run: args => configureTestWebhooks({ token, stripeKey: key, runId: '123456789', fetchImpl,
    checkpoint: report => checkpoints.push(report), ...args }) };
}

test('configures separate platform/Connect signatures and validates isolation without a financial event', async () => {
  const f = fixture(), result = await f.run();
  assert.equal(result.status, 'WEBHOOK_SIGNATURES_CONFIGURED');
  assert.equal(result.integratedFlowReady, false);
  assert.equal(result.providerPaymentsCreated, 0);
  assert.ok(result.endpoints.every(e => e.created && e.signatureVerified && e.oppositeSignatureRejected));
  assert.equal(f.calls.filter(c => c.url.includes('.supabase.co/functions/')).length, 4);
  assert.equal(f.calls.filter(c => c.method === 'POST' && c.url.endsWith('/secrets')).length, 1);
  const firstCreation = f.checkpoints.find(r => r.endpoints.length === 1);
  assert.equal(firstCreation.endpoints[0].creationAttempted, true);
  assert.equal(firstCreation.endpoints[0].id, null);
  const encoded = JSON.stringify(f.checkpoints);
  for (const secret of [key, token, 'whsec_']) assert.ok(!encoded.includes(secret));
  assert.ok(f.calls.every(c => !/payment_intents|refunds$|customers|accounts\//.test(c.url)));
});

test('check-only performs no provider write and does not authorize payments', async () => {
  const f = fixture(), result = await f.run({ checkOnly: true });
  assert.equal(result.status, 'PREREQUISITES_OK');
  assert.equal(result.integratedFlowReady, false);
  assert.ok(f.calls.every(c => c.method === 'GET' || c.url.endsWith('/database/query')));
});

test('report write failure cannot leave a successful precheck or permit a provider mutation', async () => {
  for (const checkOnly of [true, false]) {
    const f = fixture(), result = await f.run({ checkOnly,
      checkpoint: () => { throw new Error('disk unavailable'); } });
    assert.equal(result.status, checkOnly ? 'BLOCKED' : 'CONFIGURATION_REQUIRES_VERIFICATION');
    assert.equal(result.issue, 'REPORT_WRITE_FAILED');
    assert.ok(f.calls.every(c => c.method === 'GET' || c.url.endsWith('/database/query')));
  }
});

for (const [name, override, issue] of [
  ['foreign account', { account: { id: 'acct_other' } }, 'WRONG_STRIPE_ACCOUNT'],
  ['live mode', { balance: { livemode: true } }, 'NOT_TEST_MODE'],
  ['restricted test account', { account: { id: ACCOUNT, charges_enabled: false } }, 'STRIPE_TEST_RESTRICTED'],
  ['unknown capabilities', { account: { id: ACCOUNT, charges_enabled: true, payouts_enabled: true } }, 'STRIPE_TEST_RESTRICTED'],
  ['active cron', { queues: [{ active_crons: 1, refunds: 0, releases: 0 }] }, 'STAGING_NOT_QUIESCENT'],
  ['pending refund', { queues: [{ active_crons: 0, refunds: 1, releases: 0 }] }, 'STAGING_NOT_QUIESCENT'],
  ['missing key', { names: [] }, 'KEY_NOT_CONFIGURED'],
  ['existing signing key', { names: [{ name: 'STRIPE_SECRET_KEY' }, { name: 'STRIPE_PLATFORM_WEBHOOK_SECRET' }] }, 'EXISTING_WEBHOOK_CONFIG'],
  ['changed gateway', { functions: FUNCTIONS.map(slug => ({ slug, status: 'ACTIVE', verify_jwt: true })) }, 'AUTH_MODE_MISMATCH'],
  ['existing target endpoint', { list: { data: [{ id: 'we_existing', url: `https://${PROJECT}.supabase.co/functions/v1/stripe-webhook` }], has_more: false } }, 'EXISTING_WEBHOOK_CONFIG'],
  ['ambiguous pagination', { list: { data: [], has_more: true } }, 'ENDPOINT_LIST_INCOMPLETE'],
]) test(`blocks ${name} before mutation`, async () => {
  const f = fixture(override), result = await f.run();
  assert.equal(result.issue, issue); assert.equal(result.status, 'BLOCKED');
  assert.ok(f.calls.every(c => c.method === 'GET' || c.url.endsWith('/database/query')));
});

for (const options of [{ stripeKey: 'sk_live_no' }, { token: '' }, { runId: 'untrusted/path' }]) {
  test(`invalid credentials/run refuse network ${JSON.stringify(options)}`, async () => {
    const f = fixture(), result = await f.run(options);
    assert.equal(result.status, 'BLOCKED'); assert.equal(f.calls.length, 0);
  });
}

for (const override of [{ createFailure: true }, { secretFailure: true }, { probeFailure: true }, { endpoint: { livemode: true } }]) {
  test(`uncertain configuration is retained without retry or delete ${JSON.stringify(override)}`, async () => {
    const f = fixture(override), result = await f.run();
    assert.equal(result.status, 'CONFIGURATION_REQUIRES_VERIFICATION');
    assert.equal(result.integratedFlowReady, false);
    assert.ok(f.calls.every(c => c.method !== 'DELETE'));
    assert.ok(f.calls.filter(c => c.method === 'POST' && c.url.endsWith('/secrets')).length <= 1);
    assert.ok(!JSON.stringify(result).includes(key));
  });
}

test('endpoint subscriptions match the handlers; probes leave before the first database write', () => {
  const source = readFileSync(new URL('../../supabase/functions/_shared/stripe-webhook-handler.ts', import.meta.url), 'utf8');
  for (const [index, name] of ['PLATFORM_EVENT_TYPES', 'CONNECT_EVENT_TYPES'].entries()) {
    const block = source.match(new RegExp(`const ${name} = new Set\\(\\[([\\s\\S]*?)\\]\\);`))[1];
    const events = [...block.matchAll(/"([a-z_.]+)"/g)].map(match => match[1]);
    assert.deepEqual([...ROUTES[index].events].sort(), events.sort());
  }
  assert.ok(source.indexOf('if (!eventAllowedForSource') < source.indexOf('const testClassification ='));
  assert.ok(source.indexOf('const testClassification =') < source.indexOf('const { data: claimStatus'));
});

test('workflow is manual, staging-locked and reports no credential artifacts', () => {
  const workflow = readFileSync(new URL('../../.github/workflows/configure-stripe-webhooks-staging.yml', import.meta.url), 'utf8');
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /github.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /group: jolene-supabase-staging-writes/);
  assert.doesNotMatch(workflow, /pull_request:|push:|schedule:|secrets\.SUPABASE_ACCESS_TOKEN/);
  assert.match(workflow, /path: configuration-webhooks-staging.json/);
});

const resume = { setupRunId: '123456789', platformEndpointId: 'we_fixture0' };
const timestamp = 1790632800000;
const existing = { id: resume.platformEndpointId, livemode: false,
  url: `https://${PROJECT}.supabase.co/functions/v1/stripe-webhook`, status: 'enabled',
  api_version: API_VERSION, enabled_events: [...ROUTES[0].events, 'transfer.canceled'],
  created: timestamp / 1000 - 3600, metadata: { jolene_project: PROJECT, setup_run: resume.setupRunId } };
const resuming = extra => fixture({ list: { data: [existing], has_more: false }, existing,
  endpoints: [{ enabled_events: existing.enabled_events }], ...extra });

test('only the observed extra platform event is accepted; missing, duplicated and unknown events fail', () => {
  assert.ok(endpointMatches(existing, ROUTES[0]));
  for (const events of [existing.enabled_events.slice(1), [...existing.enabled_events, 'anything.created'],
    [...existing.enabled_events, 'transfer.created'], ['*'], null]) {
    assert.equal(endpointMatches({ ...existing, enabled_events: events }, ROUTES[0]), false);
  }
  assert.equal(endpointMatches({ ...existing, url: `https://${PROJECT}.supabase.co/functions/v1/stripe-connect-webhook`,
    enabled_events: [...ROUTES[1].events, 'transfer.canceled'] }, ROUTES[1]), false);
});

test('explicit recovery replays the original request/key, checks the ID and installs two verified signatures', async () => {
  const f = resuming(), result = await f.run({ runId: '987654321', resume, now: () => timestamp });
  assert.equal(result.status, 'WEBHOOK_SIGNATURES_CONFIGURED');
  assert.equal(result.resumedFromRun, resume.setupRunId);
  assert.equal(result.endpoints[0].id, resume.platformEndpointId);
  assert.equal(result.endpoints[0].replayed, true);
  assert.deepEqual(result.endpoints[0].additionalEvents, ['transfer.canceled']);
  assert.equal(f.calls.filter(c => c.method === 'POST' && c.url === 'https://api.stripe.com/v1/webhook_endpoints').length, 2);
  assert.ok(!JSON.stringify(result).includes('whsec_'));
});

for (const [name, change, issue] of [
  ['foreign metadata', { metadata: { ...existing.metadata, setup_run: '999999999' } }, 'RESUME_MISMATCH'],
  ['foreign project', { metadata: { ...existing.metadata, jolene_project: 'other' } }, 'RESUME_MISMATCH'],
  ['wrong retrieved ID', { id: 'we_other' }, 'RESUME_MISMATCH'],
  ['wrong URL', { url: 'https://other.example.invalid/webhook' }, 'RESUME_MISMATCH'],
  ['expired key', { created: timestamp / 1000 - 23 * 3600 }, 'RESUME_EXPIRED'],
  ['future creation', { created: timestamp / 1000 + 1 }, 'RESUME_EXPIRED'],
  ['missing creation date', { created: null }, 'RESUME_EXPIRED'],
]) test(`recovery refuses ${name} before any provider write`, async () => {
  const f = resuming({ existing: { ...existing, ...change } });
  const result = await f.run({ resume, now: () => timestamp });
  assert.equal(result.issue, issue);
  assert.ok(f.calls.every(c => c.method === 'GET' || c.url.endsWith('/database/query')));
});

for (const data of [[], [{ ...existing, id: 'we_other' }], [existing, { ...existing, id: 'we_duplicate' }]]) {
  test(`recovery requires exactly the expected partial endpoint: ${data.length}`, async () => {
    const f = resuming({ list: { data, has_more: false } });
    const result = await f.run({ resume, now: () => timestamp });
    assert.equal(result.issue, 'RESUME_MISMATCH');
    assert.ok(f.calls.every(c => c.method === 'GET' || c.url.endsWith('/database/query')));
  });
}

test('recovery mismatched replay never creates Connect or stores secrets', async () => {
  const f = resuming({ endpoints: [{ id: 'we_unexpected' }] });
  const result = await f.run({ resume, now: () => timestamp });
  assert.equal(result.issue, 'RESUME_MISMATCH');
  assert.equal(result.endpoints.length, 1);
  assert.equal(result.secretWriteAttempted, false);
});

test('recovery precheck is read-only and incomplete resume inputs make no requests', async () => {
  const f = resuming();
  assert.equal((await f.run({ resume, checkOnly: true, now: () => timestamp })).status, 'PREREQUISITES_OK');
  assert.ok(f.calls.every(c => c.method === 'GET' || c.url.endsWith('/database/query')));
  for (const invalid of [{ setupRunId: '123456789' }, { platformEndpointId: 'we_fixture0' }, { ...resume, setupRunId: '../bad' }]) {
    const bad = fixture();
    assert.equal((await bad.run({ resume: invalid })).issue, 'RESUME_INVALID');
    assert.equal(bad.calls.length, 0);
  }
});
