import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { backendPaths, checkBackendDeployment } from '../../scripts/mobile/delivery-plan-backend.mjs';

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
  git('tag', 'mobile-native-22');
  git('-c', 'user.name=Recette', '-c', 'user.email=recette@example.invalid', 'commit', '-q', '--allow-empty', '-m', 'candidate');
  const candidate = git('rev-parse', 'HEAD');
  if (scenario.reserved) {
    git('tag', 'mobile-native-source-23', baseline);
  }
  const checkedSha = scenario.reserved ? baseline : candidate;
  mkdirSync(join(cwd, 'config'));
  writeFileSync(join(cwd, 'config/mobile-release.json'), JSON.stringify({ marketingVersion: '1.0.6', buildNumber: 23 }));
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
    env: { PATH: process.env.PATH, GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', MOBILE_DELIVERY_SHA: scenario.backendWake ? baseline : candidate,
      MOBILE_DELIVERY_RECHECK_MAIN: scenario.backendWake ? 'true' : 'false',
      GITHUB_OUTPUT: outputFile, GITHUB_STEP_SUMMARY: summaryFile },
  });
  return { ...result, candidate, baseline, output: readFileSync(outputFile, 'utf8'), summary: readFileSync(summaryFile, 'utf8') };
}

test('all gates on the exact main push select the new native build', (t) => {
  const result = plan(t);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=native\nsha=${result.candidate}\n`);
  assert.match(result.summary, /1\.0\.6 \(23\)/);
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

test('a repaired backend ancestor wakes all release gates on current main', (t) => {
  const result = plan(t, { backendWake: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.output, `mode=native\nsha=${result.candidate}\n`);
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
  const native = workflow.slice(workflow.indexOf('\n  native:'), workflow.indexOf('\n  record-native:'));
  for (const [job, publish] of [[ota, 'Publish archive first and manifest last'], [native, 'Submit Android for review']]) {
    assert.match(job, /actions: read/);
    assert.match(job, /fetch-depth: 0/);
    assert.match(job, /MOBILE_DELIVERY_GUARD_SHA: \$\{\{ needs\.plan\.outputs\.guard_sha \}\}/);
    assert.match(job, /git show "\$MOBILE_DELIVERY_GUARD_SHA:scripts\/mobile\/delivery-plan-backend\.mjs"/);
    assert.match(job, /node "\$RUNNER_TEMP\/mobile-delivery-plan-backend\.mjs"/);
    assert.ok(job.indexOf('node "$RUNNER_TEMP/mobile-delivery-plan-backend.mjs"') < job.indexOf(`- name: ${publish}`));
  }
  assert.match(workflow, /Deploy Supabase \(migrations \\\+ edge functions\)/);
  assert.match(workflow, /MOBILE_DELIVERY_RECHECK_MAIN:/);
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
