import assert from 'node:assert/strict';
import test from 'node:test';
import { createPresenceQrController } from './qrController';
import { createPresenceGpsController } from './gpsController';
import { parsePresenceCode } from '../../workflows/presence/business';
import type { LocationNativePort, PositionSample, PositionSubscription, PresenceSensorGuard, SensorPermission } from './types';

const flush = async () => { for (let i = 0; i < 12; i += 1) await Promise.resolve(); };
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
function guardFixture() {
  const state = { current: true, foreground: true };
  const guard: PresenceSensorGuard = { scope: { userId: '11111111-1111-4111-8111-111111111111', epoch: 7 },
    isCurrent: () => state.current, isForeground: () => state.foreground };
  return { state, guard };
}
function cameraFixture() {
  const { state, guard } = guardFixture(); const calls = { read: 0, request: 0 };
  const permission = { granted: false, canAskAgain: true };
  const qr = createPresenceQrController(guard, { read: async () => { calls.read += 1; return { ...permission }; },
    request: async () => { calls.request += 1; return { granted: true, canAskAgain: true }; } });
  return { qr, state, permission, calls };
}
function gpsFixture(options: { timeout?: number; permissionTimeout?: number } = {}) {
  const { guard, state } = guardFixture(); const calls = { read: 0, request: 0, watch: 0, removed: 0 };
  const permission = { granted: true, canAskAgain: true }; const env = { services: true };
  let receive: ((sample: PositionSample) => void) | undefined;
  const native: LocationNativePort = { readPermission: async () => { calls.read += 1; return { ...permission }; },
    requestPermission: async () => { calls.request += 1; return { ...permission }; },
    servicesEnabled: async () => env.services,
    watch: async callback => { calls.watch += 1; receive = callback; return { remove: () => { calls.removed += 1; } }; } };
  const gps = createPresenceGpsController(guard, native, { now: () => 1_000_000, positionTimeoutMs: options.timeout, permissionTimeoutMs: options.permissionTimeout });
  const sample: PositionSample = { timestamp: 1_000_000, coords: { latitude: 48.85, longitude: 2.35, accuracy: 22 } };
  return { gps, state, calls, permission, native, env, sample, send: (value = sample) => { assert.ok(receive); receive(value); } };
}

test('camera does not request permission on construction; a user capture reads then requests once', async () => {
  const f = cameraFixture(); assert.deepEqual(f.calls, { read: 0, request: 0 });
  const result = f.qr.scan(); await flush();
  assert.equal(f.qr.snapshot().phase, 'scanning'); assert.deepEqual(f.calls, { read: 1, request: 1 });
  f.qr.barcode(f.qr.snapshot().requestId, 'qr', '123456');
  assert.deepEqual(await result, { kind: 'code', text: '123456' }); assert.equal(f.qr.snapshot().phase, 'closed');
});
test('only one QR event is captured; late events and a second simultaneous start cannot replace the code', async () => {
  const f = cameraFixture(); const first = f.qr.scan(); await flush(); const id = f.qr.snapshot().requestId;
  assert.deepEqual(await f.qr.scan(), { kind: 'unavailable' });
  f.qr.barcode(id, 'qr', '123456'); f.qr.barcode(id, 'qr', '654321');
  assert.deepEqual(await first, { kind: 'code', text: '123456' });
  assert.ok(!JSON.stringify(f.qr.snapshot()).includes('123456'));
});
test('invalid QR content is never extracted, retained or returned as a valid code', async () => {
  const f = cameraFixture(); const result = f.qr.scan(); await flush(); const id = f.qr.snapshot().requestId;
  f.qr.barcode(id, 'qr', 'https://example.test/123456'); const captured = await result;
  assert.deepEqual(captured, { kind: 'code', text: '' });
  if (captured.kind === 'code') assert.throws(() => parsePresenceCode(captured.text));
  assert.ok(!JSON.stringify(f.qr.snapshot()).includes('example.test'));
});
test('permanent camera denial makes manual entry possible without another OS permission request', async () => {
  const f = cameraFixture(); f.permission.canAskAgain = false;
  assert.deepEqual(await f.qr.scan(), { kind: 'denied' }); assert.equal(f.calls.request, 0);
});
test('background cancellation and changed identity ignore late camera permission results', async () => {
  const { guard, state } = guardFixture(); const pending = deferred<SensorPermission>();
  const qr = createPresenceQrController(guard, { read: () => pending.promise, request: async () => ({ granted: true, canAskAgain: true }) });
  const capture = qr.scan(); state.foreground = false; qr.cancel();
  assert.deepEqual(await capture, { kind: 'cancelled' });
  state.current = false; pending.resolve({ granted: true, canAskAgain: true }); await flush();
  assert.equal(qr.snapshot().phase, 'closed'); assert.deepEqual(await qr.scan(), { kind: 'cancelled' });
});
test('aborting an active camera closes the preview and does not accept a later frame', async () => {
  const f = cameraFixture(); const abort = new AbortController(); const capture = f.qr.scan(abort.signal); await flush();
  const id = f.qr.snapshot().requestId; abort.abort(); f.qr.barcode(id, 'qr', '123456');
  assert.deepEqual(await capture, { kind: 'cancelled' }); assert.equal(f.qr.snapshot().phase, 'closed');
});

