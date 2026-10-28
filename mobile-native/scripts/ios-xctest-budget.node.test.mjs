import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { readFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { runInNewContext } from 'node:vm';

// Exercise the actual command/collection functions without running the CI
// script's top-level simulator setup or spawning any external process.
const source = readFileSync(new URL('./run-pilot-ci.mjs', import.meta.url), 'utf8');
function implementation(start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from);
  assert.ok(from >= 0 && to > from);
  return source.slice(from, to);
}
const commandSource = implementation('function stopTree(', 'async function waitUntil(');
const xctestSource = implementation('async function runIosXCTest(', 'function verifyCaptureOrientation(');
const passed = { result: 'Passed', totalTestCount: 1, passedTests: 1, failedTests: 0, skippedTests: 0, expectedFailures: 0 };
const exited = (overrides = {}) => ({ code: 0, signal: null, expired: false, durationMs: 12, stdout: '', stderr: '', ...overrides });

function xctestHarness({ build = exited(), execution = exited(), reportError } = {}) {
  const calls = [];
  const written = new Map();
  const scenarios = [];
  const context = {
    selectedScenario: { name: 'consultation' }, iosFamily: 'ipad', platform: 'ios',
    iosProject: '/ci/NativePilotUITests.xcodeproj', device: 'simulator-id',
    output: '/proofs', appId: 'app.jolene.nativepilot', compiledClient: { iconName: 'Jolene · Pilote natif' },
    process: { env: { RUNNER_TEMP: '/ci/tmp' } }, console: { log() {} },
    resolve, basename, scenarios, mkdirSync() {}, existsSync: () => true,
    writeFileSync: (path, value) => written.set(path, value), readFileSync: () => '[]',
    iosTestMethod: (_scenario, _family, orientation) => `${orientation}Test`,
    scenarioCaptureNames: () => [], verifyCaptureOrientation() {},
    run: async (command, args, options = {}) => {
      calls.push({ command, args: [...args], options });
      if (args[0] === 'build-for-testing') return build;
      if (args[0] === 'test-without-building') return execution;
      if (args[1] === 'get') {
        // The command outcome must already exist if report reading fails.
        assert.ok([...written.keys()].some(path => path.endsWith('/xctest-command.json')));
        if (reportError) throw new Error(reportError);
        return exited({ stdout: JSON.stringify(passed) });
      }
      return exited();
    },
  };
  const run = runInNewContext(`let iosTestsBuilt = false; let stage; ${xctestSource}; runIosXCTest`, context);
  return { run, calls, written, scenarios };
}

test('one bounded build serves both orientations without changing each selected test or its allowance', async () => {
  const h = xctestHarness();
  await h.run('portrait', '/proofs/portrait');
  await h.run('landscape', '/proofs/landscape');
  const builds = h.calls.filter(call => call.args[0] === 'build-for-testing');
  const tests = h.calls.filter(call => call.args[0] === 'test-without-building');
  assert.equal(builds.length, 1);
  assert.equal(builds[0].options.timeout, 300_000);
  assert.equal(tests.length, 2);
  for (const [index, call] of tests.entries()) {
    assert.equal(call.options.timeout, 900_000);
    for (const flag of ['-project', '-scheme', '-configuration', '-sdk', '-destination', '-derivedDataPath']) {
      assert.equal(call.args[call.args.indexOf(flag) + 1], builds[0].args[builds[0].args.indexOf(flag) + 1]);
    }
    assert.ok(call.args.includes('JOLENE_TEST_APP_ID=app.jolene.nativepilot'));
    assert.ok(call.args.includes('JOLENE_TEST_HOME_ICON=Jolene · Pilote natif'));
    assert.ok(call.args.includes(`-only-testing:NativePilotUITests/NativePilotTests/${index ? 'landscape' : 'portrait'}Test`));
    assert.equal(call.args[call.args.indexOf('-maximum-test-execution-time-allowance') + 1], '600');
    assert.equal(call.args[call.args.indexOf('-parallel-testing-enabled') + 1], 'NO');
  }
  assert.equal(h.scenarios.length, 2);
});

test('an expired command and incomplete xcresult retain the timeout as the primary failure', async () => {
  const h = xctestHarness({ execution: exited({ code: null, signal: 'SIGKILL', expired: true, durationMs: 900001 }),
    reportError: 'Info.plist does not exist' });
  await assert.rejects(h.run('portrait', '/proofs/portrait'), /Délai externe XCTest de 900 s dépassé.*incomplets.*Info.plist does not exist/);
  const status = JSON.parse(h.written.get('/proofs/portrait/xctest-command.json'));
  assert.deepEqual(status, { code: null, signal: 'SIGKILL', expired: true, durationMs: 900001, timeoutMs: 900000 });
  assert.equal(h.scenarios.length, 0);
});

test('a readable Passed report cannot rescue an expired xcodebuild command', async () => {
  const h = xctestHarness({ execution: exited({ expired: true }) });
  await assert.rejects(h.run('portrait', '/proofs/portrait'), /Délai externe XCTest de 900 s dépassé/);
  assert.ok(h.written.has('/proofs/portrait/xctest-summary.json'));
  assert.ok(h.calls.some(call => call.args[1] === 'export'));
  assert.equal(h.scenarios.length, 0);
});

test('a readable Passed report cannot rescue a nonzero xcodebuild exit', async () => {
  const h = xctestHarness({ execution: exited({ code: 65 }) });
  await assert.rejects(h.run('portrait', '/proofs/portrait'), /xcodebuild code 65/);
  assert.equal(h.scenarios.length, 0);
});

test('an expired build preserves its outcome and never starts the scenario', async () => {
  const h = xctestHarness({ build: exited({ code: null, signal: 'SIGKILL', expired: true }) });
  await assert.rejects(h.run('portrait', '/proofs/portrait'), /Compilation.*300 s dépassé/);
  assert.equal(h.calls.length, 1);
  assert.equal(JSON.parse(h.written.get('/proofs/xctest-build-command.json')).expired, true);
  assert.equal(h.scenarios.length, 0);
});

test('allowFailure retains actual timeout, signal and elapsed time from the process wrapper', async () => {
  const child = Object.assign(new EventEmitter(), { pid: 123, stdout: new EventEmitter(), stderr: new EventEmitter() });
  const killed = [];
  let now = 0;
  const run = runInNewContext(`${commandSource}; run`, {
    output: '/proofs', project: '/ci', env: {}, compiled: false, streams: [], resolve,
    spawn: () => child, performance: { now: () => (now += 25) },
    setTimeout: callback => { queueMicrotask(callback); return 1; }, clearTimeout() {}, clearInterval() {},
    process: { kill: (pid, signal) => { killed.push([pid, signal]); queueMicrotask(() => child.emit('close', null, signal)); } },
  });
  const result = await run('fake-command', [], { allowFailure: true, timeout: 1 });
  assert.equal(result.expired, true);
  assert.equal(result.signal, 'SIGKILL');
  assert.equal(result.code, null);
  assert.equal(result.durationMs, 25);
  assert.deepEqual(killed, [[-123, 'SIGKILL']]);
});
