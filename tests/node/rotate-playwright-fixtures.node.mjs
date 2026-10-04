import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { FIXTURES, requireFixturePassword } from '../../scripts/lib/playwright-fixtures.mjs';
import { rotateFixtures, assertExecutionContext } from '../../scripts/ci/rotate-playwright-fixtures.mjs';

const ids = ['00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002'];
const password = 'a'.repeat(64); // Purely synthetic, never a configured secret.
const confirmation = 'ROTATE_ONLY_PLAYWRIGHT_FIXTURES';
const canary = 'PRIVATE_CANARY_MUST_NOT_APPEAR';

function fake(overrides = {}) {
  const calls = [];
  const fixtures = Object.values(FIXTURES);
  const admin = {
    rpc: async (name, args) => {
      calls.push({ name, args });
      if (name === 'fn_admin_get_user_id_by_email') {
        const index = fixtures.findIndex((f) => f.email === args.p_email);
        return { data: overrides.duplicate ? ids[0] : ids[index], error: null };
      }
      assert.equal(name, 'fn_test_nettoyer_sessions_playwright');
      assert.deepEqual(args, { p_anciennete: '0 seconds' });
      return overrides.purgeError ? { error: { message: canary } }
        : { data: { sessions_supprimees: overrides.neverEmpty ? 1000 : 0,
          refresh_tokens_supprimes: 0, limite_par_passage: 1000 }, error: null };
    },
    auth: { admin: {
      getUserById: async (id) => {
        calls.push({ name: 'inspect-auth' });
        const fixture = fixtures[ids.indexOf(id)];
        return { data: { user: { id, email: overrides.email || fixture.email,
          app_metadata: { role: overrides.role || fixture.role },
          user_metadata: { role: overrides.userRole || fixture.role }, deleted_at: overrides.deleted } }, error: null };
      },
      updateUserById: async (id, data) => {
        calls.push({ name: 'update', id });
        assert.deepEqual(data, { password });
        if (overrides.failSecond && id === ids[1]) return { error: { message: canary } };
        return { data: { user: { id } }, error: null };
      },
    } },
    from: (table) => {
      let id;
      const chain = {
        select: () => chain,
        eq: (column, value) => { if (column === 'id' || column === 'user_id') id = value; return chain; },
        maybeSingle: async () => ({ data: { id, est_compte_test: overrides.testMarker !== false }, error: null }),
        limit: async () => ({ data: overrides.platform ? [{ user_id: id }] : [], error: null }),
        then: (resolve, reject) => Promise.resolve({ data: overrides.nonTestMembership ? [{ etablissements: { est_compte_test: false } }] : [], error: null }).then(resolve, reject),
      };
      if (overrides.readError) chain.maybeSingle = async () => { throw new Error(canary); };
      return chain;
    },
  };
  return { admin, calls };
}

const readSessionCounts = async () => ({ target_count: 2, sessions_count: 0, unrevoked_refresh_count: 0 });

test('private password has no permissive missing/short/fallback path', () => {
  for (const invalid of [undefined, '', 'public-password', 'a'.repeat(63), 'g'.repeat(64), true]) {
    assert.throws(() => requireFixturePassword(invalid), /PRIVATE_SECRET_REQUIRED/);
  }
  assert.equal(requireFixturePassword(password), password);
});

test('two complete preflights precede two exact password-only updates and bounded purge', async () => {
  const { admin, calls } = fake();
  const receipt = await rotateFixtures({ admin, password, confirmation, readSessionCounts });
  assert.equal(receipt.completed, true);
  assert.equal(receipt.rotatedCount, 2);
  const firstUpdate = calls.findIndex((c) => c.name === 'update');
  assert.equal(calls.slice(0, firstUpdate).filter((c) => c.name === 'inspect-auth').length, 2);
  assert.deepEqual(calls.filter((c) => c.name === 'update').map((c) => c.id), ids);
  const json = JSON.stringify(receipt);
  for (const forbidden of [password, canary, ...ids, ...Object.values(FIXTURES).map((f) => f.email)]) assert.equal(json.includes(forbidden), false);
});

for (const [name, overrides] of Object.entries({
  'unexpected auth role': { role: 'ADMIN_PLATEFORME' },
  'user metadata admin': { userRole: 'ADMIN_PLATEFORME' },
  'non-test profile': { testMarker: false },
  'platform membership even inactive': { platform: true },
  'non-test establishment membership': { nonTestMembership: true },
  'identity mismatch': { email: 'synthetic-unexpected.invalid' },
  'deleted user': { deleted: '2020-01-01' },
  'duplicate identity': { duplicate: true },
  'provider read failure': { readError: true },
})) test(`${name}: zero writes and no raw diagnostic`, async () => {
  const { admin, calls } = fake(overrides);
  const receipt = await rotateFixtures({ admin, password, confirmation, readSessionCounts });
  assert.equal(receipt.completed, false);
  assert.equal(receipt.failureStage, 'preflight');
  assert.equal(calls.some((c) => c.name === 'update' || c.name === 'fn_test_nettoyer_sessions_playwright'), false);
  assert.equal(JSON.stringify(receipt).includes(canary), false);
});

