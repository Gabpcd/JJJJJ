#!/usr/bin/env node
// Public CI receives a closed projection, never Playwright's report or attachments.
import { execFileSync, spawn } from 'node:child_process';
import { constants } from 'node:fs';
import { chmod, lstat, mkdir, mkdtemp, open, readFile, realpath, rename, unlink } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { constants as osConstants, tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const PHASES = Object.freeze({
  'app-review': ['tablet-ipad'],
  chromium: ['chromium'],
  'series-c-ios': ['ios-webkit-audit'],
  'series-c-android': ['android-pixel-audit'],
  a11y: ['chromium'],
  'staging-comptes': ['staging-chromium'],
  'simulation-admin': ['ipad-portrait', 'ipad-paysage', 'iphone', 'android', 'ordinateur'],
});
const STATUSES = new Set(['passed', 'failed', 'timedOut', 'skipped', 'interrupted']);
const OUTCOMES = ['expected', 'unexpected', 'flaky', 'skipped'];
const MAX_REPORT_BYTES = 128 * 1024 * 1024;
const NO_FOLLOW = constants.O_NOFOLLOW || 0;
class ClosedError extends Error {
  constructor(code) { super(code); this.code = code; }
}
function requireValue(condition, code = 'REPORT_INVALID') {
  if (!condition) throw new ClosedError(code);
}
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const integer = (value, maximum = 100_000) => Number.isSafeInteger(value) && value >= 0 && value <= maximum;
const duration = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 7 * 24 * 3600_000;
const knownPhase = value => Object.hasOwn(PHASES, value);
const validSha = value => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value);
function sourceShaFromGit(cwd) {
  return execFileSync('git', ['rev-parse', 'HEAD'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

export function parseArguments(argv) {
  requireValue(argv[0] === '--phase' && knownPhase(argv[1]) && argv[2] === '--' && argv[3] === 'test', 'ARGUMENTS_REFUSED');
  const phase = argv[1];
  const args = ['test'];
  const config = phase === 'staging-comptes' ? 'e2e/playwright.staging-comptes.config.ts'
    : phase === 'simulation-admin' ? 'e2e/playwright.recette-complete.config.ts' : 'playwright.config.ts';
  let hasProject = false;
  for (let i = 4; i < argv.length; i++) {
    const arg = argv[i];
    requireValue(typeof arg === 'string' && !arg.includes('\0'), 'ARGUMENTS_REFUSED');
    const name = arg.split('=')[0];
    requireValue(arg !== '--' && !['--output', '--ui', '--ui-host', '--ui-port', '--debug', '--list', '--pass-with-no-tests', '--ignore-snapshots'].includes(name), 'ARGUMENTS_REFUSED');
    requireValue(!arg.startsWith('-c') || name === '-c' || arg.startsWith('--'), 'ARGUMENTS_REFUSED');
    if (['--reporter', '--trace', '--config', '-c', '--project'].includes(name)) {
      const value = arg.includes('=') ? arg.slice(arg.indexOf('=') + 1) : argv[++i];
      if (name === '--project') {
        requireValue(PHASES[phase].includes(value), 'ARGUMENTS_REFUSED');
        args.push(`--project=${value}`);
        hasProject = true;
      } else {
        requireValue(value === (name === '--reporter' ? 'json' : name === '--trace' ? 'off' : config), 'ARGUMENTS_REFUSED');
      }
      continue;
    }
    args.push(arg);
  }
  args.push(`--config=${config}`);
  if (!hasProject) for (const project of PHASES[phase]) args.push(`--project=${project}`);
  return { phase, args };
}

// No shell, npx, installation, or public stdio. Only the installed CLI is run.
async function launchInstalled({ cwd, args, env, stdoutFd, stderrFd }) {
  const require = createRequire(path.join(cwd, 'package.json'));
  const cli = path.join(path.dirname(require.resolve('playwright/package.json')), 'cli.js');
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cli, ...args], { cwd, env, stdio: ['ignore', stdoutFd, stderrFd] });
    const interrupt = () => child.kill('SIGINT');
    const terminate = () => child.kill('SIGTERM');
    process.once('SIGINT', interrupt);
    process.once('SIGTERM', terminate);
    const cleanup = () => {
      process.removeListener('SIGINT', interrupt);
      process.removeListener('SIGTERM', terminate);
    };
    child.once('error', () => { cleanup(); reject(new ClosedError('LAUNCH_FAILED')); });
    child.once('close', (code, signal) => {
      cleanup();
      resolve(code ?? 128 + (osConstants.signals[signal] || 1));
    });
  });
}

