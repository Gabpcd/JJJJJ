import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { projectCohort, COHORT_SELECT } from '../../scripts/ci/plan-temporary-playwright-fixtures.mjs';

function rows() {
  return Array.from({ length: 1088 }, (_, index) => {
    const kind = index < 377 ? 'soignant' : index < 770 ? 'etab' : 'draft';
    const role = kind === 'etab' ? 'etab' : 'soignant';
    const timestamp = Date.parse('2026-10-01T00:00:00.000Z') + index;
    return { id: '00000000-0000-4000-8000-' + (index + 1).toString(16).padStart(12, '0'),
      email: `playwright-test-${role}-${timestamp}-fake00@jolene.app`, created_at: new Date(timestamp + 1000).toISOString(),
      app_role: kind === 'soignant' ? 'SOIGNANT' : kind === 'etab' ? 'ADMIN_ETABLISSEMENT' : null,
      user_admin: false, soignant_profile: kind === 'soignant', soignant_test: kind === 'soignant',
      etab_profile: kind === 'etab', etab_test: kind === 'etab', platform_member: false, non_test_member: false };
  });
}

test('closed plan binds exact cohort identity without returning any row or identifier', () => {
  const input = rows(), report = projectCohort(input), output = JSON.stringify(report);
  assert.deepEqual(report.taxonomy, { soignant: 377, etab: 393, draft: 318 });
  assert.equal(report.count, 1088); assert.equal(report.confinementExecuted, false);
  assert.equal(report.authMutationsExecuted, 0); assert.equal(report.sessionMutationsExecuted, 0);
  assert.match(report.cohortSha256, /^[a-f0-9]{64}$/);
  for (const row of input) {
    assert.equal(output.includes(row.id), false); assert.equal(output.includes(row.email), false);
  }
  assert.equal(projectCohort([...input].reverse()).cohortSha256, report.cohortSha256);
  const changed = structuredClone(input); changed[0].email = changed[0].email.replace('fake00', 'fake01');
  assert.notEqual(projectCohort(changed).cohortSha256, report.cohortSha256);
});

for (const [name, alter] of Object.entries({
  'missing target': input => input.pop(),
  'extra target': input => input.push({ ...input[0] }),
  'duplicate identity': input => { input[1].id = input[0].id; },
  'ordinary address': input => { input[0].email = 'synthetic-unrelated@example.invalid'; },
  'fixed fixture address': input => { input[0].email = 'playwright-etab@jolene.app'; },
  'post-cutoff created': input => { input[0].created_at = '2026-10-04T12:35:27Z'; },
  'encoded timestamp mismatch': input => { input[0].created_at = '2026-10-01T00:10:00Z'; },
  'platform app role': input => { input[0].app_role = 'ADMIN_PLATEFORME'; },
  'user metadata admin': input => { input[0].user_admin = true; },
  'platform membership even inactive': input => { input[0].platform_member = true; },
  'non-test establishment membership': input => { input[0].non_test_member = true; },
  'unmarked profile': input => { input[0].soignant_test = false; },
  'unexpected second profile': input => { input[0].etab_profile = true; input[0].etab_test = true; },
  'draft has a role': input => { input[1000].app_role = 'INCONNU'; },
  'missing boolean': input => { delete input[0].platform_member; },
})) test(`refuses ${name}`, () => {
  const input = rows(); alter(input); assert.throws(() => projectCohort(input), /TEMPORARY_FIXTURE_PLAN_REFUSED/);
});

test('reader has no mutation route, reads no password/session contents and has a fixed upper bound', () => {
  const source = readFileSync(new URL('../../scripts/ci/plan-temporary-playwright-fixtures.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(COHORT_SELECT, /\b(update|delete|insert|alter|drop|encrypted_password|refresh_tokens)\b/i);
  assert.match(COHORT_SELECT, /limit 1089$/);
  assert.match(source, /read_only: true/);
  assert.doesNotMatch(source, /updateUserById|deleteUser|ban_duration|read_only: false|\/auth\/v1\//);
});
