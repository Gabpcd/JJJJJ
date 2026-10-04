import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { projectCohort } from '../../scripts/ci/plan-temporary-playwright-fixtures.mjs';
import { assertContext, readQuery, reviewReferences, assertFullSnapshot, banDuration, assertBan,
  revokeQuery, confine, closedRequest, BAN_EXPIRES_AT, CONFIRMATION, COHORT_SHA, MAX_OPERATION_MS } from '../../scripts/ci/confine-temporary-playwright-fixtures.mjs';

const NOW = Date.parse('2026-10-04T15:00:00Z');
const created = '2026-10-03T12:00:00.123Z';
function fixtureRows() {
  return Array.from({ length: 1088 }, (_, i) => {
    const s = i < 377, e = i >= 377 && i < 770;
    return { id: `00000000-0000-4000-8000-${(i + 1).toString(16).padStart(12, '0')}`,
      email: `playwright-test-${e ? 'etab' : 'soignant'}-${Date.parse(created)}-${i.toString(36)}@jolene.app`,
      created_at: created, app_role: s ? 'SOIGNANT' : e ? 'ADMIN_ETABLISSEMENT' : null,
      user_admin: false, soignant_profile: s, soignant_test: s, etab_profile: e, etab_test: e,
      platform_member: false, non_test_member: false, auth_deleted: false, banned_until: null,
      sessions_count: 1, refresh_count: 1 };
  });
}
function proof(references = []) {
  return JSON.stringify({ schema: 1, source: 'canonical-review-reference-inventory', repository: 'Gabpcd/JJJJJ',
    complete: true, githubMetadataChecked: true, storeReferenceChecked: true,
    checkedAt: new Date(NOW - 1000).toISOString(), noReferencesExplicit: references.length === 0, references });
}
function harness() {
  const rows = fixtureRows();
  const digest = projectCohort(rows).cohortSha256;
  const events = [], passwords = new Set();
  let n = 0;
  const h = { rows, digest, events, passwords,
    input: { now: () => NOW, confirmation: CONFIRMATION, reviewProof: proof(), digest,
      random: () => (++n).toString(16).padStart(64, '0'),
      drain: async () => { events.push('drain'); },
      read: async (ids) => { events.push(ids === null ? 'read-all' : `read-${ids.length}`);
        return { rows: structuredClone(ids ? rows.filter((r) => ids.includes(r.id)) : rows), cohort_sha256: digest }; },
      update: async (id, attributes) => { events.push('update');
        assert.deepEqual(Object.keys(attributes).sort(), ['ban_duration', 'password']);
        assert.match(attributes.password, /^[a-f0-9]{64}$/); assert.equal(passwords.has(attributes.password), false);
        passwords.add(attributes.password);
        const row = rows.find((r) => r.id === id); assert.ok(row);
        row.banned_until = new Date(NOW + Number.parseInt(attributes.ban_duration) * 1000).toISOString();
        return { id, banned_until: row.banned_until }; },
      revoke: async (ids) => { events.push('revoke'); assert.equal(ids.length, 1088);
        for (const row of rows) { row.sessions_count = 0; row.refresh_count = 0; }
        return { guard_passed: true, refresh_revoked: 1088, sessions_removed: 1088 }; } } };
  return h;
}

test('1088 synthetic targets: two full preflights, individual secrets, exact ban, UUID readback and zero sessions', async () => {
  const h = harness(); const r = await confine(h.input);
  assert.equal(r.completed, true); assert.equal(r.preflights, 2); assert.equal(r.sqlAndNodeDigestEqual, true);
  assert.equal(r.reviewIntersectionEmpty, true); assert.equal(r.authUpdated, 1088);
  assert.equal(r.verifiedBannedCount, 1088); assert.equal(r.remainingSessions, 0); assert.equal(r.remainingUnrevokedRefresh, 0);
  assert.equal(h.passwords.size, 1088); assert.equal(r.businessRowsDeleted, 0);
  assert.deepEqual(h.events.slice(0, 6), ['drain', 'read-all', 'drain', 'read-1088', 'read-1', 'update']);
  assert.deepEqual(h.events.slice(-3), ['read-1088', 'revoke', 'read-1088']);
  assert.equal(JSON.stringify(r).includes(h.rows[0].id), false);
  assert.equal(JSON.stringify(r).includes(h.rows[0].email), false);
  assert.equal([...h.passwords].some((p) => JSON.stringify(r).includes(p)), false);
});

