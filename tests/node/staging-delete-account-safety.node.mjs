import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { createDeletionSafetyGate, PROJECT } from '../../scripts/ci/staging-delete-account-safety.mjs';
import { withPreservedPscCanary } from '../../e2e/helpers/staging-psc-canary.mjs';

const SHA = 'a'.repeat(40), SECRET = 'PRIVATE_MANAGEMENT_CANARY';
const fixture = JSON.parse(readFileSync(new URL('../fixtures/staging-delete-account/safe-v55.json', import.meta.url), 'utf8'));
const query = readFileSync(new URL('../fixtures/staging-delete-account/catalogue.sql', import.meta.url), 'utf8');
const hash = value => createHash('sha256').update(value).digest('hex');
function source() {
  const manifest = structuredClone(fixture);
  const files = new Map(Object.keys(manifest.files).map(path => [path, `// Synthetic ${path}\n`]));
  manifest.files = Object.fromEntries([...files].map(([path, value]) => [path, hash(value)]));
  return { sha: SHA, manifest, files, query };
}
function harness(options = {}) {
  const s = source(), calls = []; let reads = 0;
  const env = { GITHUB_ACTIONS: 'true', GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', GITHUB_JOB: 'comptes',
    GITHUB_EVENT_NAME: 'pull_request', JOLENE_E2E_EXPECTED_SHA: SHA,
    STAGING_SUPABASE_PROJECT_REF: PROJECT, STAGING_SUPABASE_URL: `https://${PROJECT}.supabase.co`,
    STAGING_SUPABASE_ACCESS_TOKEN: SECRET, ...options.env };
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (options.throw) throw new Error(SECRET);
    if (url.endsWith('/functions')) return Response.json([options.metadata?.(++reads, s.manifest.edge) ?? s.manifest.edge]);
    if (url.endsWith('/body')) {
      const rows = [...s.files].map(([name, content]) => ({ name, content }));
      if (options.multipart) {
        const form = new FormData();
        form.set('metadata', JSON.stringify({ deployment_id: 'synthetic' }));
        for (const row of rows) form.append('file', new Blob([row.content]), row.name);
        return new Response(form);
      }
      return Response.json({ files: options.body?.(rows) ?? rows });
    }
    if (url.endsWith('/database/query')) return Response.json([{ catalogue: options.catalogue?.(s.manifest.catalogue) ?? s.manifest.catalogue }]);
    throw new Error('Unexpected request');
  };
  return { calls, run: async () => createDeletionSafetyGate({ env, source: s, fetchImpl })() };
}

test('pins exact Edge, shared files and seven-routine catalogue; only fixed read endpoints', async () => {
  const h = harness(); await h.run(); assert.equal(h.calls.length, 4);
  for (const { url, init } of h.calls) {
    assert.ok(url.startsWith(`https://api.supabase.com/v1/projects/${PROJECT}/`));
    assert.equal(init.redirect, 'error'); assert.ok(init.signal instanceof AbortSignal);
    assert.equal(init.headers.Authorization, `Bearer ${SECRET}`);
    if (init.method === 'POST') assert.deepEqual(JSON.parse(init.body), { query, read_only: true });
    else { assert.equal(init.method, 'GET'); assert.equal(init.body, undefined); }
  }
  assert.doesNotMatch(query, /FROM\s+(?:public\.)?psc_auth_sessions\b/i);
  assert.equal(fixture.catalogue.routines.length, 7);
});

test('old deployment and drift after source read both refuse', async () => {
  for (const at of [1, 2]) {
    const h = harness({ metadata: (n, row) => n === at ? { ...row, version: 54 } : row });
    await assert.rejects(h.run(), /DELETE_ACCOUNT_SAFETY_DEPLOYMENT_DRIFT/);
    assert.equal(h.calls.length, at === 1 ? 1 : 4);
  }
});

test('shared source mismatch, incomplete body, traversal and duplicate source refuse before SQL', async () => {
  for (const body of [rows => rows.map((r, i) => i === 0 ? { ...r, content: 'old global deletion' } : r),
    rows => rows.slice(1), rows => rows.map((r, i) => i === 0 ? { ...r, name: '../outside.ts' } : r),
    rows => [rows[0], rows[0], rows[2], rows[3]]]) {
    const h = harness({ body }); await assert.rejects(h.run(), /DELETE_ACCOUNT_SAFETY_BODY/);
    assert.equal(h.calls.length, 2);
  }
});

test('SQL definition/ACL drift blocks; returned data is never reflected in error', async () => {
  const h = harness({ catalogue: value => ({ ...value, routines: [{ secret: SECRET }] }) });
  await assert.rejects(h.run(), error => error.message === 'DELETE_ACCOUNT_SAFETY_RPC_DRIFT');
});

test('multipart Management response preserves all exact source bytes', async () => {
  await harness({ multipart: true }).run();
});

