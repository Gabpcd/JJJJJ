import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { backendPaths, checkBackendDeployment } from '../../scripts/mobile/delivery-plan-backend.mjs';
import {
  COQUILLE_IOS_FIGEE, exigerOtaAndroidSeul, lireConfigLivraison, plateformeMobileDelivery, tagsLivraison,
} from '../../scripts/mobile/release-config.mjs';
import { verifierAlignement } from '../../scripts/check-mobile-build-alignment.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const planner = join(root, 'scripts/mobile/delivery-plan.mjs');

// Run the real planner against disposable git history and a closed API fixture.
// No token, external fetch, build, store submission or real repository mutation.
function plan(t, scenario = {}) {
  const cwd = mkdtempSync(join(tmpdir(), 'jolene-delivery-plan-'));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init', '-q', '--initial-branch=main');
  if (scenario.backendMissing || scenario.backendEvidence) {
    mkdirSync(join(cwd, 'supabase/functions/example'), { recursive: true });
    writeFileSync(join(cwd, 'supabase/functions/example/index.ts'), 'export const version = 1;');
    git('add', '.');
  }
  git('-c', 'user.name=Recette', '-c', 'user.email=recette@example.invalid', 'commit', '-q', '--allow-empty', '-m', 'baseline');
  const baseline = git('rev-parse', 'HEAD');
  // Lot 6 : tags scindés par plateforme. Le runtime Android précédent porte `mobile-native-android-22`.
  for (const tag of scenario.baselineTags ?? ['mobile-native-android-22']) git('tag', tag);
  for (const [path, text] of Object.entries(scenario.files ?? {})) {
    mkdirSync(dirname(join(cwd, path)), { recursive: true });
    writeFileSync(join(cwd, path), text);
  }
  if (scenario.files) git('add', '-A');
  git('-c', 'user.name=Recette', '-c', 'user.email=recette@example.invalid', 'commit', '-q', '--allow-empty', '-m', 'candidate');
  const candidate = git('rev-parse', 'HEAD');
  const build = scenario.build ?? 23;
  if (scenario.reserved) {
    git('tag', `mobile-native-source-android-${build}`, baseline);
  }
  const checkedSha = scenario.reserved ? baseline : candidate;
  mkdirSync(join(cwd, 'config'));
  writeFileSync(join(cwd, 'config/mobile-release.json'), JSON.stringify(scenario.config ?? {
    ios: { runtime: 'swift', marketingVersion: '2.0.0', minimumBuildNumber: 32 },
    android: { runtime: 'capacitor', marketingVersion: '1.0.6', buildNumber: build },
  }));
  const fixture = { ...scenario, candidate, baseline, checkedSha };
  writeFileSync(join(cwd, 'fixture.json'), JSON.stringify(fixture));
  writeFileSync(join(cwd, 'api.mjs'), `
    import assert from 'node:assert/strict';
    import { appendFileSync, readFileSync } from 'node:fs';
    const f = JSON.parse(readFileSync('fixture.json', 'utf8'));
    const backendRun = { id: 21, workflow_id: 3, path: '.github/workflows/deploy-supabase.yml', run_attempt: 1,
      head_sha: f.baseline, head_branch: 'main', event: 'push', repository: { full_name: 'Gabpcd/JJJJJ' },
      head_repository: { full_name: 'Gabpcd/JJJJJ' }, status: 'completed', conclusion: 'success', updated_at: '2026-09-28T09:01:00Z' };
    globalThis.fetch = async (url) => {
      const parsed = new URL(url);
      assert.equal(parsed.origin, 'https://api.github.com');
      const path = parsed.pathname.replace('/repos/Gabpcd/JJJJJ/', '');
      appendFileSync('requests.jsonl', JSON.stringify(path) + '\\n');
      if (path === 'git/ref/heads/main') return Response.json({ object: { sha: f.newerMain ? f.baseline : f.candidate } });
      if (path === 'actions/workflows/deploy-supabase.yml') return Response.json({ id: 3, path: '.github/workflows/deploy-supabase.yml', state: 'active' });
      if (path === 'actions/workflows/3/runs') return Response.json({ total_count: f.backendEvidence ? 1 : 0, workflow_runs: f.backendEvidence ? [backendRun] : [] });
      if (path === 'actions/runs/21/attempts/1/jobs') return Response.json({ total_count: 2, jobs:
        ['Apply SQL migrations', 'Deploy edge functions'].map((name, index) => ({ id: index + 1, name, run_id: 21, head_sha: f.baseline,
          status: 'completed', conclusion: 'success', started_at: '2026-09-28T09:00:00Z' })) });
      if (path === 'actions/runs/21') return Response.json(backendRun);
      if (path.startsWith('actions/workflows/')) {
        assert.equal(parsed.searchParams.get('head_sha'), f.checkedSha);
        assert.equal(parsed.searchParams.get('event'), 'push');
        const workflow = path.split('/')[2];
        assert.ok(['validate-pr.yml', 'playwright-e2e.yml', 'lighthouse.yml', 'android-native-recette.yml'].includes(workflow));
        if (workflow === f.apiFailure) return new Response('', { status: 503 });
        const run = { id: 12, head_branch: 'main', head_sha: f.checkedSha, event: 'push', conclusion: 'success' };
        let runs = [run];
        if (workflow === 'android-native-recette.yml') {
          if (f.nativeConclusion !== undefined) run.conclusion = f.nativeConclusion;
          if (f.nativeWrongSha) run.head_sha = f.baseline;
          if (f.nativePr) run.event = 'pull_request';
          if (f.nativeOtherBranch) run.head_branch = 'fix/test';
          if (f.nativeAbsent) runs = [];
          if (f.olderSuccess) runs.push({ ...run, id: 11, conclusion: 'success' });
        }
        return Response.json({ workflow_runs: runs });
      }
      if (path === 'commits/' + f.checkedSha + '/status') return Response.json({ statuses: [{ context: 'Vercel', state: f.vercelState || 'success' }] });
      const pulls = path.match(/^commits\\/([a-f0-9]{40})\\/pulls$/);
      if (pulls) return Response.json(f.otaReviewed ? [{ merged_at: '2026-11-24T09:00:00Z', merge_commit_sha: pulls[1], labels: [{ name: 'mobile:ota' }] }] : []);
      throw new Error('Unexpected API request: ' + path);
    };
  `);
  const outputFile = join(cwd, 'output');
  const summaryFile = join(cwd, 'summary');
  writeFileSync(outputFile, '');
  writeFileSync(summaryFile, '');
  let executable = scenario.recheck ? join(root, 'scripts/mobile/delivery-plan-backend.mjs') : planner;
  if (scenario.legacyGuard) {
    const guardPath = 'scripts/mobile/delivery-plan-backend.mjs';
    assert.throws(() => git('show', `${candidate}:${guardPath}`));
    mkdirSync(join(cwd, 'scripts/mobile'), { recursive: true });
    writeFileSync(join(cwd, guardPath), readFileSync(join(root, guardPath)));
    git('add', guardPath);
    git('-c', 'user.name=Recette', '-c', 'user.email=recette@example.invalid', 'commit', '-q', '-m', 'trusted main guard');
    const trustedGuardSha = git('rev-parse', 'HEAD');
    executable = join(cwd, 'guard-from-trusted-main.mjs');
    writeFileSync(executable, git('show', `${trustedGuardSha}:${guardPath}`));
  }
  const result = spawnSync(process.execPath, ['--import', join(cwd, 'api.mjs'), executable], {
    cwd,
    encoding: 'utf8',
    env: { PATH: process.env.PATH, GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', MOBILE_DELIVERY_SHA: candidate,
      GITHUB_EVENT_NAME: scenario.event ?? 'workflow_dispatch', GITHUB_REF: scenario.ref ?? 'refs/heads/main',
      MOBILE_DELIVERY_MODE: scenario.mode ?? 'native',
      ...(scenario.platform === undefined ? {} : { MOBILE_DELIVERY_PLATFORM: scenario.platform }),
      GITHUB_OUTPUT: outputFile, GITHUB_STEP_SUMMARY: summaryFile },
  });
  const requests = existsSync(join(cwd, 'requests.jsonl')) ? readFileSync(join(cwd, 'requests.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line)) : [];
  return { ...result, candidate, baseline, requests, output: readFileSync(outputFile, 'utf8'), summary: readFileSync(summaryFile, 'utf8') };
}

test('an explicit native dispatch with all gates on the exact main push selects the new native build', (t) => {
  const result = plan(t);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=native\nsha=${result.candidate}\n`);
  assert.match(result.summary, /Android 1\.0\.6 \(23\)/);
});

for (const [name, scenario] of Object.entries({
  absent: { nativeAbsent: true },
  pending: { nativeConclusion: null },
  failure: { nativeConclusion: 'failure' },
  cancelled: { nativeConclusion: 'cancelled' },
  skipped: { nativeConclusion: 'skipped' },
  'wrong SHA': { nativeWrongSha: true },
  'PR instead of push': { nativePr: true },
  'other branch': { nativeOtherBranch: true },
  'latest failure after older success': { nativeConclusion: 'failure', olderSuccess: true },
})) {
  test(`native gate ${name} prevents delivery`, (t) => {
    const result = plan(t, scenario);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.output, `mode=none\nsha=${result.candidate}\n`);
    assert.match(result.summary, /Waiting for android-native-recette.yml/);
  });
}

test('a newer main prevents delivery before checking the old candidate', (t) => {
  const result = plan(t, { newerMain: true });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.output, /^mode=none\n/);
  assert.match(result.summary, /newer main/);
});

test('a partial native delivery checks every gate on its reserved source', (t) => {
  const result = plan(t, { reserved: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=native\nsha=${result.baseline}\n`);
});

test('a missing native result blocks even a partially reserved delivery', (t) => {
  const result = plan(t, { reserved: true, nativeAbsent: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=none\nsha=${result.baseline}\n`);
});

test('Vercel must still succeed after the native gate', (t) => {
  const result = plan(t, { vercelState: 'pending' });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.output, /^mode=none\n/);
  assert.match(result.summary, /Waiting for the Vercel deployment/);
});

test('native workflow API failure fails closed without a delivery output', (t) => {
  const result = plan(t, { apiFailure: 'android-native-recette.yml' });
  assert.notEqual(result.status, 0);
  assert.equal(result.output, '');
  assert.match(result.stderr, /GitHub 503/);
});

test('the real planner blocks a frontend-only push without inherited backend evidence', (t) => {
  const result = plan(t, { backendMissing: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=none\nsha=${result.candidate}\n`);
  assert.match(result.summary, /Waiting for Supabase: no deployment evidence/);
});

test('the real planner accepts a frontend descendant with a compatible deployed backend', (t) => {
  const result = plan(t, { backendEvidence: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=native\nsha=${result.candidate}\n`);
});

test('the backend guard also protects the resolved reservation, not just the new main', (t) => {
  const result = plan(t, { reserved: true, backendMissing: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=none\nsha=${result.baseline}\n`);
  assert.match(result.summary, /Waiting for Supabase/);
});

test('the final submission recheck fails with a nonzero exit when backend evidence disappears', (t) => {
  const result = plan(t, { backendMissing: true, recheck: true });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Waiting for Supabase/);
});

test('the final submission recheck succeeds without writing any release output when evidence is valid', (t) => {
  const result = plan(t, { backendEvidence: true, recheck: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, '');
  assert.match(result.summary, /Supabase .* verified by run 21, attempt 1/);
});

test('an older reserved source without a guard file is verified by the standalone guard frozen from trusted main', (t) => {
  const result = plan(t, { backendEvidence: true, recheck: true, legacyGuard: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, '');
  assert.match(result.summary, /Supabase .* verified by run 21, attempt 1/);
});

test('the extracted trusted guard still blocks an older reserved source with no backend evidence', (t) => {
  const result = plan(t, { backendMissing: true, recheck: true, legacyGuard: true });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Waiting for Supabase/);
});

for (const event of ['push', 'status', 'workflow_run', 'pull_request', '']) {
  test(`event ${event || 'absent'} cannot authorize a release even with native mode`, (t) => {
    const result = plan(t, { event });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.output, `mode=none\nsha=${result.candidate}\n`);
    assert.match(result.summary, /explicit manual dispatch/);
  });
}

test('manual dispatch on another branch cannot authorize a release', (t) => {
  const result = plan(t, { ref: 'refs/heads/fix/example' });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.output, /^mode=none\n/);
});

for (const mode of ['check', '']) {
  test(`verification ${mode || 'default'} checks the gates without starting a build`, (t) => {
    const result = plan(t, { mode });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.output, /^mode=none\n/);
    assert.match(result.summary, /Verification only/);
  });
}

