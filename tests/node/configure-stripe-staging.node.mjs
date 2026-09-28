import test from 'node:test';
import assert from 'node:assert/strict';
import { configureStripeTest, PROJECT, ACCOUNT, FUNCTIONS } from '../../scripts/recette-fournisseurs/configure-stripe-test.mjs';

const token = 'management-test-fixture';
const stripeKey = 'sk_test_fixtureOnly123';
function fixture(overrides = {}) {
  const calls = [];
  let written = false;
  const fetchImpl = async (url, options) => {
    calls.push({ url, ...options });
    assert.equal(options.redirect, 'error');
    const response = value => ({ ok: true, json: async () => value });
    if (url === 'https://api.stripe.com/v1/account') return response(overrides.account ?? { id: ACCOUNT });
    if (url === 'https://api.stripe.com/v1/balance') return response(overrides.balance ?? { livemode: false });
    assert.ok(url.startsWith(`https://api.supabase.com/v1/projects/${PROJECT}/`));
    assert.equal(options.headers.Authorization, `Bearer ${token}`);
    if (url.endsWith('/functions')) return response(overrides.functions ?? FUNCTIONS.map(slug => ({ slug, status: 'ACTIVE', verify_jwt: false })));
    if (url.endsWith('/database/query')) {
      assert.equal(JSON.parse(options.body).read_only, true);
      return response(overrides.queues ?? [{ active_crons: 0, releases: 0, refunds: 0 }]);
    }
    assert.ok(url.endsWith('/secrets'));
    if (options.method === 'POST') {
      written = true;
      if (overrides.writeError) throw new Error(`provider echoed ${stripeKey}`);
      if (overrides.writeRejected) return { ok: false, json: async () => { throw new Error('must not read error body'); } };
      return response({});
    }
    return response(written ? overrides.after ?? [{ name: 'STRIPE_SECRET_KEY', value: 'not-for-report' }]
      : overrides.before ?? [{ name: 'UNRELATED_KEY', value: 'not-for-report' }]);
  };
  return { calls, run: args => configureStripeTest({ token, stripeKey, fetchImpl, ...args }) };
}

test('installs only the existing test key in fixed staging; does not certify transports', async () => {
  const f = fixture(); const report = await f.run();
  assert.equal(report.status, 'KEY_CONFIGURED_ONLY');
  assert.equal(report.secretWriteAccepted, true);
  assert.equal(report.secretPresent, true);
  assert.equal(report.readyForTransports, false);
  assert.equal(report.integratedFlowReady, false);
  const writes = f.calls.filter(call => call.url.endsWith('/secrets') && call.method === 'POST');
  assert.equal(writes.length, 1);
  assert.deepEqual(JSON.parse(writes[0].body), [{ name: 'STRIPE_SECRET_KEY', value: stripeKey }]);
  assert.ok(!JSON.stringify(report).includes(stripeKey));
  assert.ok(!JSON.stringify(report).includes(token));
  assert.ok(!JSON.stringify(report).includes('not-for-report'));
  assert.ok(f.calls.every(call => !call.url.includes('webhook_endpoints') && !call.url.includes('payment_intents')));
});

test('precheck runs all guards without installing a key', async () => {
  const f = fixture(); const report = await f.run({ checkOnly: true });
  assert.equal(report.status, 'PREREQUISITES_OK');
  assert.equal(report.secretWriteAttempted, false);
  assert.equal(report.readyForTransports, false);
  assert.equal(f.calls.filter(call => call.method === 'POST' && call.url.endsWith('/secrets')).length, 0);
  const blocked = fixture({ queues: [{ active_crons: 1, releases: 0, refunds: 0 }] });
  assert.equal((await blocked.run({ checkOnly: true })).status, 'BLOCKED');
});

for (const [title, args, code] of [
  ['no token', { token: '' }, 'STAGING_TOKEN_MISSING'],
  ['live key', { stripeKey: 'sk_live_wrong' }, 'TEST_KEY_REQUIRED'],
  ['malformed key', { stripeKey: 'sk_test_bad\nvalue' }, 'TEST_KEY_REQUIRED'],
]) test(`blocks ${title} before network`, async () => {
  const f = fixture(); const report = await f.run(args);
  assert.equal(report.issue, code); assert.equal(f.calls.length, 0);
});

for (const [title, overrides, code] of [
  ['another account', { account: { id: 'acct_foreign' } }, 'STRIPE_ACCOUNT_MISMATCH'],
  ['live balance', { balance: { livemode: true } }, 'STRIPE_TEST_MODE_UNCONFIRMED'],
  ['unknown mode', { balance: {} }, 'STRIPE_TEST_MODE_UNCONFIRMED'],
  ['active cron', { queues: [{ active_crons: 1, releases: 0, refunds: 0 }] }, 'STAGING_NOT_QUIESCENT'],
  ['pending release', { queues: [{ active_crons: 0, releases: 1, refunds: 0 }] }, 'STAGING_NOT_QUIESCENT'],
  ['pending refund', { queues: [{ active_crons: 0, releases: 0, refunds: 1 }] }, 'STAGING_NOT_QUIESCENT'],
  ['unknown queues', { queues: [] }, 'STAGING_NOT_QUIESCENT'],
  ['existing key', { before: [{ name: 'STRIPE_SECRET_KEY' }] }, 'EXISTING_KEY_REQUIRES_VERIFICATION'],
  ['platform webhook', { before: [{ name: 'STRIPE_PLATFORM_WEBHOOK_SECRET' }] }, 'WEBHOOKS_ALREADY_CONFIGURED'],
  ['default webhook', { before: [{ name: 'STRIPE_WEBHOOK_SECRET' }] }, 'WEBHOOKS_ALREADY_CONFIGURED'],
  ['connect webhook', { before: [{ name: 'STRIPE_CONNECT_WEBHOOK_SECRET' }] }, 'WEBHOOKS_ALREADY_CONFIGURED'],
  ['malformed secrets', { before: [{}] }, 'INVALID_SECRET_METADATA'],
  ['missing function metadata', { functions: [] }, 'EXISTING_FUNCTION_AUTH_MODE_MISMATCH'],
  ['different gateway authentication', { functions: FUNCTIONS.map(slug => ({ slug, status: 'ACTIVE', verify_jwt: true })) }, 'EXISTING_FUNCTION_AUTH_MODE_MISMATCH'],
]) test(`blocks ${title} without any secret write`, async () => {
  const f = fixture(overrides); const report = await f.run();
  assert.equal(report.status, 'BLOCKED'); assert.equal(report.issue, code);
  assert.equal(report.secretWriteAttempted, false);
  assert.equal(f.calls.filter(call => call.method === 'POST' && call.url.endsWith('/secrets')).length, 0);
});

for (const overrides of [{ writeError: true }, { writeRejected: true }, { after: [] }]) {
  test(`uncertain write is not retried or deleted: ${JSON.stringify(overrides)}`, async () => {
    const f = fixture(overrides); const report = await f.run();
    assert.equal(report.status, 'WRITE_REQUIRES_VERIFICATION');
    assert.equal(report.readyForTransports, false);
    assert.equal(f.calls.filter(call => call.method === 'POST' && call.url.endsWith('/secrets')).length, 1);
    assert.ok(f.calls.every(call => call.method !== 'DELETE'));
    assert.ok(!JSON.stringify(report).includes(stripeKey));
  });
}
