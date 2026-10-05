import test from 'node:test';
import assert from 'node:assert/strict';
import { prepareAdbRoot, transientAdbFailure } from './adb-readiness.mjs';

const closed = () => Object.assign(new Error('synthetic transport error'), {
  code: 1, stderr: 'adb: unable to connect for root: closed\n', stdout: '', killed: false, signal: null,
});
const offline = () => Object.assign(new Error('synthetic offline'), {
  code: 1, stderr: 'error: device offline\n', stdout: '', killed: false, signal: null,
});

function fixture({ initialUid = '2000', respond } = {}) {
  let time = 0, uid = initialUid;
  const calls = [], records = [];
  return { calls, records, run: (options = {}) => prepareAdbRoot({
    adb: async (args, budget) => {
      calls.push({ args, ...budget, at: time });
      const value = respond?.({ args, call: calls.length, time,
        setUid: value => { uid = value; }, elapse: ms => { time += ms; } });
      if (value !== undefined) return value;
      const command = args.join(' ');
      if (command === 'get-state') return 'device\n';
      if (command === 'shell pm list packages app.jolene.recette') return '';
      if (command === 'shell id -u') return uid + '\n';
      if (command === 'root') { uid = '0'; return 'restarting adbd as root\n'; }
      throw new Error('Unexpected synthetic command');
    },
    record: async entry => { records.push(entry); }, now: () => time,
    pause: async ms => { time += ms; }, ...options,
  }) };
}

const rootCalls = f => f.calls.filter(call => call.args.join(' ') === 'root');
const isReady = f => f.records.some(entry => entry.phase === 'ready-before-installation');

test('requires two root and absence probes a second apart without rerooting an already-root daemon', async () => {
  const f = fixture({ initialUid: '0' });
  await f.run();
  assert.equal(rootCalls(f).length, 0);
  assert.deepEqual(f.records.at(-1), { phase: 'ready-before-installation', elapsedMs: 1000,
    attempt: 2, uid: 0, fixtureInstalled: false, stableMs: 1000, rootRequests: 0 });
  assert.equal(f.calls.filter(call => call.args.includes('pm')).length, 2);
});

test('successful root request still requires fresh UID 0 and absence evidence after restart', async () => {
  const f = fixture();
  await f.run();
  assert.equal(rootCalls(f).length, 1);
  assert.equal(f.records.at(-1).elapsedMs, 2000);
  assert.equal(f.records.filter(entry => entry.phase === 'probe' && entry.uid === 0).length, 2);
});

test('observed root closed reprobes and does not reroot if the restart already succeeded', async () => {
  const f = fixture({ respond: ({ args, setUid }) => {
    if (args[0] === 'root') { setUid('0'); throw closed(); }
  } });
  await f.run();
  assert.equal(rootCalls(f).length, 1);
  assert.deepEqual(f.records.find(entry => entry.phase === 'transport-wait'), {
    phase: 'transport-wait', elapsedMs: 0, attempt: 1, stage: 'root', reason: 'root_closed',
  });
  assert.equal(f.records.at(-1).uid, 0);
});

test('closed before root takes effect permits a bounded fresh root request only after rechecking absence', async () => {
  let roots = 0;
  const f = fixture({ respond: ({ args }) => { if (args[0] === 'root' && ++roots === 1) throw closed(); } });
  await f.run();
  assert.equal(rootCalls(f).length, 2);
  for (const root of rootCalls(f)) {
    const index = f.calls.indexOf(root);
    assert.deepEqual(f.calls[index - 2].args, ['shell', 'pm', 'list', 'packages', 'app.jolene.recette']);
    assert.deepEqual(f.calls[index - 1].args, ['shell', 'id', '-u']);
  }
});

test('offline transport resets the stable root interval and remains bounded', async () => {
  const f = fixture({ initialUid: '0', respond: ({ args, time }) => {
    if (args[0] === 'get-state' && time === 1000) throw offline();
  } });
  await f.run();
  assert.equal(f.records.at(-1).elapsedMs, 3000);
  assert.equal(rootCalls(f).length, 0);
});

test('an explicit offline state waits without requesting root or querying Android', async () => {
  const f = fixture({ initialUid: '0', respond: ({ args, time }) =>
    args[0] === 'get-state' && time === 0 ? 'offline\n' : undefined });
  await f.run();
  assert.equal(f.records.at(-1).elapsedMs, 2000);
  assert.equal(f.calls.filter(call => call.at === 0).length, 1);
  assert.equal(rootCalls(f).length, 0);
});

test('refuses an installed fixture before any root request, including after a transport loss', async () => {
  for (const appearsLater of [false, true]) {
    const f = fixture({ respond: ({ args, time }) => {
      if (appearsLater && time === 0 && args[0] === 'root') throw closed();
      if (args.includes('pm') && (!appearsLater || time > 0)) return 'package:app.jolene.recette\n';
    } });
    await assert.rejects(f.run(), /APP_ALREADY_INSTALLED/);
    assert.equal(rootCalls(f).length, appearsLater ? 1 : 0);
    assert.equal(isReady(f), false);
  }
});

