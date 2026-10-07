import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { captureAccessibility } from './capture-accessibility.mjs';

const serial = 'emulator-5554', pid = '3447';
const markerNames = ['greetingFull', 'greetingPart', 'welcomePart', 'soignantExplanation', 'etabPrepareMission'];
const fields = ['text', 'desc', 'fixtureText', 'fixtureDesc', 'visibleFixtureText', 'visibleFixtureDesc'];
const good = () => ({ schema: 1, fixturePackagePresent: true, fixtureVisibleBoundsPresent: true,
  markers: Object.fromEntries(markerNames.map(name => [name, Object.fromEntries(fields.map(key => [key, false]))])) });
const canary = 'PRIVATE-CANARY-never-in-report';
function setup(change = async () => undefined) {
  const calls = [];
  const run = async (file, args, options) => {
    calls.push({ file, args, options });
    const changed = await change(file, args, options, calls);
    if (changed !== undefined) return changed;
    if (file === 'python3') return { stdout: JSON.stringify(good()), stderr: '' };
    assert.equal(file, 'adb'); assert.deepEqual(args.slice(0, 2), ['-s', serial]);
    assert(options.timeout > 0 && options.timeout <= 18000);
    assert.equal(options.killSignal, 'SIGKILL');
    if (args.includes('pidof')) return { stdout: pid+'\n', stderr: '' };
    if (args.includes('dumpsys')) return { stdout: 'mCurrentFocus=Window{123 u0 app.jolene.recette/app.jolene.android.MainActivity}\n', stderr: '' };
    if (args.includes('wm')) return { stdout: 'Physical size: 1080x1920\n', stderr: '' };
    if (args.includes('cat')) return { stdout: Buffer.from(canary), stderr: '' };
    return { stdout: '', stderr: '' };
  };
  return { calls, run, options: { expectedPid: pid, closeClient: async () => { calls.push({ close: true }); }, run } };
}
const cleanupCalls = calls => calls.filter(x => x.args?.includes('rm'));

test('terminal collection closes first, stops only driver, pins serial, projects then deletes; no raw canary', async () => {
  const fixture = setup();
  const result = await captureAccessibility(serial, fixture.options);
  assert.equal(result.status, 'COMPLETE'); assert.equal(result.cleanup, 'REMOVED');
  assert.equal(fixture.calls[0].close, true);
  const stop = fixture.calls.filter(x => x.args?.includes('force-stop'));
  assert.equal(stop.length, 1); assert.equal(stop[0].args.at(-1), 'com.microsoft.playwright.androiddriver');
  assert.equal(fixture.calls.filter(x => x.args?.includes('uiautomator')).length, 1);
  assert.deepEqual(fixture.calls.find(x => x.args?.includes('uiautomator')).args.slice(2), ['shell', 'timeout', '-s', 'KILL', '15', 'uiautomator', 'dump', '/data/local/tmp/jolene-recette-accessibility.xml']);
  assert.equal(fixture.calls.find(x => x.args?.includes('cat')).options.encoding, null);
  assert.equal(cleanupCalls(fixture.calls).length, 1);
  assert(!JSON.stringify(result).includes(canary));
});

test('existing diagnostic file is preserved, never read or removed', async () => {
  const fixture = setup(async (_, args) => { if (args.includes('test')) throw Object.assign(new Error(canary), {code: 1}); });
  const result = await captureAccessibility(serial, fixture.options);
  assert.equal(result.phase, 'temporary-file-absence'); assert.equal(result.status, 'FAILED');
  assert.equal(cleanupCalls(fixture.calls).length, 0);
  assert(!fixture.calls.some(x => x.args?.includes('cat')));
});

