import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { closeAndroidDriver, finalizeAndroidDriver } from './close-android-driver.mjs';

const serial = 'emulator-5554', expectedPid = '42';
const driver = 'com.microsoft.playwright.androiddriver';
const processMarker = '\nJOLENE_DRIVER_PROCESS_READ_COMPLETE\n';
const socketMarker = '\nJOLENE_DRIVER_SOCKET_READ_COMPLETE\n';
const ps = (extra = '') => ` PID NAME\n 42 app.jolene.recette\n${extra}` + processMarker;
const sockets = (name = '') => 'Num       RefCount Protocol Flags    Type St Inode Path\n'
  + (name ? `00000000: 00000002 00000000 00010000 0001 01 555 ${name}\n` : '') + socketMarker;
const canary = 'PRIVATE_RAW_CANARY';

function setup({ change = async () => undefined, closeError, driverAttempted = true } = {}) {
  const calls = [];
  let psReads = 0, clock = 0;
  const options = { expectedPid, driverAttempted, now: () => clock,
    closeClient: async () => { calls.push({ phase: 'close' }); if (closeError) throw closeError; },
    run: async (file, args, settings) => {
      assert.equal(file, 'adb'); assert.deepEqual(args.slice(0, 2), ['-s', serial]);
      assert(settings.timeout > 0 && settings.timeout <= 5000);
      assert.equal(settings.killSignal, 'SIGKILL'); assert.equal(settings.maxBuffer, 1024 * 1024);
      const phase = args[3]?.startsWith('ps -A') ? 'ps' : args[3]?.startsWith('cat /proc/net/unix')
        ? 'socket' : args.includes('force-stop') ? 'stop' : 'packages';
      calls.push({ phase, args });
      const custom = await change({ phase, calls, settings, setClock: value => { clock = value; } });
      if (custom !== undefined) return custom;
      if (phase === 'ps') return { stdout: ps(++psReads === 1 && driverAttempted ? ` 84 ${driver}\n` : ''), stderr: '' };
      if (phase === 'socket') return { stdout: sockets(), stderr: '' };
      if (phase === 'packages') return { stdout: `package:${driver}\npackage:${driver}.test\n`, stderr: '' };
      return { stdout: '', stderr: '' };
    } };
  return { calls, options, run: () => closeAndroidDriver(serial, options) };
}

test('UI cleanup closes client, stops only owned driver, then proves socket/process absence and same app', async () => {
  const f = setup(), receipt = await f.run();
  assert.deepEqual(f.calls.map(x => x.phase), ['close', 'ps', 'packages', 'stop', 'socket', 'ps']);
  assert.deepEqual(f.calls.find(x => x.phase === 'stop').args, ['-s', serial, 'shell', 'am', 'force-stop', driver]);
  assert.deepEqual(receipt, { schema: 1, status: 'COMPLETE', phase: 'complete', code: 'NONE',
    clientClosed: true, driverStopRequested: true, driverProcessesAbsent: true,
    driverSocketAbsent: true, originalProcessPreserved: true });
  assert(!JSON.stringify(receipt).includes(expectedPid));
});

test('client rejection never becomes success but owned driver cleanup continues', async () => {
  const f = setup({ closeError: new Error(canary) }), receipt = await f.run();
  assert.equal(receipt.status, 'FAILED'); assert.equal(receipt.phase, 'close-client');
  assert.equal(receipt.code, 'COMMAND_FAILED'); assert.equal(receipt.clientClosed, false);
  assert.equal(receipt.driverProcessesAbsent, true); assert.equal(receipt.driverSocketAbsent, true);
  assert(f.calls.some(x => x.phase === 'stop')); assert(!JSON.stringify(receipt).includes(canary));
});

test('hung close consumes only its fixed total budget; no later ADB after exhaustion', async (t) => {
  const f = setup();
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let clock = 0;
  const pending = closeAndroidDriver(serial, { ...f.options, now: () => clock,
    budgetMs: 10, closeClient: () => new Promise(() => {}) });
  // Advance the deadline and timer together. Real timers can fire after a
  // rounded delay but before the overall deadline, leaving cleanup time.
  clock = 10;
  t.mock.timers.tick(10);
  const receipt = await pending;
  assert.equal(receipt.status, 'FAILED'); assert.equal(receipt.code, 'TIMEOUT');
  assert.equal(f.calls.length, 0);
});

test('late completion is refused even if timer dispatch has not occurred', async () => {
  const f = setup({ change: async ({ phase, calls, setClock }) => {
    if (phase === 'ps' && calls.filter(x => x.phase === 'ps').length === 2) setClock(30001);
  } });
  const receipt = await f.run(); assert.equal(receipt.status, 'FAILED'); assert.equal(receipt.code, 'TIMEOUT');
});

