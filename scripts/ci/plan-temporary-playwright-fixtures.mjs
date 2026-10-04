#!/usr/bin/env node
// READ ONLY. This module cannot ban, update or delete an account or session.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const PROJECT = 'flripxtsyegjshnhzjkz';
export const CUTOFF = '2026-10-04T12:35:27Z';
export const EXPECTED_COUNT = 1088;
export const EXPECTED_TAXONOMY = Object.freeze({ soignant: 377, etab: 393, draft: 318 });
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const EMAIL = /^playwright-test-(soignant|etab)-([0-9]{13})-[a-z0-9]{1,6}@jolene\.app$/;
const fail = () => { throw new Error('TEMPORARY_FIXTURE_PLAN_REFUSED'); };

export function assertExecutionContext({ eventName, ref, sha, expectedSha, checkoutSha }) {
  if (eventName !== 'workflow_dispatch'
    || !['refs/heads/main', 'refs/heads/fix/identifiants-recette-prives-20261004'].includes(ref)
    || !/^[a-f0-9]{40}$/.test(expectedSha || '') || sha !== expectedSha || checkoutSha !== expectedSha) fail();
}


// Identifiers stay in process memory only. Neither a raw row nor an arbitrary
// diagnostic is part of the public plan. No password/hash/token field is read.
export const COHORT_SELECT = `
select u.id::text id, u.email, u.created_at::text created_at,
 u.raw_app_meta_data->>'role' app_role,
 coalesce(u.raw_user_meta_data->>'role'='ADMIN_PLATEFORME',false) user_admin,
 exists(select 1 from public.soignants s where s.id=u.id) soignant_profile,
 exists(select 1 from public.soignants s where s.id=u.id and s.est_compte_test is true) soignant_test,
 exists(select 1 from public.etablissements e where e.id=u.id) etab_profile,
 exists(select 1 from public.etablissements e where e.id=u.id and e.est_compte_test is true) etab_test,
 exists(select 1 from public.equipe_admin a where a.user_id=u.id) platform_member,
 exists(select 1 from public.membres_etablissement m join public.etablissements e on e.id=m.etablissement_id
   where m.user_id=u.id and m.actif is true and e.est_compte_test is not true) non_test_member
from auth.users u
where u.email ~ '^playwright-test-(soignant|etab)-[0-9]{13}-[a-z0-9]{1,6}@jolene[.]app$'
 and u.created_at < timestamptz '${CUTOFF}'
order by u.id limit 1089`;

export function projectCohort(rows) {
  if (!Array.isArray(rows) || rows.length !== EXPECTED_COUNT) fail();
  const ids = new Set(), taxonomy = { soignant: 0, etab: 0, draft: 0 }, manifest = [];
  for (const row of rows) {
    const match = typeof row.email === 'string' && EMAIL.exec(row.email);
    const created = Date.parse(row.created_at), generated = match && Number(match[2]);
    if (!UUID.test(row.id || '') || ids.has(row.id) || !match || !Number.isFinite(created)
      || !Number.isSafeInteger(generated) || created >= Date.parse(CUTOFF) || generated >= Date.parse(CUTOFF)
      || created < generated - 60_000 || created > generated + 300_000) fail();
    for (const key of ['user_admin', 'soignant_profile', 'soignant_test', 'etab_profile', 'etab_test', 'platform_member', 'non_test_member']) {
      if (typeof row[key] !== 'boolean') fail();
    }
    if (row.user_admin || row.platform_member || row.non_test_member) fail();
    let kind;
    if (match[1] === 'soignant' && row.app_role === 'SOIGNANT' && row.soignant_profile && row.soignant_test
      && !row.etab_profile && !row.etab_test) kind = 'soignant';
    else if (match[1] === 'etab' && row.app_role === 'ADMIN_ETABLISSEMENT' && row.etab_profile && row.etab_test
      && !row.soignant_profile && !row.soignant_test) kind = 'etab';
    else if (row.app_role === null && !row.soignant_profile && !row.soignant_test && !row.etab_profile && !row.etab_test) kind = 'draft';
    else fail();
    ids.add(row.id); taxonomy[kind]++;
    manifest.push({ id: row.id, email: row.email, created_at: new Date(created).toISOString(), kind });
  }
  if (Object.keys(EXPECTED_TAXONOMY).some((key) => taxonomy[key] !== EXPECTED_TAXONOMY[key])) fail();
  manifest.sort((a, b) => a.id.localeCompare(b.id));
  return { schema: 1, mode: 'READ_ONLY_PLAN', cutoff: CUTOFF, count: EXPECTED_COUNT, taxonomy,
    cohortSha256: createHash('sha256').update(manifest.map((row) => [row.id, row.email, row.created_at, row.kind].join('\t')).join('\n') + '\n').digest('hex'),
    authMutationsExecuted: 0, sessionMutationsExecuted: 0, confinementExecuted: false };
}

async function main() {
  assertExecutionContext({ eventName: process.env.GITHUB_EVENT_NAME, ref: process.env.GITHUB_REF,
    sha: process.env.GITHUB_SHA, expectedSha: process.env.FIXTURE_EXPECTED_SHA,
    checkoutSha: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim() });
  if (process.env.GITHUB_REPOSITORY !== 'Gabpcd/JJJJJ' || process.argv.length !== 2) fail();
  const token = process.env.SUPABASE_ACCESS_TOKEN;
  if (!token) fail();
  const response = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: COHORT_SELECT, read_only: true }), signal: AbortSignal.timeout(45_000),
  });
  if (!response.ok) fail();
  const receipt = projectCohort(await response.json());
  const bytes = JSON.stringify(receipt, null, 2) + '\n';
  writeFileSync('temporary-fixture-plan-public.json', bytes, { mode: 0o600 });
  console.log(bytes.trim());
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch(() => {
  console.error('Plan des fixtures temporaires refusé ; aucun détail sensible publié et aucune mutation.');
  process.exitCode = 1;
});
