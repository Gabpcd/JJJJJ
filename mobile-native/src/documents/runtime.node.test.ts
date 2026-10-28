import assert from 'node:assert/strict';
import test from 'node:test';
import { createDocumentRuntime } from './runtime';
import type { DocumentMediaScope, ManagedDocumentMediaAdapter } from '../media/documents/types';
import type { DocumentScreenGateway, DocumentUploadJournal } from '../ui/documents/adapters';

const deferred = () => { let resolve!: () => void; const promise = new Promise<void>(done => { resolve = done; }); return { promise, resolve }; };
function fixture(prepareGate?: Promise<void>) {
  let session: DocumentMediaScope | null = { userId: 'first', epoch: 1 };
  let failCleanup = false;
  const made: Array<{ media: ManagedDocumentMediaAdapter; prepares: number; disposes: number; disposed: boolean }> = [];
  const journal = { read: async () => ({ storageKey: 'unresolved' }), write: async () => {}, clear: async () => {} } as DocumentUploadJournal;
  const runtime = createDocumentRuntime({ gateway: {} as DocumentScreenGateway, uploadJournal: journal,
    currentSession: () => session,
    createMedia: (scope, isCurrent) => {
      const state = { media: null as unknown as ManagedDocumentMediaAdapter, prepares: 0, disposes: 0, disposed: false };
      state.media = { sources: ['file'],
        prepare: async () => { state.prepares++; if (prepareGate) await prepareGate; },
        pick: async () => { if (state.disposed || !isCurrent(scope)) throw new Error('stale'); return null; },
        dispose: async () => { state.disposes++; state.disposed = true; if (failCleanup) throw new Error('cleanup unavailable'); },
      };
      made.push(state); return state.media;
    },
  });
  return { runtime, made, journal, session: () => session!, change: (next: DocumentMediaScope | null) => { session = next; }, failCleanup: (fail: boolean) => { failCleanup = fail; } };
}

test('concurrent screens join one session preparation and keep one durable journal', async () => {
  const gate = deferred(); const f = fixture(gate.promise);
  const first = f.runtime.prepareSession(f.session()); const second = f.runtime.prepareSession(f.session());
  await Promise.resolve(); assert.equal(f.made.length, 1); assert.equal(f.made[0]!.prepares, 1);
  gate.resolve(); const [a, b] = await Promise.all([first, second]);
  assert.equal(a, b); assert.equal(f.runtime.uploadJournal, f.journal);
  assert.equal(await f.runtime.prepareSession(f.session()), a); assert.equal(f.made[0]!.prepares, 1);
});

test('account change invalidates old media synchronously and cannot return a late preparation', async () => {
  const gate = deferred(); const f = fixture(gate.promise);
  const old = f.runtime.prepareSession(f.session());
  const rejected = assert.rejects(old, { name: 'AbortError' });
  await Promise.resolve(); f.change({ userId: 'second', epoch: 2 });
  const disposal = f.runtime.invalidateSession();
  assert.equal(f.made[0]!.disposed, true);
  await assert.rejects(f.made[0]!.media.pick('file', new AbortController().signal), /stale/);
  gate.resolve(); await Promise.all([rejected, disposal]);
  const fresh = await f.runtime.prepareSession(f.session());
  assert.notEqual(fresh, f.made[0]!.media); assert.equal(f.made.length, 2);
});

test('failed cleanup blocks the next preparation and retries without clearing the upload receipt', async () => {
  const f = fixture(); await f.runtime.prepareSession(f.session());
  f.failCleanup(true); f.change({ userId: 'first', epoch: 2 });
  await assert.rejects(f.runtime.invalidateSession(), /nettoyage/);
  await assert.rejects(f.runtime.prepareSession(f.session()), /nettoyage/);
  assert.equal(f.made[1]!.prepares, 0);
  assert.deepEqual(await f.runtime.uploadJournal.read('first'), { storageKey: 'unresolved' });
  f.failCleanup(false); const next = await f.runtime.prepareSession(f.session());
  assert.equal(next, f.made[1]!.media); assert.equal(f.made[1]!.prepares, 1);
  assert.equal(f.made[0]!.disposes, 3);
});

test('logout rejects preparation and final release preserves unresolved upload state', async () => {
  const f = fixture(); const scope = { ...f.session() }; await f.runtime.prepareSession(scope);
  f.change(null); await f.runtime.invalidateSession(); await f.runtime.releaseSession();
  await assert.rejects(f.runtime.prepareSession(scope), { name: 'AbortError' });
  assert.equal(f.made.length, 1); assert.equal(f.made[0]!.disposes, 1);
  assert.deepEqual(await f.runtime.uploadJournal.read('first'), { storageKey: 'unresolved' });
});