async function sourceLocation(spec, reportRoot, cwd) {
  requireValue(typeof spec.file === 'string' && /^[a-zA-Z0-9_./-]+\.spec\.[cm]?[jt]sx?$/.test(spec.file));
  requireValue(!spec.file.split('/').some(part => part === '..' || part === '') && !path.isAbsolute(spec.file));
  const candidate = path.resolve(reportRoot, spec.file);
  const e2e = path.join(cwd, 'e2e');
  requireValue(candidate.startsWith(e2e + path.sep));
  requireValue(await realpath(candidate) === candidate && (await lstat(candidate)).isFile());
  const lines = (await readFile(candidate, 'utf8')).split('\n');
  requireValue(integer(spec.line, lines.length) && spec.line > 0 && integer(spec.column) && spec.column > 0);
  return { file: path.relative(cwd, candidate).split(path.sep).join('/'), line: spec.line, column: spec.column };
}

// Only a coordinate in the already-published spec may leave the private report.
// Messages, code frames, function names, arbitrary paths and stack bytes never do.
async function failureLocation(result, location, cwd) {
  if (!['failed', 'timedOut'].includes(result.status)) return undefined;
  const candidate = path.join(cwd, location.file);
  if (await realpath(candidate) !== candidate || !(await lstat(candidate)).isFile()) return undefined;
  const lines = (await readFile(candidate, 'utf8')).split('\n');
  const coordinate = value => {
    if (!object(value) || ![candidate, location.file].includes(value.file)) return undefined;
    if (!integer(value.line, lines.length) || value.line === 0) return undefined;
    if (!integer(value.column, lines[value.line - 1].length + 1) || value.column === 0) return undefined;
    return { file: location.file, line: value.line, column: value.column };
  };
  const errors = [...result.errors.slice(0, 20), result.error].filter(object);
  for (const error of errors) {
    const structured = coordinate(error.location);
    if (structured) return structured;
    if (typeof error.stack !== 'string' || error.stack.length > 64 * 1024) continue;
    for (const frame of error.stack.split('\n').slice(0, 100)) {
      // Match a complete frame only; its captured path still must be the exact known spec.
      const match = /^\s+at (?:[^()\r\n]{1,512} \()?([^()\r\n]+):([0-9]{1,6}):([0-9]{1,6})\)?$/.exec(frame);
      if (!match) continue;
      const parsed = coordinate({ file: match[1], line: Number(match[2]), column: Number(match[3]) });
      if (parsed) return parsed;
    }
  }
  return undefined;
}

function outcomeOf(results, expectedStatus) {
  const executed = results.filter(result => !['skipped', 'interrupted'].includes(result.status));
  const expected = executed.filter(result => result.status === expectedStatus).length;
  const unexpected = executed.length - expected;
  if (!executed.length) return 'skipped';
  if (!unexpected) return 'expected';
  if (!expected && !results.some(result => result.status === 'skipped' && expectedStatus === 'skipped')) return 'unexpected';
  return 'flaky';
}