test('budget exhaustion prevents subsequent native commands', async () => {
  const f = setup({ change: async ({ phase, setClock }) => { if (phase === 'packages') setClock(30001); } });
  const receipt = await f.run(); assert.equal(receipt.code, 'TIMEOUT');
  assert.deepEqual(f.calls.map(x => x.phase), ['close', 'ps', 'packages']);
});

for (const name of [driver, driver + ':worker', driver + '.test', driver + '.test:worker']) {
  test(`a remaining owned process ${name} refuses cleanup`, async () => {
    const f = setup({ change: async ({ phase }) => phase === 'ps' ? { stdout: ps(` 84 ${name}\n`) } : undefined });
    const receipt = await f.run(); assert.equal(receipt.status, 'FAILED');
    assert.equal(receipt.code, 'DRIVER_PROCESS_REMAINS'); assert.equal(receipt.driverProcessesAbsent, false);
  });
}

test('exact driver socket is refused but similar unrelated socket/process names are untouched', async () => {
  const f = setup({ change: async ({ phase }) => phase === 'socket' ? { stdout: sockets('@playwright_android_driver_socket') } : undefined });
  assert.equal((await f.run()).code, 'DRIVER_SOCKET_REMAINS');
  const similar = setup({ change: async ({ phase }) => phase === 'socket'
    ? { stdout: sockets('@playwright_android_driver_socket_other') }
    : phase === 'ps' ? { stdout: ps(` 84 ${driver}Other\n`) } : undefined });
  assert.equal((await similar.run()).status, 'COMPLETE');
});

test('changed app PID refuses action before stop and rejects completion after stop', async () => {
  for (const atRead of [1, 2]) {
    const f = setup({ change: async ({ phase, calls }) => phase === 'ps'
      && calls.filter(x => x.phase === 'ps').length === atRead ? { stdout: ps().replace('42 app.', '43 app.') } : undefined });
    const receipt = await f.run(); assert.equal(receipt.code, 'APP_PROCESS_CHANGED');
    assert.equal(receipt.status, 'FAILED'); assert.equal(receipt.originalProcessPreserved, false);
    assert.equal(f.calls.some(x => x.phase === 'stop'), atRead === 2);
  }
});

test('driver not attempted is never stopped; unexpected process refuses ownership', async () => {
  const absent = setup({ driverAttempted: false }); assert.equal((await absent.run()).status, 'COMPLETE');
  assert.deepEqual(absent.calls.map(x => x.phase), ['close', 'ps', 'socket', 'ps']);
  const unexpected = setup({ driverAttempted: false, change: async ({ phase }) => phase === 'ps' ? { stdout: ps(` 84 ${driver}\n`) } : undefined });
  assert.equal((await unexpected.run()).code, 'DRIVER_NOT_OWNED');
  assert(!unexpected.calls.some(x => x.phase === 'stop'));
});

test('missing installed package with a live driver refuses stop ownership', async () => {
  const f = setup({ change: async ({ phase }) => phase === 'packages' ? { stdout: '' } : undefined });
  assert.equal((await f.run()).code, 'DRIVER_NOT_OWNED'); assert(!f.calls.some(x => x.phase === 'stop'));
});

for (const phase of ['ps', 'packages', 'stop', 'socket']) {
  test(`${phase} command failure cannot be mistaken for absence and never leaks raw data`, async () => {
    const f = setup({ change: async step => { if (step.phase === phase) throw Object.assign(new Error(canary), { stdout: canary, stderr: canary, code: 1 }); } });
    const receipt = await f.run(); assert.equal(receipt.status, 'FAILED'); assert.equal(receipt.code, 'COMMAND_FAILED');
    assert(!JSON.stringify(receipt).includes(canary));
  });
}

test('truncated or malformed process/socket outputs never prove absence', async () => {
  for (const [phase, stdout] of [['ps', ''], ['ps', ps().replace(processMarker, '')],
    ['ps', ps('BROKEN\n')], ['socket', ''], ['socket', sockets().replace(socketMarker, '')],
    ['socket', 'BAD HEADER\n' + socketMarker], ['socket', sockets().replace(socketMarker, 'BAD ROW\n' + socketMarker)]]) {
    const f = setup({ change: async step => step.phase === phase ? { stdout } : undefined });
    const receipt = await f.run(); assert.equal(receipt.status, 'FAILED'); assert.equal(receipt.code, 'INVALID_PROJECTION');
  }
});

test('invalid context makes no command or client call', async () => {
  for (const change of [{ expectedPid: undefined }, { expectedPid: '0' }, { driverAttempted: undefined }, { budgetMs: 30001 }]) {
    const f = setup(); const receipt = await closeAndroidDriver(serial, { ...f.options, ...change });
    assert.equal(receipt.code, 'INVALID_CONTEXT'); assert.equal(f.calls.length, 0);
  }
  const f = setup(); assert.equal((await closeAndroidDriver('bad;serial', f.options)).code, 'INVALID_CONTEXT');
  assert.equal(f.calls.length, 0);
});