test('verification reports missing checks without releasing', (t) => {
  const result = plan(t, { mode: 'check', nativeAbsent: true });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.output, /^mode=none\n/);
  assert.match(result.summary, /Waiting for android-native-recette/);
});

test('an OTA request never escalates to a native build when a runtime is missing', (t) => {
  const result = plan(t, { mode: 'ota' });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.output, /^mode=none\n/);
  assert.match(result.summary, /OTA cannot start a native/);
});

test('legacy auto mode is rejected without a release output', (t) => {
  const result = plan(t, { mode: 'auto' });
  assert.notEqual(result.status, 0);
  assert.equal(result.output, '');
  assert.match(result.stderr, /Unknown manual delivery mode/);
});

// A real git graph proves ancestry/content; only the GitHub transport is fake.
function backendFixture(t) {
  const cwd = mkdtempSync(join(tmpdir(), 'jolene-backend-gate-'));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init', '-q', '--initial-branch=main');
  function commit(files, message) {
    for (const [path, text] of Object.entries(files)) {
      const file = join(cwd, path);
      mkdirSync(dirname(file), { recursive: true });
      if (text === null) rmSync(file); else writeFileSync(file, text);
    }
    git('add', '-A');
    git('-c', 'user.name=Recette', '-c', 'user.email=recette@example.invalid', 'commit', '-q', '--allow-empty', '-m', message);
    return git('rev-parse', 'HEAD');
  }
  const first = commit({ 'supabase/functions/example/index.ts': 'version 1' }, 'backend 1');
  const second = commit({ 'supabase/functions/example/index.ts': 'version 2' }, 'backend 2');
  const frontend = commit({ 'src/App.tsx': 'frontend' }, 'frontend only');
  const requests = [];
  const iso = seconds => new Date(Date.UTC(2026, 8, 28, 9, 0, seconds)).toISOString();
  function run(id, sha, options = {}) {
    return { id, workflow_id: 3, path: '.github/workflows/deploy-supabase.yml', run_attempt: 1,
      head_sha: sha, head_branch: 'main', event: 'push', repository: { full_name: 'Gabpcd/JJJJJ' },
      head_repository: { full_name: 'Gabpcd/JJJJJ' }, status: 'completed', conclusion: 'success',
      updated_at: iso(id * 10), ...options };
  }
  const state = { runs: [run(1, first), run(2, second)], jobs: null, attemptJobs: {}, apiFailure: false, malformed: false,
    inconsistent: false, foreignWorkflow: false, refreshed: null, pageSize: 100, jobsMissing: false };
  const api = async path => {
    requests.push(path);
    if (state.apiFailure) throw new Error('GitHub 503');
    if (path === 'actions/workflows/deploy-supabase.yml') return { id: 3,
      path: state.foreignWorkflow ? '.github/workflows/staging.yml' : '.github/workflows/deploy-supabase.yml', state: 'active' };
    if (path.startsWith('actions/workflows/3/runs?')) {
      const page = Number(new URLSearchParams(path.split('?')[1]).get('page'));
      const items = state.runs.slice((page - 1) * state.pageSize, page * state.pageSize);
      return state.malformed ? {} : { total_count: state.runs.length + (state.inconsistent && page > 1 ? 1 : 0), workflow_runs: items };
    }
    const match = path.match(/^actions\/runs\/(\d+)\/attempts\/(\d+)\/jobs\?/);
    if (match) {
      const r = state.runs.find(r => r.id === Number(match[1]));
      const attempt = Number(match[2]);
      assert.ok(attempt >= 1 && attempt <= r.run_attempt);
      const jobs = state.attemptJobs[attempt] || state.jobs || ['Apply SQL migrations', 'Deploy edge functions'].map((name, index) => ({
        id: r.id * 10 + index, name, run_id: r.id, head_sha: r.head_sha,
        status: 'completed', conclusion: 'success', started_at: iso(r.id * 10 - 5 + index),
      }));
      return { total_count: state.jobsMissing ? jobs.length + 1 : jobs.length, jobs: state.jobsMissing ? [] : jobs };
    }
    const detail = path.match(/^actions\/runs\/(\d+)$/);
    if (detail) return state.refreshed || state.runs.find(r => r.id === Number(detail[1]));
    throw new Error('Unexpected API request: ' + path);
  };
  return { git, commit, first, second, frontend, run, state, api, requests, iso,
    check: (sha = frontend) => checkBackendDeployment({ sha, api, git }) };
}

