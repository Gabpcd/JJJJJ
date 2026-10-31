import { parsePresenceCode } from '../../workflows/presence/business';
import type { PresenceQrPort } from '../../workflows/presence/types';
import type { CameraPermissionPort, ManagedPresenceQr, PresenceSensorGuard, QrViewState } from './types';

type Capture = Awaited<ReturnType<PresenceQrPort['scan']>>;
export function createPresenceQrController(guard: PresenceSensorGuard, permissions: CameraPermissionPort): ManagedPresenceQr {
  let disposed = false; let sequence = 0; let state: QrViewState = { phase: 'closed', requestId: 0 };
  const listeners = new Set<() => void>();
  let pending: { id: number; finish(result: Capture): void } | null = null;
  const current = () => !disposed && guard.isCurrent(guard.scope);
  const publish = (next: QrViewState) => { state = next; for (const listener of listeners) listener(); };
  const api: ManagedPresenceQr = {
    snapshot: () => state,
    subscribe: listener => { listeners.add(listener); return () => { listeners.delete(listener); }; },
    scan(signal) {
      if (!current() || !guard.isForeground() || signal?.aborted) return Promise.resolve({ kind: 'cancelled' });
      if (pending) return Promise.resolve({ kind: 'unavailable' });
      const id = ++sequence;
      return new Promise<Capture>(resolve => {
        let done = false;
        const finish = (result: Capture) => {
          if (done) return; done = true; clearTimeout(timer); signal?.removeEventListener('abort', onAbort);
          if (pending?.id === id) { pending = null; publish({ phase: 'closed', requestId: id }); }
          resolve(current() ? result : { kind: 'cancelled' });
        };
        const onAbort = () => finish({ kind: 'cancelled' });
        const timer = setTimeout(() => finish({ kind: 'unavailable' }), 90_000);
        pending = { id, finish }; signal?.addEventListener('abort', onAbort, { once: true });
        publish({ phase: 'permission', requestId: id });
        void (async () => {
          try {
            let permission = await permissions.read();
            if (pending?.id !== id || !current()) return finish({ kind: 'cancelled' });
            if (!permission.granted && permission.canAskAgain) permission = await permissions.request();
            if (pending?.id !== id || !current()) return finish({ kind: 'cancelled' });
            if (!permission.granted) return finish({ kind: 'denied' });
            publish({ phase: 'scanning', requestId: id });
          } catch { finish({ kind: 'unavailable' }); }
        })();
      });
    },
    barcode(requestId, type, data) {
      if (!current() || !guard.isForeground() || state.phase !== 'scanning' || pending?.id !== requestId || type !== 'qr') return;
      // Invalid data is reduced to an empty sentinel; never retain a scanned URL or unrelated content.
      let code = ''; try { code = parsePresenceCode(data); } catch { /* canonical captureCode reports invalid */ }
      pending.finish({ kind: 'code', text: code });
    },
    unavailable(requestId) { if (pending?.id === requestId) pending.finish({ kind: 'unavailable' }); },
    cancel() { pending?.finish({ kind: 'cancelled' }); },
    dispose() { if (disposed) return; disposed = true; pending?.finish({ kind: 'cancelled' }); listeners.clear(); },
  };
  return api;
}