test('cannot pass if the fixture appears between the two root observations', async () => {
  const f = fixture({ initialUid: '0', respond: ({ args, time }) =>
    args.includes('pm') && time > 0 ? 'package:app.jolene.recette' : undefined });
  await assert.rejects(f.run(), /APP_ALREADY_INSTALLED/);
  assert.equal(rootCalls(f).length, 0);
  assert.equal(f.records.filter(entry => entry.phase === 'probe').length, 1);
  assert.equal(isReady(f), false);
});

test('rejects unauthorized, multiple devices, timeouts, signals and unknown errors without waiting', async () => {
  const errors = [
    Object.assign(offline(), { stderr: 'error: device unauthorized' }),
    Object.assign(offline(), { stderr: 'error: more than one device/emulator' }),
    Object.assign(offline(), { killed: true, signal: 'SIGTERM', code: null }),
    Object.assign(offline(), { code: 2 }),
    Object.assign(offline(), { stderr: 'error: device offline\nApplication Not Responding: app.jolene.recette' }),
    Object.assign(offline(), { stdout: 'unexpected output' }),
    new Error('arbitrary command error'),
  ];
  for (const error of errors) {
    const f = fixture({ respond: () => { throw error; } });
    await assert.rejects(f.run(), /COMMAND_REFUSED_STATE/);
    assert.equal(f.calls.length, 1);
    assert.equal(isReady(f), false);
    assert.equal(f.records.some(entry => entry.phase === 'transport-wait'), false);
  }
});

test('closed is admitted only for root, and absent-device only for the state probe', () => {
  assert.equal(transientAdbFailure(closed(), 'root'), 'root_closed');
  for (const stage of ['state', 'uid', 'absence']) assert.equal(transientAdbFailure(closed(), stage), null);
  const missing = Object.assign(offline(), { stderr: 'error: no devices/emulators found' });
  assert.equal(transientAdbFailure(missing, 'state'), 'device_missing');
  assert.equal(transientAdbFailure(missing, 'root'), null);
});

test('refuses unknown state, unexpected UID and production-build root denial without retry', async () => {
  for (const [command, response, expected] of [
    ['get-state', 'unauthorized', /STATE_REFUSED/],
    ['shell id -u', '1000', /UID_REFUSED/],
    ['root', 'adbd cannot run as root in production builds', /ROOT_REFUSED/],
    ['root', 'unexpected reply', /ROOT_REFUSED/],
  ]) {
    const f = fixture({ respond: ({ args }) => args.join(' ') === command ? response : undefined });
    await assert.rejects(f.run(), expected);
    assert.equal(f.records.some(entry => entry.phase === 'transport-wait'), false);
    assert.equal(isReady(f), false);
  }
});

test('empty successful adb reply still needs two fresh stable root probes', async () => {
  const f = fixture({ respond: ({ args, setUid }) => {
    if (args[0] === 'root') { setUid('0'); return ''; }
  } });
  await f.run();
  assert.equal(rootCalls(f).length, 1);
  assert.equal(f.records.at(-1).elapsedMs, 2000);
  assert.equal(f.records.filter(entry => entry.phase === 'probe' && entry.uid === 0).length, 2);
  assert.equal(f.records.find(entry => entry.phase === 'root-reply').reply, 'empty');
});

test('a root command that never establishes UID 0 cannot pass and is requested at most three times', async () => {
  for (const reply of ['restarting adbd as root', '']) {
    const f = fixture({ respond: ({ args }) => args[0] === 'root' ? reply : undefined });
    await assert.rejects(f.run(), /ROOT_REQUEST_LIMIT/);
    assert.equal(rootCalls(f).length, 3);
    assert.equal(isReady(f), false);
  }
});

test('persistent root closed is capped at three requests; persistent offline at thirty probes', async () => {
  const root = fixture({ respond: ({ args }) => { if (args[0] === 'root') throw closed(); } });
  await assert.rejects(root.run(), /ROOT_REQUEST_LIMIT/);
  assert.equal(rootCalls(root).length, 3);
  const offlineFixture = fixture({ respond: () => { throw offline(); } });
  await assert.rejects(offlineFixture.run(), /ATTEMPT_LIMIT/);
  assert.equal(offlineFixture.calls.length, 30);
});

test('deadline bounds every command and rejects a late successful response', async () => {
  const f = fixture({ respond: ({ elapse }) => { elapse(5100); return 'device'; } });
  await assert.rejects(f.run({ timeoutMs: 5000 }), /TIMEOUT/);
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].timeoutMs, 5000);
  const g = fixture({ respond: ({ args, time }) => {
    if (args[0] === 'get-state' && time < 2000) throw offline();
  } });
  await assert.rejects(g.run({ timeoutMs: 2500 }), /TIMEOUT/);
  assert(g.calls.filter(call => call.at === 2000).every(call => call.timeoutMs === 500));
});

test('transport preparation never installs, launches, stops or reconnects an application or device', async () => {
  const f = fixture();
  await f.run();
  const allowed = new Set(['get-state', 'shell pm list packages app.jolene.recette', 'shell id -u', 'root']);
  assert(f.calls.every(call => allowed.has(call.args.join(' '))));
  assert(f.calls.every(call => call.timeoutMs > 0 && call.timeoutMs <= 5000));
});