export async function projectReport(report, { phase, cwd }) {
  requireValue(knownPhase(phase) && object(report) && object(report.config) && object(report.stats));
  requireValue(Array.isArray(report.suites) && Array.isArray(report.errors) && integer(report.errors.length));
  const root = path.join(cwd, 'e2e', phase === 'staging-comptes' ? 'staging' : '');
  requireValue(report.config.rootDir === root && await realpath(root) === root);
  requireValue(duration(report.stats.duration));
  for (const key of OUTCOMES) requireValue(integer(report.stats[key]));
  const counts = { expected: 0, unexpected: 0, flaky: 0, skipped: 0 };
  const tests = [];
  const visit = async (suites, depth = 0) => {
    requireValue(depth <= 30 && suites.length <= 100_000);
    for (const suite of suites) {
      requireValue(object(suite) && Array.isArray(suite.specs));
      for (const spec of suite.specs) {
        requireValue(object(spec) && Array.isArray(spec.tests) && spec.tests.length > 0);
        const location = await sourceLocation(spec, root, cwd);
        for (const test of spec.tests) {
          requireValue(object(test) && PHASES[phase].includes(test.projectName));
          requireValue(STATUSES.has(test.expectedStatus) && OUTCOMES.includes(test.status) && Array.isArray(test.results));
          requireValue(test.results.length <= 1000 && tests.length < 100_000);
          const attempts = await Promise.all(test.results.map(async (result, index) => {
            requireValue(object(result) && STATUSES.has(result.status) && duration(result.duration) && result.retry === index);
            requireValue(Array.isArray(result.errors));
            requireValue(!['passed', 'skipped'].includes(result.status) || (result.errors.length === 0 && !result.error), 'REPORT_INCONSISTENT');
            const assertion = await failureLocation(result, location, cwd);
            return {
              ...(assertion ? { failureLocation: assertion } : {}),
              retry: index, status: result.status, durationMs: result.duration,
              code: result.status === 'timedOut' ? 'TIMEOUT' : result.status === 'interrupted' ? 'INTERRUPTED'
                : result.status === 'failed' ? 'TEST_FAILED' : result.status === 'skipped' ? 'SKIPPED' : 'PASSED',
            };
          }));
          requireValue(outcomeOf(attempts, test.expectedStatus) === test.status, 'REPORT_INCONSISTENT');
          counts[test.status]++;
          tests.push({ ordinal: tests.length + 1, ...location, project: test.projectName, expectedStatus: test.expectedStatus, outcome: test.status, attempts });
        }
      }
      if (suite.suites !== undefined) { requireValue(Array.isArray(suite.suites)); await visit(suite.suites, depth + 1); }
    }
  };
  await visit(report.suites);
  for (const key of OUTCOMES) requireValue(counts[key] === report.stats[key], 'REPORT_INCONSISTENT');
  requireValue(tests.length > 0 || report.errors.length > 0, 'NO_TESTS');
  return { counts, durationMs: report.stats.duration, globalErrorCount: report.errors.length, tests };
}

async function readPrivateReport(filename) {
  const handle = await open(filename, constants.O_RDONLY | NO_FOLLOW);
  try {
    const stat = await handle.stat();
    requireValue(stat.isFile() && stat.nlink === 1 && stat.size > 0, 'REPORT_MISSING');
    requireValue(stat.size <= MAX_REPORT_BYTES, 'REPORT_TOO_LARGE');
    try { return JSON.parse(await handle.readFile('utf8')); }
    catch { throw new ClosedError('REPORT_MALFORMED'); }
  } finally { await handle.close(); }
}

async function publish(cwd, phase, receipt) {
  const directory = path.join(cwd, 'playwright-public');
  await mkdir(directory, { mode: 0o700 }).catch(error => { if (error.code !== 'EEXIST') throw error; });
  const directoryStat = await lstat(directory);
  if (directoryStat.isSymbolicLink()) {
    await unlink(directory); // Remove only the link, never read or alter its target.
    throw new ClosedError('PUBLIC_PATH_REFUSED');
  }
  requireValue(directoryStat.isDirectory() && await realpath(directory) === directory, 'PUBLIC_PATH_REFUSED');
  await chmod(directory, 0o700);
  const destination = path.join(directory, `${phase}.json`);
  const previous = await lstat(destination).catch(error => { if (error.code !== 'ENOENT') throw error; return null; });
  if (previous?.isSymbolicLink() || (previous?.isFile() && previous.nlink !== 1)) {
    await unlink(destination);
    throw new ClosedError('PUBLIC_PATH_REFUSED');
  }
  requireValue(!previous || previous.isFile(), 'PUBLIC_PATH_REFUSED');
  const temporary = path.join(directory, `.${phase}.${process.pid}.tmp`);
  const handle = await open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | NO_FOLLOW, 0o600);
  try { await handle.writeFile(JSON.stringify(receipt, null, 2) + '\n'); }
  finally { await handle.close(); }
  try { await rename(temporary, destination); }
  catch (error) { await unlink(temporary).catch(() => {}); throw error; }
}