test('an exact backend commit is allowed only with a complete successful production deployment', async (t) => {
  const f = backendFixture(t);
  assert.equal((await f.check(f.second)).ready, true);
});

test('frontend descendants reuse the matching deployed backend without requiring a new deployment', async (t) => {
  const f = backendFixture(t);
  assert.equal((await f.check()).ready, true);
});

for (const conclusion of ['failure', 'cancelled', 'skipped', null]) {
  test(`a ${conclusion} backend deployment followed by a green frontend cannot inherit an older success`, async (t) => {
    const f = backendFixture(t);
    f.state.runs[1].conclusion = conclusion;
    assert.equal((await f.check()).ready, false);
  });
}

test('a missing latest deployment is detected by backend content, not by a frontend diff', async (t) => {
  const f = backendFixture(t);
  f.state.runs.pop();
  const result = await f.check();
  assert.equal(result.ready, false);
  assert.match(result.reason, /backend changes/);
});

test('no deployment signal fails closed even with green frontend checks', async (t) => {
  const f = backendFixture(t);
  f.state.runs = [];
  assert.equal((await f.check()).ready, false);
});

test('a newer successful backend and its frontend descendants are accepted', async (t) => {
  const f = backendFixture(t);
  const backend3 = f.commit({ 'supabase/migrations/001.sql': 'select 1;' }, 'backend 3');
  const candidate = f.commit({ 'src/App.tsx': 'frontend 2' }, 'frontend 2');
  f.state.runs.push(f.run(3, backend3));
  assert.equal((await f.check(candidate)).ready, true);
  assert.equal((await f.check(f.frontend)).ready, false, 'An older reserved source cannot resume against the newer backend');
});

