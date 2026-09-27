import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const planner = join(root, 'scripts/mobile/delivery-plan.mjs');

// Run the real planner against disposable git history and a closed API fixture.
// No token, external fetch, build, store submission or real repository mutation.
function plan(t, scenario = {}) {
  const cwd = mkdtempSync(join(tmpdir(), 'jolene-delivery-plan-'));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init', '-q', '--initial-branch=main');
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
    globalThis.fetch = async (url) => {
      const parsed = new URL(url);
      assert.equal(parsed.origin, 'https://api.github.com');
      const path = parsed.pathname.replace('/repos/Gabpcd/JJJJJ/', '');
      appendFileSync('requests.jsonl', JSON.stringify(path) + '\\n');
      if (path === 'git/ref/heads/main') return Response.json({ object: { sha: f.newerMain ? f.baseline : f.candidate } });
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
  const result = spawnSync(process.execPath, ['--import', join(cwd, 'api.mjs'), planner], {
    cwd,
    encoding: 'utf8',
    env: { PATH: process.env.PATH, GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', MOBILE_DELIVERY_SHA: candidate,
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
