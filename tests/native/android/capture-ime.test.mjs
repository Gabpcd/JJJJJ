import assert from 'node:assert/strict';
import test from 'node:test';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { captureIme } from './capture-ime.mjs';

const execute = promisify(execFile);
const serial = 'emulator-fixture-5782';
const pid = '3360';
const windowDump = '  mCurrentFocus=Window{abc u0 app.jolene.recette/app.jolene.android.MainActivity}\n';
const dump = 'Current Input Method Manager state:\n  mInputShown=false\n  mStartInputHistory:\n    mInputShown=true\n';
const complete = `${dump}\nJOLENE_IME_DUMP_COMPLETE\n`;
const interrupted = () => Object.assign(new Error('interrupted shell'), {
  code: 255, killed: false, signal: null, stderr: '',
  stdout: 'Current Input Method Manager state:\n  mInputShown=true\n',
});

function fixture({ ime = [], pids = [], windows = [], waitError } = {}) {
  const calls = [], entries = [];
  let imeCalls = 0, pidCalls = 0, windowCalls = 0;
  const run = async (binary, args, options) => {
    assert.equal(binary, 'adb');
    assert.deepEqual(args.slice(0, 2), ['-s', serial]);
    assert.equal(options.encoding, 'utf8');
    assert.equal(options.maxBuffer, 4 * 1024 * 1024);
    calls.push({ args: args.slice(2), options });
    const command = args.slice(2).join(' ');
    let result;
    if (command === 'shell pidof app.jolene.recette') result = pids[pidCalls++] ?? `${pid}\n`;
    else if (command === 'shell dumpsys -t 10 window') result = windows[windowCalls++] ?? windowDump;
    else if (command === "shell dumpsys -t 10 input_method && printf '\\nJOLENE_IME_DUMP_COMPLETE\\n'") {
      result = ime[imeCalls++] ?? complete;
    } else if (command === 'wait-for-device') result = waitError ?? '';
    else assert.fail(`Unexpected command ${command}`);
    if (result instanceof Error) throw result;
    if (typeof result === 'function') return result(options);
    return { stdout: result, stderr: '' };
  };
  return { calls, entries, options: { expectedPid: pid, run, record: async entry => entries.push(entry) },
    get imeCalls() { return imeCalls; } };
}

test('complete evidence preserves every byte and verifies the original app before/after', async () => {
  const f = fixture();
  assert.equal(await captureIme(serial, f.options), dump);
  assert.deepEqual(f.calls.map(c => c.args), [
    ['shell', 'pidof', 'app.jolene.recette'], ['shell', 'dumpsys', '-t', '10', 'window'],
    ['shell', "dumpsys -t 10 input_method && printf '\\nJOLENE_IME_DUMP_COMPLETE\\n'"],
    ['shell', 'pidof', 'app.jolene.recette'], ['shell', 'dumpsys', '-t', '10', 'window'],
  ]);
  assert.deepEqual(f.calls.map(c => c.options.timeout), [5000, 15000, 15000, 5000, 15000]);
  assert.deepEqual(f.entries, [{ phase: 'complete', attempt: 1, pid, bytes: Buffer.byteLength(dump) }]);
});

test('one interrupted transport reconnects without app actions or accepting partial stdout', async () => {
  const f = fixture({ ime: [interrupted(), complete] });
  assert.equal(await captureIme(serial, f.options), dump);
  assert.equal(f.imeCalls, 2);
  assert.equal(f.calls.filter(c => c.args[0] === 'wait-for-device').length, 1);
  assert.deepEqual(f.entries.map(e => e.phase), ['collection-failed', 'transport-recovered-same-app', 'complete']);
  assert.equal(f.entries[2].attempt, 2);
});

test('second interrupted read aborts without a third attempt', async () => {
  const second = interrupted();
  const f = fixture({ ime: [interrupted(), second] });
  await assert.rejects(captureIme(serial, f.options), error => error.cause === second);
  assert.equal(f.imeCalls, 2);
  assert.deepEqual(f.entries.map(e => e.phase), ['collection-failed', 'transport-recovered-same-app', 'collection-failed']);
});