test('a push ending with a frontend commit can prove all backend changes from that push', async (t) => {
  const f = backendFixture(t);
  f.state.runs = [f.run(1, f.first), f.run(2, f.frontend)];
  assert.equal((await f.check()).ready, true);
});

for (const [name, change] of Object.entries({
  'other ref': { head_branch: 'repair/backend' },
  'foreign head repository': { head_repository: { full_name: 'other/repository' } },
  'PR event': { event: 'pull_request' },
  'different workflow path': { path: '.github/workflows/staging.yml' },
})) {
  test(`a newer deployment from ${name} cannot authorize production delivery`, async (t) => {
    const f = backendFixture(t);
    Object.assign(f.state.runs[1], change);
    assert.equal((await f.check()).ready, false);
  });
}

test('a successful manual dispatch on main is valid deployment evidence', async (t) => {
  const f = backendFixture(t);
  f.state.runs[1].event = 'workflow_dispatch';
  assert.equal((await f.check()).ready, true);
});

test('an older run rerun later and failing invalidates the newer old success', async (t) => {
  const f = backendFixture(t);
  Object.assign(f.state.runs[0], { run_attempt: 2, updated_at: f.iso(40), conclusion: 'failure' });
  assert.equal((await f.check()).ready, false);
});

test('an in-progress rerun blocks even when its run id is old', async (t) => {
  const f = backendFixture(t);
  Object.assign(f.state.runs[0], { run_attempt: 2, updated_at: f.iso(40), status: 'in_progress', conclusion: null });
  assert.equal((await f.check()).ready, false);
});

function preparePartialRerun(f) {
  const names = ['Apply SQL migrations', 'Deploy edge functions'];
  const job = (index, attempt, start, conclusion = 'success') => ({
    id: attempt * 100 + index, name: names[index], run_id: 2, head_sha: f.second,
    status: 'completed', conclusion, started_at: f.iso(start),
  });
  Object.assign(f.state.runs[1], { run_attempt: 2, updated_at: f.iso(50) });
  f.state.attemptJobs[1] = [job(0, 1, 15), job(1, 1, 16, 'failure')];
  f.state.attemptJobs[2] = [job(1, 2, 40)];
  return job;
}

test('rerunning only failed Edge jobs preserves a successful migration parent', async (t) => {
  const f = backendFixture(t);
  preparePartialRerun(f);
  assert.equal((await f.check()).ready, true);
  assert.ok(f.requests.some(path => path.includes('/attempts/1/jobs')));
});

test('a partial rerun is blocked if another deployment intervened after the reused migration', async (t) => {
  const f = backendFixture(t);
  preparePartialRerun(f);
  f.state.runs.push(f.run(3, f.second)); // Ends at 30, after migration 15 and before Edge rerun 40.
  const result = await f.check();
  assert.equal(result.ready, false);
  assert.match(result.reason, /ambiguous or overlapping/);
});

test('a full rerun after an intervening deployment uses only the new complete evidence', async (t) => {
  const f = backendFixture(t);
  const job = preparePartialRerun(f);
  f.state.runs.push(f.run(3, f.second));
  f.state.attemptJobs[2] = [job(0, 2, 40), job(1, 2, 41)];
  assert.equal((await f.check()).ready, true);
  assert.equal(f.requests.some(path => path.includes('/attempts/1/jobs')), false);
});

test('repeated partial reruns can reuse the original successful migration without reusing failed Edge states', async (t) => {
  const f = backendFixture(t);
  const job = preparePartialRerun(f);
  Object.assign(f.state.runs[1], { run_attempt: 3, updated_at: f.iso(60) });
  f.state.attemptJobs[2] = [job(1, 2, 40, 'failure')];
  f.state.attemptJobs[3] = [job(1, 3, 55)];
  assert.equal((await f.check()).ready, true);
});

test('a new Edge failure never falls back to an older successful Edge job', async (t) => {
  const f = backendFixture(t);
  const job = preparePartialRerun(f);
  f.state.attemptJobs[1][1].conclusion = 'success';
  f.state.attemptJobs[2] = [job(1, 2, 40, 'failure')];
  assert.equal((await f.check()).ready, false);
});

for (const fault of ['missing parent', 'failed parent', 'duplicate name', 'duplicate id across attempts', 'wrong identity']) {
  test(`partial rerun with ${fault} remains blocked`, async (t) => {
    const f = backendFixture(t);
    preparePartialRerun(f);
    if (fault === 'missing parent') f.state.attemptJobs[1].shift();
    if (fault === 'failed parent') f.state.attemptJobs[1][0].conclusion = 'failure';
    if (fault === 'duplicate name') f.state.attemptJobs[2].push({ ...f.state.attemptJobs[2][0], id: 299 });
    if (fault === 'duplicate id across attempts') f.state.attemptJobs[1][0].id = f.state.attemptJobs[2][0].id;
    if (fault === 'wrong identity') f.state.attemptJobs[1][0].head_sha = f.first;
    assert.equal((await f.check()).ready, false);
  });
}

test('overlapping attempts cannot establish the active backend', async (t) => {
  const f = backendFixture(t);
  f.state.runs[0].updated_at = f.iso(16);
  assert.match((await f.check()).reason, /ambiguous or overlapping/);
});

test('an attempt restarted during verification cannot authorize delivery', async (t) => {
  const f = backendFixture(t);
  f.state.refreshed = { ...f.state.runs[1], run_attempt: 2, status: 'queued', conclusion: null };
  assert.equal((await f.check()).ready, false);
});

for (const path of backendPaths) {
  test(`changes to backend input ${path}, including shared code, require a deployment`, async (t) => {
    const f = backendFixture(t);
    const file = path.endsWith('.toml') || path.endsWith('.yml') ? path : `${path}/_shared/new.txt`;
    const candidate = f.commit({ [file]: 'changed backend input' }, 'backend input changed');
    assert.equal((await f.check(candidate)).ready, false);
  });
}