test('unverified/missing/expired or intersecting Review inventory prevents every Auth write', async () => {
  for (const variant of [undefined, '{}', proof([fixtureRows()[0].id]), proof([fixtureRows()[0].email]),
    JSON.stringify({ ...JSON.parse(proof()), storeReferenceChecked: false }),
    JSON.stringify({ ...JSON.parse(proof()), checkedAt: '2026-10-01T00:00:00Z' })]) {
    const h = harness(); h.input.reviewProof = variant; const r = await confine(h.input);
    assert.equal(r.completed, false); assert.equal(h.passwords.size, 0); assert.equal(h.events.includes('revoke'), false);
  }
});

test('empty Review references require explicit complete canonical proof', () => {
  assert.deepEqual(reviewReferences(proof(), NOW), []);
  for (const patch of [{ noReferencesExplicit: false }, { complete: false }, { githubMetadataChecked: false },
    { references: null }, { source: 'email-regex-inference' }, { checkedAt: new Date(NOW + 1).toISOString() }]) {
    assert.throws(() => reviewReferences(JSON.stringify({ ...JSON.parse(proof()), ...patch }), NOW));
  }
});

test('CI activity and incorrect confirmation prevent all writes', async () => {
  for (const variant of ['busy', 'confirmation']) {
    const h = harness(); if (variant === 'busy') h.input.drain = async () => { throw Error('synthetic'); };
    else h.input.confirmation = 'wrong';
    const r = await confine(h.input); assert.equal(r.completed, false); assert.equal(h.passwords.size, 0);
  }
});

test('SQL/Node digest disagreement and second preflight drift prevent every write', async () => {
  for (const variant of ['sql', 'second']) {
    const h = harness(), read = h.input.read; let count = 0;
    h.input.read = async (ids) => { const s = await read(ids); count++;
      if (variant === 'sql') s.cohort_sha256 = COHORT_SHA;
      if (variant === 'second' && count === 2) s.rows[0].non_test_member = true;
      return s; };
    const r = await confine(h.input); assert.equal(r.completed, false); assert.equal(h.passwords.size, 0);
  }
});

test('fixed target disappears or becomes admin immediately before Auth: refusal', async () => {
  for (const variant of ['gone', 'admin']) {
    const h = harness(), read = h.input.read;
    h.input.read = async (ids) => { const s = await read(ids); if (ids?.length === 1) {
      if (variant === 'gone') s.rows = []; else s.rows[0].platform_member = true;
    } return s; };
    const r = await confine(h.input); assert.equal(r.completed, false); assert.equal(h.passwords.size, 0);
  }
});

test('post-Auth identity drift produces partial non-green receipt and no next target', async () => {
  const h = harness(), update = h.input.update;
  h.input.update = async (...args) => { const r = await update(...args); h.rows[0].app_role = 'ADMIN_PLATEFORME'; return r; };
  const r = await confine(h.input); assert.equal(r.completed, false); assert.equal(r.authUpdated, 1);
  assert.equal(h.passwords.size, 1); assert.equal(h.events.includes('revoke'), false);
});

test('second Auth transport failure preserves partial progress without canary', async () => {
  const h = harness(), update = h.input.update; let count = 0;
  h.input.update = async (...args) => { if (++count === 2) throw Error('PRIVATE_SYNTHETIC_CANARY'); return update(...args); };
  const r = await confine(h.input); assert.equal(r.completed, false); assert.equal(r.authUpdated, 1);
  assert.equal(JSON.stringify(r).includes('PRIVATE_SYNTHETIC_CANARY'), false);
  assert.equal(h.events.includes('revoke'), false);
});

test('duplicate generated secret refuses before second Auth update', async () => {
  const h = harness(); h.input.random = () => 'a'.repeat(64);
  const r = await confine(h.input); assert.equal(r.completed, false); assert.equal(r.authUpdated, 1);
});

test('operation time budget stops with closed partial result before runner timeout', async () => {
  const h = harness(), update = h.input.update; let clock = NOW;
  h.input.now = () => clock;
  h.input.update = async (...args) => { const result = await update(...args); clock = NOW + MAX_OPERATION_MS + 1; return result; };
  const r = await confine(h.input); assert.equal(r.completed, false); assert.equal(r.authUpdated, 1);
  assert.equal(h.passwords.size, 1); assert.equal(h.events.includes('revoke'), false);
});

