import type { NativeAccountContext } from '../account/types';
import { accountErrorMessage, NativeAccountError } from '../account/errors';

export type SessionStatus = 'loading' | 'signedOut' | 'signingIn' | 'authenticated' | 'unsupported' | 'error';
export interface SessionSnapshot {
  status: SessionStatus;
  mode: 'demo' | 'staging';
  context: NativeAccountContext | null;
  error: string | null;
  /** Changes only at an identity boundary; use as the navigation/cache key. */
  epoch: number;
}
export interface AuthSession { user: { id: string }; access_token: string }
export interface AuthPort {
  getSession(): Promise<AuthSession | null>;
  subscribe(listener: (session: AuthSession | null) => void): () => void;
  signIn(email: string, password: string): Promise<AuthSession>;
  signOut(): Promise<void>;
  clearStorage(): Promise<void>;
  setForeground?(foreground: boolean): void;
}
export class UnsupportedNativeAccount extends Error {}
type ControllerOptions = { mode: 'demo'; context: NativeAccountContext } | {
  mode: 'staging'; auth: AuthPort;
  resolveContext: (session: AuthSession, signal: AbortSignal) => Promise<NativeAccountContext>;
};

export function createNativeSessionController(options: ControllerOptions) {
  let snapshot: SessionSnapshot = { status: options.mode === 'demo' ? 'signedOut' : 'loading', mode: options.mode, context: null, error: null, epoch: 0 };
  let active = false;
  let lifecycle = 0;
  let revision = 0;
  let authEventRevision = 0;
  let operationRevision = 0;
  let suppressEvents = false;
  let wantSignedOut = false;
  let foreground = true;
  let unsubscribe: (() => void) | undefined;
  let resolver: AbortController | undefined;
  let queue = Promise.resolve();
  const listeners = new Set<() => void>();
  const emit = (patch: Partial<SessionSnapshot>) => {
    snapshot = { ...snapshot, ...patch };
    listeners.forEach((listener) => listener());
  };
  const clearIdentity = (status: SessionStatus, error: string | null = null) => {
    resolver?.abort();
    revision += 1;
    emit({ status, error, context: null, epoch: snapshot.epoch + 1 });
  };
  const enqueue = (action: () => Promise<void>) => {
    queue = queue.catch(() => undefined).then(action);
    return queue;
  };
  async function accept(session: AuthSession | null, force = false) {
    if (!active || wantSignedOut) return;
    if (!session) { clearIdentity('signedOut'); return; }
    if (!force && snapshot.status === 'authenticated' && snapshot.context?.userId === session.user.id) return;
    if (options.mode !== 'staging') return;
    resolver?.abort();
    const abort = new AbortController();
    resolver = abort;
    const current = ++revision;
    const sameIdentity = snapshot.context?.userId === session.user.id;
    if (!sameIdentity) emit({ status: 'loading', context: null, error: null, epoch: snapshot.epoch + 1 });
    let timeout: ReturnType<typeof setTimeout> | undefined;
    try {
      const context = await Promise.race([
        options.resolveContext(session, abort.signal),
        new Promise<never>((_, reject) => {
          timeout = setTimeout(() => { abort.abort(); reject(new Error('timeout')); }, 15_000);
        }),
      ]);
      if (!active || current !== revision || wantSignedOut) return;
      if (context.userId !== session.user.id) throw new Error('identity mismatch');
      emit({ status: 'authenticated', context, error: null });
    } catch (error) {
      if (!active || current !== revision || wantSignedOut) return;
      clearIdentity(error instanceof UnsupportedNativeAccount ? 'unsupported' : 'error',
        error instanceof UnsupportedNativeAccount ? error.message : 'Impossible de vérifier votre accès TEST. Vérifiez votre connexion puis réessayez.');
    } finally { if (timeout) clearTimeout(timeout); }
  }
  const controller = {
    getSnapshot: () => snapshot,
    subscribe(listener: () => void) { listeners.add(listener); return () => { listeners.delete(listener); }; },
    start() {
      if (active) return;
      active = true;
      const startup = ++lifecycle;
      if (options.mode === 'demo') return;
      unsubscribe = options.auth.subscribe((session) => {
        const event = ++authEventRevision;
        if (!suppressEvents && !wantSignedOut && active && startup === lifecycle &&
          (!session || (snapshot.context && snapshot.context.userId !== session.user.id))) {
          clearIdentity(session ? 'loading' : 'signedOut');
        }
        // Supabase may hold its internal auth lock here. All async work runs later.
        setTimeout(() => {
          if (event !== authEventRevision || suppressEvents || !active || wantSignedOut || startup !== lifecycle) return;
          void accept(session);
        }, 0);
      });
      const initialEvent = authEventRevision;
      void options.auth.getSession().then((session) => {
        if (startup === lifecycle && initialEvent === authEventRevision && !suppressEvents) return accept(session);
      }).catch(() => {
        if (active && startup === lifecycle && initialEvent === authEventRevision && !suppressEvents && !wantSignedOut)
          clearIdentity('error', 'La session TEST n’a pas pu être restaurée. Vous pouvez vous reconnecter.');
      });
    },
    stop() {
      active = false;
      lifecycle += 1;
      operationRevision += 1;
      suppressEvents = false;
      revision += 1;
      resolver?.abort();
      unsubscribe?.();
      unsubscribe = undefined;
      if (options.mode === 'staging') options.auth.setForeground?.(false);
    },
    setForeground(value: boolean) {
      foreground = value;
      if (options.mode === 'staging') options.auth.setForeground?.(foreground && !wantSignedOut);
    },
    enterDemo(context?: NativeAccountContext) {
      if (options.mode !== 'demo') return;
      wantSignedOut = false;
      emit({ status: 'authenticated', context: context ?? options.context, error: null, epoch: snapshot.epoch + 1 });
    },
    updateDemoContext(context: NativeAccountContext) {
      if (options.mode !== 'demo' || snapshot.status !== 'authenticated' || snapshot.context?.userId !== context.userId || snapshot.context.kind !== context.kind) {
        throw new NativeAccountError('Le compte de démonstration a changé. Rouvrez le parcours.');
      }
      emit({ context });
    },
    signIn(email: string, password: string) {
      if (options.mode !== 'staging' || snapshot.status === 'signingIn' || snapshot.status === 'loading') return Promise.resolve();
      const current = ++operationRevision;
      wantSignedOut = false;
      suppressEvents = true;
      options.auth.setForeground?.(foreground);
      clearIdentity('signingIn');
      return enqueue(async () => {
        suppressEvents = true;
        try {
          const session = await options.auth.signIn(email.trim(), password);
          if (current !== operationRevision || wantSignedOut || !active) return;
          await accept(session, true);
        } catch (error) {
          if (active && current === operationRevision && !wantSignedOut)
            clearIdentity('error', accountErrorMessage(error));
        } finally { if (current === operationRevision) suppressEvents = false; }
      });
    },
    /** Account mutations share the auth queue: logout clears tokens written by a late signup/callback. */
    runAuthOperation<T>(action: (assertActive: () => void) => Promise<T>): Promise<T> {
      if (options.mode !== 'staging' || !active || suppressEvents || snapshot.status === 'loading' || snapshot.status === 'signingIn') {
        return Promise.reject(new NativeAccountError('Une opération de connexion est déjà en cours. Réessayez.'));
      }
      const current = ++operationRevision;
      const startup = lifecycle;
      wantSignedOut = false;
      suppressEvents = true;
      options.auth.setForeground?.(foreground);
      resolver?.abort();
      revision += 1;
      const assertActive = () => {
        if (!active || current !== operationRevision || startup !== lifecycle || wantSignedOut) {
          throw new NativeAccountError('Cette demande a été annulée. Reconnectez-vous pour continuer.', 'CANCELLED');
        }
      };
      let result!: T;
      return enqueue(async () => {
        try {
          assertActive();
          result = await action(assertActive);
          assertActive();
        } finally {
          if (active && current === operationRevision && startup === lifecycle && !wantSignedOut) {
            try { await accept(await options.auth.getSession(), true); }
            catch { clearIdentity('error', 'La session doit être vérifiée à nouveau. Réessayez.'); }
            finally { if (current === operationRevision) suppressEvents = false; }
          }
        }
      }).then(() => result);
    },
    signOut() {
      const current = ++operationRevision;
      wantSignedOut = true;
      suppressEvents = true;
      clearIdentity('signedOut');
      if (options.mode === 'demo') return Promise.resolve();
      options.auth.setForeground?.(false);
      // A sign-in already in flight must finish before clearing its persisted token.
      return enqueue(async () => {
        try {
          // Offline remote revocation must not block a new local login. The
          // secure tombstone, not the network response, decides local cleanup.
          await options.auth.signOut().catch(() => undefined);
          await options.auth.clearStorage();
        } catch {
          if (active && wantSignedOut) emit({ error: 'La session est fermée à l’écran, mais son effacement sécurisé n’a pas pu être confirmé. Réessayez la déconnexion avant de fermer ce pilote.' });
        } finally { if (current === operationRevision) suppressEvents = false; }
      });
    },
    async revalidate() {
      if (options.mode !== 'staging' || !active || suppressEvents || wantSignedOut) return;
      const event = authEventRevision;
      try {
        const session = await options.auth.getSession();
        if (event === authEventRevision && !suppressEvents) await accept(session, true);
      } catch {
        if (active && event === authEventRevision && !suppressEvents && !wantSignedOut)
          clearIdentity('error', 'La vérification de votre session TEST a échoué. Réessayez.');
      }
    },
  };
  return controller;
}
export type NativeSessionController = ReturnType<typeof createNativeSessionController>;
