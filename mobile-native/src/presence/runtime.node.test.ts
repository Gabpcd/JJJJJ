import assert from 'node:assert/strict';
import test from 'node:test';
import type { NativeAccountContext } from '../account/types';
import type { PresenceContext } from '../workflows/presence/types';
import type { ManagedPresenceSensors, PresenceSensorScope } from '../media/presence/types';
import { DemoPresenceGateway } from '../workflows/presence/demoGateway';
import { createPresenceRuntime, nativePresenceContext, presenceScenario } from './runtime';

const caregiver: PresenceContext = { kind: 'soignant', userId: 'demo-soignant', epoch: 1 };
const establishment: PresenceContext = { kind: 'etablissement', userId: 'demo-etablissement-user', etablissementId: 'demo-etablissement', epoch: 3 };
function fixture() {
  let current: PresenceContext | null = caregiver;
  const gateway = new DemoPresenceGateway({ currentSession: () => current, scenario: 'uncertain-first-scan' });
  const created: Array<{ scope: PresenceSensorScope; current(scope: PresenceSensorScope): boolean; cancelled: number; disposed: number }> = [];
  let consent: () => Promise<boolean> = async () => true;
  const runtime = createPresenceRuntime({ currentSession: () => current, createSession(context, isCurrent) {
    const record = { scope: { userId: context.userId, epoch: context.epoch }, current: isCurrent, cancelled: 0, disposed: 0 };
    created.push(record);
    const sensors = { scope: record.scope, cancel() { ++record.cancelled; }, dispose() { ++record.disposed; } } as ManagedPresenceSensors;
    return { gateway, sensors, readGpsConsent: () => consent() };
  } });
  return { runtime, created, gateway, setCurrent(value: PresenceContext | null) { current = value; },
    setConsent(value: () => Promise<boolean>) { consent = value; } };
}

test('pointage scenario is explicit and cannot enable synthetic outcomes in staging', () => {
  assert.equal(presenceScenario('demo', undefined), false);
  assert.equal(presenceScenario('demo', '1'), true);
  assert.equal(presenceScenario('staging', '0'), false);
  assert.throws(() => presenceScenario('staging', '1'));
  assert.throws(() => presenceScenario('demo', 'true'));
});
test('account projection preserves establishment identity instead of replacing it with the member ID', () => {
  const account = { kind: 'etablissement', userId: 'member', etablissementId: 'site' } as NativeAccountContext;
  assert.deepEqual(nativePresenceContext(account, 7), { kind: 'etablissement', userId: 'member', etablissementId: 'site', epoch: 7 });
  assert.equal(nativePresenceContext({ kind: 'onboarding' } as NativeAccountContext, 1), null);
  assert.equal(nativePresenceContext(account, -1), null);
});
test('list, detail and scan share a single sensor/gateway bundle for the current account epoch', () => {
  const f = fixture(); const list = f.runtime.session(caregiver); const scan = f.runtime.session({ ...caregiver });
  assert.equal(list, scan); assert.equal(list.gateway, scan.gateway); assert.equal(list.sensors, scan.sensors);
  f.runtime.cancelSensors(); assert.equal(f.created[0].cancelled, 1);
  assert.equal(f.runtime.session(caregiver), list); assert.equal(f.created.length, 1);
});
test('account or epoch changes invalidate sensors before a new bundle is exposed', () => {
  const f = fixture(); f.runtime.session(caregiver); const old = f.created[0];
  f.setCurrent({ ...caregiver, epoch: 2 }); f.runtime.invalidateSession();
  assert.equal(old.disposed, 1); assert.equal(old.current(old.scope), false);
  assert.throws(() => f.runtime.session(caregiver), { name: 'AbortError' });
  f.runtime.session({ ...caregiver, epoch: 2 }); assert.equal(f.created.length, 2);
  f.setCurrent(null); f.runtime.invalidateSession(); assert.equal(f.created[1].disposed, 1);
});
test('release invalidates late callbacks even if the exact same account epoch is mounted again', async () => {
  const f = fixture(); const old = f.runtime.session(caregiver); const sensor = f.created[0];
  f.runtime.releaseSession(); const fresh = f.runtime.session(caregiver);
  assert.notEqual(old, fresh); assert.equal(sensor.current(sensor.scope), false);
  await assert.rejects(old.readGpsConsent(), { name: 'AbortError' });
  assert.equal(await fresh.readGpsConsent(), true);
});
test('late GPS consent for the old account cannot enable the next account', async () => {
  const f = fixture(); let resolve!: (value: boolean) => void;
  f.setConsent(() => new Promise<boolean>(done => { resolve = done; }));
  const pending = f.runtime.session(caregiver).readGpsConsent();
  f.setCurrent(establishment); f.runtime.invalidateSession(); resolve(true);
  await assert.rejects(pending, { name: 'AbortError' });
});
test('an aborted canonical consent read never grants GPS permission', async () => {
  const f = fixture(); const signal = new AbortController(); signal.abort();
  await assert.rejects(f.runtime.session(caregiver).readGpsConsent(signal.signal), { name: 'AbortError' });
});
test('demo uncertain receipt survives tab release, and role switching reads the same actual mission and renewed code', async () => {
  const f = fixture(); const session = f.runtime.session(caregiver);
  assert.equal((await session.gateway.scan(caregiver, '654321')).kind, 'unconfirmed');
  f.runtime.releaseSession(); const resumed = f.runtime.session(caregiver);
  const receipt = await resumed.gateway.pending(caregiver); assert.ok(receipt);
  const arrived = await resumed.gateway.reconcile(caregiver, receipt.attemptId);
  assert.equal(arrived.kind, 'confirmed'); assert.equal(arrived.mission?.id, 'demo-presence-b');
  assert.equal((await resumed.gateway.scan(caregiver, '100001')).proof?.type_scan, 'FERMETURE');
  f.setCurrent(null); f.runtime.invalidateSession(); f.setCurrent(establishment);
  const employer = f.runtime.session(establishment);
  const detail = await employer.gateway.read(establishment, 'demo-presence-b');
  assert.equal(detail.establishmentCode, '100002'); assert.equal(detail.numberOfScans, 2); assert.equal(detail.hasOpenSegment, false);
  assert.equal((await employer.gateway.read(establishment, 'demo-presence-a')).numberOfScans, 0);
});