test('backend deletion or rename is not treated as no backend', async (t) => {
  const f = backendFixture(t);
  const candidate = f.commit({ 'supabase/functions/example/index.ts': null, 'supabase/functions/renamed/index.ts': 'version 2' }, 'rename backend');
  assert.equal((await f.check(candidate)).ready, false);
});

test('an undeployed backend change remains visible beyond a 300-file diff', async (t) => {
  const f = backendFixture(t);
  const files = Object.fromEntries(Array.from({ length: 301 }, (_, i) => [`src/file-${i}.ts`, 'frontend']));
  files['supabase/functions/example/index.ts'] = 'version 3';
  assert.equal((await f.check(f.commit(files, 'large change'))).ready, false);
});

test('full pagination includes a late rerun on an older page', async (t) => {
  const f = backendFixture(t);
  f.state.pageSize = 1;
  f.state.runs.reverse();
  Object.assign(f.state.runs[1], { run_attempt: 2, updated_at: f.iso(40), conclusion: 'failure' });
  assert.equal((await f.check()).ready, false);
  assert.ok(f.requests.some(path => path.endsWith('page=2')));
});

for (const flag of ['apiFailure', 'malformed', 'inconsistent', 'foreignWorkflow', 'jobsMissing']) {
  test(`${flag} cannot silently allow a delivery`, async (t) => {
    const f = backendFixture(t);
    f.state[flag] = true;
    if (flag === 'inconsistent') f.state.pageSize = 1;
    await assert.rejects(f.check());
  });
}

test('a shallow checkout is rejected rather than assuming no backend history', async (t) => {
  const f = backendFixture(t);
  await assert.rejects(checkBackendDeployment({ sha: f.frontend, api: f.api,
    git: (...args) => args[0] === 'rev-parse' ? 'true' : f.git(...args) }), /Full git history/);
});

test('workflow rechecks protect both publishing paths and retain read-only Actions permission', () => {
  const workflow = readFileSync(join(root, '.github/workflows/mobile-delivery.yml'), 'utf8');
  const ota = workflow.slice(workflow.indexOf('\n  ota:'), workflow.indexOf('\n  reserve-native:'));
  const native = workflow.slice(workflow.indexOf('\n  native:'));
  for (const [job, publish] of [[ota, 'Publish archive first and manifest last'], [native, 'Submit Android for review']]) {
    assert.match(job, /actions: read/);
    assert.match(job, /fetch-depth: 0/);
    assert.match(job, /MOBILE_DELIVERY_GUARD_SHA: \$\{\{ needs\.plan\.outputs\.guard_sha \}\}/);
    assert.match(job, /git show "\$MOBILE_DELIVERY_GUARD_SHA:scripts\/mobile\/delivery-plan-backend\.mjs"/);
    assert.match(job, /node "\$RUNNER_TEMP\/mobile-delivery-plan-backend\.mjs"/);
    assert.ok(job.indexOf('node "$RUNNER_TEMP/mobile-delivery-plan-backend.mjs"') < job.indexOf(`- name: ${publish}`));
  }
  const triggers = workflow.slice(workflow.indexOf('\non:\n'), workflow.indexOf('\npermissions:'));
  assert.match(triggers, /workflow_dispatch:/);
  assert.doesNotMatch(triggers, /status:|workflow_run:|push:|schedule:/);
  assert.match(triggers, /default: check/);
  for (const [job, mode] of [[ota, 'ota'], [native, 'native']]) {
    assert.ok(job.includes("github.event_name == 'workflow_dispatch'"));
    assert.ok(job.includes("github.ref == 'refs/heads/main'"));
    assert.ok(job.includes(`inputs.mode == '${mode}'`));
  }
  assert.match(workflow, /guard_sha: \$\{\{ steps\.guard\.outputs\.sha \}\}/);
  assert.match(workflow, /echo "sha=\$\(git rev-parse HEAD\)" >> "\$GITHUB_OUTPUT"/);
});

test('the backend comparison covers exactly the production workflow path triggers', () => {
  const workflow = readFileSync(join(root, '.github/workflows/deploy-supabase.yml'), 'utf8');
  const paths = workflow.match(/    paths:\n([\s\S]+?)  workflow_dispatch:/)[1];
  const triggers = [...paths.matchAll(/- '([^']+)'/g)].map(match => match[1].replace(/\/\*\*$/, ''));
  assert.deepEqual(backendPaths, triggers);
  for (const jobName of ['Apply SQL migrations', 'Deploy edge functions']) assert.ok(workflow.includes(`name: ${jobName}`));
});

// ---------------------------------------------------------------------------------------------
// Lot 6 : livraisons scindées par plateforme (docs/mobile-swift/DECISIONS_LOT6.md).
// Android (coquille Capacitor) se livre seul, natif Play et OTA ; iOS (Swift) ne passe jamais par
// ce planificateur, n'a pas d'OTA (Apple 2.5.2) et la coquille Capacitor iOS n'est plus construite.
// ---------------------------------------------------------------------------------------------

const SCINDEE = { ios: { runtime: 'swift', marketingVersion: '2.0.0', minimumBuildNumber: 32 },
  android: { runtime: 'capacitor', marketingVersion: '1.0.8', buildNumber: 25 } };
const scindee = (patch = {}) => JSON.stringify({ ios: { ...SCINDEE.ios, ...patch.ios }, android: { ...SCINDEE.android, ...patch.android }, ...patch.racine });

test('la configuration du dépôt est scindée : iOS Swift 2.0.0 (build 32 minimum), Android Capacitor 1.0.x', () => {
  const config = lireConfigLivraison(readFileSync(join(root, 'config/mobile-release.json'), 'utf8'));
  assert.deepEqual(Object.keys(config).sort(), ['android', 'ios']);
  assert.equal(config.ios.runtime, 'swift');
  assert.equal(config.ios.marketingVersion, '2.0.0');
  assert.ok(config.ios.minimumBuildNumber >= 32, 'TestFlight contient déjà 2.0.0 (25 à 31)');
  assert.equal(config.android.runtime, 'capacitor');
  assert.match(config.android.marketingVersion, /^1\.0\.\d+$/);
  assert.ok(config.android.buildNumber >= COQUILLE_IOS_FIGEE.buildNumber);
  assert.deepEqual(COQUILLE_IOS_FIGEE, { marketingVersion: '1.0.7', buildNumber: 24 });
});