/** Injection is an imported unit-test seam, never a CLI/environment switch. */
export async function runPublicPlaywright(argv, { cwd = process.cwd(), env = process.env, launch = launchInstalled, getSourceSha = sourceShaFromGit, emit = value => process.stdout.write(value) } = {}) {
  let phase;
  let sourceSha = null;
  let childExitCode = null;
  let receipt;
  let stdout;
  let stderr;
  try {
    const parsed = parseArguments(argv);
    phase = parsed.phase;
    cwd = await realpath(cwd);
    const candidateSha = await getSourceSha(cwd);
    const expectedSha = env.JOLENE_E2E_EXPECTED_SHA ?? env.GITHUB_SHA;
    requireValue(validSha(candidateSha) && (expectedSha === undefined || (validSha(expectedSha) && expectedSha === candidateSha)), 'SOURCE_SHA_REFUSED');
    sourceSha = candidateSha;
    // Replace any previous success before running. An interrupted run stays red.
    await publish(cwd, phase, { schemaVersion: 1, phase, sourceSha, complete: false, childExitCode: null, exitCode: 1, codes: ['RUNNING'], counts: null, tests: [] });
    const privateDir = await mkdtemp(path.join(env.RUNNER_TEMP || tmpdir(), 'jolene-private-e2e-'));
    await chmod(privateDir, 0o700);
    stdout = await open(path.join(privateDir, 'stdout.log'), 'wx', 0o600);
    stderr = await open(path.join(privateDir, 'stderr.log'), 'wx', 0o600);
    const reportPath = path.join(privateDir, 'report.json');
    await (await open(reportPath, 'wx', 0o600)).close();
    const childEnv = {
      ...env, JOLENE_PRIVATE_E2E: '1', PLAYWRIGHT_JSON_OUTPUT_FILE: reportPath,
      PLAYWRIGHT_HTML_OUTPUT_DIR: path.join(privateDir, 'html'), PLAYWRIGHT_HTML_OPEN: 'never',
      PLAYWRIGHT_BLOB_OUTPUT_DIR: path.join(privateDir, 'blob'),
      UX_AUDIT_SCREENSHOTS_DIR: path.join(privateDir, 'screenshots'),
      UX_ADMIN_AUDIT_SCREENSHOTS_DIR: path.join(privateDir, 'admin-screenshots'),
      RECETTE_DIR: path.join(privateDir, 'manual-captures'),
      RECETTE_RESULTS_DIR: path.join(privateDir, 'recette'),
    };
    for (const directory of ['screenshots', 'admin-screenshots', 'manual-captures', 'recette']) {
      await mkdir(path.join(privateDir, directory), { mode: 0o700 });
    }
    childExitCode = await launch({
      cwd, env: childEnv, stdoutFd: stdout.fd, stderrFd: stderr.fd,
      args: [...parsed.args, '--reporter=json', `--output=${path.join(privateDir, 'artifacts')}`, '--trace=off', '--fail-on-flaky-tests'],
    });
    requireValue(integer(childExitCode, 255), 'CHILD_EXIT_INVALID');
    const projection = await projectReport(await readPrivateReport(reportPath), { phase, cwd });
    const codes = [];
    if (projection.globalErrorCount) codes.push('GLOBAL_ERROR');
    if (projection.counts.unexpected) codes.push('UNEXPECTED_TESTS');
    if (projection.counts.flaky) codes.push('FLAKY_TESTS');
    if (projection.tests.some(test => test.attempts.some(attempt => attempt.status === 'interrupted'))) codes.push('INTERRUPTED');
    if (!projection.tests.some(test => test.outcome !== 'skipped')) codes.push('NO_TEST_EXECUTED');
    if (childExitCode !== 0) codes.push('PLAYWRIGHT_FAILED');
    if (childExitCode === 0 && codes.length) codes.push('EXIT_STATUS_INCONSISTENT');
    receipt = { schemaVersion: 1, phase, sourceSha, complete: true, childExitCode, exitCode: childExitCode || (codes.length ? 1 : 0), codes, ...projection };
  } catch (error) {
    // Never serialize exception messages, JSON excerpts, paths or child output.
    receipt = { schemaVersion: 1, phase: phase || null, sourceSha, complete: false, childExitCode: integer(childExitCode, 255) ? childExitCode : null,
      exitCode: integer(childExitCode, 255) && childExitCode !== 0 ? childExitCode : 1,
      codes: [error instanceof ClosedError ? error.code : 'PRIVATE_RUN_FAILED'], counts: null, tests: [] };
  } finally {
    await stdout?.close().catch(() => {});
    await stderr?.close().catch(() => {});
  }
  if (phase) {
    try { await publish(cwd, phase, receipt); }
    catch { receipt = { schemaVersion: 1, phase, sourceSha, complete: false, childExitCode: receipt.childExitCode, exitCode: receipt.exitCode || 1, codes: ['PUBLIC_WRITE_FAILED'], counts: null, tests: [] }; }
  }
  emit(JSON.stringify(receipt) + '\n');
  return receipt.exitCode;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  runPublicPlaywright(process.argv.slice(2)).then(code => { process.exitCode = code; }).catch(() => {
    process.stdout.write('{"complete":false,"codes":["PUBLIC_RUN_FAILED"]}\n');
    process.exitCode = 1;
  });
}
