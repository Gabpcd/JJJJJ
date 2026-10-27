import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createIosNavigationStallMonitor } from './ios-navigation-stall.mjs';

const device = '12345678-1234-1234-1234-123456789ABC';
const app = `/Users/runner/Library/Developer/CoreSimulator/Devices/${device}/data/Containers/Bundle/Application/EXPO/Exponent.app`;
const executable = `${app}/Expo Go`;
const originalProcess = `5136 501 Tue Oct 27 13:01:00 2026 ${executable}\n`;
const env = { GITHUB_ACTIONS: 'true', EXPO_PUBLIC_JOLENE_MODE: 'demo', EXPO_PUBLIC_JOLENE_NAVIGATION_DIAGNOSTICS: '1' };
const line = (sequence, event, detail, elapsedMs = sequence * 100) => ` LOG [jolene-native-navigation] ${JSON.stringify({ sequence, event, detail, elapsedMs })}\n`;
const mission = (sequence = 1, elapsedMs = 100) => line(sequence, 'state', 'ExplorationSoignant[0/3]/Mission[1/2]', elapsedMs);
const flush = async () => { for (let index = 0; index < 12; index++) await Promise.resolve(); };
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };

async function fixture(t, overrides = {}, commandOverride) {
  const output = mkdtempSync(join(tmpdir(), 'jolene-stall-unit-'));
  let monitor;
  t.after(async () => { await monitor?.dispose(); rmSync(output, { recursive: true, force: true }); });
  let clock = 1_000;
  let nextTimer = 0;
  const timers = new Map();
  const calls = [];
  const run = async (command, args, options) => {
    calls.push({ command, args, options });
    const overridden = commandOverride?.({ command, args, options, calls });
    if (overridden !== undefined) return overridden;
    const stdout = command === 'xcrun' ? app
      : command === '/usr/libexec/PlistBuddy' ? args[1].includes('Identifier') ? 'host.exp.Exponent' : 'Expo Go'
        : command === '/bin/ps' ? originalProcess : '';
    return { code: 0, stdout, stderr: '' };
  };
  monitor = await createIosNavigationStallMonitor({ env, platform: 'ios', device, output, run,
    hostPlatform: 'darwin', uid: 501, launchOutput: 'host.exp.Exponent: 5136\n',
    schedule(callback, milliseconds) { const id = ++nextTimer; timers.set(id, { due: clock + milliseconds, callback }); return id; },
    cancel(id) { timers.delete(id); }, now: () => clock, ...overrides });
  return { monitor, calls, output,
    samples: () => calls.filter(call => call.command === '/usr/bin/sample'),
    report: () => JSON.parse(readFileSync(join(output, 'ios-navigation-stall/index.json'), 'utf8')),
    async advance(milliseconds) {
      clock += milliseconds;
      for (const [id, timer] of [...timers]) if (timer.due <= clock) { timers.delete(id); timer.callback(); }
      await flush();
    },
  };
}

test('one bounded sample follows a Mission state delayed beyond two seconds', async t => {
  const f = await fixture(t);
  f.monitor.consume('stdout', mission());
  await f.advance(1_999);
  assert.equal(f.samples().length, 0);
  await f.advance(1);
  assert.equal(f.samples().length, 1);
  assert.deepEqual(f.samples()[0], { command: '/usr/bin/sample', args: ['5136', '3', '10', '-file', join(f.output, 'ios-navigation-stall/expo-main-thread.sample.txt')],
    options: { timeout: 15_000, allowFailure: true, logfile: 'ios-navigation-stall/sample-command.log' } });
  assert.equal(f.calls.filter(call => call.command === '/bin/ps').length, 2);
  assert.equal(f.report().status, 'collected');
  assert.equal(f.report().process.executable, executable);
  assert.equal(f.report().trigger.route, 'ExplorationSoignant[0/3]/Mission[1/2]');
  f.monitor.consume('stdout', line(2, 'state', 'ExplorationSoignant[0/3]/Missions[0/2]'));
  f.monitor.consume('stdout', mission(3));
  await f.advance(20_000);
  assert.equal(f.samples().length, 1);
});

test('normal transition, route departure and disposal cancel collection', async t => {
  for (const finish of ['transition', 'departure', 'dispose']) {
    const f = await fixture(t);
    f.monitor.consume('stdout', mission());
    await f.advance(1_500);
    if (finish === 'transition') f.monitor.consume('stdout', line(2, 'transitionStart', 'Mission:push'));
    if (finish === 'departure') f.monitor.consume('stdout', line(2, 'state', 'ExplorationSoignant[0/3]/Missions[0/2]'));
    if (finish === 'dispose') await f.monitor.dispose();
    await f.advance(1_000);
    assert.equal(f.samples().length, 0, finish);
  }
});

test('split chunks and ANSI suffix are parsed; unrelated, malformed and duplicate states do not re-arm', async t => {
  const f = await fixture(t);
  f.monitor.consume('stdout', 'x'.repeat(20_000));
  f.monitor.consume('stdout', '\n LOG [jolene-native-navigation] invalid\n');
  f.monitor.consume('stdout', line(1, 'state', 'MissionDetail[1/2]'));
  await f.advance(2_001);
  assert.equal(f.samples().length, 0);
  const event = mission(2).replace('\n', '\u001b[0m\n');
  f.monitor.consume('stdout', event.slice(0, 48));
  f.monitor.consume('stderr', 'an unrelated warning\n');
  f.monitor.consume('stdout', event.slice(48));
  await f.advance(1_500);
  f.monitor.consume('stdout', mission(3)); // Same state must not postpone this wait.
  f.monitor.consume('stdout', line(2, 'transitionStart', 'Mission:push')); // Stale sequence.
  await f.advance(500);
  assert.equal(f.samples().length, 1);
});