for (const [nom, source, attendu] of [
  ['l\'ancien format à plat', JSON.stringify({ marketingVersion: '1.0.7', buildNumber: 24 }), /scindée par plateforme/],
  ['un reste de l\'ancien format', scindee({ racine: { buildNumber: 24 } }), /scindée par plateforme/],
  ['une plateforme inconnue', scindee({ racine: { web: {} } }), /clé inconnue « web »/],
  ['un iOS qui ne serait pas Swift', scindee({ ios: { runtime: 'capacitor' } }), /ios\.runtime doit valoir « swift »/],
  ['un Android qui ne serait pas Capacitor', scindee({ android: { runtime: 'swift' } }), /android\.runtime doit valoir « capacitor »/],
  ['une version iOS qui ne dépasse pas la coquille 1.0.7', scindee({ ios: { marketingVersion: '1.0.7' } }), /ios\.marketingVersion .* doit dépasser 1\.0\.7/],
  ['un build iOS minimal qui ne dépasse pas 24', scindee({ ios: { minimumBuildNumber: 24 } }), /ios\.minimumBuildNumber .* doit dépasser 24/],
  ['un numéro de build iOS figé', scindee({ ios: { buildNumber: 32 } }), /ios\.buildNumber n'existe pas/],
  ['un versionCode Android invalide', scindee({ android: { buildNumber: '25' } }), /android\.buildNumber/],
  ['une version Android invalide', scindee({ android: { marketingVersion: '1.0.x' } }), /android\.marketingVersion/],
  ['un JSON illisible', '{', /illisible/],
]) {
  test(`la configuration de livraison refuse ${nom}`, () => {
    assert.throws(() => lireConfigLivraison(source), (error) => {
      assert.match(error.message, attendu);
      assert.match(error.message, /docs\/mobile-swift\/DECISIONS_LOT6\.md/);
      return true;
    });
  });
}

test('les tags sont scindés par plateforme et la plateforme de mobile-delivery est Android seul', () => {
  assert.deepEqual(tagsLivraison('android', 25), { soumis: 'mobile-native-android-25', source: 'mobile-native-source-android-25' });
  assert.deepEqual(tagsLivraison('ios', 32), { soumis: 'mobile-native-ios-32', source: null });
  assert.throws(() => tagsLivraison('web', 1), /Plateforme inconnue/);
  assert.throws(() => tagsLivraison('android', 0), /Numéro de build invalide/);
  assert.equal(plateformeMobileDelivery(undefined), 'android');
  assert.equal(plateformeMobileDelivery('android'), 'android');
  assert.throws(() => plateformeMobileDelivery('ios'), /ios-native-testflight\.yml.*ios-native-app-store\.yml.*2\.5\.2/s);
  assert.throws(() => plateformeMobileDelivery('all'), /Plateforme de livraison inconnue/);
});

test('une OTA n\'est possible que sur un runtime Android que la coquille iOS n\'a jamais porté', () => {
  const config = lireConfigLivraison(scindee());
  assert.deepEqual(exigerOtaAndroidSeul(config), { marketingVersion: '1.0.8', buildNumber: 25 });
  const partage = lireConfigLivraison(scindee({ android: { marketingVersion: '1.0.7', buildNumber: 24 } }));
  assert.throws(() => exigerOtaAndroidSeul(partage), /runtime 24 .* coquille Capacitor iOS 1\.0\.7 \(24\)/s);
});

test('Android se livre seul : aucun tag ni build iOS n\'est exigé, le résumé nomme la plateforme', (t) => {
  const result = plan(t, { platform: 'android' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=native\nsha=${result.candidate}\n`);
  assert.match(result.summary, /Google Play/);
});

for (const mode of ['native', 'ota', 'check']) {
  test(`iOS natif ne passe jamais par ce planificateur (mode ${mode})`, (t) => {
    const result = plan(t, { platform: 'ios', mode });
    assert.notEqual(result.status, 0);
    assert.equal(result.output, '');
    assert.match(result.stderr, /ios-native-app-store\.yml/);
    assert.match(result.stderr, /2\.5\.2/);
  });
}

test('l\'ancien format de configuration arrête le planificateur sans sortie de livraison', (t) => {
  const result = plan(t, { config: { marketingVersion: '1.0.6', buildNumber: 23 } });
  assert.notEqual(result.status, 0);
  assert.equal(result.output, '');
  assert.match(result.stderr, /scindée par plateforme/);
});

for (const [nom, baselineTags] of Object.entries({
  'un tag Android scindé': ['mobile-native-android-23'],
  'un ancien tag commun': ['mobile-native-23'],
  'un tag Android plus récent': ['mobile-native-android-22', 'mobile-native-android-30'],
  'un ancien tag commun plus récent': ['mobile-native-30'],
})) {
  test(`le numéro de build Android doit dépasser ${nom}`, (t) => {
    const result = plan(t, { baselineTags });
    assert.notEqual(result.status, 0);
    assert.equal(result.output, '');
    assert.match(result.stderr, /Native build number must increase|Build number already submitted/);
  });
}

test('les tags iOS (coquille ou Swift) ne bloquent ni ne débloquent une livraison Android', (t) => {
  const result = plan(t, { baselineTags: ['mobile-native-android-22', 'mobile-native-ios-22', 'mobile-native-ios-31', 'mobile-native-ios-40'] });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=native\nsha=${result.candidate}\n`);
});

const OTA = { mode: 'ota', build: 25, baselineTags: ['mobile-native-android-25'], otaReviewed: true, files: { 'src/App.tsx': 'correctif' } };

test('une OTA Android part du tag mobile-native-android-N, sans tag commun ni tag iOS', (t) => {
  const result = plan(t, OTA);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=ota\nsha=${result.candidate}\n`);
});

test('un ancien tag commun seul ne vaut pas runtime Android : pas d\'OTA', (t) => {
  const result = plan(t, { ...OTA, baselineTags: ['mobile-native-25'] });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.output, /^mode=none\n/);
  assert.match(result.summary, /OTA cannot start a native/);
});

test('une OTA sur le runtime 24, partagé avec la coquille iOS encore installée, est refusée', (t) => {
  const result = plan(t, { ...OTA, build: 24, baselineTags: ['mobile-native-android-24', 'mobile-native-ios-24', 'mobile-native-24'] });
  assert.notEqual(result.status, 0);
  assert.equal(result.output, '');
  assert.match(result.stderr, /coquille Capacitor iOS 1\.0\.7 \(24\)/);
});

for (const fichier of ['ios-native/Jolene/JoleneApp.swift', 'ios-native/Config/Base.xcconfig', 'ios/App/App/Info.plist', 'android/app/build.gradle']) {
  test(`une OTA est refusée dès qu'un diff touche ${fichier.split('/')[0]}/ : build store exigé`, (t) => {
    const result = plan(t, { ...OTA, files: { ...OTA.files, [fichier]: 'modifié' } });
    assert.notEqual(result.status, 0);
    assert.equal(result.output, '');
    assert.match(result.stderr, new RegExp(`Native changes require a store build: ${fichier.replaceAll('.', '\\.')}`));
  });
}

test('une OTA sans PR relue mobile:ota ne part pas', (t) => {
  const result = plan(t, { ...OTA, otaReviewed: false });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.output, /^mode=none\n/);
  assert.match(result.summary, /No reviewed mobile:ota PR/);
});

