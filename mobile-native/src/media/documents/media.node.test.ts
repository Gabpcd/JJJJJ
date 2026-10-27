import assert from 'node:assert/strict';
import test from 'node:test';
import type { DocumentSelection } from '../../ui/documents/adapters';
import type { DocumentOriginal } from '../../workflows/documents/types';
import { createDocumentMediaAdapter } from './core';
import { assertLocalDocumentUri, decodePickerJpeg, DOCUMENTS_STAGING_ORIGIN, isCacheDescendant,
  jpegCopyName, MAX_DOCUMENT_BYTES, validateOriginalForOpening } from './policy';
import type { DocumentMediaPorts, PickedDocumentAsset } from './types';

const UID = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';
const NOW = Date.parse('2026-10-27T12:00:00Z');
const jpeg = new Uint8Array([255, 216, 255, 0]);
const pdf = () => new TextEncoder().encode('%PDF-1.7\nfictif');
const original = (): DocumentOriginal => ({
  uri: `${DOCUMENTS_STAGING_ORIGIN}/storage/v1/object/sign/jolene-documents/${UID}/documents/DIPLOME/test.pdf?token=fictif`,
  mime: 'application/pdf', fileName: 'diplome.pdf', expiresAt: new Date(NOW + 60_000).toISOString(),
});
const pending = <T,>() => {
  let resolve!: (value: T) => void; let reject!: (cause: unknown) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
function fixture(options: { platform?: 'ios' | 'android'; permission?: boolean; choose?: Promise<PickedDocumentAsset | null>;
  bytes?: Uint8Array; open?: Promise<'opened' | 'cancel' | 'dismiss' | 'locked'>;
  dismiss?: () => void; throwNative?: boolean } = {}) {
  const calls: string[] = []; let epoch = 1; let uri: string | null = null;
  const copies: Uint8Array[] = [];
  const ports: DocumentMediaPorts = {
    platform: options.platform ?? 'ios',
    requestCameraPermission: async () => { calls.push('permission.camera'); return options.permission ?? true; },
    choose: async source => {
      calls.push(`choose.${source}`);
      if (options.throwNative) throw new Error('Private URL https://provider.invalid/?token=do-not-render');
      if (options.choose) return options.choose;
      return source === 'file' ? { uri: 'file:///cache/requested.pdf', name: 'diplome.pdf', mime: 'application/pdf' }
        : { uri: 'file:///library/original.HEIC', name: 'original.HEIC', base64: Buffer.from(jpeg).toString('base64') };
    },
    discardPendingResult: async () => { calls.push('discard.pending'); },
    readLocalDocument: async source => { calls.push(`read.${source}`); return options.bytes ?? pdf(); },
    createPrivateCopy: async file => {
      calls.push('copy.own'); copies.push(new Uint8Array(file.bytes));
      return { uri: 'file:///cache/our-copy', release: async () => { calls.push('release.own'); } };
    },
    cleanupPickedAsset: async asset => { if (asset.uri.startsWith('file:///cache/')) calls.push(`cleanup.requested.${asset.uri}`); },
    cleanup: async () => { calls.push('cleanup.all.own'); },
    openSystemDocument: async target => { calls.push('open.system'); uri = target; return options.open ?? 'opened'; },
    ...(options.platform === 'android' ? {} : { dismissSystemDocument: async () => { calls.push('dismiss.system'); options.dismiss?.(); } }),
  };
  const adapter = createDocumentMediaAdapter({ scope: { userId: UID, epoch: 1 },
    isCurrent: scope => scope.userId === UID && scope.epoch === epoch, ports, now: () => NOW });
  return { adapter, calls, copies, ports, changeEpoch: () => { epoch += 1; }, opened: () => uri };
}

test('JPEG decoder checks actual signature, canonical base64, and decoded size before allocation', () => {
  assert.deepEqual(decodePickerJpeg('/9j/AA=='), jpeg);
  for (const value of [null, '', '/9j/AB==', '=9j/AA==', '/9j/AA= ', 'data:image/jpeg;base64,/9j/AA==', 'JVBERi0x']) {
    assert.throws(() => decodePickerJpeg(value));
  }
  assert.throws(() => decodePickerJpeg(Buffer.alloc(MAX_DOCUMENT_BYTES + 1).toString('base64')), /10 Mo/);
  assert.equal(jpegCopyName('portrait.HEIC'), 'portrait.jpg');
  assert.equal(jpegCopyName('../../portrait.AVIF'), 'portrait.jpg');
});

test('cleanup policy excludes originals, cache siblings, encoded traversal, and nonlocal URLs', () => {
  assert.equal(isCacheDescendant('file:///app/cache/picked/file.pdf', 'file:///app/cache/'), true);
  for (const uri of ['file:///app/cache', 'file:///app/cache-other/file.pdf', 'file:///app/original.pdf',
    'file:///app/cache/../original.pdf', 'file:///app/cache/%2e%2e/original.pdf',
    'content://provider/document/1', 'https://example.invalid/file.pdf', 'file:///app/cache/a%2fb.pdf']) {
    assert.equal(isCacheDescendant(uri, 'file:///app/cache/'), false, uri);
  }
  assert.doesNotThrow(() => assertLocalDocumentUri('content://provider/document/1'));
  assert.throws(() => assertLocalDocumentUri('https://example.invalid/file.pdf'));
});

test('original viewer accepts only the exact current-account artifact with bounded future TTL', () => {
  const file = original(); assert.equal(validateOriginalForOpening(file, UID, NOW), file.uri);
  const invalids = [
    { ...file, uri: file.uri.replace(UID, OTHER) }, { ...file, uri: file.uri.replace('mejpriaetwgtcstbgfid', 'production') },
    { ...file, uri: `${file.uri}&token=second` }, { ...file, uri: `${file.uri}&download=1` },
    { ...file, uri: `${file.uri}#fragment` }, { ...file, uri: file.uri.replace('test.pdf', '%2e%2e/test.pdf') },
    { ...file, uri: file.uri.replace('https://', 'https://user@') },
    { ...file, expiresAt: new Date(NOW + 4000).toISOString() },
    { ...file, expiresAt: new Date(NOW + 3600_001).toISOString() },
    { ...file, expiresAt: 'invalid' }, { ...file, mime: 'text/html' }, { ...file, mime: 'application/octet-stream' },
  ];
  for (const candidate of invalids) assert.throws(() => validateOriginalForOpening(candidate, UID, NOW));
});

test('camera permission occurs only at camera gesture, with explicit denial and no photo picker', async () => {
  const sample = fixture({ permission: false }); assert.equal(sample.calls.length, 0);
  await sample.adapter.prepare(); assert.equal(sample.calls.length, 0);
  await assert.rejects(sample.adapter.pick('camera', new AbortController().signal), { code: 'PERMISSION_DENIED' });
  assert.deepEqual(sample.calls, ['permission.camera']); await sample.adapter.dispose();
});

test('library uses real decoded JPEG, preserves HEIC source, and releases only the adapter copy', async () => {
  const sample = fixture(); const selection = (await sample.adapter.pick('library', new AbortController().signal))!;
  assert.equal(selection.file.name, 'original.jpg'); assert.equal(selection.file.mime, 'image/jpeg');
  assert.deepEqual(selection.file.bytes, jpeg); assert.deepEqual(sample.copies, [jpeg]);
  assert.equal(sample.calls.some(call => call.includes('permission')), false);
  assert.equal(sample.calls.some(call => call.includes('cleanup.requested')), false);
  const forged: DocumentSelection = { file: { name: 'original.HEIC', mime: 'image/heic', bytes: jpeg.slice() },
    localPreviewUri: 'file:///library/original.HEIC' };
  await sample.adapter.release?.(forged); assert.equal(sample.calls.includes('release.own'), false);
  await sample.adapter.release?.(selection); assert.equal(sample.calls.filter(call => call === 'release.own').length, 1);
  assert.deepEqual(selection.file.bytes, new Uint8Array(4)); await sample.adapter.dispose();
});

test('fresh file is validated by actual bytes, copied privately, and requested cache copy cleaned', async () => {
  const sample = fixture(); const selection = (await sample.adapter.pick('file', new AbortController().signal))!;
  assert.equal(selection.file.mime, 'application/pdf'); assert.deepEqual(selection.file.bytes, pdf());
  assert.ok(sample.calls.includes('cleanup.requested.file:///cache/requested.pdf'));
  await sample.adapter.dispose(); assert.ok(sample.calls.includes('release.own'));
  const fakePdf = fixture({ bytes: jpeg.slice() });
  await assert.rejects(fakePdf.adapter.pick('file', new AbortController().signal), { code: 'INVALID_FILE' });
  assert.equal(fakePdf.calls.includes('copy.own'), false); await fakePdf.adapter.dispose();
  const large = fixture({ bytes: new Uint8Array(MAX_DOCUMENT_BYTES + 1) });
  await assert.rejects(large.adapter.pick('file', new AbortController().signal), /10 Mo/);
  assert.equal(large.calls.includes('copy.own'), false); await large.adapter.dispose();
});

test('fresh ImagePicker cache copies are cleaned too, including a late cancelled camera result', async () => {
  const asset = { uri: 'file:///cache/ImagePicker/photo.HEIC', name: 'photo.HEIC', base64: Buffer.from(jpeg).toString('base64') };
  const sample = fixture({ choose: Promise.resolve(asset) });
  const selection = await sample.adapter.pick('library', new AbortController().signal); assert.ok(selection);
  assert.ok(sample.calls.includes(`cleanup.requested.${asset.uri}`)); await sample.adapter.dispose();
  const choice = pending<PickedDocumentAsset | null>(); const late = fixture({ choose: choice.promise });
  const controller = new AbortController(); const operation = late.adapter.pick('camera', controller.signal);
  const assertion = assert.rejects(operation, { name: 'AbortError' });
  // The test controls the native response; wait for the mocked permission and presentation.
  for (let i = 0; i < 6 && !late.calls.includes('choose.camera'); i += 1) await Promise.resolve();
  assert.ok(late.calls.includes('choose.camera')); controller.abort(); choice.resolve(asset); await assertion;
  assert.equal(late.calls.includes('copy.own'), false);
  assert.ok(late.calls.includes(`cleanup.requested.${asset.uri}`)); await late.adapter.dispose();
});

test('Android recovered results are discarded before a fresh selection and never exposed', async () => {
  const cancelled = fixture({ platform: 'android', choose: Promise.resolve(null) });
  await cancelled.adapter.prepare(); assert.deepEqual(cancelled.calls, ['discard.pending']);
  assert.equal(await cancelled.adapter.pick('library', new AbortController().signal), null);
  assert.deepEqual(cancelled.calls, ['discard.pending', 'choose.library']);
  assert.equal(cancelled.copies.length, 0); await cancelled.adapter.dispose();
});

test('abort before picking does not present native UI; late old-account result cannot become a draft', async () => {
  const sample = fixture(); const controller = new AbortController(); controller.abort();
  await assert.rejects(sample.adapter.pick('file', controller.signal), { name: 'AbortError' });
  assert.equal(sample.calls.length, 0); await sample.adapter.dispose();
  const choice = pending<PickedDocumentAsset | null>(); const old = fixture({ choose: choice.promise });
  const operation = old.adapter.pick('file', new AbortController().signal);
  const assertion = assert.rejects(operation, { name: 'AbortError' });
  await Promise.resolve(); await Promise.resolve(); old.changeEpoch();
  choice.resolve({ uri: 'file:///cache/old-picked.pdf', name: 'old.pdf', mime: 'application/pdf' });
  await assertion; assert.equal(old.calls.includes('copy.own'), false);
  assert.ok(old.calls.includes('cleanup.requested.file:///cache/old-picked.pdf')); await old.adapter.dispose();
});

test('disposing an active picker prevents another session presentation until the old native sheet returns', async () => {
  const choice = pending<PickedDocumentAsset | null>(); const old = fixture({ choose: choice.promise });
  const operation = old.adapter.pick('file', new AbortController().signal);
  const assertion = assert.rejects(operation, { name: 'AbortError' });
  await Promise.resolve(); await Promise.resolve();
  let cleaned = false;
  const disposal = old.adapter.dispose().then(() => { cleaned = true; });
  await Promise.resolve(); assert.equal(cleaned, false);
  const next = fixture();
  await assert.rejects(next.adapter.pick('file', new AbortController().signal), /déjà ouvert/);
  choice.resolve(null); await Promise.all([assertion, disposal]); assert.equal(cleaned, true);
  const selection = await next.adapter.pick('file', new AbortController().signal); assert.ok(selection);
  await next.adapter.dispose();
});

test('logout retains a late picker copy until its failed purge can be retried', async () => {
  const choice = pending<PickedDocumentAsset | null>(), started = pending<void>();
  const old = fixture(); const cacheCopies = new Set<string>(); let failCleanup = true;
  old.ports.choose = async () => {
    started.resolve(); const asset = await choice.promise;
    if (asset) cacheCopies.add(asset.uri); // Emulates the fresh SDK cache copy registry.
    return asset;
  };
  old.ports.cleanupPickedAsset = async asset => {
    if (failCleanup) throw new Error('Private path must not be exposed');
    cacheCopies.delete(asset.uri);
  };
  old.ports.cleanup = async () => {
    old.calls.push('cleanup.all.own');
    if (failCleanup && cacheCopies.size) throw new Error('Temporary cache removal failed');
    cacheCopies.clear();
  };
  const operation = old.adapter.pick('file', new AbortController().signal);
  const rejectedOperation = assert.rejects(operation, (error: Error) =>
    error.message.includes('indisponible') && !error.message.includes('Private'));
  await started.promise; old.changeEpoch();
  let retired = false;
  const disposal = old.adapter.dispose().then(() => { retired = true; });
  const rejectedDisposal = assert.rejects(disposal, { code: 'UNAVAILABLE' });
  await Promise.resolve(); await Promise.resolve();
  assert.equal(retired, false); assert.equal(old.calls.includes('cleanup.all.own'), false);
  await assert.rejects(old.adapter.pick('file', new AbortController().signal), { name: 'AbortError' });
  const lateUri = 'file:///cache/ImagePicker/late-after-logout.pdf';
  choice.resolve({ uri: lateUri, name: 'fictif.pdf', mime: 'application/pdf' });
  await Promise.all([rejectedOperation, rejectedDisposal]);
  assert.equal(retired, false); assert.equal(cacheCopies.has(lateUri), true);
  assert.equal(old.calls.includes('copy.own'), false);
  // The runtime still owns this rejected disposal. A fresh preparation retries it.
  failCleanup = false; await old.adapter.dispose(); retired = true;
  assert.equal(retired, true); assert.equal(cacheCopies.size, 0);
  const next = fixture(); await next.adapter.prepare(); await next.adapter.dispose();
});

test('native errors never expose private file paths or provider URL tokens', async () => {
  const sample = fixture({ throwNative: true });
  await assert.rejects(sample.adapter.pick('file', new AbortController().signal), (error: Error) =>
    error.message.includes('indisponible') && !error.message.includes('token') && !error.message.includes('provider'));
  await sample.adapter.dispose();
});

test('system viewer receives the unmodified signed artifact and rejects wrong scope before opening', async () => {
  const sample = fixture({ platform: 'android' }); const doc = original();
  await sample.adapter.open?.(doc, new AbortController().signal); assert.equal(sample.opened(), doc.uri);
  await assert.rejects(sample.adapter.open!({ ...doc, uri: doc.uri.replace(UID, OTHER) }, new AbortController().signal));
  assert.equal(sample.calls.filter(call => call === 'open.system').length, 1);
  await sample.adapter.dispose(); assert.equal(sample.calls.includes('dismiss.system'), false);
});

test('iOS abort requests system-browser dismissal and does not claim a successful viewing', async () => {
  const browser = pending<'dismiss'>(); const sample = fixture({ open: browser.promise, dismiss: () => browser.resolve('dismiss') });
  const controller = new AbortController(); const operation = sample.adapter.open!(original(), controller.signal);
  const assertion = assert.rejects(operation, { name: 'AbortError' });
  controller.abort(); await assertion;
  assert.ok(sample.calls.includes('dismiss.system')); await sample.adapter.dispose();
});

test('session disposal invalidates pending browser result and all subsequent actions', async () => {
  const browser = pending<'dismiss'>(); const sample = fixture({ open: browser.promise, dismiss: () => browser.resolve('dismiss') });
  const operation = sample.adapter.open!(original(), new AbortController().signal);
  const assertion = assert.rejects(operation, { name: 'AbortError' });
  await sample.adapter.dispose(); await assertion;
  await assert.rejects(sample.adapter.pick('file', new AbortController().signal), { name: 'AbortError' });
});
