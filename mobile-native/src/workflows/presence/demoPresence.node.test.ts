import assert from 'node:assert/strict';
import test from 'node:test';
import { DemoPresenceGateway } from './demoGateway';
import { PresenceWorkflowError, type PresenceContext } from './types';

const caregiver = (userId = 'demo-soignant', epoch = 1): PresenceContext => ({ kind: 'soignant', userId, epoch });
const establishment = (epoch = 2): PresenceContext => ({ kind: 'etablissement', userId: 'demo-etablissement-user',
  etablissementId: 'demo-etablissement', epoch });
function setup(scenario?: 'uncertain-first-scan') {
  let context = caregiver();
  const gateway = new DemoPresenceGateway({ currentSession: () => context, scenario });
  return { gateway, get context() { return context; }, change: (next: PresenceContext) => { context = next; } };
}
const errorCode = (code: PresenceWorkflowError['code']) => (error: unknown) => error instanceof PresenceWorkflowError && error.code === code;

test('demo shows two explicitly fictitious missions without exposing the establishment code to the caregiver', async () => {
  const demo = setup();
  assert.equal(demo.gateway.mode, 'demo');
  const page = await demo.gateway.list(demo.context);
  assert.equal(page.rows.length, 2);
  assert.ok(page.rows.every(row => row.intitule.endsWith('fictive')));
  const detail = await demo.gateway.read(demo.context, page.rows[0].id);
  assert.equal(detail.establishmentCode, null);
  assert.equal(detail.permissions.displayCode, false);
  assert.equal(detail.hasOpenSegment, false);
  demo.change(establishment());
  assert.equal((await demo.gateway.read(demo.context, page.rows[0].id)).establishmentCode, '123456');
});

test('account code chooses mission B even after reading mission A; the code rotates and the old code is rejected', async () => {
  const demo = setup();
  await demo.gateway.read(demo.context, 'demo-presence-a');
  const result = await demo.gateway.scan(demo.context, '654321');
  assert.equal(result.kind, 'confirmed'); if (result.kind !== 'confirmed') return;
  assert.equal(result.mission.id, 'demo-presence-b');
  assert.equal(result.proof.mission_id, result.mission.id);
  assert.equal(result.segment.mission_id, result.mission.id);
  assert.equal(result.proof.type_scan, 'OUVERTURE');
  assert.equal((await demo.gateway.read(demo.context, 'demo-presence-a')).numberOfScans, 0);
  const refused = await demo.gateway.scan(demo.context, '654321');
  assert.equal(refused.kind, 'rejected');
  assert.equal((await demo.gateway.read(demo.context, 'demo-presence-b')).numberOfScans, 1);
  demo.change(establishment());
  const rotated = await demo.gateway.read(demo.context, 'demo-presence-b');
  assert.equal(rotated.establishmentCode, '100001');
  demo.change(caregiver('demo-soignant', 3));
  const departure = await demo.gateway.scan(demo.context, rotated.establishmentCode!);
  assert.equal(departure.kind, 'confirmed'); if (departure.kind !== 'confirmed') return;
  assert.equal(departure.proof.type_scan, 'FERMETURE');
  assert.equal(departure.segment.id, result.segment.id);
  assert.notEqual(departure.segment.fin, null);
  assert.equal((await demo.gateway.read(demo.context, 'demo-presence-b')).hasOpenSegment, false);
});

test('explicit uncertain demo outcome is reconciled without adding another scan, including after a new session epoch', async () => {
  const demo = setup('uncertain-first-scan');
  const result = await demo.gateway.scan(demo.context, '123456');
  assert.equal(result.kind, 'unconfirmed');
  assert.equal(result.mission, null);
  assert.ok(await demo.gateway.pending(demo.context));
  await assert.rejects(demo.gateway.scan(demo.context, '654321'), errorCode('RECONCILIATION_REQUIRED'));
  demo.change(caregiver('demo-soignant', 2));
  const pending = await demo.gateway.pending(demo.context);
  assert.ok(pending);
  const recovered = await demo.gateway.reconcile(demo.context, pending.attemptId);
  assert.equal(recovered.kind, 'confirmed');
  assert.equal((await demo.gateway.read(demo.context, 'demo-presence-a')).numberOfScans, 1);
  assert.equal(await demo.gateway.pending(demo.context), null);
});

