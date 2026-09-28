import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyFixtureIsolation } from '../../scripts/recette-fournisseurs/verify-finance-fixture-isolation.mjs';

const restored = [{ inscriptions: '0', acteurs: 0 }];
test('aucun appel sans accès staging', async () => {
  const result = await verifyFixtureIsolation({ fetchImpl() { throw new Error('unexpected'); } });
  assert.equal(result.issue, 'TOKEN_MISSING');
});
test('projet fixe, assertions SQL et rollback, puis contrôle distinct', async () => {
  const calls = [];
  const result = await verifyFixtureIsolation({ token: 'fixture-token', fetchImpl: async (url, options) => {
    assert.equal(url, 'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');
    assert.equal(options.redirect, 'error'); assert.equal(options.method, 'POST');
    assert.ok(options.signal instanceof AbortSignal);
    const body = JSON.parse(options.body); calls.push(body);
    return { ok: true, json: async () => body.read_only ? restored : [] };
  } });
  assert.deepEqual(calls.map(c => c.read_only), [true, false, true]);
  assert.match(calls[1].query, /BEGIN ISOLATION LEVEL REPEATABLE READ/);
  assert.match(calls[1].query, /ROLLBACK;\s*$/);
  assert.match(calls[1].query, /Cohorte existante requalifiée/);
  assert.match(calls[1].query, /Droits de publication indus/);
  assert.equal(result.status, 'FIXTURE_ISOLATION_VERIFIED');
  assert.equal(result.integratedFlowReady, false);
  assert.ok(!JSON.stringify(result).includes('fixture-token'));
});
for (const bad of [[], null, [{ inscriptions: '1', acteurs: 0 }], [{ inscriptions: '0', acteurs: 1 }]]) {
  test(`précondition inconnue ou non restaurée : ${JSON.stringify(bad)}`, async () => {
    let calls = 0;
    const result = await verifyFixtureIsolation({ token: 'fixture-token', fetchImpl: async () => {
      calls++; return { ok: true, json: async () => bad };
    } });
    assert.equal(result.issue, 'INITIAL_STATE_INVALID'); assert.equal(calls, 1);
  });
}
for (const failure of ['http', 'network', 'json', 'restoration']) {
  test(`échec ${failure} : aucun retry ni faux succès ni erreur brute`, async () => {
    let calls = 0;
    const result = await verifyFixtureIsolation({ token: 'fixture-token', fetchImpl: async () => {
      calls++;
      if (calls === 1) return { ok: true, json: async () => restored };
      if (failure === 'network') throw new Error('fixture-token');
      if (failure === 'http') return { ok: false };
      if (failure === 'json') return { ok: true, json: async () => { throw new Error('fixture-token'); } };
      return { ok: true, json: async () => calls === 2 ? [] : [{ inscriptions: '0', acteurs: 1 }] };
    } });
    assert.equal(calls, failure === 'restoration' ? 3 : 2);
    assert.equal(result.rollbackConfirmed, false);
    assert.equal(result.integratedFlowReady, false);
    assert.ok(!JSON.stringify(result).includes('fixture-token'));
  });
}