test('GPS neither asks permission nor reads coordinates until chosen and armed for a submission', async () => {
  const f = gpsFixture(); assert.deepEqual(await f.gps.locate(), { kind: 'not_requested' });
  assert.equal(f.calls.read, 0); assert.equal(f.calls.watch, 0);
  await f.gps.choose(true); assert.equal(f.calls.watch, 0);
  assert.deepEqual(await f.gps.locate(), { kind: 'not_requested' });
  const release = f.gps.arm(); const result = f.gps.locate(); await flush(); f.send();
  assert.deepEqual(await result, { kind: 'available', latitude: 48.85, longitude: 2.35, accuracyMeters: 22 });
  assert.equal(f.calls.removed, 1); release(); assert.equal(f.gps.snapshot(), 'off');
  assert.deepEqual(await f.gps.locate(), { kind: 'not_requested' });
});
test('GPS refusal is explicit, contains no coordinates, and never starts a location watcher', async () => {
  const f = gpsFixture(); f.permission.granted = false; f.permission.canAskAgain = false;
  assert.equal(await f.gps.choose(true), 'denied'); const release = f.gps.arm();
  assert.deepEqual(await f.gps.locate(), { kind: 'denied' }); assert.equal(f.calls.watch, 0); assert.equal(f.calls.request, 0); release();
});
test('revocation after opt-in is checked without requesting another permission during submission', async () => {
  const f = gpsFixture(); await f.gps.choose(true); const release = f.gps.arm(); f.permission.granted = false;
  assert.deepEqual(await f.gps.locate(), { kind: 'denied' }); assert.equal(f.calls.request, 0); assert.equal(f.calls.watch, 0); release();
});
test('disabled services and a position timeout remain optional unavailable outcomes', async () => {
  const disabled = gpsFixture(); await disabled.gps.choose(true); disabled.env.services = false;
  const release = disabled.gps.arm(); assert.deepEqual(await disabled.gps.locate(), { kind: 'unavailable' });
  assert.equal(disabled.calls.watch, 0); release();
  const timed = gpsFixture({ timeout: 5 }); await timed.gps.choose(true); const done = timed.gps.arm();
  assert.deepEqual(await timed.gps.locate(), { kind: 'unavailable' }); assert.equal(timed.calls.removed, 1); done();
});
test('a stalled native permission read during submission is bounded and cannot start a late watcher', async () => {
  const f = gpsFixture({ timeout: 5 }); await f.gps.choose(true);
  const delayed = deferred<SensorPermission>(); f.native.readPermission = () => delayed.promise;
  const release = f.gps.arm(); assert.deepEqual(await f.gps.locate(), { kind: 'unavailable' });
  delayed.resolve({ granted: true, canAskAgain: true }); await flush();
  assert.equal(f.calls.watch, 0); release();
});
test('coordinates marked mocked, stale, nonfinite or without known accuracy are never sent as a real position', async () => {
  for (const patch of [{ mocked: true }, { timestamp: 900_000 }, { coords: { latitude: NaN, longitude: 2.35, accuracy: 1 } },
    { coords: { latitude: 48.85, longitude: 2.35, accuracy: null } }]) {
    const f = gpsFixture(); await f.gps.choose(true); const release = f.gps.arm(); const result = f.gps.locate(); await flush();
    f.send({ ...f.sample, ...patch }); assert.deepEqual(await result, { kind: 'unavailable' }); assert.equal(f.calls.removed, 1); release();
  }
});
test('late subscription creation after cancellation is immediately removed and no old-session coordinates escape', async () => {
  const f = gpsFixture(); const subscription = deferred<PositionSubscription>();
  f.native.watch = async () => { f.calls.watch += 1; return subscription.promise; };
  await f.gps.choose(true); const release = f.gps.arm(); const result = f.gps.locate(); await flush();
  f.state.current = false; f.gps.dispose(); assert.deepEqual(await result, { kind: 'unavailable' });
  subscription.resolve({ remove: () => { f.calls.removed += 1; } }); await flush();
  assert.equal(f.calls.removed, 1); release();
});
test('a callback preceding subscription resolution is consumed only once and its late handle is removed', async () => {
  const f = gpsFixture(); const subscription = deferred<PositionSubscription>();
  f.native.watch = async receive => { receive(f.sample); return subscription.promise; };
  await f.gps.choose(true); const release = f.gps.arm(); const result = f.gps.locate();
  assert.equal((await result).kind, 'available');
  subscription.resolve({ remove: () => { f.calls.removed += 1; } }); await flush(); assert.equal(f.calls.removed, 1); release();
});
test('duplicate location calls do not create duplicate watchers, and background cancellation stops the active one', async () => {
  const f = gpsFixture(); await f.gps.choose(true); const release = f.gps.arm(); const first = f.gps.locate();
  assert.deepEqual(await f.gps.locate(), { kind: 'unavailable' }); await flush();
  f.state.foreground = false; f.gps.cancel(); assert.deepEqual(await first, { kind: 'unavailable' });
  assert.equal(f.calls.watch, 1); assert.equal(f.calls.removed, 1); release();
});
test('a late finally from a cancelled submission cannot release a newer GPS attempt', async () => {
  const f = gpsFixture(); await f.gps.choose(true); const oldRelease = f.gps.arm(); f.gps.cancel();
  await f.gps.choose(true); const currentRelease = f.gps.arm(); oldRelease();
  const result = f.gps.locate(); await flush(); f.send();
  assert.equal((await result).kind, 'available'); currentRelease();
});
test('a permission read resolving after the choice timeout cannot open a late system prompt', async () => {
  const f = gpsFixture({ permissionTimeout: 5 }); const delayed = deferred<SensorPermission>();
  f.native.readPermission = () => delayed.promise;
  assert.equal(await f.gps.choose(true), 'unavailable');
  delayed.resolve({ granted: false, canAskAgain: true }); await flush();
  assert.equal(f.calls.request, 0); assert.equal(f.calls.watch, 0);
});
