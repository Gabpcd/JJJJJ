#!/usr/bin/env node
// Incident-specific operator. No account/profile/business deletion. No raw diagnostics.
import { randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { PROJECT, CUTOFF, EXPECTED_COUNT, COHORT_SELECT, projectCohort } from './plan-temporary-playwright-fixtures.mjs';

export const COHORT_SHA = 'd49ace5fcdb5e49f33e5a76bd052dc360811cffa5e89c6d286758602aaef4e38';
export const BAN_EXPIRES_AT = '2027-10-04T12:35:27.000Z';
export const CONFIRMATION = 'CONFINE_EXACT_1088_D49ACE5F';
export const MAX_OPERATION_MS = 75 * 60 * 1000;
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const fail = () => { throw new Error('TEMPORARY_FIXTURE_CONFINEMENT_REFUSED'); };
const integer = (value) => Number.isSafeInteger(value) && value >= 0;

export async function closedRequest(fetchImpl, url, token, options = {}) {
  try {
    const response = await fetchImpl(url, { ...options, headers: { Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json', ...(options.headers || {}) }, signal: AbortSignal.timeout(45_000) });
    if (!response.ok) fail(); return await response.json();
  } catch { fail(); }
}

export function assertContext(env, checkoutSha) {
  if (env.GITHUB_REPOSITORY !== 'Gabpcd/JJJJJ' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch'
    || !['refs/heads/main', 'refs/heads/fix/identifiants-recette-prives-20261004',
      'refs/heads/fix/confiner-cohorte-temporaire-20261004'].includes(env.GITHUB_REF)
    || !/^[a-f0-9]{40}$/.test(env.FIXTURE_EXPECTED_SHA || '')
    || env.GITHUB_SHA !== env.FIXTURE_EXPECTED_SHA || checkoutSha !== env.FIXTURE_EXPECTED_SHA
    || env.FIXTURE_CONFINEMENT_CONFIRMATION !== CONFIRMATION
    || env.FIXTURE_SHARED_LOCK !== 'jolene-playwright-shared-database') fail();
}

function idList(ids) {
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > EXPECTED_COUNT
    || new Set(ids).size !== ids.length || ids.some((id) => !UUID.test(id))) fail();
  return ids.map((id) => `'${id}'::uuid`).join(',');
}

// SQL and Node both truncate source timestamps to UTC milliseconds. The digest
// binds the same sorted id/email/created_at/kind records as the historical receipt.
function selectRows(ids) {
  let sql = COHORT_SELECT.replace('select u.id::text id,', `select
 u.deleted_at is not null auth_deleted, u.banned_until::text banned_until,
 (select count(*)::int from auth.sessions s where s.user_id=u.id) sessions_count,
 (select count(*)::int from auth.refresh_tokens r where r.user_id=u.id::text and r.revoked is not true) refresh_count,
 u.id::text id,`);
  if (ids) sql = sql.replace(/where u.email ~[\s\S]*?order by u.id limit 1089$/, `where u.id in (${idList(ids)}) order by u.id`);
  return sql;
}

export function readQuery(ids = null) {
  return `with cohort as (${selectRows(ids)}), canonical as (
 select *,case when soignant_profile then 'soignant' when etab_profile then 'etab' else 'draft' end kind from cohort
 ) select coalesce(jsonb_agg(to_jsonb(c) order by id),'[]'::jsonb) rows,
 encode(extensions.digest(coalesce(string_agg(id || E'\\t' || email || E'\\t' ||
 to_char(date_trunc('milliseconds',created_at::timestamptz) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') || E'\\t' || kind,
 E'\\n' order by id),'') || E'\\n','sha256'),'hex') cohort_sha256 from canonical c`;
}

const identityKeys = ['id', 'email', 'app_role', 'user_admin', 'soignant_profile', 'soignant_test',
  'etab_profile', 'etab_test', 'platform_member', 'non_test_member', 'auth_deleted'];
export function assertIdentity(row, expected) {
  if (!row || identityKeys.some((key) => row[key] !== expected[key])
    || new Date(row.created_at).toISOString() !== new Date(expected.created_at).toISOString()
    || row.auth_deleted !== false || !integer(row.sessions_count) || !integer(row.refresh_count)) fail();
}

export function reviewReferences(raw, now = Date.now()) {
  let proof; try { proof = JSON.parse(raw); } catch { fail(); }
  // This private input must come from the independently reviewed canonical
  // reference inventory, not an inferred absence from an email naming pattern.
  if (proof?.schema !== 1 || proof.source !== 'canonical-review-reference-inventory'
    || proof.repository !== 'Gabpcd/JJJJJ' || proof.complete !== true
    || proof.githubMetadataChecked !== true || proof.storeReferenceChecked !== true
    || proof.noReferencesExplicit !== (Array.isArray(proof.references) && proof.references.length === 0)
    || !Number.isFinite(Date.parse(proof.checkedAt)) || Date.parse(proof.checkedAt) > now
    || now - Date.parse(proof.checkedAt) > 24 * 60 * 60 * 1000
    || !Array.isArray(proof.references) || proof.references.length > 100) fail();
  const refs = proof.references.map((value) => {
    if (typeof value !== 'string' || value.length > 254 || (!UUID.test(value)
      && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value))) fail();
    return value.toLowerCase();
  });
  if (new Set(refs).size !== refs.length) fail();
  return refs;
}

export function assertFullSnapshot(snapshot, references, { initial = true, expected = null, digest = COHORT_SHA } = {}) {
  if (!snapshot || !Array.isArray(snapshot.rows)) fail();
  const report = projectCohort(snapshot.rows);
  if (report.cohortSha256 !== digest || snapshot.cohort_sha256 !== digest) fail();
  for (const row of snapshot.rows) {
    if (row.auth_deleted !== false || !integer(row.sessions_count) || !integer(row.refresh_count)
      || references.includes(row.id) || references.includes(row.email.toLowerCase())) fail();
    if (initial && row.banned_until !== null) fail();
    if (expected) {
      const before = expected.get(row.id); if (!before) fail(); assertIdentity(row, before);
    }
  }
  return report;
}

export function banDuration(now = Date.now()) {
  const seconds = Math.ceil((Date.parse(BAN_EXPIRES_AT) - now) / 1000);
  if (!Number.isSafeInteger(seconds) || seconds <= 0 || seconds > 366 * 86400) fail();
  return `${seconds}s`;
}

export function assertBan(value) {
  const time = Date.parse(value);
  if (!Number.isFinite(time) || Math.abs(time - Date.parse(BAN_EXPIRES_AT)) > 90_000) fail();
}

// Each statement has one bounded session/refresh mutation and repeats the exact
// fixed-UUID guard. No account/profile/business SQL write or persistent DDL.
export function revokeQuery(ids, kind) {
  const list = idList(ids); if (ids.length !== EXPECTED_COUNT || !['refresh', 'sessions'].includes(kind)) fail();
  const mutation = kind === 'refresh'
    ? "update auth.refresh_tokens set revoked=true,updated_at=now() where user_id in (select id from canonical) and revoked is not true"
    : `delete from auth.sessions where user_id in (${list})`;
  return `with cohort as (${selectRows(ids)}), canonical as (
 select *,case when soignant_profile then 'soignant' when etab_profile then 'etab' else 'draft' end kind from cohort
 ), guard as (select count(*)=${EXPECTED_COUNT} and
 bool_and((not auth_deleted and not user_admin and not platform_member and not non_test_member
 and banned_until::timestamptz between timestamptz '${BAN_EXPIRES_AT}'-interval '90 seconds' and timestamptz '${BAN_EXPIRES_AT}'+interval '90 seconds'
 and ((kind='soignant' and app_role='SOIGNANT' and soignant_test and not etab_profile)
 or (kind='etab' and app_role='ADMIN_ETABLISSEMENT' and etab_test and not soignant_profile)
 or (kind='draft' and app_role is null and not soignant_profile and not etab_profile))) is true) and
 encode(extensions.digest(string_agg(id || E'\\t' || email || E'\\t' ||
 to_char(date_trunc('milliseconds',created_at::timestamptz) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') || E'\\t' || kind,
 E'\\n' order by id) || E'\\n','sha256'),'hex')='${COHORT_SHA}' ok from canonical),
 changed as (${mutation} and (select ok from guard) returning id)
 select (select ok from guard) guard_passed,(select count(*)::int from changed) rows_affected`;
}

/** All state is held in memory; injected adapters permit offline tests only. */
export async function confine({ read, update, revoke, drain, reviewProof, confirmation,
  now = Date.now, random = () => randomBytes(32).toString('hex'), digest = COHORT_SHA, checkpoint = () => {} }) {
  const receipt = { schema: 1, operation: 'confine-exact-historical-fixture-cohort', completed: false,
    count: EXPECTED_COUNT, cutoff: CUTOFF, cohortSha256: COHORT_SHA, banExpiresAt: BAN_EXPIRES_AT,
    preflights: 0, sqlAndNodeDigestEqual: false, reviewIntersectionEmpty: false, authUpdated: 0, sessionRowsRemoved: 0,
    refreshRowsRevoked: 0, remainingSessions: null, remainingUnrevokedRefresh: null,
    verifiedBannedCount: 0, businessRowsDeleted: 0, outsideCohortTargets: 0,
    existingJwtMayRemainValidUntilExpiry: true, stage: 'configuration' };
  try {
    const started = now();
    if (confirmation !== CONFIRMATION) fail(); banDuration(now());
    const references = reviewReferences(reviewProof, now());
    receipt.stage = 'quiescence'; await drain();
    receipt.stage = 'preflight-one'; const first = await read(null);
    assertFullSnapshot(first, references, { digest }); receipt.preflights++;
    const expected = new Map(first.rows.map((row) => [row.id, structuredClone(row)]));
    const ids = [...expected.keys()].sort();
    receipt.stage = 'preflight-two'; await drain(); const second = await read(ids);
    assertFullSnapshot(second, references, { expected, digest }); receipt.preflights++;
    receipt.sqlAndNodeDigestEqual = true;
    receipt.reviewIntersectionEmpty = true;
    checkpoint(structuredClone(receipt));
    const usedSecrets = new Set();
    receipt.stage = 'auth-confinement';
    for (const id of ids) {
      // Leave time for a closed partial receipt before the runner's 90-minute
      // deadline. This stops; it never retries a partly confined cohort.
      if (now() - started > MAX_OPERATION_MS) fail();
      const fresh = await read([id]);
      if (fresh?.rows?.length !== 1) fail();
      assertIdentity(fresh.rows[0], expected.get(id));
      if (fresh.rows[0].banned_until !== null) fail();
      const password = random();
      if (typeof password !== 'string' || !/^[a-f0-9]{64}$/.test(password) || usedSecrets.has(password)) fail();
      usedSecrets.add(password); // Memory only; never serialized or hashed for output.
      const result = await update(id, { password, ban_duration: banDuration(now()) });
      if (result?.id !== id) fail(); assertBan(result.banned_until); receipt.authUpdated++;
      const after = await read([id]); if (after?.rows?.length !== 1) fail();
      assertIdentity(after.rows[0], expected.get(id)); assertBan(after.rows[0].banned_until);
      if (receipt.authUpdated % 25 === 0) checkpoint(structuredClone(receipt));
    }
    usedSecrets.clear();
    receipt.stage = 'pre-revocation'; const beforeRevoke = await read(ids);
    assertFullSnapshot(beforeRevoke, references, { initial: false, expected, digest });
    for (const row of beforeRevoke.rows) assertBan(row.banned_until);
    receipt.stage = 'session-revocation'; const result = await revoke(ids);
    if (result?.guard_passed !== true || !integer(result.refresh_revoked) || !integer(result.sessions_removed)) fail();
    receipt.refreshRowsRevoked = result.refresh_revoked; receipt.sessionRowsRemoved = result.sessions_removed;
    receipt.stage = 'fixed-uuid-readback'; const last = await read(ids);
    assertFullSnapshot(last, references, { initial: false, expected, digest });
    for (const row of last.rows) assertBan(row.banned_until);
    receipt.verifiedBannedCount = last.rows.length;
    receipt.remainingSessions = last.rows.reduce((sum, row) => sum + row.sessions_count, 0);
    receipt.remainingUnrevokedRefresh = last.rows.reduce((sum, row) => sum + row.refresh_count, 0);
    if (receipt.remainingSessions || receipt.remainingUnrevokedRefresh || receipt.authUpdated !== EXPECTED_COUNT) fail();
    receipt.completed = true; receipt.stage = 'complete';
  } catch { /* Closed receipt preserves partial progress, never remote error bodies. */ }
  return receipt;
}

async function main() {
  assertContext(process.env, execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim());
  if (process.argv.length !== 2 || !process.env.SUPABASE_ACCESS_TOKEN || !process.env.GITHUB_TOKEN) fail();
  // Validate private reference inventory before retrieving any maintenance key.
  reviewReferences(process.env.COHORT_REVIEW_REFERENCE_JSON);
  const request = (url, token, options = {}) => closedRequest(fetch, url, token, options);
  const management = (path, options) => request(`https://api.supabase.com/v1/projects/${PROJECT}/${path}`, process.env.SUPABASE_ACCESS_TOKEN, options);
  const query = async (sql, readOnly = true) => {
    const rows = await management('database/query', { method: 'POST', body: JSON.stringify({ query: sql, read_only: readOnly }) });
    if (!Array.isArray(rows) || rows.length !== 1) fail(); return rows[0];
  };
  const drain = async () => {
    for (const status of ['in_progress', 'queued', 'waiting', 'requested', 'pending']) {
      const data = await request(`https://api.github.com/repos/Gabpcd/JJJJJ/actions/workflows/playwright-e2e.yml/runs?status=${status}&per_page=100`, process.env.GITHUB_TOKEN);
      if (!Number.isSafeInteger(data.total_count) || data.total_count > 100 || !Array.isArray(data.workflow_runs)
        || data.workflow_runs.some((run) => String(run.id) !== process.env.GITHUB_RUN_ID)) fail();
    }
  };
  await drain();
  const keys = await management('api-keys?reveal=true');
  const key = Array.isArray(keys) && (keys.find((k) => k.name === 'service_role' && k.api_key)
    || keys.find((k) => k.type === 'secret' && !k.disabled && k.api_key));
  if (!key) fail();
  // Use the Auth REST endpoint directly: no SDK logger can serialize transport
  // exceptions. Request/response bodies, UUIDs and credentials never reach logs.
  const update = async (id, attributes) => {
    if (!UUID.test(id)) fail();
    const user = await request(`https://${PROJECT}.supabase.co/auth/v1/admin/users/${id}`, key.api_key,
      { method: 'PUT', headers: { apikey: key.api_key }, body: JSON.stringify(attributes) });
    return { id: user?.id, banned_until: user?.banned_until };
  };
  const result = await confine({ read: (ids) => query(readQuery(ids)), update,
    revoke: async (ids) => {
      const refresh = await query(revokeQuery(ids, 'refresh'), false);
      if (refresh.guard_passed !== true || !integer(refresh.rows_affected)) fail();
      const sessions = await query(revokeQuery(ids, 'sessions'), false);
      if (sessions.guard_passed !== true || !integer(sessions.rows_affected)) fail();
      return { guard_passed: true, refresh_revoked: refresh.rows_affected, sessions_removed: sessions.rows_affected };
    }, drain, checkpoint: (receipt) => {
      writeFileSync('temporary-fixture-confinement-public.json', JSON.stringify(receipt, null, 2) + '\n', { mode: 0o600 });
      console.log(JSON.stringify({ operation: receipt.operation, completed: false, stage: receipt.stage,
        preflights: receipt.preflights, authUpdated: receipt.authUpdated }));
    },
    reviewProof: process.env.COHORT_REVIEW_REFERENCE_JSON, confirmation: process.env.FIXTURE_CONFINEMENT_CONFIRMATION });
  const bytes = JSON.stringify(result, null, 2) + '\n';
  writeFileSync('temporary-fixture-confinement-public.json', bytes, { mode: 0o600 }); console.log(bytes.trim());
  if (!result.completed) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch(() => {
  console.error('Confinement arrêté avant reçu final ; aucune donnée sensible publiée. Contrôle indépendant requis.');
  process.exitCode = 1;
});