test('missing explicit confirmation: no read or write', async () => {
  const { admin, calls } = fake();
  const receipt = await rotateFixtures({ admin, password, confirmation: '', readSessionCounts });
  assert.equal(receipt.failureStage, 'configuration'); assert.equal(calls.length, 0);
});
test('missing secret: no read or write', async () => {
  const { admin, calls } = fake();
  const receipt = await rotateFixtures({ admin, password: '', confirmation, readSessionCounts });
  assert.equal(receipt.failureStage, 'configuration'); assert.equal(calls.length, 0);
});
test('partial rotation is not reported as success and no secrets leak', async () => {
  const { admin } = fake({ failSecond: true });
  const receipt = await rotateFixtures({ admin, password, confirmation, readSessionCounts });
  assert.equal(receipt.completed, false); assert.equal(receipt.rotatedCount, 1);
  assert.equal(receipt.failureStage, 'rotation'); assert.equal(JSON.stringify(receipt).includes(canary), false);
});
test('failed purge cannot be called completed', async () => {
  const { admin } = fake({ purgeError: true });
  const receipt = await rotateFixtures({ admin, password, confirmation, readSessionCounts });
  assert.equal(receipt.completed, false); assert.equal(receipt.failureStage, 'session-revocation');
});
test('remaining refresh token prevents completion', async () => {
  const { admin } = fake();
  const receipt = await rotateFixtures({ admin, password, confirmation,
    readSessionCounts: async () => ({ target_count: 2, sessions_count: 0, unrevoked_refresh_count: 1 }) });
  assert.equal(receipt.completed, false); assert.equal(receipt.failureStage, 'readback');
});
test('purge is bounded to ten calls even when sessions keep arriving', async () => {
  const { admin } = fake({ neverEmpty: true });
  const receipt = await rotateFixtures({ admin, password, confirmation,
    readSessionCounts: async () => ({ target_count: 2, sessions_count: 1, unrevoked_refresh_count: 1 }) });
  assert.equal(receipt.completed, false); assert.equal(receipt.purgePasses, 10);
});

test('maintenance only accepts reviewed exact source in manual trusted refs', () => {
  const valid = { eventName: 'workflow_dispatch', ref: 'refs/heads/fix/identifiants-recette-prives-20261004',
    sha: 'b'.repeat(40), expectedSha: 'b'.repeat(40), checkoutSha: 'b'.repeat(40) };
  assert.doesNotThrow(() => assertExecutionContext(valid));
  assert.doesNotThrow(() => assertExecutionContext({ ...valid, ref: 'refs/heads/main' }));
  for (const patch of [{ eventName: 'pull_request' }, { ref: 'refs/heads/unreviewed' },
    { ref: 'refs/tags/main' }, { expectedSha: '' }, { expectedSha: 'b'.repeat(8) },
    { sha: 'c'.repeat(40) }, { checkoutSha: 'c'.repeat(40) }]) {
    assert.throws(() => assertExecutionContext({ ...valid, ...patch }), /REVIEWED_SOURCE_REQUIRED/);
  }
});

test('actual SDK transport failure cannot print raw diagnostic; unsafe witness does', () => {
  const require = createRequire(import.meta.url);
  const sdkPath = require.resolve('@supabase/supabase-js');
  const modulePath = new URL('../../scripts/ci/rotate-playwright-fixtures.mjs', import.meta.url).href;
  const code = (safe) => `
    import { createRequire } from 'node:module';
    import { closedTransport } from ${JSON.stringify(modulePath)};
    const { createClient } = createRequire(import.meta.url)(${JSON.stringify(sdkPath)});
    const transport = async () => { throw new Error(${JSON.stringify(canary)}); };
    const client = createClient('https://synthetic.invalid', 'synthetic-key', {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch: ${safe ? 'closedTransport(transport)' : 'transport'} }
    });
    const { error } = await client.auth.admin.getUserById(${JSON.stringify(ids[0])});
    if (!error) process.exitCode = 1;
  `;
  for (const safe of [false, true]) {
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', code(safe)], { encoding: 'utf8' });
    assert.equal(result.status, 0);
    assert.equal((result.stdout + result.stderr).includes(canary), !safe);
    if (safe) assert.equal(result.stderr.includes('FIXTURE_TRANSPORT_FAILED'), true);
  }
});