test('output-limit kill remains distinct from command timeout', async () => {
  for (const [error, code] of [[{ code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER', killed: true }, 'OUTPUT_LIMIT'], [{ killed: true }, 'TIMEOUT']]) {
    const f = setup({ change: async () => { throw Object.assign(new Error(canary), error); } });
    const receipt = await f.run(); assert.equal(receipt.status, 'FAILED'); assert.equal(receipt.code, code);
  }
});

test('finalization records exactly the closed receipt then refuses failed cleanup or failed receipt', async () => {
  const ok = setup(), records = [];
  await finalizeAndroidDriver(serial, ok.options, async value => records.push(value));
  assert.equal(records.length, 1); assert.equal(records[0].status, 'COMPLETE');
  const bad = setup({ closeError: new Error(canary) }), failed = [];
  await assert.rejects(finalizeAndroidDriver(serial, bad.options, async value => failed.push(value)), /^Error: ANDROID_DRIVER_CLEANUP_FAILED$/);
  assert.equal(failed[0].status, 'FAILED');
  const write = setup();
  await assert.rejects(finalizeAndroidDriver(serial, write.options, async () => { throw new Error(canary); }), /^Error: ANDROID_DRIVER_CLEANUP_RECEIPT_FAILED$/);
});

test('navigation finally preserves UI failure and rejects cleanup failure after UI success', async () => {
  const source = await readFile(new URL('./navigation.mjs', import.meta.url), 'utf8');
  const tail = source.slice(source.lastIndexOf('\n} finally {') + '\n} finally {'.length, source.lastIndexOf('\n}'));
  const importLine = "    const { finalizeAndroidDriver } = await import('./close-android-driver.mjs');";
  assert(tail.includes(importLine));
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const run = new AsyncFunction('navigationFailed', 'finalizeAndroidDriver', 'device', 'originalAppPid',
    'accessibilityDriverAttempted', 'save', tail.replace(importLine, ''));
  for (const uiFailed of [true, false]) {
    const original = new Error('ORIGINAL_UI_FAILURE'), cleanup = new Error('ANDROID_DRIVER_CLEANUP_FAILED');
    for (const cleanupFailed of [true, false]) {
      const order = [];
      const finish = async (deviceSerial, options, record) => {
        assert.equal(deviceSerial, serial); assert.equal(options.expectedPid, expectedPid);
        assert.equal(options.driverAttempted, true); await options.closeClient();
        await record({ status: cleanupFailed ? 'FAILED' : 'COMPLETE' });
        if (cleanupFailed) throw cleanup;
      };
      const scenario = async () => {
        try { if (uiFailed) throw original; }
        finally { await run(uiFailed, finish, { serial: () => serial, close: async () => order.push('close') },
          expectedPid, true, async (name, text) => { assert.equal(name, 'driver-cleanup.json'); JSON.parse(text); order.push('receipt'); }); }
      };
      if (uiFailed || cleanupFailed) await assert.rejects(scenario(), error => error === (uiFailed ? original : cleanup));
      else await scenario();
      assert.deepEqual(order, ['close', 'receipt']);
    }
  }
  assert(!/process\.exit\s*\(/.test(tail));
  assert(source.indexOf('accessibilityDriverAttempted = true;') < source.indexOf('await device.wait({ pkg }, { timeout: 60000 });'));
  assert.equal(source.match(/await device\.wait\(\{ pkg, text:.*timeout: 10000/g)?.length, 1);
});

test('navigation catch keeps original cause when failure receipt or terminal capture fails', async () => {
  const source = await readFile(new URL('./navigation.mjs', import.meta.url), 'utf8');
  const marker = '} catch (error) {\n  // Record the original cause';
  const body = source.slice(source.lastIndexOf(marker) + '} catch (error) {'.length, source.lastIndexOf('\n} finally {'));
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const run = new AsyncFunction('error', 'save', 'capture', 'captureAccessibility', 'device',
    'originalAppPid', 'validations', 'errors', 'let navigationFailed = false;\n' + body);
  for (const mode of ['receipt', 'diagnostic', 'none']) {
    const original = new Error('ORIGINAL_UI_FAILURE'), order = [];
    const save = async name => { order.push(name); if (mode === 'receipt') throw new Error(canary); };
    const capture = async () => { order.push('capture'); };
    const diagnostic = async () => { if (mode === 'diagnostic') throw new Error(canary); return {}; };
    await assert.rejects(run(original, save, capture, diagnostic, { serial: () => serial, close: async () => {} },
      expectedPid, [], []), error => error === original);
    assert.equal(order[0], 'failure.json');
  }
});
