import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { assertCandidate, assertHarnessCleanupReady, cleanupWebhooks, createWebhooks, RECETTE_REF, PROD_REF, CLEANUP_BLOCKER } from '../../scripts/lib/recette-escrow-safety.mjs';
import { preflight } from '../../scripts/recette-escrow-preflight.mjs';

const sha = 'a'.repeat(40);
const branch = { project_ref: RECETTE_REF, parent_project_ref: PROD_REF, is_default: false, with_data: false, status: 'FUNCTIONS_DEPLOYED', preview_project_status: 'ACTIVE_HEALTHY' };
const base = { branchRef: RECETTE_REF, actualSha: sha, expectedSha: sha, branches: [branch], expectedMigrations: ['20260101000000', '20260927152738'], appliedMigrations: ['20260101000000', '20260927152738'] };

test('candidate matches the exact checkout and migration registry', () => assert.doesNotThrow(() => assertCandidate(base)));
for (const [name, override, reason] of [
  ['production', { branchRef: PROD_REF }, /CIBLE_REFUSEE/],
  ['shared staging', { branchRef: 'mejpriaetwgtcstbgfid' }, /CIBLE_REFUSEE/],
  ['arbitrary branch', { branchRef: 'x'.repeat(20) }, /CIBLE_REFUSEE/],
  ['different SHA', { actualSha: 'b'.repeat(40) }, /SHA_INCOMPATIBLE/],
  ['missing requested SHA', { expectedSha: '' }, /SHA_INCOMPATIBLE/],
  ['historical schema', { appliedMigrations: ['20260711193000'] }, /SCHEMA_INCOMPATIBLE/],
  ['extra migration', { appliedMigrations: [...base.appliedMigrations, '20261001000000'] }, /SCHEMA_INCOMPATIBLE/],
  ['missing branch', { branches: [] }, /BRANCHE_NON_PRETE/],
  ...Object.entries({ status: 'MIGRATIONS_FAILED', is_default: true, with_data: true, parent_project_ref: 'x'.repeat(20), preview_project_status: 'INACTIVE' })
    .map(([key, value]) => [key, { branches: [{ ...branch, [key]: value }] }, /BRANCHE_NON_PRETE/]),
]) {
  test(`prevents ${name} before any write`, () => assert.throws(() => assertCandidate({ ...base, ...override }), reason));
}

function fakePreflight(scenario = {}) {
  const requests = [];
  const fetchImpl = async (url, init) => {
    requests.push({ url, method: init.method || 'GET' });
    if (scenario.httpFailure) return new Response('hidden secret response', { status: 503 });
    if (url.endsWith('/branches')) return Response.json([branch]);
    if (url.endsWith('/database/query')) {
      assert.equal(init.method, 'POST');
      assert.equal(JSON.parse(init.body).query, 'SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;');
      return Response.json((scenario.versions || base.appliedMigrations).map((version) => ({ version })));
    }
    if (url === 'https://api.stripe.com/v1/balance') return Response.json({ livemode: scenario.live ?? false });
    throw new Error('Unexpected network request');
  };
  return { requests, promise: preflight({ ...base, token: 'management-fixture', stripeKey: 'sk_test_fixture', fetchImpl }) };
}

test('even a healthy matching branch remains blocked while legacy cleanup is missing', async () => {
  const { requests, promise } = fakePreflight();
  await assert.rejects(promise, /RECETTE_BLOQUEE/);
  assert.equal(requests.length, 3);
  assert.throws(assertHarnessCleanupReady, /bearer Vault/);
});
test('legacy SQL entry point refuses before transport, even with fake production credentials and old force flag', () => {
  // Node 24 strips TypeScript natively. Stub only the external client import,
  // so this proof also runs before npm ci and cannot contact a real backend.
  const transportTrap = `import { registerHooks } from 'node:module';
  const clientTrap = "export function createClient() { throw new Error('RECETTE_CLIENT_CREATED'); }";
  registerHooks({ resolve(specifier, context, nextResolve) {
    if (specifier === '@supabase/supabase-js') return {
      shortCircuit: true, url: 'data:text/javascript,' + encodeURIComponent(clientTrap),
    };
    return nextResolve(specifier, context);
  }});
  globalThis.fetch = () => {
    process.stderr.write('RECETTE_NETWORK_CALLED\\n');
    throw new Error('No network allowed');
  };`;
  const child = spawnSync(process.execPath, [
    '--import', `data:text/javascript,${encodeURIComponent(transportTrap)}`,
    'scripts/recette-escrow.ts',
  ], {
    cwd: fileURLToPath(new URL('../../', import.meta.url)),
    env: {
      SUPABASE_URL: `https://${PROD_REF}.supabase.co`,
      SUPABASE_SERVICE_ROLE_KEY: 'service-role-fixture-not-a-secret',
      RECETTE_ETAB_ID: 'e2e00000-0000-4000-8000-0000000000e7',
      RECETTE_SOIGNANT_ID: 'e2e00000-0000-4000-8000-000000000001',
      RECETTE_FORCE_PROD: '1',
    },
    encoding: 'utf8', timeout: 15_000,
  });
  assert.ifError(child.error);
  assert.equal(child.signal, null);
  assert.equal(child.status, 1);
  assert.equal(child.stderr.split('\n').find(line => line.startsWith('Error: ')), `Error: ${CLEANUP_BLOCKER}`);
  assert.doesNotMatch(child.stderr, /RECETTE_NETWORK_CALLED|RECETTE_CLIENT_CREATED/);
  assert.equal(child.stdout, '');
});
test('old SQL schema fails before the Stripe balance request', async () => {
  const { requests, promise } = fakePreflight({ versions: ['20260711193000'] });
  await assert.rejects(promise, /SCHEMA_INCOMPATIBLE/);
  assert.equal(requests.length, 2);
});
test('live balance is refused', async () => await assert.rejects(fakePreflight({ live: true }).promise, /STRIPE_LIVE_INTERDIT/));
test('HTTP failures fail closed without echoing provider response bodies', async () => {
  await assert.rejects(fakePreflight({ httpFailure: true }).promise, (error) => error.message.includes('HTTP_503') && !error.message.includes('hidden secret'));
});
test('invalid key never reaches the transport', async () => {
  await assert.rejects(preflight({ ...base, token: 'fixture', stripeKey: 'sk_live_fixture', fetchImpl: () => assert.fail('No network allowed') }), /SECRETS_TEST_REQUIS/);
});

