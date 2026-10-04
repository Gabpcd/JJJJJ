#!/usr/bin/env node
import { pathToFileURL } from 'node:url';
import { writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { FIXTURES, preflightAllFixtures, requireFixturePassword } from '../lib/playwright-fixtures.mjs';

const PROJECT = 'flripxtsyegjshnhzjkz';
const CONFIRMATION = 'ROTATE_ONLY_PLAYWRIGHT_FIXTURES';

export function assertExecutionContext({ eventName, ref, sha, expectedSha, checkoutSha }) {
  if (eventName !== 'workflow_dispatch'
    || !['refs/heads/main', 'refs/heads/fix/identifiants-recette-prives-20261004'].includes(ref)
    || !/^[a-f0-9]{40}$/.test(expectedSha || '') || sha !== expectedSha || checkoutSha !== expectedSha) {
    throw new Error('FIXTURE_REVIEWED_SOURCE_REQUIRED');
  }
}

// Auth-js logs a thrown fetch error before returning it. Never give the SDK
// a transport exception carrying a URL, request body or provider diagnostic.
export function closedTransport(fetchImpl) {
  return async (...args) => {
    try { return await fetchImpl(...args); }
    catch { throw new Error('FIXTURE_TRANSPORT_FAILED'); }
  };
}

/** Injected clients permit offline tests; every diagnostic is a closed projection. */
export async function rotateFixtures({ admin, password, confirmation, readSessionCounts }) {
  const receipt = { schema: 1, operation: 'rotate-two-playwright-fixtures', completed: false,
    preflightPassed: false, rotatedCount: 0, purgePasses: 0, deletedSessions: 0,
    deletedRefreshTokens: 0, remainingSessions: null, remainingUnrevokedRefresh: null,
    accessJwtMayRemainValidUntilExpiry: true, failureStage: null };
  let stage = 'configuration';
  try {
    if (confirmation !== CONFIRMATION) throw new Error('CONFIRMATION_REQUIRED');
    requireFixturePassword(password);
    stage = 'preflight';
    // Both identities/roles/test profiles are checked BEFORE the first update.
    const userIds = await preflightAllFixtures(admin);
    receipt.preflightPassed = true;
    stage = 'rotation';
    for (const userId of userIds) {
      const result = await admin.auth.admin.updateUserById(userId, { password });
      if (result.error || result.data?.user?.id !== userId) throw new Error('ROTATION_FAILED');
      receipt.rotatedCount += 1;
    }
    stage = 'session-revocation';
    // Existing service-role-only RPC, exact same two fixed accounts, <=1000/pass.
    for (let pass = 0; pass < 10; pass += 1) {
      const { data, error } = await admin.rpc('fn_test_nettoyer_sessions_playwright', { p_anciennete: '0 seconds' });
      if (error || data?.limite_par_passage !== 1000
        || !Number.isInteger(data?.sessions_supprimees) || data.sessions_supprimees < 0 || data.sessions_supprimees > 1000
        || !Number.isInteger(data?.refresh_tokens_supprimes) || data.refresh_tokens_supprimes < 0) throw new Error('REVOCATION_FAILED');
      receipt.purgePasses += 1;
      receipt.deletedSessions += data.sessions_supprimees;
      receipt.deletedRefreshTokens += data.refresh_tokens_supprimes;
      if (data.sessions_supprimees === 0) break;
    }
    stage = 'readback';
    const counts = await readSessionCounts();
    if (counts?.target_count !== 2 || !Number.isInteger(counts.sessions_count)
      || !Number.isInteger(counts.unrevoked_refresh_count)
      || counts.sessions_count < 0 || counts.unrevoked_refresh_count < 0) throw new Error('READBACK_FAILED');
    receipt.remainingSessions = counts.sessions_count;
    receipt.remainingUnrevokedRefresh = counts.unrevoked_refresh_count;
    if (counts.sessions_count !== 0 || counts.unrevoked_refresh_count !== 0) throw new Error('SESSIONS_REMAIN');
    receipt.completed = true;
  } catch {
    // Do not serialize SDK errors, request bodies, tokens, user IDs or passwords.
    receipt.failureStage = stage;
  }
  return receipt;
}

async function main() {
  assertExecutionContext({ eventName: process.env.GITHUB_EVENT_NAME, ref: process.env.GITHUB_REF,
    sha: process.env.GITHUB_SHA, expectedSha: process.env.FIXTURE_EXPECTED_SHA,
    checkoutSha: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim() });
  const password = requireFixturePassword(process.env.E2E_TEST_PASSWORD);
  const token = process.env.SUPABASE_ACCESS_TOKEN;
  if (!token || process.env.FIXTURE_ROTATION_CONFIRMATION !== CONFIRMATION) throw new Error('CONFIGURATION_REQUIRED');
  const management = async (path, options = {}) => {
    const response = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}/${path}`, {
      ...options, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error('MANAGEMENT_FAILED');
    return response.json();
  };
  const keys = await management('api-keys?reveal=true');
  const key = Array.isArray(keys) && (keys.find((k) => k.name === 'service_role' && k.api_key)
    || keys.find((k) => k.type === 'secret' && !k.disabled && k.api_key));
  if (!key) throw new Error('MAINTENANCE_KEY_UNAVAILABLE');
  // Value exists only in memory; never exported to GITHUB_ENV or artifacts.
  const { createClient } = await import('@supabase/supabase-js');
  const admin = createClient(`https://${PROJECT}.supabase.co`, key.api_key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: closedTransport(fetch) },
  });
  const emails = Object.values(FIXTURES).map(({ email }) => `'${email.replaceAll("'", "''")}'`).join(',');
  const query = `select (select count(*)::int from auth.users where email in (${emails})) target_count,
    (select count(*)::int from auth.sessions s join auth.users u on u.id=s.user_id where u.email in (${emails})) sessions_count,
    (select count(*)::int from auth.refresh_tokens r join auth.users u on u.id::text=r.user_id::text where u.email in (${emails}) and not r.revoked) unrevoked_refresh_count`;
  const readSessionCounts = async () => {
    const rows = await management('database/query', { method: 'POST', body: JSON.stringify({ query, read_only: true }) });
    if (!Array.isArray(rows) || rows.length !== 1) throw new Error('READBACK_SHAPE');
    return rows[0];
  };
  // Prove the final readback is available before any write.
  await readSessionCounts();
  const receipt = await rotateFixtures({ admin, password, confirmation: process.env.FIXTURE_ROTATION_CONFIRMATION, readSessionCounts });
  const output = JSON.stringify(receipt, null, 2) + '\n';
  writeFileSync('fixture-rotation-public.json', output, { mode: 0o600 });
  console.log(output.trim());
  if (!receipt.completed) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    console.error('Rotation des fixtures arrêtée ; contrôle manuel requis. Aucun diagnostic sensible publié.');
    process.exitCode = 1;
  });
}
