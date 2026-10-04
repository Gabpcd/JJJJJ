// @vitest-environment node
import { randomBytes } from 'node:crypto';
import { writeSync } from 'node:fs';
import { lstat, mkdir, mkdtemp, readFile, readdir, realpath, rm, symlink, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { parseArguments, runPublicPlaywright } from '../../../scripts/ci/run-playwright-public.mjs';

const sha = 'a'.repeat(40);
let directory: string;
let cwd: string;
let runnerTemp: string;
let canary: string;
let output: string[];
let launches: number;
let seen: any;

beforeEach(async () => {
  directory = await realpath(await mkdtemp(path.join(tmpdir(), 'jolene-export-unit-')));
  cwd = path.join(directory, 'repo');
  runnerTemp = path.join(directory, 'private');
  await mkdir(path.join(cwd, 'e2e', 'flows'), { recursive: true });
  await mkdir(runnerTemp, { mode: 0o700 });
  await writeFile(path.join(cwd, 'e2e', 'flows', 'export.spec.ts'), '// fixture\n');
  canary = `runtime-canary-${randomBytes(24).toString('hex')}`;
  output = [];
  launches = 0;
});
afterEach(async () => { await rm(directory, { recursive: true, force: true }); });

function report() {
  return {
    config: { rootDir: path.join(cwd, 'e2e'), metadata: { private: canary } },
    suites: [{ title: canary, specs: [{ title: canary, id: canary, tags: [canary],
      file: 'flows/export.spec.ts', line: 1, column: 1,
      tests: [{ projectName: 'chromium', projectId: canary, expectedStatus: 'passed', status: 'expected',
        annotations: [{ type: 'skip', description: canary }],
        results: [{ status: 'passed', duration: 12, retry: 0, errors: [],
          stdout: [{ text: canary }], stderr: [{ text: canary }],
          attachments: [{ name: canary, body: canary, contentType: 'text/plain' }],
          steps: [{ title: canary, error: { message: canary } }],
        }],
      }],
    }] }],
    errors: [], stats: { duration: 20, expected: 1, unexpected: 0, flaky: 0, skipped: 0 },
  } as any;
}
function testOf(value: any) { return value.suites[0].specs[0].tests[0]; }
function argumentsFor(phase = 'chromium') { return ['--phase', phase, '--', 'test']; }

async function execute(value: any, code = 0, options: any = {}) {
  const launch = async (context: any) => {
    launches++;
    seen = context;
    writeSync(context.stdoutFd, canary + '\n');
    writeSync(context.stderrFd, canary + '\n');
    if (options.during) await options.during(context);
    if (options.throw) throw new Error(canary);
    if (!options.missing) {
      await writeFile(context.env.PLAYWRIGHT_JSON_OUTPUT_FILE, typeof value === 'string' ? value : JSON.stringify(value));
    }
    return code;
  };
  const exitCode = await runPublicPlaywright(options.argv || argumentsFor(), {
    cwd, env: { RUNNER_TEMP: runnerTemp, ...(options.env || {}) }, launch,
    getSourceSha: () => options.sourceSha ?? sha,
    emit: (text: string) => output.push(text),
  });
  const published = output.join('');
  expect(published).not.toContain(canary);
  return { exitCode, receipt: JSON.parse(published) };
}

describe('publication fermée des diagnostics Playwright connectés', () => {
  it('publie uniquement la projection ; login, stderr, HTML et pièces restent privés', async () => {
    const { exitCode, receipt } = await execute(report(), 0, {
      during: async (context: any) => {
        const privateRoot = path.dirname(context.env.PLAYWRIGHT_JSON_OUTPUT_FILE);
        await writeFile(path.join(privateRoot, 'capture.png'), canary);
        await writeFile(path.join(privateRoot, 'trace.zip'), canary);
        await writeFile(path.join(privateRoot, 'page.html'), canary);
        await symlink(path.join(privateRoot, 'page.html'), path.join(privateRoot, 'attachment-link'));
      },
    });
    expect(exitCode).toBe(0);
    expect(receipt).toMatchObject({ sourceSha: sha, complete: true, exitCode: 0, counts: { expected: 1, unexpected: 0, flaky: 0, skipped: 0 } });
    expect(receipt.tests).toEqual([{ ordinal: 1, file: 'e2e/flows/export.spec.ts', line: 1, column: 1,
      project: 'chromium', expectedStatus: 'passed', outcome: 'expected',
      attempts: [{ retry: 0, status: 'passed', durationMs: 12, code: 'PASSED' }],
    }]);
    expect(await readdir(path.join(cwd, 'playwright-public'))).toEqual(['chromium.json']);
    const publicBytes = await readFile(path.join(cwd, 'playwright-public', 'chromium.json'), 'utf8');
    expect(publicBytes).not.toContain(canary);
    expect(publicBytes).not.toMatch(/attachments|stderr|stdout|metadata|title|https?:/);
    const privateRoot = path.dirname(seen.env.PLAYWRIGHT_JSON_OUTPUT_FILE);
    expect((await lstat(privateRoot)).mode & 0o777).toBe(0o700);
    for (const name of ['stdout.log', 'stderr.log', 'report.json']) {
      expect((await lstat(path.join(privateRoot, name))).mode & 0o777).toBe(0o600);
      expect(await readFile(path.join(privateRoot, name), 'utf8')).toContain(canary);
    }
    expect(seen.env.JOLENE_PRIVATE_E2E).toBe('1');
    expect(seen.args).toContain('--reporter=json');
    expect(seen.args).toContain('--trace=off');
    expect(seen.args).toContain('--fail-on-flaky-tests');
    expect(seen.args.find((arg: string) => arg.startsWith('--output='))).toBe(`--output=${path.join(privateRoot, 'artifacts')}`);
  });

  it('conserve le code de sortie original et les assertions échouées', async () => {
    const value = report();
    value.stats.expected = 0; value.stats.unexpected = 1;
    testOf(value).status = 'unexpected';
    Object.assign(testOf(value).results[0], { status: 'failed', errors: [{ message: canary }], error: { message: canary } });
    const { exitCode, receipt } = await execute(value, 7);
    expect(exitCode).toBe(7);
    expect(receipt.childExitCode).toBe(7);
    expect(receipt.codes).toEqual(['UNEXPECTED_TESTS', 'PLAYWRIGHT_FAILED']);
    expect(receipt.tests[0].attempts[0].code).toBe('TEST_FAILED');
  });

  it('ne transforme pas un retry réussi en succès de phase', async () => {
    const value = report();
    value.stats.expected = 0; value.stats.flaky = 1;
    const test = testOf(value);
    test.status = 'flaky';
    test.results.unshift({ status: 'failed', duration: 10, retry: 0, errors: [{ message: canary }] });
    test.results[1].retry = 1;
    const { exitCode, receipt } = await execute(value, 0);
    expect(exitCode).toBe(1);
    expect(receipt.codes).toContain('FLAKY_TESTS');
    expect(receipt.codes).toContain('EXIT_STATUS_INCONSISTENT');
    expect(receipt.tests[0].attempts.map((attempt: any) => attempt.retry)).toEqual([0, 1]);
  });

  it('accepte les formes Playwright skip déclaré, non exécuté et échec attendu', async () => {
    const value = report();
    const expectedFailure = structuredClone(testOf(value));
    expectedFailure.expectedStatus = 'failed';
    Object.assign(expectedFailure.results[0], { status: 'failed', errors: [{ message: canary }] });
    const skipped = structuredClone(testOf(value));
    skipped.expectedStatus = 'skipped'; skipped.status = 'skipped'; skipped.results[0].status = 'skipped';
    const notRun = structuredClone(skipped);
    notRun.expectedStatus = 'passed'; notRun.results = [];
    value.suites[0].specs[0].tests.push(expectedFailure, skipped, notRun);
    value.stats.expected = 2; value.stats.skipped = 2;
    const { exitCode, receipt } = await execute(value);
    expect(exitCode).toBe(0);
    expect(receipt.counts).toEqual({ expected: 2, unexpected: 0, flaky: 0, skipped: 2 });
    expect(receipt.tests[1].expectedStatus).toBe('failed');
    expect(receipt.tests[3].attempts).toEqual([]);
  });

  it('fait échouer une erreur globale sans exposer son message', async () => {
    const value = report();
    value.errors = [{ message: canary, stack: canary }];
    const { exitCode, receipt } = await execute(value);
    expect(exitCode).toBe(1);
    expect(receipt.globalErrorCount).toBe(1);
    expect(receipt.codes).toContain('GLOBAL_ERROR');
  });

  it.each(['malformed', 'missing', 'exception'])('refuse le rapport %s sans reproduire de contenu privé', async mode => {
    const { exitCode, receipt } = await execute(mode === 'malformed' ? `{${canary}` : report(), 0, {
      missing: mode === 'missing', throw: mode === 'exception',
    });
    expect(exitCode).toBe(1);
    expect(receipt.complete).toBe(false);
    expect(receipt.counts).toBeNull();
    expect(receipt.codes).toEqual([mode === 'malformed' ? 'REPORT_MALFORMED' : mode === 'missing' ? 'REPORT_MISSING' : 'PRIVATE_RUN_FAILED']);
  });

  it.each(['counts', 'outcome', 'passed-error', 'retry', 'project', 'source', 'line', 'duration'])('refuse une incohérence %s', async kind => {
    const value = report();
    const test = testOf(value);
    if (kind === 'counts') value.stats.expected = 9;
    if (kind === 'outcome') test.status = 'skipped';
    if (kind === 'passed-error') test.results[0].errors = [{ message: canary }];
    if (kind === 'retry') test.results[0].retry = 3;
    if (kind === 'project') test.projectName = canary;
    if (kind === 'source') value.suites[0].specs[0].file = `../${canary}.spec.ts`;
    if (kind === 'line') value.suites[0].specs[0].line = 999;
    if (kind === 'duration') test.results[0].duration = canary;
    const { exitCode, receipt } = await execute(value);
    expect(exitCode).toBe(1);
    expect(receipt.complete).toBe(false);
  });

  it('refuse les sources et les rapports liés symboliquement sans les publier', async () => {
    const source = path.join(cwd, 'e2e', 'flows', 'export.spec.ts');
    const external = path.join(directory, 'outside.spec.ts');
    await writeFile(external, canary);
    await unlink(source); await symlink(external, source);
    expect((await execute(report())).exitCode).toBe(1);
    output = [];
    await unlink(source); await writeFile(source, '// fixture\n');
    const result = await execute(report(), 0, { missing: true, during: async (context: any) => {
      await unlink(context.env.PLAYWRIGHT_JSON_OUTPUT_FILE);
      await symlink(external, context.env.PLAYWRIGHT_JSON_OUTPUT_FILE);
    } });
    expect(result.exitCode).toBe(1);
    expect(await readFile(external, 'utf8')).toBe(canary);
  });

  it('remplace un ancien succès par RUNNING avant le lancement puis par l’échec', async () => {
    await execute(report());
    output = [];
    let pending: any;
    const result = await execute(report(), 0, { throw: true, during: async () => {
      pending = JSON.parse(await readFile(path.join(cwd, 'playwright-public', 'chromium.json'), 'utf8'));
    } });
    expect(pending.exitCode).toBe(1);
    expect(pending.codes).toEqual(['RUNNING']);
    expect(result.exitCode).toBe(1);
    const saved = JSON.parse(await readFile(path.join(cwd, 'playwright-public', 'chromium.json'), 'utf8'));
    expect(saved.complete).toBe(false);
  });

  it('retire uniquement un lien public dangereux sans toucher sa cible', async () => {
    await mkdir(path.join(cwd, 'playwright-public'));
    const target = path.join(directory, 'private-value.json');
    await writeFile(target, canary);
    await symlink(target, path.join(cwd, 'playwright-public', 'chromium.json'));
    const { exitCode } = await execute(report());
    expect(exitCode).toBe(1);
    expect(launches).toBe(0);
    expect(await readFile(target, 'utf8')).toBe(canary);
    expect(await readFile(path.join(cwd, 'playwright-public', 'chromium.json'), 'utf8')).not.toContain(canary);
  });

  it.each(['not-sha', 'mismatched-ci'])('refuse le SHA %s avant toute exécution', async kind => {
    const { exitCode, receipt } = await execute(report(), 0, kind === 'not-sha'
      ? { sourceSha: canary } : { env: { GITHUB_SHA: 'b'.repeat(40) } });
    expect(exitCode).toBe(1);
    expect(launches).toBe(0);
    expect(receipt.codes).toEqual(['SOURCE_SHA_REFUSED']);
  });

  it('accepte le head PR distinct du merge virtuel seulement avec le SHA attendu explicite exact', async () => {
    const { exitCode, receipt } = await execute(report(), 0, {
      env: { GITHUB_SHA: 'b'.repeat(40), JOLENE_E2E_EXPECTED_SHA: sha },
    });
    expect(exitCode).toBe(0);
    expect(receipt.sourceSha).toBe(sha);
    expect(launches).toBe(1);
  });

  it.each(['mismatch', 'invalid'])('refuse un SHA attendu explicite %s malgré GITHUB_SHA correct', async kind => {
    const { exitCode, receipt } = await execute(report(), 0, {
      env: { GITHUB_SHA: sha, JOLENE_E2E_EXPECTED_SHA: kind === 'mismatch' ? 'b'.repeat(40) : canary },
    });
    expect(exitCode).toBe(1);
    expect(launches).toBe(0);
    expect(receipt.codes).toEqual(['SOURCE_SHA_REFUSED']);
  });

  it.each(['--reporter=html', '--output=public', '--trace=on', '--list', '--ui', '--config=elsewhere.ts', '--project=admin-desktop-audit', '--'])('refuse une option contraire %s', async option => {
    const { exitCode, receipt } = await execute(report(), 0, { argv: [...argumentsFor(), option] });
    expect(exitCode).toBe(1);
    expect(launches).toBe(0);
    expect(receipt.codes).toEqual(['ARGUMENTS_REFUSED']);
  });

  it('conserve la sélection des tests et les réglages existants', () => {
    const args = parseArguments([...argumentsFor(), 'e2e/flows/admin-lot21-dark-mode.spec.ts', '--project=chromium', '--grep-invert=release review', '--retries=0', '--reporter=json']).args;
    expect(args).toEqual(['test', 'e2e/flows/admin-lot21-dark-mode.spec.ts', '--project=chromium', '--grep-invert=release review', '--retries=0', '--config=playwright.config.ts']);
    expect(parseArguments(argumentsFor('simulation-admin')).args).toContain('--config=e2e/playwright.recette-complete.config.ts');
    expect(parseArguments(argumentsFor('staging-comptes')).args).toContain('--project=staging-chromium');
  });
});
