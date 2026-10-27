import { DocumentMediaError, type DocumentSelection, type DocumentSource } from '../../ui/documents/adapters';
import { validateDocumentBytes } from '../../workflows/documents/bytes';
import { DocumentWorkflowError, type DocumentOriginal, type NativeDocumentFile } from '../../workflows/documents/types';
import { decodePickerJpeg, jpegCopyName, validateOriginalForOpening } from './policy';
import type { DocumentMediaPorts, DocumentMediaScope, ManagedDocumentMediaAdapter, OwnedDocumentCopy } from './types';

// One OS presentation at a time, including an old picker finishing after a session change.
let presentationOwner: symbol | null = null;
const aborted = () => Object.assign(new Error('La sélection a été interrompue.'), { name: 'AbortError' });
const unavailable = () => new DocumentMediaError('UNAVAILABLE', 'Cette action est indisponible. Revenez au dossier et réessayez.');

export function createDocumentMediaAdapter(input: {
  scope: DocumentMediaScope; isCurrent: (scope: DocumentMediaScope) => boolean;
  ports: DocumentMediaPorts; now?: () => number;
}): ManagedDocumentMediaAdapter {
  const scope = Object.freeze({ ...input.scope }); const ports = input.ports; const owner = Symbol('documents-media');
  const now = input.now ?? Date.now;
  if (!scope.userId || !Number.isSafeInteger(scope.epoch)) throw unavailable();
  let disposed = false; let prepared = false; let browserOpen = false;
  const selections = new Map<DocumentSelection, OwnedDocumentCopy>();
  // Completion barriers never reject. Register before invoking a native port, including
  // ports that synchronously trigger session invalidation, so dispose cannot miss them.
  const presentations = new Set<Promise<void>>();
  const current = (signal?: AbortSignal) => {
    if (signal?.aborted) throw aborted();
    if (disposed || !input.isCurrent(scope)) throw aborted();
  };
  const exclusive = async <T,>(operation: () => Promise<T>): Promise<T> => {
    current();
    if (presentationOwner !== null) throw new DocumentMediaError('UNAVAILABLE', 'Fermez la sélection ou le document déjà ouvert avant de continuer.');
    presentationOwner = owner;
    let complete!: () => void;
    const completion = new Promise<void>(resolve => { complete = resolve; });
    presentations.add(completion);
    try { return await operation(); }
    catch (error) {
      if (error instanceof DocumentMediaError || (error instanceof Error && error.name === 'AbortError')) throw error;
      if (error instanceof DocumentWorkflowError && error.code === 'INVALID_FILE') throw new DocumentMediaError('INVALID_FILE', error.message);
      // Native SDK errors can contain file paths or signed URLs: never forward those messages.
      throw unavailable();
    } finally {
      if (presentationOwner === owner) presentationOwner = null;
      presentations.delete(completion); complete();
    }
  };
  const prepare = async () => {
    if (prepared) return;
    if (ports.platform === 'android') await ports.discardPendingResult();
    current(); prepared = true;
  };
  const dismiss = async () => {
    if (browserOpen && presentationOwner === owner && ports.dismissSystemDocument) {
      try { await ports.dismissSystemDocument(); } catch { /* iOS may already have closed the view. */ }
    }
  };
  const release = async (selection: DocumentSelection) => {
    const copy = selections.get(selection);
    if (!copy) return; // Never delete a URI supplied by the UI or another adapter instance.
    selection.file.bytes.fill(0);
    try { await copy.release(); selections.delete(selection); }
    catch { throw new DocumentMediaError('UNAVAILABLE', 'La copie temporaire n’a pas pu être supprimée. Réessayez son nettoyage.'); }
  };
  return {
    sources: ['camera', 'library', 'file'],
    prepare: () => exclusive(prepare),
    pick: (source: DocumentSource, signal: AbortSignal) => exclusive(async () => {
      current(signal); await prepare(); current(signal);
      if (!['camera', 'library', 'file'].includes(source)) throw unavailable();
      if (source === 'camera') {
        const granted = await ports.requestCameraPermission(); current(signal);
        if (!granted) throw new DocumentMediaError('PERMISSION_DENIED', 'Autorisez l’accès à l’appareil photo dans les réglages pour photographier ce document.');
      }
      const asset = await ports.choose(source);
      let bytes: Uint8Array | undefined; let copy: OwnedDocumentCopy | undefined; let retained = false;
      try {
        current(signal); if (!asset) return null;
        let file: NativeDocumentFile;
        if (source === 'file') {
          bytes = await ports.readLocalDocument(asset.uri); current(signal);
          file = { name: asset.name ?? '', mime: asset.mime ?? '', bytes };
        } else {
          bytes = decodePickerJpeg(asset.base64);
          file = { name: jpegCopyName(asset.name), mime: 'image/jpeg', bytes };
        }
        const validated = await validateDocumentBytes(file);
        bytes.fill(0); bytes = new Uint8Array(validated.bytes);
        current(signal);
        file = { name: validated.safeName, mime: validated.mime, bytes };
        copy = await ports.createPrivateCopy(file); current(signal);
        const selection: DocumentSelection = { file, localPreviewUri: copy.uri };
        // Cleanup the fresh native picker cache copy before exposing our own copy.
        await ports.cleanupPickedAsset(asset);
        current(signal); selections.set(selection, copy); retained = true;
        return selection;
      } finally {
        if (!retained) {
          bytes?.fill(0);
          if (copy) await copy.release();
          if (asset) await ports.cleanupPickedAsset(asset);
        }
      }
    }),
    release,
    open: (original: DocumentOriginal, signal: AbortSignal) => exclusive(async () => {
      current(signal);
      const uri = validateOriginalForOpening(original, scope.userId, now());
      const onAbort = () => { void dismiss(); };
      signal.addEventListener('abort', onAbort, { once: true });
      browserOpen = true;
      try {
        // There is deliberately no warm-up, URL logging, persistence or browser redirect.
        current(signal);
        const result = await ports.openSystemDocument(uri);
        if (signal.aborted || disposed || !input.isCurrent(scope)) await dismiss();
        current(signal);
        if (result === 'locked') throw unavailable();
        // Android 'opened' proves handoff only, never that a PDF was rendered/read.
      } finally { signal.removeEventListener('abort', onAbort); browserOpen = false; }
    }),
    dispose: async () => {
      // This happens before the first await, so a pending picker cannot return into the next account.
      disposed = true; await dismiss();
      // Native pickers cannot always be dismissed programmatically. Keep this disposal
      // pending until their late result and its cleanup have settled. The runtime then
      // retains the adapter if the final purge fails, instead of losing its ownership map.
      // Dismiss the browser first: awaiting its presentation before dismissing would deadlock.
      await Promise.all([...presentations]);
      const outcomes = await Promise.allSettled([...selections.keys()].map(release));
      let cleanupFailed = outcomes.some(result => result.status === 'rejected');
      try { await ports.cleanup(); } catch { cleanupFailed = true; }
      if (cleanupFailed) throw new DocumentMediaError('UNAVAILABLE', 'Le nettoyage des documents temporaires doit être repris.');
    },
  };
}
