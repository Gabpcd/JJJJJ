import type { DocumentMediaScope, ManagedDocumentMediaAdapter } from '../media/documents/types';
import type { DocumentScreenGateway, DocumentUploadJournal } from '../ui/documents/adapters';

export interface NativeDocumentRuntime {
  readonly gateway: DocumentScreenGateway;
  readonly uploadJournal: DocumentUploadJournal;
  prepareSession(scope: DocumentMediaScope): Promise<ManagedDocumentMediaAdapter>;
  /** Called on every controller change, before a late native result can reach another account. */
  invalidateSession(): Promise<void>;
  /** Does not clear the durable upload journal. Failed cleanup remains retryable. */
  releaseSession(): Promise<void>;
}

const interrupted = () => Object.assign(new Error('La session documentaire a changé.'), { name: 'AbortError' });

/** One gateway/journal per runtime, one media instance per authenticated user and epoch. */
export function createDocumentRuntime(input: {
  gateway: DocumentScreenGateway;
  uploadJournal: DocumentUploadJournal;
  currentSession: () => DocumentMediaScope | null;
  createMedia: (scope: DocumentMediaScope, isCurrent: (scope: DocumentMediaScope) => boolean) => ManagedDocumentMediaAdapter;
}): NativeDocumentRuntime {
  type Active = { scope: DocumentMediaScope; media: ManagedDocumentMediaAdapter; preparation?: Promise<void> };
  let active: Active | null = null;
  // null denotes a failed cleanup that must be retried, never a successful purge.
  const cleanup = new Map<ManagedDocumentMediaAdapter, Promise<void> | null>();
  const isCurrent = (scope: DocumentMediaScope) => {
    const current = input.currentSession();
    return current?.userId === scope.userId && current.epoch === scope.epoch;
  };
  const clean = (media: ManagedDocumentMediaAdapter): Promise<void> => {
    const running = cleanup.get(media);
    if (running) return running;
    // dispose invalidates the adapter synchronously, before its first native await.
    const task = media.dispose().then(() => { cleanup.delete(media); }, () => {
      cleanup.set(media, null);
      throw new Error('Le nettoyage des copies temporaires doit être repris avant de continuer.');
    });
    cleanup.set(media, task);
    return task;
  };
  const retire = (): Promise<void> => {
    const previous = active;
    active = null;
    return previous ? clean(previous.media) : Promise.resolve();
  };
  return {
    gateway: input.gateway, uploadJournal: input.uploadJournal,
    async prepareSession(scope) {
      if (!isCurrent(scope)) throw interrupted();
      if (active && (active.scope.userId !== scope.userId || active.scope.epoch !== scope.epoch)) await retire();
      if (!isCurrent(scope)) throw interrupted();
      if (!active) active = { scope: { ...scope }, media: input.createMedia({ ...scope }, isCurrent) };
      const owner = active;
      if (!owner.preparation) {
        const preparation = (async () => {
          await Promise.all([...cleanup.keys()].map(clean));
          if (active !== owner || !isCurrent(scope)) throw interrupted();
          await owner.media.prepare();
          if (active !== owner || !isCurrent(scope)) throw interrupted();
        })();
        owner.preparation = preparation;
        void preparation.catch(() => { if (owner.preparation === preparation) owner.preparation = undefined; });
      }
      await owner.preparation;
      if (active !== owner || !isCurrent(scope)) throw interrupted();
      return owner.media;
    },
    invalidateSession() { return active && !isCurrent(active.scope) ? retire() : Promise.resolve(); },
    releaseSession: retire,
  };
}
