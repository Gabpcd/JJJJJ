import assert from 'node:assert/strict';
import test from 'node:test';
import { createDocumentUploadJournal } from './uploadJournal';
import type { SecureKeyValueStore } from '../session/secureSessionStorage';

const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const first = `${A}/documents/DIPLOME/33333333-3333-4333-8333-333333333333-diplome.pdf`;
const second = `${A}/documents/DIPLOME/44444444-4444-4444-8444-444444444444-diplome.pdf`;
const keyA = `jolene.native.documents.staging.${A}`;
function memoryStore() {
  const values = new Map<string, string>();
  const store: SecureKeyValueStore = {
    async getItem(key) { return values.get(key) ?? null; },
    async setItem(key, value) { values.set(key, value); },
    async removeItem(key) { values.delete(key); },
  };
  return { values, store };
}

test('an upload receipt survives a new runtime, isolated from another account', async () => {
  const { store } = memoryStore();
  await createDocumentUploadJournal(store).write(A, { storageKey: first });
  const resumed = createDocumentUploadJournal(store);
  assert.deepEqual(await resumed.read(A), { storageKey: first });
  assert.equal(await resumed.read(B), null);
});

test('a new upload cannot overwrite an unresolved receipt, and stale clear cannot erase it', async () => {
  const { store } = memoryStore(); const journal = createDocumentUploadJournal(store);
  await journal.write(A, { storageKey: first });
  await assert.rejects(journal.write(A, { storageKey: second }));
  await assert.rejects(journal.clear(A, second));
  assert.deepEqual(await journal.read(A), { storageKey: first });
  await journal.clear(A, first);
  await journal.write(A, { storageKey: second });
  await assert.rejects(journal.clear(A, first));
  assert.deepEqual(await journal.read(A), { storageKey: second });
});

test('receipt arguments are snapshotted and writes serialized before reads', async () => {
  const { store } = memoryStore(); const journal = createDocumentUploadJournal(store);
  const receipt = { storageKey: first };
  const write = journal.write(A, receipt);
  receipt.storageKey = second;
  assert.deepEqual(await journal.read(A), { storageKey: first });
  await write;
});

test('corrupt, oversized, foreign-account and extra credential data block new uploads', async () => {
  for (const raw of ['{', 'x'.repeat(1025), JSON.stringify({ version: 1, userId: B, storageKey: first }),
    JSON.stringify({ version: 1, userId: A, storageKey: first, token: 'unexpected' }),
    JSON.stringify({ version: 2, userId: A, storageKey: first })]) {
    const { store, values } = memoryStore(); values.set(keyA, raw);
    const journal = createDocumentUploadJournal(store);
    await assert.rejects(journal.read(A));
    await assert.rejects(journal.write(A, { storageKey: first }));
    assert.equal(values.get(keyA), raw, 'A corrupt receipt must not be erased to hide uncertainty');
  }
});

test('foreign paths, URL tokens and traversal never enter the journal', () => {
  const { store, values } = memoryStore(); const journal = createDocumentUploadJournal(store);
  for (const path of [first.replace(A, B), first + '?token=secret', first.replace('diplome.pdf', '../file.pdf'),
    `https://example.test/${first}`, `${A}/documents/DIPLOME/épreuve.pdf`]) {
    assert.throws(() => journal.write(A, { storageKey: path }));
  }
  assert.throws(() => journal.read('../someone-else'));
  assert.equal(values.size, 0);
});

test('failed persistence or readback cannot permit upload to start', async () => {
  const { store } = memoryStore();
  const journal = createDocumentUploadJournal({ ...store, async setItem() { throw new Error('locked'); } });
  let uploaded = false;
  await assert.rejects(journal.write(A, { storageKey: first }).then(() => { uploaded = true; }));
  assert.equal(uploaded, false);
  const missing = createDocumentUploadJournal({ ...store, async setItem() {} });
  await assert.rejects(missing.write(A, { storageKey: first }));
});

test('a failed clear keeps the persisted receipt and does not unlock another write', async () => {
  const { store } = memoryStore();
  const journal = createDocumentUploadJournal({ ...store, async removeItem() { throw new Error('locked'); } });
  await journal.write(A, { storageKey: first });
  await assert.rejects(journal.clear(A, first));
  assert.deepEqual(await journal.read(A), { storageKey: first });
  await assert.rejects(journal.write(A, { storageKey: second }));
});

test('concurrent writes admit one receipt, and repeating that same receipt is idempotent', async () => {
  const { store } = memoryStore(); const journal = createDocumentUploadJournal(store);
  const results = await Promise.allSettled([
    journal.write(A, { storageKey: first }), journal.write(A, { storageKey: second }),
  ]);
  assert.equal(results[0].status, 'fulfilled'); assert.equal(results[1].status, 'rejected');
  await journal.write(A, { storageKey: first });
  await journal.clear(A, first);
  await journal.clear(A, first);
  assert.equal(await journal.read(A), null);
});


test('registration barrier survives restart and cannot downgrade or change replacement metadata', async () => {
  const { store } = memoryStore(); const journal = createDocumentUploadJournal(store);
  const prepared = { storageKey: first, registration: { phase: 'prepared' as const, name: 'diplome.pdf', mime: 'application/pdf', size: 20,
    label: 'Diplôme', previousIds: [B] } };
  await journal.write(A, prepared);
  const started = { ...prepared, registration: { ...prepared.registration, phase: 'started' as const } };
  await journal.write(A, started);
  const restart = createDocumentUploadJournal(store);
  assert.deepEqual(await restart.read(A), started);
  await assert.rejects(restart.write(A, prepared));
  await assert.rejects(restart.write(A, { ...started, registration: { ...started.registration, previousIds: [] } }));
  await restart.write(A, { storageKey: first });
  assert.deepEqual(await restart.read(A), started, 'Legacy response cannot erase durable RPC barrier');
});


test('an in-progress local close remains scoped to its captured account and never erases a later receipt', async () => {
  const { store } = memoryStore(); let release!: () => void; let started!: () => void;
  const began = new Promise<void>(resolve => { started = resolve; });
  const gate = new Promise<void>(resolve => { release = resolve; });
  const journal = createDocumentUploadJournal({ ...store, removeItem: async key => { started(); await gate; await store.removeItem(key); } });
  await journal.write(A, { storageKey: first });
  const foreign = first.replace(A, B); await journal.write(B, { storageKey: foreign });
  const close = journal.clear(A, first); await began;
  // The later account is independent from the captured close in progress.
  release(); await close;
  assert.equal(await journal.read(A), null); assert.deepEqual(await journal.read(B), { storageKey: foreign });
  await journal.write(A, { storageKey: second });
  await assert.rejects(journal.clear(A, first));
  assert.deepEqual(await journal.read(A), { storageKey: second });
});
