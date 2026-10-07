import { requireValue } from './contract.mjs';
import { execFileSync } from 'node:child_process';
import { readFileSync, lstatSync, realpathSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

export const PRODUCT_SHA = '58968a0e42d65b90d0c8916479149326635a390e';
export const MIGRATION_COUNT = 221;
export const WORKFLOW_PATH = '.github/workflows/restore-local-bootstrap.yml';
export const BRANCH = 'ci/restore-app-phase-b-20261004';
export const ROOT = resolve(fileURLToPath(new URL('.', import.meta.url)), '../../../../..');
export const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const required = ok => requireValue(ok, 'B_IDENTITY');
export function executionIdentity(env, head) {
  required(env.GITHUB_REPOSITORY === 'Gabpcd/JJJJJ' && env.GITHUB_EVENT_NAME === 'workflow_dispatch'
    && env.GITHUB_REF === 'refs/heads/' + BRANCH && /^[a-f0-9]{40}$/.test(head) && env.GITHUB_SHA === head
    && env.GITHUB_WORKFLOW_REF === env.GITHUB_REPOSITORY + '/' + WORKFLOW_PATH + '@refs/heads/' + BRANCH
    && env.GITHUB_WORKFLOW_SHA === head
    && head !== PRODUCT_SHA && /^[1-9][0-9]{0,14}$/.test(env.GITHUB_RUN_ID ?? '')
    && /^[1-9][0-9]{0,2}$/.test(env.GITHUB_RUN_ATTEMPT ?? ''), 'PHASE_A_IDENTITY_REFUSED');
  const suffix = env.GITHUB_RUN_ID + '-' + env.GITHUB_RUN_ATTEMPT;
  return { productSha: PRODUCT_SHA, harnessSha: head, run: 'jolene-restore-drill-' + suffix,
    privateRoot: '/tmp/jolene-restore-phase-b-private-' + suffix,
    proofRoot: '/tmp/jolene-restore-phase-b-proof-' + suffix };
}
export function checkIdentity(env, head, changed, dirty, allowed) {
  const identity = executionIdentity(env, head);
  required(dirty === '' && changed.length > 0 && changed.every(path => allowed.includes(path)), 'PHASE_A_IDENTITY_REFUSED');
  return identity;
}
export function recoverySource(env = process.env) {
  // Cleanup still requires this exact run/ref/commit and the existing bootstrap's
  // resource ownership/plan guards, but not successful source/import/test pins.
  const head = execFileSync('git', ['-c','gc.auto=0','rev-parse', 'HEAD'], { cwd: ROOT, encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: process.env.HOME, GIT_CONFIG_NOSYSTEM: '1', GIT_NO_LAZY_FETCH: '1' }, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  return executionIdentity(env, head);
}
export function checkVercel(base, current) {
  const expected = { ...base, git: { ...(base.git ?? {}), deploymentEnabled: { ...(base.git?.deploymentEnabled ?? {}), 'ci/restore-app-phase-a-20261004': false, [BRANCH]: false } } };
  const canonical = value => value && typeof value === 'object' && !Array.isArray(value)
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
  required(JSON.stringify(canonical(expected)) === JSON.stringify(canonical(current)), 'PHASE_A_VERCEL_REFUSED');
}
export function source(env = process.env) {
  const git = args => execFileSync('git', ['-c','gc.auto=0',...args], { cwd: ROOT, encoding: null, maxBuffer: 32 * 1024 * 1024,
    env: { PATH: process.env.PATH, HOME: process.env.HOME, GIT_CONFIG_NOSYSTEM: '1', GIT_NO_LAZY_FETCH: '1' }, stdio: ['ignore', 'pipe', 'pipe'] });
  const pins = JSON.parse(readFileSync(new URL('./pins.json', import.meta.url), 'utf8'));
  required(pins.productSha === PRODUCT_SHA && pins.migrationCount === MIGRATION_COUNT && pins.migrations.length === MIGRATION_COUNT, 'PHASE_A_PIN_CONTEXT');
  const head = git(['-c','gc.auto=0','rev-parse', 'HEAD']).toString().trim();
  git(['merge-base', '--is-ancestor', PRODUCT_SHA, head]);
  required(git(['rev-parse', PRODUCT_SHA + '^{tree}']).toString().trim() === pins.productTree, 'PHASE_A_BASE_TREE_REFUSED');
  const changed = git(['diff', '--name-only', '-z', PRODUCT_SHA, head]).toString().split('\0').filter(Boolean);
  const identity = checkIdentity(env, head, changed, git(['status', '--porcelain', '--untracked-files=all']).toString(), pins.allowedChangedPaths);
  checkVercel(JSON.parse(git(['show', PRODUCT_SHA + ':vercel.json'])), JSON.parse(readFileSync(join(ROOT, 'vercel.json'), 'utf8')));
  for (const file of pins.pinnedFiles) {
    const path = join(ROOT, file.path), info = lstatSync(path);
    required(info.isFile() && !info.isSymbolicLink() && realpathSync(path) === path && info.size === file.bytes
      && hash(readFileSync(path)) === file.sha256, 'PHASE_A_PIN_CHANGED');
  }
  const canonicalPaths = git(['ls-tree', '-r', '--name-only', '-z', PRODUCT_SHA, 'supabase/migrations']).toString().split('\0').filter(Boolean);
  required(JSON.stringify(canonicalPaths) === JSON.stringify(pins.migrations.map(file => file.path)), 'PHASE_A_MIGRATION_INVENTORY');
  const migrations = pins.migrations.map(file => {
    const path = join(ROOT, file.path), bytes = readFileSync(path), canonical = git(['show', PRODUCT_SHA + ':' + file.path]);
    required(lstatSync(path).isFile() && realpathSync(path) === path && bytes.equals(canonical)
      && bytes.length === file.bytes && hash(bytes) === file.sha256, 'PHASE_A_MIGRATION_CHANGED');
    return { ...file, bytes };
  });
  const testPath = 'tests/security/refund-reuse-fixture-pg17.test.sql', testBytes = readFileSync(join(ROOT, testPath));
  return { ...identity, pins, migrations, test: { path: testPath, bytes: testBytes, sha256: hash(testBytes) } };
}
