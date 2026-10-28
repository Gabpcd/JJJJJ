import test from 'node:test';
import assert from 'node:assert/strict';
import { DemoDocumentGateway, type DemoDocumentSession } from './demoGateway';
import { createDemoDocumentFile } from './demoFixture';
import { createDemoDocumentUploadJournal } from './demoJournal';
import { createDemoDocumentChoices, createDemoDocumentScenarioMedia } from './demoScenario';

const A = 'demo-soignant'; const B = 'demo-inscription';
const currentTime = () => new Date('2026-10-27T12:00:00Z');
function fixture() {
  let session: DemoDocumentSession | null = { userId: A, epoch: 1, profile: { profession: 'IDE', type_exercice: 'MIXTE' } };
  const currentSession = () => session;
  const gateway = new DemoDocumentGateway({ currentSession, now: currentTime,
    outcomes: [{ userId: A, typeDocument: 'RCP_ASSURANCE', kind: 'uncertain_committed' }] });
  return { gateway, currentSession, setSession: (next: DemoDocumentSession | null) => { session = next; }, journal: createDemoDocumentUploadJournal() };
}

test('only explicit demo identities are accepted and the selected profession is preserved', async () => {
  const f = fixture();
  const initial = await f.gateway.readDossier({ userId: A });
  assert.equal(initial.profile?.profession, 'IDE');
  assert.equal(initial.documents.length, 3);
  await assert.rejects(f.gateway.readDossier({ userId: B }));
  await assert.rejects(f.gateway.readDossier({ userId: '00000000-0000-0000-0000-000000000001' }));
  f.setSession({ userId: A, epoch: 2, profile: { profession: 'MEDECIN', type_exercice: 'SALARIE' } });
  const doctor = await f.gateway.readDossier({ userId: A });
  assert.equal(doctor.profile?.profession, 'MEDECIN');
  assert.equal(doctor.profile?.rpps_verifie, false);
  assert(doctor.requirements.every(rule => rule.profession === 'MEDECIN'));
  f.setSession({ userId: B, epoch: 3 });
  const other = await f.gateway.readDossier({ userId: B });
  assert.deepEqual(other.documents, []);
  assert.equal(other.profile?.id, B);
});

test('mutating a returned dossier cannot alter stored statuses, owners or originals', async () => {
  const f = fixture(); const initial = await f.gateway.readDossier({ userId: A });
  const id = initial.documents.find(doc => doc.type_document === 'CARTE_IDENTITE')!.id;
  initial.documents[0].soignant_id = B;
  initial.profile!.rpps_verifie = true;
  const reviewed = await f.gateway.requestReview({ userId: A }, id, 'Revue fictive demandée dans le scénario');
  assert.equal(reviewed.document?.statut_verification, 'REVUE_MANUELLE_REQUISE');
  const latest = await f.gateway.readDossier({ userId: A });
  assert(latest.documents.every(doc => doc.soignant_id === A));
  assert.equal(latest.profile?.rpps_verifie, false);
  assert.match(reviewed.message, /Simulation/);
});

test('uncertain synthetic upload is reconciled without a second file or invented verification', async () => {
  const f = fixture(); const phases: string[] = [];
  const result = await f.gateway.upload({ userId: A }, { typeDocument: 'RCP_ASSURANCE', file: createDemoDocumentFile(),
    onPrepared: async receipt => { phases.push(receipt.registration!.phase); await f.journal.write(A, receipt); } });
  assert.equal(result.kind, 'unconfirmed');
  assert.equal(result.document, null);
  const pending = (await f.journal.read(A))!;
  const reconciled = await f.gateway.reconcileUpload({ userId: A }, pending.storageKey);
  assert.equal(reconciled.kind, 'confirmed');
  assert.equal(reconciled.document?.statut_verification, 'EN_ATTENTE');
  assert.equal(reconciled.dossier?.documents.filter(doc => doc.type_document === 'RCP_ASSURANCE').length, 1);
  assert.deepEqual(phases, ['prepared', 'started']);
  await f.journal.clear(A, pending.storageKey);
  assert.equal(await f.journal.read(A), null);
  const verified = await f.gateway.verify({ userId: A }, reconciled.document!.id);
  assert.equal(verified.document?.statut_verification, 'VERIFIE');
  assert.equal(verified.dossier?.profile?.rpps_verifie, false);
});

test('abort before synthetic commit clears only its prepared receipt and leaves the dossier unchanged', async () => {
  const f = fixture(); const before = await f.gateway.readDossier({ userId: A });
  const abort = new AbortController(); let notStarted = 0;
  await assert.rejects(f.gateway.upload({ userId: A }, {
    typeDocument: 'RCP_ASSURANCE', file: createDemoDocumentFile(),
    onPrepared: async receipt => { await f.journal.write(A, receipt); abort.abort(); },
    onNotStarted: async receipt => { notStarted += 1; await f.journal.clear(A, receipt.storageKey); },
  }, abort.signal), { name: 'AbortError' });
  assert.equal(notStarted, 1);
  assert.equal(await f.journal.read(A), null);
  assert.deepEqual(await f.gateway.readDossier({ userId: A }), before);
});