test('host timeout, buffer limit, missing binary, offline device and remote errors fail closed', async () => {
  for (const patch of [
    { code: 'ENOENT' }, { code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER' },
    { code: null, killed: true, signal: 'SIGTERM' }, { code: 1, stderr: 'adb: device offline' },
    { code: 255, stderr: 'Permission Denial' }, { code: 255, stdout: '' }, { code: 255, signal: 'SIGKILL' },
    { code: 255, stdout: `${dump}*** SERVICE DUMP TIMEOUT EXPIRED ***\n` },
    { code: 255, stdout: complete },
  ]) {
    const cause = Object.assign(interrupted(), patch);
    const f = fixture({ ime: [cause] });
    await assert.rejects(captureIme(serial, f.options), error => error.cause === cause);
    assert.equal(f.imeCalls, 1);
    assert(!f.calls.some(c => c.args[0] === 'wait-for-device'));
  }
});

test('unsuccessful reconnect is bounded and cannot reach another dump', async () => {
  const waitError = Object.assign(new Error('wait timed out'), { killed: true, signal: 'SIGTERM' });
  const f = fixture({ ime: [interrupted()], waitError });
  await assert.rejects(captureIme(serial, f.options), error => error.cause === waitError);
  assert.equal(f.imeCalls, 1);
  assert.equal(f.calls.at(-1).options.timeout, 5000);
});

test('successful transport rejects missing marker/structure, ambiguous state and remote timeout', async () => {
  for (const invalid of [
    '', dump, 'mInputShown=false\n\nJOLENE_IME_DUMP_COMPLETE\n',
    complete.replace('mStartInputHistory:', 'missingHistory:'),
    complete.replace('mInputShown=false', 'mInputShown=false\n  mInputShown=true'),
    complete.replace('mInputShown=false', 'no current visibility'),
    complete.replace('  mStartInputHistory:', '*** SERVICE DUMP TIMEOUT EXPIRED ***\n  mStartInputHistory:'),
    complete.replace('  mStartInputHistory:', "Can't find service: input_method\n  mStartInputHistory:"),
  ]) {
    const f = fixture({ ime: [invalid] });
    await assert.rejects(captureIme(serial, f.options), /Required IME evidence collection failed/);
    assert.equal(f.imeCalls, 1);
    assert(!f.entries.some(e => e.phase === 'complete'));
  }
});

test('missing, changed or multiple app PIDs abort before accepting a dump', async () => {
  for (const actual of ['', '3361\n', '3360 3361\n']) {
    for (const pids of [[actual], [pid, actual]]) {
      const f = fixture({ pids });
      await assert.rejects(captureIme(serial, f.options), error => /stopped or restarted/.test(error.cause.message));
      assert(!f.entries.some(e => e.phase === 'complete'));
    }
  }
});

test('app restart during reconnection cannot become a successful retry', async () => {
  const f = fixture({ ime: [interrupted()], pids: [pid, '4400'] });
  await assert.rejects(captureIme(serial, f.options), error => /stopped or restarted/.test(error.cause.message));
  assert.equal(f.imeCalls, 1);
  assert(!f.entries.some(e => e.phase === 'transport-recovered-same-app'));
});

test('lost focus, ANR and crash dialogs are fatal, including after reconnection', async () => {
  for (const badWindow of [
    'mCurrentFocus=Window{abc u0 other/.MainActivity}\n',
    `${windowDump}Window{error Application Not Responding: app.jolene.recette}\n`,
    `${windowDump}Window{error Application Error: app.jolene.recette}\n`,
  ]) {
    for (const config of [
      { windows: [badWindow] }, { windows: [windowDump, badWindow] },
      { ime: [interrupted()], windows: [windowDump, badWindow] },
    ]) {
      const f = fixture(config);
      await assert.rejects(captureIme(serial, f.options), /Required IME evidence collection failed/);
      assert(!f.entries.some(e => e.phase === 'complete'));
      assert(f.imeCalls <= 1);
    }
  }
});

test('missing serial or original PID never selects an arbitrary device/process', async () => {
  for (const [device, expectedPid] of [['', pid], [serial, undefined], [serial, ''], [serial, '33 60']]) {
    let calls = 0;
    await assert.rejects(captureIme(device, { expectedPid, run: async () => calls++ }));
    assert.equal(calls, 0);
  }
});

test('evidence logging failure cannot produce a passing capture', async () => {
  const f = fixture();
  const cause = new Error('artifact write failed');
  f.options.record = async () => { throw cause; };
  await assert.rejects(captureIme(serial, f.options), error => error.cause === cause);
});

// Exercise real Node subprocess errors without ADB, Android or networking.
test('real child-process exit255 is recognized; only the new complete dump is returned', async () => {
  const f = fixture({ ime: [options => execute(process.execPath, ['-e',
    "process.stdout.write('Current Input Method Manager state:\\n  mInputShown=true\\n'); process.exitCode=255;"], options)] });
  assert.equal(await captureIme(serial, f.options), dump);
  assert.equal(f.imeCalls, 2);
  assert.equal(f.entries[0].code, 255);
});

test('real child-process timeout never triggers another collection', async () => {
  const f = fixture({ ime: [options => execute(process.execPath, ['-e', 'setTimeout(() => {}, 10000)'],
    { ...options, timeout: 50 })] });
  await assert.rejects(captureIme(serial, f.options), error => error.cause.killed === true);
  assert.equal(f.imeCalls, 1);
});

test('real maxBuffer overflow is fatal despite a plausible current IME state', async () => {
  const f = fixture({ ime: [options => execute(process.execPath, ['-e',
    "process.stdout.write('Current Input Method Manager state:\\n  mInputShown=false\\n' + 'x'.repeat(5 * 1024 * 1024));"], options)] });
  await assert.rejects(captureIme(serial, f.options), error => error.cause.code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER');
  assert.equal(f.imeCalls, 1);
});