// --- release-state.mjs : tags scindés, jamais « les deux plateformes » -------------------------

function etat(t, { args, tags = {}, env = {}, config = SCINDEE }) {
  const cwd = mkdtempSync(join(tmpdir(), 'jolene-release-state-'));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  mkdirSync(join(cwd, 'config'));
  writeFileSync(join(cwd, 'config/mobile-release.json'), JSON.stringify(config));
  writeFileSync(join(cwd, 'tags.json'), JSON.stringify(tags));
  writeFileSync(join(cwd, 'api.mjs'), `
    import { appendFileSync, readFileSync } from 'node:fs';
    const tags = JSON.parse(readFileSync('tags.json', 'utf8'));
    globalThis.fetch = async (url, init = {}) => {
      const path = new URL(url).pathname.replace('/repos/Gabpcd/JJJJJ/', '');
      const method = init.method || 'GET';
      appendFileSync('requests.jsonl', JSON.stringify({ method, path, body: init.body ? JSON.parse(init.body) : null }) + '\\n');
      if (method === 'GET' && path.startsWith('git/ref/tags/')) {
        const sha = tags[path.slice('git/ref/tags/'.length)];
        return sha ? Response.json({ object: { sha } }) : new Response('', { status: 404 });
      }
      if (method === 'POST' && path === 'git/refs') return Response.json({}, { status: 201 });
      throw new Error('Unexpected API request: ' + method + ' ' + path);
    };
  `);
  const outputFile = join(cwd, 'output');
  writeFileSync(outputFile, '');
  const result = spawnSync(process.execPath, ['--import', join(cwd, 'api.mjs'), join(root, 'scripts/mobile/release-state.mjs'), ...args], {
    cwd, encoding: 'utf8',
    env: { PATH: process.env.PATH, GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', RELEASE_SHA: 'a'.repeat(40), GITHUB_OUTPUT: outputFile, ...env },
  });
  const requests = existsSync(join(cwd, 'requests.jsonl')) ? readFileSync(join(cwd, 'requests.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line)) : [];
  return { ...result, requests, created: requests.filter(r => r.method === 'POST').map(r => r.body), output: readFileSync(outputFile, 'utf8') };
}

const SHA = 'a'.repeat(40);
const AUTRE = 'b'.repeat(40);

test('Android réserve sa source puis consigne sa soumission sous des tags Android, sans tag commun', (t) => {
  const reserve = etat(t, { args: ['reserve', 'android'] });
  assert.equal(reserve.status, 0, reserve.stderr);
  assert.deepEqual(reserve.created, [{ ref: 'refs/tags/mobile-native-source-android-25', sha: SHA }]);
  const record = etat(t, { args: ['record', 'android'] });
  assert.equal(record.status, 0, record.stderr);
  assert.deepEqual(record.created, [{ ref: 'refs/tags/mobile-native-android-25', sha: SHA }]);
  for (const { requests } of [reserve, record]) {
    assert.ok(requests.every(r => !/mobile-native-ios-|mobile-native-\d+$|mobile-native-source-\d+$/.test(r.path + (r.body?.ref ?? ''))), 'aucune lecture ni écriture de tag iOS ou commun');
  }
});

test('l\'état Android se lit sans l\'état iOS, et une reprise sur le même commit ne réécrit rien', (t) => {
  const absent = etat(t, { args: ['check', 'android'] });
  assert.equal(absent.status, 0, absent.stderr);
  assert.equal(absent.output, 'submitted=false\n');
  const present = etat(t, { args: ['check', 'android'], tags: { 'mobile-native-android-25': SHA } });
  assert.equal(present.output, 'submitted=true\n');
  const reprise = etat(t, { args: ['record', 'android'], tags: { 'mobile-native-android-25': SHA } });
  assert.equal(reprise.status, 0, reprise.stderr);
  assert.deepEqual(reprise.created, []);
});

test('un tag de plateforme appartenant à un autre commit arrête tout', (t) => {
  for (const args of [['check', 'android'], ['record', 'android'], ['reserve', 'android']]) {
    const tag = args[0] === 'reserve' ? 'mobile-native-source-android-25' : 'mobile-native-android-25';
    const result = etat(t, { args, tags: { [tag]: AUTRE } });
    assert.notEqual(result.status, 0, args.join(' '));
    assert.deepEqual(result.created, []);
  }
});

test('une soumission iOS Swift se consigne seule, avec le numéro du build TestFlight soumis', (t) => {
  const record = etat(t, { args: ['record', 'ios'], env: { RELEASE_BUILD_NUMBER: '32' } });
  assert.equal(record.status, 0, record.stderr);
  assert.deepEqual(record.created, [{ ref: 'refs/tags/mobile-native-ios-32', sha: SHA }]);
  assert.ok(record.requests.every(r => !/android/.test(r.path + (r.body?.ref ?? ''))), 'aucun tag Android lu ni écrit');
  for (const numero of [undefined, '', '31', '24', 'abc', '32.5', '032']) {
    const refus = etat(t, { args: ['record', 'ios'], env: numero === undefined ? {} : { RELEASE_BUILD_NUMBER: numero } });
    assert.notEqual(refus.status, 0, `numéro ${numero}`);
    assert.deepEqual(refus.created, []);
    assert.match(refus.stderr, /RELEASE_BUILD_NUMBER/);
  }
});

test('iOS ne réserve aucune source et l\'ancienne clôture commune est verrouillée', (t) => {
  const reserve = etat(t, { args: ['reserve', 'ios'], env: { RELEASE_BUILD_NUMBER: '32' } });
  assert.notEqual(reserve.status, 0);
  assert.match(reserve.stderr, /TestFlight/);
  for (const args of [['complete'], ['complete', 'android'], ['reserve'], ['record'], ['check'], ['record', 'web']]) {
    const result = etat(t, { args });
    assert.notEqual(result.status, 0, args.join(' '));
    assert.deepEqual(result.created, [], args.join(' '));
  }
  assert.match(etat(t, { args: ['complete'] }).stderr, /DECISIONS_LOT6\.md/);
});

// --- Workflow, OTA et alignement des versions ---------------------------------------------------

test('mobile-delivery.yml ne construit ni ne soumet plus rien pour iOS', () => {
  const workflow = readFileSync(join(root, '.github/workflows/mobile-delivery.yml'), 'utf8');
  const actif = workflow.split('\n').filter(line => !/^\s*#/.test(line)).join('\n');
  assert.doesNotMatch(actif, /xcodebuild|macos-|fastlane ios|ios\/App|ExportOptions|\bIOS_[A-Z_]+|\bASC_[A-Z_]+|security (?:create|import|unlock)-keychain|\.ipa\b/);
  assert.doesNotMatch(actif, /matrix/);
  assert.doesNotMatch(actif, /release-state\.mjs complete|record-native:/);
  assert.match(actif, /MOBILE_DELIVERY_PLATFORM: android/);
  for (const appel of ['release-state.mjs reserve android', 'release-state.mjs check android', 'release-state.mjs record android']) {
    assert.ok(actif.includes(appel), appel);
  }
  assert.deepEqual([...actif.matchAll(/\bfastlane\s+(\S+\s+\S+)/g)].map(m => m[1]), ['android submit']);
  const native = actif.slice(actif.indexOf('\n  native:'));
  assert.ok(native.indexOf('fastlane android submit') < native.indexOf('release-state.mjs record android'), 'le tag ne se pose qu\'après la soumission');
});

test('la signature et la publication OTA lisent la configuration Android par la garde commune', () => {
  for (const script of ['scripts/mobile/sign-update.mjs', 'scripts/mobile/publish-update.mjs']) {
    const source = readFileSync(join(root, script), 'utf8');
    assert.match(source, /exigerOtaAndroidSeul\(chargerConfigLivraison\(\)\)/, script);
    assert.doesNotMatch(source, /JSON\.parse\(readFileSync\('config\/mobile-release\.json'/, script);
  }
});

test('l\'app Swift n\'embarque aucun client de mise à jour à chaud (Apple 2.5.2)', () => {
  const interdit = /capawesome|live[-_ ]?update|mobile-ota|codepush|hot[-_ ]?update/i;
  const fichiers = execFileSync('git', ['ls-files', 'ios-native'], { cwd: root, encoding: 'utf8' }).trim().split('\n')
    .filter(file => /\.(swift|yml|resolved|xcconfig|plist|pbxproj)$/.test(file));
  assert.ok(fichiers.length > 100, 'sources Swift listées');
  const fautifs = fichiers.filter(file => interdit.test(readFileSync(join(root, file), 'utf8')));
  assert.deepEqual(fautifs, [], 'aucune OTA ne peut viser l\'app iOS native');
});

const gradle = (code, name) => `android {\n    defaultConfig {\n        versionCode ${code}\n        versionName "${name}"\n    }\n}\n`;
const xcconfig = (version) => `MARKETING_VERSION = ${version}\nCURRENT_PROJECT_VERSION = 25\n`;
const pbxproj = (version, build) => `CURRENT_PROJECT_VERSION = ${build};\nMARKETING_VERSION = ${version};\nCURRENT_PROJECT_VERSION = ${build};\nMARKETING_VERSION = ${version};\n`;

test('l\'alignement des versions se vérifie par plateforme : Android, Swift, coquille iOS gelée', () => {
  const config = lireConfigLivraison(scindee());
  const ok = { config, androidGradle: gradle(25, '1.0.8'), baseXcconfig: xcconfig('2.0.0'), coquilleIos: pbxproj('1.0.7', 24) };
  assert.deepEqual(verifierAlignement(ok), []);
  assert.deepEqual(verifierAlignement({ ...ok, coquilleIos: null }), [], 'ios/ supprimé au lot 7 : plus rien à geler');
  assert.match(verifierAlignement({ ...ok, androidGradle: gradle(24, '1.0.8') })[0], /Android versionCode=24, attendu 25/);
  assert.match(verifierAlignement({ ...ok, androidGradle: gradle(25, '1.0.7') })[0], /Android versionName=1\.0\.7, attendu 1\.0\.8/);
  assert.match(verifierAlignement({ ...ok, baseXcconfig: xcconfig('2.0.1') })[0], /iOS Swift MARKETING_VERSION=2\.0\.1, attendu 2\.0\.0/);
  assert.match(verifierAlignement({ ...ok, baseXcconfig: '' })[0], /iOS Swift MARKETING_VERSION=absent/);
  assert.match(verifierAlignement({ ...ok, coquilleIos: pbxproj('1.0.8', 26) }).join('\n'), /coquille Capacitor iOS .* gelée à 1\.0\.7 \(24\)/);
});

test('le dépôt actuel est aligné par plateforme', () => {
  const result = spawnSync(process.execPath, [join(root, 'scripts/check-mobile-build-alignment.mjs')], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Android .* iOS Swift/s);
});