for (const [name, command, error, code] of [
  ['dump timeout', 'uiautomator', { killed: true, stdout: canary }, 'TIMEOUT'],
  ['partial read', 'cat', {code: 1, stdout: canary}, 'COMMAND_FAILED'],
  ['output limit', 'cat', {code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER', stdout: canary}, 'OUTPUT_LIMIT'],
]) test(`${name} is closed, cleaned, never parsed/retried`, async () => {
  const fixture = setup(async (_, args) => { if(args.includes(command)) throw Object.assign(new Error(canary), error); });
  const result = await captureAccessibility(serial, fixture.options);
  assert.equal(result.status, 'FAILED'); assert.equal(result.code, code); assert.equal(result.cleanup, 'REMOVED');
  assert.equal(cleanupCalls(fixture.calls).length, 1); assert(!fixture.calls.some(x => x.file === 'python3'));
  assert(!JSON.stringify(result).includes(canary)); assert.equal(result.projection, undefined);
});

test('cleanup failure stays a failure and cannot disclose earlier projection or stdout', async () => {
  const fixture = setup(async (_, args) => { if(args.includes('rm')) throw new Error(canary); });
  const result = await captureAccessibility(serial, fixture.options);
  assert.equal(result.status, 'FAILED'); assert.equal(result.code, 'CLEANUP_FAILED');
  assert.equal(result.cleanup, 'FAILED'); assert.equal(result.projection, undefined);
  assert(!JSON.stringify(result).includes(canary));
});

test('parser output is schema checked, unknown properties and forged counters never exported', async () => {
  for (const malformed of [{ ...good(), raw: canary }, { ...good(), fixturePackagePresent: false, markers: { ...good().markers, greetingFull: {...good().markers.greetingFull, fixtureText: true} } }, { error: canary }]) {
    const fixture = setup(async (file) => file === 'python3' ? {stdout: JSON.stringify(malformed)} : undefined);
    const result = await captureAccessibility(serial, fixture.options);
    assert.equal(result.code, 'INVALID_PROJECTION'); assert.equal(result.cleanup, 'REMOVED');
    assert(!JSON.stringify(result).includes(canary));
  }
});

test('changed app PID and ANR abort; no app restart or modal dismissal', async () => {
  for (const which of ['pidof', 'dumpsys']) {
    const fixture = setup(async (_, args) => args.includes(which) ? {stdout: which === 'pidof' ? '3555\n' : 'mCurrentFocus=Window{123 u0 app.jolene.recette/app.jolene.android.MainActivity}\nApplication Not Responding: app.jolene.recette'} : undefined);
    const result = await captureAccessibility(serial, fixture.options);
    assert.equal(result.code, 'APP_STATE_CHANGED'); assert.equal(result.status, 'FAILED');
    assert(!fixture.calls.some(x => x.args?.includes('force-stop')));
  }
});

test('changed app after dump rejects evidence and still removes temporary file', async () => {
  let pids=0;
  const fixture = setup(async (_, args) => args.includes('pidof') && ++pids === 2 ? {stdout:'3555\n'} : undefined);
  const result = await captureAccessibility(serial, fixture.options);
  assert.equal(result.phase, 'after-app-check'); assert.equal(result.status, 'FAILED'); assert.equal(result.cleanup, 'REMOVED');
  assert.equal(result.projection, undefined);
});

test('client close failure cannot start a second UiAutomation connection', async () => {
  const fixture = setup();
  const result = await captureAccessibility(serial, {...fixture.options, closeClient: async () => {throw new Error(canary);}});
  assert.equal(result.phase, 'close-client'); assert.equal(result.status, 'FAILED'); assert.equal(fixture.calls.length, 0);
});

test('client close timeout is bounded and no adb follows', async () => {
  const fixture = setup();
  const result = await captureAccessibility(serial, {...fixture.options, budgetMs: 10, closeClient: () => new Promise(() => {})});
  assert.equal(result.code, 'TIMEOUT'); assert.equal(fixture.calls.length, 0);
});

test('invalid serial or original pid is rejected without commands', async () => {
  const fixture = setup();
  for (const [device, expectedPid] of [['x; bad',pid],[serial,undefined]]) {
    const result = await captureAccessibility(device, {...fixture.options, expectedPid});
    assert.equal(result.code,'INVALID_CONTEXT'); assert.equal(fixture.calls.length,0);
  }
});

test('actual terminal catch always rethrows original error even if diagnostic or its record fails', async () => {
  const source = await readFile(new URL('./navigation.mjs', import.meta.url), 'utf8');
  const prefix = '} catch (error) {';
  const body = source.slice(source.lastIndexOf(prefix) + prefix.length, source.lastIndexOf('\n} finally {'));
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const executeCatch = new AsyncFunction('error', 'capture', 'save', 'device', 'captureAccessibility', 'originalAppPid', 'validations', 'errors', body);
  for (const mode of ['success', 'diagnostic-failure', 'record-failure']) {
    const original = new Error('ORIGINAL_UI_FAILURE');
    const order = [];
    const capture = async () => {order.push('capture');};
    const save = async (name) => {order.push(name); if(mode === 'record-failure' && name === 'failure-accessibility.json') throw new Error(canary);};
    const device = {serial: () => serial, close: async () => {order.push('close');}};
    const collect = async (_, options) => {await options.closeClient(); if(mode === 'diagnostic-failure') throw new Error(canary); return {status: 'COMPLETE'};};
    await assert.rejects(executeCatch(original,capture,save,device,collect,pid,[],[]), error => error === original);
    assert(order.indexOf('capture') < order.indexOf('close'));
    assert(order.indexOf('failure.json') < order.indexOf('close'));
  }
});

test('global budget prevents starting a remote dump without its complete deadline and reserves cleanup', async () => {
  let clock=0;
  const fixture = setup(async (_, args) => {if (args.includes('wm')) clock=30000;});
  const result = await captureAccessibility(serial,{...fixture.options, now:()=>clock});
  assert.equal(result.code,'TIMEOUT'); assert.equal(result.phase,'dump'); assert.equal(result.cleanup,'REMOVED');
  assert(!fixture.calls.some(x=>x.args?.includes('uiautomator')));
  assert.equal(cleanupCalls(fixture.calls)[0].options.timeout,5000);
});