function webhooks(scenario = {}) {
  const calls = [], saved = [], objects = new Map();
  const api = async (method, resource, params, idempotencyKey) => {
    calls.push({ method, resource });
    if (method === 'POST') {
      const number = objects.size + 1;
      if (number === 2) {
        assert.equal(saved.at(-1).webhooks.length, 1, 'first ID must be persisted before second request');
        if (scenario.secondFails) throw new Error('STRIPE_HTTP_503');
      }
      assert.match(idempotencyKey, /^recette-escrow-123-1-(platform|connect)$/);
      const object = { ...params, id: `we_${number}`, livemode: false, secret: `whsec_fixture${number}` };
      objects.set(object.id, object);
      return object;
    }
    const id = resource.split('/')[1];
    if (method === 'GET') {
      if (scenario.readFails) throw new Error('STRIPE_HTTP_503');
      const object = objects.get(id);
      return scenario.foreignOwner ? { ...object, description: 'other-run' } : object;
    }
    if (method === 'DELETE') {
      if (scenario.deleteFails) throw new Error('STRIPE_HTTP_503');
      return { id, deleted: !scenario.deleteUnconfirmed };
    }
    assert.fail(`Unexpected method: ${method}`);
  };
  const save = async (manifest) => {
    const json = JSON.stringify(manifest);
    assert.doesNotMatch(json, /whsec_|sk_test_|management-fixture/);
    saved.push(JSON.parse(json));
  };
  return { api, save, calls, saved, objects, create: () => createWebhooks({ api, save, branchRef: RECETTE_REF, runId: '123-1' }) };
}

test('second creation failure cleans the first endpoint, with a durable secret-free manifest', async () => {
  const f = webhooks({ secondFails: true });
  await assert.rejects(f.create(), /HTTP_503/);
  assert.deepEqual(f.calls.map((x) => x.method), ['POST', 'POST', 'GET', 'DELETE']);
  assert.equal(f.saved.at(-1).webhooks[0].deleted, true);
});
test('two created endpoints are owned, deleted and confirmed; repeat cleanup does not delete again', async () => {
  const f = webhooks();
  const { manifest } = await f.create();
  await cleanupWebhooks({ ...f, manifest });
  assert.equal(manifest.webhooks.filter((entry) => entry.deleted).length, 2);
  const callCount = f.calls.length;
  await cleanupWebhooks({ ...f, manifest });
  assert.equal(f.calls.length, callCount);
});
for (const scenario of ['readFails', 'deleteFails', 'deleteUnconfirmed', 'foreignOwner']) {
  test(`cleanup reports ${scenario} and never marks deletions as confirmed`, async () => {
    const f = webhooks({ [scenario]: true });
    const { manifest } = await f.create();
    await assert.rejects(cleanupWebhooks({ ...f, manifest }), /NETTOYAGE_WEBHOOK_INCOMPLET/);
    assert.ok(manifest.webhooks.every((entry) => !entry.deleted));
    assert.equal(f.calls.filter((call) => call.method === 'DELETE').length, ['readFails', 'foreignOwner'].includes(scenario) ? 0 : 2);
  });
}
test('cleanup failure after partial creation remains a failure, with the remaining endpoint in the manifest', async () => {
  const f = webhooks({ secondFails: true, deleteFails: true });
  await assert.rejects(f.create(), /NETTOYAGE_WEBHOOK_INCOMPLET/);
  assert.equal(f.saved.at(-1).webhooks.length, 1);
  assert.equal(f.saved.at(-1).webhooks[0].deleted, false);
});