test('missing secret, wrong project/job/SHA refuse before requests; raw network error is closed', async () => {
  for (const env of [{ STAGING_SUPABASE_ACCESS_TOKEN: '' }, { STAGING_SUPABASE_PROJECT_REF: 'production' },
    { GITHUB_JOB: 'other' }, { GITHUB_ACTIONS: 'false' }, { JOLENE_E2E_EXPECTED_SHA: 'b'.repeat(40) }]) {
    const h = harness({ env }); await assert.rejects(h.run(), /DELETE_ACCOUNT_SAFETY_CONTEXT/);
    assert.equal(h.calls.length, 0);
  }
  await assert.rejects(harness({ throw: true }).run(), error => error.message === 'DELETE_ACCOUNT_SAFETY_READ_REFUSED');
});

function database(options = {}) {
  const rows = new Map([['independent', { state: 'independent', nonce: 'NEVER_READ', expire_le: '2020-01-01' }]]);
  const calls = []; let inserted;
  const admin = { from(table) {
    assert.equal(table, 'psc_auth_sessions');
    return {
      async insert(row) {
        calls.push({ kind: 'insert', row }); inserted = row;
        if (options.conflict) return { error: { code: '23505' } };
        rows.set(row.state, { ...row });
        return { error: options.lostInsert ? { code: '', message: SECRET } : null };
      },
      select() { return { eq(column, state) { assert.equal(column, 'state'); return { async maybeSingle() {
        calls.push({ kind: 'read', state }); assert.notEqual(state, 'independent');
        return { error: null, data: rows.get(state) ?? null };
      } }; } }; },
      delete() { return { match(expected) { calls.push({ kind: 'delete', expected }); return { async select() {
        const current = rows.get(expected.state);
        if (current && Object.keys(expected).every(key => current[key] === expected[key])) {
          rows.delete(expected.state); return { error: null, data: [{ state: expected.state }] };
        }
        return { error: null, data: [] };
      } }; } }; },
    };
  } };
  let uuid = 0;
  return { rows, calls, get inserted() { return inserted; },
    run: (verify, action) => withPreservedPscCanary(admin, verify, action, {
      uuid: () => `00000000-0000-4000-8000-${String(++uuid).padStart(12, '0')}`, now: () => 1_800_000_000_000 }) };
}

test('canary preserved for business action, cleanup full tuple only, independent row untouched', async () => {
  const h = database(); let verified = 0, actions = 0;
  assert.equal(await h.run(async () => { verified++; }, async () => { actions++; return 'result'; }), 'result');
  assert.equal(verified, 2); assert.equal(actions, 1); assert.equal(h.rows.size, 1);
  assert.equal(h.rows.get('independent').nonce, 'NEVER_READ');
  assert.deepEqual(h.calls.find(x => x.kind === 'delete').expected, h.inserted);
  assert.equal(h.calls.filter(x => x.kind === 'insert').length, 1);
});

test('unsafe deployed function blocks before canary or deletion action', async () => {
  const h = database();
  await assert.rejects(h.run(async () => { throw new Error('deployment refused'); }, async () => assert.fail('must not invoke')), /deployment refused/);
  assert.equal(h.calls.length, 0);
});

test('deployment moves after canary preparation: cleanup own row, no business invocation', async () => {
  const h = database(); let n = 0;
  await assert.rejects(h.run(async () => { if (++n === 2) throw new Error('drift'); }, async () => assert.fail('must not invoke')), /drift/);
  assert.equal(h.rows.size, 1);
});

test('global deletion regression is detected without querying any independent session', async () => {
  const h = database();
  await assert.rejects(h.run(async () => {}, async () => { h.rows.clear(); }), /PSC_CANARY_NOT_PRESERVED/);
});

test('lost insertion response: exact cleanup, no replay and no business invocation', async () => {
  const h = database({ lostInsert: true });
  await assert.rejects(h.run(async () => {}, async () => assert.fail('must not invoke')), /PSC_CANARY_INSERT_UNCONFIRMED/);
  assert.equal(h.rows.size, 1); assert.equal(h.calls.filter(x => x.kind === 'insert').length, 1);
});

test('certain duplicate-key refusal confers no ownership, reads or cleanup', async () => {
  const h = database({ conflict: true });
  await assert.rejects(h.run(async () => {}, async () => assert.fail('must not invoke')), /PSC_CANARY_INSERT_UNCONFIRMED/);
  assert.deepEqual(h.calls.map(x => x.kind), ['insert']);
});

test('changed canary tuple is never blindly deleted; cleanup uncertainty remains a failure', async () => {
  const h = database();
  await assert.rejects(h.run(async () => {}, async () => { h.rows.get(h.inserted.state).nonce = 'changed'; }), /PSC_CANARY_CLEANUP_UNCONFIRMED/);
  assert.equal(h.rows.size, 2); assert.equal(h.rows.get(h.inserted.state).nonce, 'changed');
});

test('business error is preserved after own canary cleanup', async () => {
  const h = database();
  await assert.rejects(h.run(async () => {}, async () => { throw new Error('business refusal'); }), /business refusal/);
  assert.equal(h.rows.size, 1);
});