test('bounded progress checkpoints are closed non-green snapshots, never raw identities or secrets', async () => {
  const h = harness(), checkpoints = []; h.input.checkpoint = (r) => checkpoints.push(r);
  const r = await confine(h.input); assert.equal(r.completed, true); assert.equal(checkpoints.length, 44);
  assert.equal(checkpoints[0].authUpdated, 0); assert.equal(checkpoints.at(-1).authUpdated, 1075);
  assert.equal(checkpoints.every((c) => c.completed === false), true);
  const bytes = JSON.stringify(checkpoints);
  assert.equal(bytes.includes(h.rows[0].id), false); assert.equal(bytes.includes(h.rows[0].email), false);
  assert.equal([...h.passwords].some((p) => bytes.includes(p)), false);
});

test('wrong returned ban expiry is never accepted', async () => {
  const h = harness(), update = h.input.update;
  h.input.update = async (...args) => ({ ...await update(...args), banned_until: '2026-10-05T00:00:00Z' });
  const r = await confine(h.input); assert.equal(r.completed, false); assert.equal(h.passwords.size, 1);
  assert.equal(h.events.includes('revoke'), false);
});

test('revocation guard failure and remaining sessions/refresh prevent completion', async () => {
  for (const variant of ['guard', 'sessions', 'refresh']) {
    const h = harness(), revoke = h.input.revoke;
    h.input.revoke = async (ids) => { const r = await revoke(ids);
      if (variant === 'guard') r.guard_passed = false;
      if (variant === 'sessions') h.rows[0].sessions_count = 1;
      if (variant === 'refresh') h.rows[0].refresh_count = 1;
      return r; };
    const r = await confine(h.input); assert.equal(r.completed, false); assert.equal(r.authUpdated, 1088);
  }
});

test('ban deadline is fixed and expired/out-of-range execution refuses', () => {
  assert.equal(new Date(NOW + Number.parseInt(banDuration(NOW)) * 1000).toISOString(), BAN_EXPIRES_AT);
  assert.throws(() => banDuration(Date.parse(BAN_EXPIRES_AT)));
  assert.throws(() => banDuration(Date.parse('2026-01-01T00:00:00Z')));
  assert.throws(() => assertBan(null)); assert.throws(() => assertBan('invalid')); assertBan(BAN_EXPIRES_AT);
});

test('manual event, approved branch, repository, matching SHA and real shared lock are mandatory', () => {
  const sha = 'a'.repeat(40), env = { GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: 'refs/heads/fix/confiner-cohorte-temporaire-20261004', GITHUB_SHA: sha, FIXTURE_EXPECTED_SHA: sha,
    FIXTURE_CONFINEMENT_CONFIRMATION: CONFIRMATION, FIXTURE_SHARED_LOCK: 'jolene-playwright-shared-database' };
  assertContext(env, sha);
  for (const patch of [{ GITHUB_EVENT_NAME: 'push' }, { GITHUB_REPOSITORY: 'other/repo' },
    { GITHUB_REF: 'refs/heads/unreviewed' }, { FIXTURE_EXPECTED_SHA: 'b'.repeat(40) },
    { FIXTURE_SHARED_LOCK: 'different' }, { FIXTURE_CONFINEMENT_CONFIRMATION: '' }]) assert.throws(() => assertContext({ ...env, ...patch }, sha));
  assert.throws(() => assertContext(env, 'b'.repeat(40)));
});

test('SQL is bounded to fixed UUIDs, same UTC-ms identity and two permitted session tables', () => {
  const ids = fixtureRows().map((r) => r.id);
  const initial = readQuery(), fixed = readQuery(ids), session = revokeQuery(ids, 'sessions'), refresh = revokeQuery(ids, 'refresh');
  assert.match(initial, /limit 1089/); assert.doesNotMatch(fixed, /where u.email ~/); assert.match(fixed, /where u.id in/);
  for (const sql of [initial, fixed, session, refresh]) assert.match(sql, /date_trunc\('milliseconds',created_at::timestamptz\) at time zone 'UTC'/);
  for (const sql of [session, refresh]) { assert.ok(sql.includes(COHORT_SHA)); assert.ok(sql.includes(BAN_EXPIRES_AT));
    assert.match(sql, /count\(\*\)=1088/); assert.match(sql, /and \(select ok from guard\)/);
    assert.doesNotMatch(sql, /(?:delete from|update) (?:auth\.users|public\.)/i); }
  assert.match(session, /delete from auth.sessions where user_id in/);
  assert.match(refresh, /update auth.refresh_tokens set revoked=true/);
  assert.throws(() => revokeQuery(ids.slice(1), 'sessions')); assert.throws(() => revokeQuery(ids, 'users'));
  assert.throws(() => readQuery(['invalid'])); assert.throws(() => readQuery([ids[0], ids[0]]));
});