test('other demo user cannot read, clear or inherit the first user’s pending scan', async () => {
  const demo = setup('uncertain-first-scan');
  const result = await demo.gateway.scan(demo.context, '123456');
  demo.change(caregiver('demo-inscription', 2));
  assert.equal(await demo.gateway.pending(demo.context), null);
  await assert.rejects(demo.gateway.reconcile(demo.context, result.attemptId), errorCode('INVALID_SCOPE'));
  assert.equal((await demo.gateway.read(demo.context, 'demo-presence-a')).numberOfScans, 0);
  demo.change(caregiver('demo-soignant', 3));
  assert.equal((await demo.gateway.pending(demo.context))?.attemptId, result.attemptId);
});

test('stale session and non-demo identities fail closed instead of opening a real or fallback gateway', async () => {
  const demo = setup(); const stale = demo.context;
  demo.change(caregiver('demo-soignant', 2));
  await assert.rejects(demo.gateway.list(stale), errorCode('SESSION_CHANGED'));
  demo.change(caregiver('a0f8d5ea-ae73-4652-aeb5-164c1cd47ad0', 3));
  await assert.rejects(demo.gateway.scan(demo.context, '123456'), errorCode('INVALID_SCOPE'));
  demo.change({ kind: 'etablissement', userId: 'demo-etablissement-user', etablissementId: 'other-establishment', epoch: 4 });
  await assert.rejects(demo.gateway.read(demo.context, 'demo-presence-a'), errorCode('INVALID_SCOPE'));
});

test('duplicate taps do not create two simulations, and a cancellation before commit creates none', async () => {
  const demo = setup();
  const first = demo.gateway.scan(demo.context, '123456');
  await assert.rejects(demo.gateway.scan(demo.context, '123456'), errorCode('BUSY'));
  assert.equal((await first).kind, 'confirmed');
  assert.equal((await demo.gateway.read(demo.context, 'demo-presence-a')).numberOfScans, 1);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(demo.gateway.scan(demo.context, '654321', controller.signal), { name: 'AbortError' });
  assert.equal((await demo.gateway.read(demo.context, 'demo-presence-b')).numberOfScans, 0);
});

test('return objects cannot mutate the in-memory proof or expose an establishment code through later reads', async () => {
  const demo = setup();
  const result = await demo.gateway.scan(demo.context, '123456');
  assert.equal(result.kind, 'confirmed'); if (result.kind !== 'confirmed') return;
  result.mission.intitule = 'changed outside'; result.segment.debut = 'not a date';
  const detail = await demo.gateway.read(demo.context, 'demo-presence-a');
  assert.equal(detail.mission.intitule, 'Mission A fictive');
  assert.ok(detail.segments.every(segment => Number.isFinite(Date.parse(segment.debut))));
  assert.equal(detail.establishmentCode, null);
});

test('camera remains explicitly unavailable and malformed codes are not extracted or reinterpreted', async () => {
  const demo = setup(); let cameraInvoked = false;
  assert.deepEqual(await demo.gateway.captureCode(demo.context, { scan: async () => { cameraInvoked = true; return { kind: 'code', text: '123456' }; } }), { kind: 'unavailable' });
  assert.equal(cameraInvoked, false);
  await assert.rejects(demo.gateway.scan(demo.context, 'https://example.test/123456'), errorCode('INVALID_INPUT'));
  assert.equal((await demo.gateway.read(demo.context, 'demo-presence-a')).numberOfScans, 0);
});
