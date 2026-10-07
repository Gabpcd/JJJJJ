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

test('closed diagnostic locates PID and focus checks before and after collection', async () => {
  const lostFocus = 'mCurrentFocus=Window{abc u0 other/.MainActivity}\n';
  for (const [config, phase, expectedReads] of [
    [{ pids: ['4400'] }, 'before-pid-check', 0],
    [{ windows: [lostFocus] }, 'before-window-check', 0],
    [{ pids: [pid, '4400'] }, 'after-pid-check', 1],
    [{ windows: [windowDump, lostFocus] }, 'after-window-check', 1],
  ]) {
    const f = fixture(config);
    await assert.rejects(captureIme(serial, f.options), error => {
      assert(error.message.endsWith(`[phase=${phase}; code=ASSERTION_FAILED]`));
      assert.equal(error.cause.code, 'ERR_ASSERTION');
      return true;
    });
    assert.equal(f.imeCalls, expectedReads);
    assert(!f.entries.some(entry => entry.phase === 'complete'));
  }
});

test('closed diagnostic distinguishes each IME structural assertion', async () => {
  for (const [value, phase] of [
    [dump, 'ime-marker-check'],
    [complete.replace('Current Input Method Manager state:', 'missing header'), 'ime-header-check'],
    [complete.replace('mStartInputHistory:', 'missingHistory:'), 'ime-history-check'],
    [complete.replace('  mStartInputHistory:', 'Error dumping service\n  mStartInputHistory:'), 'ime-service-check'],
    [complete.replace('mInputShown=false', 'no current visibility'), 'ime-visibility-check'],
  ]) {
    const f = fixture({ ime: [value] });
    await assert.rejects(captureIme(serial, f.options), error => {
      assert(error.message.endsWith(`[phase=${phase}; code=ASSERTION_FAILED]`));
      return true;
    });
    assert.equal(f.imeCalls, 1);
    assert(!f.calls.some(call => call.args[0] === 'wait-for-device'));
  }
});

test('closed diagnostic codes never copy arbitrary inner error data into failure.json fields', async () => {
  const privateValue = 'DO_NOT_PUBLISH_INNER_ERROR_DATA';
  for (const [properties, code] of [
    [{ code: 'ENOENT' }, 'FILE_NOT_FOUND'],
    [{ code: 'EACCES' }, 'ACCESS_DENIED'],
    [{ code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER' }, 'OUTPUT_LIMIT'],
    [{ killed: true, signal: 'SIGTERM' }, 'PROCESS_KILLED'],
    [{ code: 255 }, 'ADB_EXIT_255'],
    [{ code: 1 }, 'ADB_EXIT_NONZERO'],
    [{ code: privateValue }, 'OTHER'],
    [{ code: 0 }, 'OTHER'],
    [{}, 'OTHER'],
  ]) {
    const cause = Object.assign(new Error(privateValue), {
      stdout: privateValue, stderr: privateValue, command: privateValue, ...properties,
    });
    const f = fixture({ pids: [cause] });
    await assert.rejects(captureIme(serial, f.options), error => {
      assert.equal(error.cause, cause);
      assert(error.message.endsWith(`[phase=before-pid-read; code=${code}]`));
      // navigation.mjs saves precisely these two outer error fields.
      assert(!JSON.stringify({ message: error.message, stack: error.stack }).includes(privateValue));
      return true;
    });
    assert.equal(f.calls.length, 1);
    assert.equal(f.imeCalls, 0);
    assert.deepEqual(f.entries, []);
  }
});

test('closed diagnostic locates window transport and the unchanged failed reconnect', async () => {
  const cause = Object.assign(new Error('read failed'), { code: 1 });
  for (const [config, phase] of [
    [{ windows: [cause] }, 'before-window-read'],
    [{ windows: [windowDump, cause] }, 'after-window-read'],
    [{ ime: [interrupted()], waitError: cause }, 'reconnect-wait'],
    [{ ime: [interrupted()], pids: [pid, cause] }, 'reconnected-pid-read'],
    [{ ime: [interrupted()], windows: [windowDump, cause] }, 'reconnected-window-read'],
  ]) {
    const f = fixture(config);
    await assert.rejects(captureIme(serial, f.options), error => {
      assert.equal(error.cause, cause);
      assert(error.message.endsWith(`[phase=${phase}; code=ADB_EXIT_NONZERO]`));
      return true;
    });
    assert(f.imeCalls <= 1);
    assert(!f.entries.some(entry => entry.phase === 'complete'));
  }
});

test('closed diagnostic preserves IME read failure after successful failure recording', async () => {
  const cause = Object.assign(new Error('read failed'), { code: 1 });
  const f = fixture({ ime: [cause] });
  await assert.rejects(captureIme(serial, f.options), error => {
    assert.equal(error.cause, cause);
    assert(error.message.endsWith('[phase=ime-read; code=ADB_EXIT_NONZERO]'));
    return true;
  });
  assert.equal(f.imeCalls, 1);
  assert.deepEqual(f.entries.map(entry => entry.phase), ['collection-failed']);
});

test('closed diagnostic locates artifact writes without extra recording or retries', async () => {
  for (const [config, failedEntry, phase] of [
    [{}, 'complete', 'complete-record'],
    [{ ime: [interrupted()] }, 'collection-failed', 'collection-failure-record'],
    [{ ime: [interrupted()] }, 'transport-recovered-same-app', 'transport-recovery-record'],
  ]) {
    const f = fixture(config);
    const cause = new Error('artifact write failed');
    let records = 0;
    f.options.record = async entry => {
      records++;
      if (entry.phase === failedEntry) throw cause;
    };
    await assert.rejects(captureIme(serial, f.options), error => {
      assert.equal(error.cause, cause);
      assert(error.message.endsWith(`[phase=${phase}; code=OTHER]`));
      return true;
    });
    assert.equal(f.imeCalls, 1);
    assert.equal(records, failedEntry === 'transport-recovered-same-app' ? 2 : 1);
  }
});


test('ENOENT while recording does not claim ADB is missing', async () => {
  const f = fixture();
  const cause = Object.assign(new Error('fixture output missing'), { code: 'ENOENT' });
  f.options.record = async () => { throw cause; };
  await assert.rejects(captureIme(serial, f.options), error => {
    assert.equal(error.cause, cause);
    assert(error.message.endsWith('[phase=complete-record; code=FILE_NOT_FOUND]'));
    return true;
  });
  assert.equal(f.imeCalls, 1);
});