test('a native transition arriving before its state event prevents a false sample', async t => {
  const f = await fixture(t);
  f.monitor.consume('stdout', line(1, 'transitionStart', 'Mission:push', 100));
  f.monitor.consume('stdout', mission(2, 110));
  await f.advance(2_001);
  assert.equal(f.samples().length, 0);
});

test('diagnostic is disabled outside opted-in iOS CI demo, without executing any command', async t => {
  for (const override of [
    { env: { ...env, GITHUB_ACTIONS: 'false' } },
    { env: { ...env, EXPO_PUBLIC_JOLENE_MODE: 'staging' } },
    { env: { ...env, EXPO_PUBLIC_JOLENE_NAVIGATION_DIAGNOSTICS: '0' } },
    { platform: 'android' }, { hostPlatform: 'linux' }, { device: 'booted' },
  ]) {
    const f = await fixture(t, override);
    f.monitor.consume('stdout', mission());
    await f.advance(3_000);
    assert.equal(f.calls.length, 0);
  }
});

test('launch PID must be exact and unique; never find a process by name', async t => {
  for (const launchOutput of ['host.exp.Exponent: 0', 'host.exp.Exponent: 1', 'other.bundle: 5136',
    'host.exp.Exponent: 5136\nhost.exp.Exponent: 5137', 'host.exp.Exponent: 5136 extra', 'host.exp.Exponent: 2147483648']) {
    const f = await fixture(t, { launchOutput });
    assert.equal(f.calls.length, 0);
    assert.equal(f.report().reason, 'INVALID_LAUNCH_PID');
  }
});

test('bundle path, bundle identity, process UID and executable must match the launched simulator', async t => {
  for (const bad of ['container', 'bundle', 'executable', 'uid', 'pid']) {
    const f = await fixture(t, {}, ({ command, args }) => {
      if (bad === 'container' && command === 'xcrun') return { code: 0, stdout: '/Applications/Expo Go.app' };
      if (bad === 'bundle' && command === '/usr/libexec/PlistBuddy' && args[1].includes('Identifier')) return { code: 0, stdout: 'another.bundle' };
      if (command === '/bin/ps') {
        const stdout = bad === 'executable' ? originalProcess.replace(executable, '/Applications/Other.app/Expo Go')
          : bad === 'uid' ? originalProcess.replace(' 501 ', ' 502 ')
            : bad === 'pid' ? originalProcess.replace('5136', '9999') : originalProcess;
        return { code: 0, stdout };
      }
    });
    assert.equal(f.report().status, 'unavailable', bad);
    f.monitor.consume('stdout', mission());
    await f.advance(3_000);
    assert.equal(f.samples().length, 0);
  }
});

test('PID reuse or process mismatch at collection time prevents sampling and is not retried', async t => {
  const f = await fixture(t, {}, ({ command, calls }) => {
    if (command === '/bin/ps' && calls.filter(call => call.command === '/bin/ps').length === 2) {
      return { code: 0, stdout: originalProcess.replace('13:01:00', '13:02:00') };
    }
  });
  f.monitor.consume('stdout', mission());
  await f.advance(2_000);
  assert.equal(f.samples().length, 0);
  assert.equal(f.report().reason, 'LAUNCHED_PROCESS_CHANGED');
  f.monitor.consume('stdout', line(2, 'state', 'Missions[0/2]'));
  f.monitor.consume('stdout', mission(3));
  await f.advance(2_000);
  assert.equal(f.calls.filter(call => call.command === '/bin/ps').length, 2);
});

test('recovered transition during process verification cancels sampling', async t => {
  const gate = deferred();
  const f = await fixture(t, {}, ({ command, calls }) => command === '/bin/ps'
    && calls.filter(call => call.command === '/bin/ps').length === 2 ? gate.promise : undefined);
  f.monitor.consume('stdout', mission());
  await f.advance(2_000);
  f.monitor.consume('stdout', line(2, 'transitionStart', 'Mission:push'));
  gate.resolve({ code: 0, stdout: originalProcess });
  await flush();
  assert.equal(f.samples().length, 0);
  assert.equal(f.report().status, 'cancelled-before-sample');
});

test('dispose joins the one in-flight sample; collection errors cannot replace the test verdict', async t => {
  const gate = deferred();
  const f = await fixture(t, {}, ({ command }) => command === '/usr/bin/sample' ? gate.promise : undefined);
  f.monitor.consume('stdout', mission());
  await f.advance(2_000);
  let disposed = false;
  const ending = f.monitor.dispose().then(() => { disposed = true; });
  await flush();
  assert.equal(disposed, false);
  gate.resolve({ code: null, stdout: '', stderr: 'sample timed out' });
  await ending;
  assert.equal(f.report().status, 'collection-failed');
  assert.equal(f.report().exitCode, null);
  assert.equal(f.samples().length, 1);
  f.monitor.consume('stdout', mission(2));
  await f.advance(10_000);
  assert.equal(f.samples().length, 1);
});

test('setup command errors are recorded without throwing or sampling', async t => {
  const f = await fixture(t, {}, ({ command }) => command === 'xcrun' ? { code: 1, stdout: '', stderr: 'unavailable' } : undefined);
  assert.equal(f.report().status, 'unavailable');
  assert.equal(f.report().reason, 'DIAGNOSTIC_COMMAND_FAILED');
  assert.equal(f.samples().length, 0);
});