test('changing demo account after preparation cannot commit into either account', async () => {
  const f = fixture(); const before = await f.gateway.readDossier({ userId: A });
  await assert.rejects(f.gateway.upload({ userId: A }, { typeDocument: 'RCP_ASSURANCE', file: createDemoDocumentFile(),
    onPrepared: async receipt => { await f.journal.write(A, receipt); f.setSession({ userId: B, epoch: 2 }); },
    onNotStarted: receipt => f.journal.clear(A, receipt.storageKey),
  }));
  assert.equal(await f.journal.read(A), null);
  assert.equal((await f.gateway.readDossier({ userId: B })).documents.length, 0);
  f.setSession({ userId: A, epoch: 3 });
  assert.deepEqual(await f.gateway.readDossier({ userId: A }), before);
});

test('replacement and withdrawal keep former originals immutable and return active rows only', async () => {
  const f = fixture(); const before = await f.gateway.readDossier({ userId: A });
  const old = before.documents.find(doc => doc.type_document === 'DIPLOME')!;
  const replacement = await f.gateway.upload({ userId: A }, {
    typeDocument: 'DIPLOME', replacesDocumentId: old.id, file: createDemoDocumentFile('remplacement-demo.png'),
  });
  assert.equal(replacement.kind, 'confirmed');
  assert.notEqual(replacement.document?.id, old.id);
  assert.equal(old.revoque_le, null, 'previously returned snapshot remains immutable');
  assert(!replacement.dossier?.documents.some(doc => doc.id === old.id));
  await assert.rejects(f.gateway.verify({ userId: A }, old.id));
  const removed = await f.gateway.logicalDelete({ userId: A }, replacement.document!.id);
  assert(!removed.dossier?.documents.some(doc => doc.type_document === 'DIPLOME'));
  assert.equal((await f.gateway.readDossier({ userId: A })).documents.some(doc => doc.type_document === 'DIPLOME'), false);
});

test('demo journal isolates users and refuses stale overwrite or deletion', async () => {
  const journal = createDemoDocumentUploadJournal();
  const one = `${A}/documents/DIPLOME/demo-one.png`; const two = `${A}/documents/DIPLOME/demo-two.png`;
  const other = `${B}/documents/CARTE_IDENTITE/demo-other.png`;
  await journal.write(A, { storageKey: one }); await journal.write(B, { storageKey: other });
  await assert.rejects(journal.write(A, { storageKey: two }));
  await assert.rejects(journal.clear(A, two));
  assert.deepEqual(await journal.read(A), { storageKey: one });
  assert.deepEqual(await journal.read(B), { storageKey: other });
  await journal.clear(A, one); await journal.write(A, { storageKey: two });
  await assert.rejects(journal.clear(A, one));
  assert.deepEqual(await journal.read(A), { storageKey: two });
});

test('demo picker returns only injected files and rejects a changed session', async () => {
  const f = fixture(); const media = createDemoDocumentScenarioMedia({ identity: f.currentSession()!, currentSession: f.currentSession, choices: createDemoDocumentChoices() });
  assert.equal(media.open, undefined);
  assert.deepEqual(media.sources, ['file']);
  const selected = await media.pick('file', new AbortController().signal);
  assert.equal(selected?.file.name, 'remplacement-annule-demo.png');
  f.setSession({ userId: B, epoch: 2 });
  await assert.rejects(media.pick('file', new AbortController().signal));
});


test('synthetic reconciliation finds archived rows and closes a never-registered prepared receipt', async () => {
  const f = fixture();
  const result = await f.gateway.upload({ userId: A }, { typeDocument: 'RCP_ASSURANCE', file: createDemoDocumentFile(),
    onPrepared: receipt => f.journal.write(A, receipt) });
  const pending = (await f.journal.read(A))!;
  const before = await f.gateway.reconcileUpload({ userId: A }, pending);
  await f.gateway.logicalDelete({ userId: A }, before.document!.id);
  const archived = await f.gateway.reconcileUpload({ userId: A }, pending);
  assert.equal(archived.resolution?.outcome, 'archived'); assert.equal(archived.kind, 'rejected');
  await f.journal.clear(A, pending.storageKey);
  const prepared = { ...pending, storageKey: pending.storageKey.replace('demo-upload-', 'demo-never-registered-'),
    registration: { ...pending.registration!, phase: 'prepared' as const } };
  await f.journal.write(A, prepared);
  const closed = await f.gateway.reconcileUpload({ userId: A }, prepared);
  assert.equal(closed.resolution?.outcome, 'not_registered');
  assert.equal(result.kind, 'unconfirmed');
});


test('explicit demo interruption before registration leaves the current RIB untouched and releases by read', async () => {
  const f = fixture();
  const gateway = new DemoDocumentGateway({ currentSession: f.currentSession,
    outcomes: [{ userId: A, typeDocument: 'RIB', kind: 'uncertain_prepared' }] });
  const before = await gateway.readDossier({ userId: A });
  const original = before.documents.find(row => row.type_document === 'RIB')!;
  const result = await gateway.upload({ userId: A }, { typeDocument: 'RIB', file: createDemoDocumentFile(), replacesDocumentId: original.id,
    onPrepared: receipt => f.journal.write(A, receipt) });
  assert.equal(result.kind, 'unconfirmed');
  const pending = (await f.journal.read(A))!; assert.equal(pending.registration?.phase, 'prepared');
  const read = await gateway.reconcileUpload({ userId: A }, pending);
  assert.equal(read.resolution?.outcome, 'not_registered');
  assert.deepEqual(read.dossier?.documents.find(row => row.type_document === 'RIB'), original);
  await f.journal.clear(A, read.resolution!.storageKey); assert.equal(await f.journal.read(A), null);
});