test('UTC microseconds and equivalent timezone canonicalize identically at milliseconds', () => {
  const a = fixtureRows(), b = fixtureRows(); b[0].created_at = '2026-10-03T14:00:00.123999+02:00';
  assert.equal(projectCohort(a).cohortSha256, projectCohort(b).cohortSha256);
  const digest = projectCohort(a).cohortSha256;
  assert.doesNotThrow(() => assertFullSnapshot({ rows: b, cohort_sha256: digest }, [], { digest }));
});

test('real transport boundary suppresses exception/HTTP/JSON payload canaries without SDK logging', async () => {
  const canary = 'PRIVATE_TRANSPORT_CANARY', messages = [], originals = {};
  for (const name of ['log', 'error', 'warn', 'info', 'debug']) { originals[name] = console[name]; console[name] = (...args) => messages.push(args); }
  try {
    for (const fetchImpl of [async () => { throw Error(canary); }, async () => ({ ok: false, json: async () => ({ canary }) }),
      async () => ({ ok: true, json: async () => { throw Error(canary); } })]) {
      await assert.rejects(closedRequest(fetchImpl, 'https://fake.invalid', 'FAKE_TEST_TOKEN'), { message: 'TEMPORARY_FIXTURE_CONFINEMENT_REFUSED' });
    }
  } finally { for (const name of Object.keys(originals)) console[name] = originals[name]; }
  assert.equal(messages.length, 0);
  const source = readFileSync(new URL('../../scripts/ci/confine-temporary-playwright-fixtures.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /@supabase\/supabase-js/);
});

test('workflow selects one maintenance operation and never combines it with real browser or simulations', () => {
  const workflow = readFileSync(new URL('../../.github/workflows/playwright-e2e.yml', import.meta.url), 'utf8');
  const section = (name) => workflow.split(`\n  ${name}:\n`)[1]?.split(/\n  [a-z][a-z-]+:\n/)[0];
  const eligible = (name, event, rotate, confine) => {
    const expression = section(name).match(/^    if: (.+)$/m)[1].replace(/^\$\{\{\s*|\s*\}\}$/g, '')
      .replaceAll('github.event_name', JSON.stringify(event)).replaceAll('inputs.rotate_fixture_credentials', String(rotate))
      .replaceAll('inputs.confine_historical_fixture_cohort', String(confine));
    return Function(`return Boolean(${expression})`)();
  };
  for (const [rotate, confineFlag] of [[false, true], [true, false], [true, true]]) {
    assert.equal(eligible('simulation-interfaces', 'workflow_dispatch', rotate, confineFlag), false);
    assert.equal(eligible('e2e-main', 'workflow_dispatch', rotate, confineFlag), false);
    assert.equal(eligible('confine-historical-fixture-cohort', 'workflow_dispatch', rotate, confineFlag), confineFlag && !rotate);
    assert.equal(eligible('rotate-fixture-credentials', 'workflow_dispatch', rotate, confineFlag), rotate && !confineFlag);
  }
  assert.equal(eligible('e2e-pr', 'pull_request', false, false), true);
  assert.equal(eligible('e2e-main', 'push', false, false), true);
  assert.equal(eligible('e2e-main', 'workflow_dispatch', false, false), true);
  const maintenance = section('confine-historical-fixture-cohort');
  assert.match(maintenance, /group: jolene-playwright-shared-database/);
  assert.match(maintenance, /cancel-in-progress: false/); assert.match(maintenance, /ref: \$\{\{ github.sha \}\}/);
  assert.match(maintenance, /needs: validate-maintenance-mode/);
  assert.match(maintenance, /COHORT_REVIEW_REFERENCE_JSON: \$\{\{ secrets.COHORT_REVIEW_REFERENCE_JSON \}\}/);
  assert.doesNotMatch(maintenance, /npm ci|PLAYWRIGHT_FIXTURE_PASSWORD|E2E_TEST_PASSWORD|playwright test/);
  assert.match(section('validate-maintenance-mode'), /\[ "\$ROTATE" = true \] && \[ "\$CONFINE" = true \]/);
  const validate = readFileSync(new URL('../../.github/workflows/validate-pr.yml', import.meta.url), 'utf8');
  assert.match(validate, /node --test[^\n]*temporary-fixture-plan.node.mjs[^\n]*temporary-fixture-confinement.node.mjs/);
});
