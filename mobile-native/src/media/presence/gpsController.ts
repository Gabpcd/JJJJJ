import { validGps } from '../../workflows/presence/business';
import type { GpsObservation } from '../../workflows/presence/types';
import type { GpsChoice, LocationNativePort, ManagedPresenceGps, PositionSample, PositionSubscription, PresenceSensorGuard } from './types';

/** Coordinates are acquired only for one armed submission, and are never cached or persisted here. */
export function createPresenceGpsController(guard: PresenceSensorGuard, native: LocationNativePort,
  options: { now?: () => number; positionTimeoutMs?: number; permissionTimeoutMs?: number } = {}): ManagedPresenceGps {
  const now = options.now ?? Date.now;
  const timeoutMs = options.positionTimeoutMs ?? 12_000;
  const permissionTimeoutMs = options.permissionTimeoutMs ?? 60_000;
  if (!Number.isFinite(timeoutMs) || timeoutMs < 1 || timeoutMs > 30_000) throw new Error('Invalid position timeout');
  if (!Number.isFinite(permissionTimeoutMs) || permissionTimeoutMs < 1 || permissionTimeoutMs > 60_000) throw new Error('Invalid permission timeout');
  let disposed = false; let generation = 0; let choice: GpsChoice = 'off'; let armSequence = 0; let activeArm: number | null = null; let locating = false;
  let stop: (() => void) | null = null;
  let stopPermission: (() => void) | null = null;
  let stopLocate: (() => void) | null = null;
  const listeners = new Set<() => void>();
  const current = () => !disposed && guard.isCurrent(guard.scope);
  const usable = () => current() && guard.isForeground();
  const publish = (value: GpsChoice) => { choice = value; for (const listener of listeners) listener(); };
  function observe(signal?: AbortSignal): Promise<GpsObservation> {
    const epoch = generation;
    return new Promise(resolve => {
      let settled = false; let subscription: PositionSubscription | null = null;
      const finish = (value: GpsObservation) => {
        if (settled) return; settled = true; clearTimeout(timer); signal?.removeEventListener('abort', cancel);
        try { subscription?.remove(); } catch { /* no background task is requested */ }
        if (stop === cancel) stop = null;
        resolve(usable() && epoch === generation && !signal?.aborted ? value : { kind: 'unavailable' });
      };
      const cancel = () => finish({ kind: 'unavailable' });
      const timer = setTimeout(cancel, timeoutMs); stop = cancel;
      signal?.addEventListener('abort', cancel, { once: true });
      const receive = (sample: PositionSample) => {
        if (settled) return;
        const age = now() - sample.timestamp;
        const value: GpsObservation = { kind: 'available', latitude: sample.coords?.latitude,
          longitude: sample.coords?.longitude, accuracyMeters: sample.coords?.accuracy as number };
        if (sample.mocked === true || !Number.isFinite(age) || age < -5_000 || age > 30_000 || !validGps(value)
          || typeof sample.coords?.accuracy !== 'number') return finish({ kind: 'unavailable' });
        finish(value);
      };
      if (!usable() || signal?.aborted) return cancel();
      void Promise.resolve().then(() => {
        if (settled || !usable() || epoch !== generation || signal?.aborted) { cancel(); return null; }
        return native.watch(receive, cancel);
      }).then(value => {
        if (!value) return;
        if (settled || !usable() || epoch !== generation || signal?.aborted) { try { value.remove(); } catch { /* listener already inactive */ } }
        else subscription = value;
      }, cancel);
    });
  }
  const api: ManagedPresenceGps = {
    snapshot: () => choice,
    subscribe: listener => { listeners.add(listener); return () => { listeners.delete(listener); }; },
    async choose(include, signal) {
      if (activeArm !== null) return choice;
      const epoch = ++generation; stop?.(); stopPermission?.();
      if (!include) { publish('off'); return 'off'; }
      if (!usable() || signal?.aborted) { publish('off'); return 'off'; }
      publish('permission');
      let permissionFinished = false;
      let timer: ReturnType<typeof setTimeout> | undefined;
      let onAbort: (() => void) | undefined;
      try {
        const permission = await Promise.race([
          (async () => { let result = await native.readPermission();
            if (permissionFinished || epoch !== generation || !current() || signal?.aborted) return null;
            if (!result.granted && result.canAskAgain) result = await native.requestPermission(); return result; })(),
          new Promise<null>(resolve => { onAbort = () => { permissionFinished = true; resolve(null); };
            timer = setTimeout(onAbort, permissionTimeoutMs);
            stopPermission = onAbort; signal?.addEventListener('abort', onAbort, { once: true }); }),
        ]);
        if (epoch !== generation || !current() || signal?.aborted) return 'off';
        const next = permission === null ? 'unavailable' : permission.granted ? 'ready' : 'denied'; publish(next); return next;
      } catch { if (epoch === generation && current()) publish('unavailable'); return 'unavailable'; }
      finally { permissionFinished = true; if (timer) clearTimeout(timer); if (onAbort) signal?.removeEventListener('abort', onAbort);
        if (stopPermission === onAbort) stopPermission = null; }
    },
    arm() {
      if (activeArm !== null || !usable()) throw new Error('Pointage capteurs indisponible');
      const lease = ++armSequence; activeArm = lease;
      let released = false;
      return () => { if (released) return; released = true; if (activeArm !== lease) return;
        activeArm = null; ++generation; stop?.(); stopLocate?.(); publish('off'); };
    },
    async locate(signal) {
      if (activeArm === null || choice === 'off' || choice === 'permission') return { kind: 'not_requested' };
      if (choice === 'denied') return { kind: 'denied' };
      if (choice !== 'ready' || !usable() || signal?.aborted || locating) return { kind: 'unavailable' };
      const epoch = generation; locating = true; let expired = false;
      let timer: ReturnType<typeof setTimeout> | undefined; let onAbort: (() => void) | undefined;
      try {
        return await Promise.race<GpsObservation>([
          (async (): Promise<GpsObservation> => {
            const permission = await native.readPermission();
            if (expired || !usable() || signal?.aborted || epoch !== generation) return { kind: 'unavailable' };
            if (!permission.granted) return { kind: 'denied' };
            const enabled = await native.servicesEnabled();
            if (expired || !enabled || !usable() || signal?.aborted || epoch !== generation) return { kind: 'unavailable' };
            return observe(signal);
          })(),
          new Promise<GpsObservation>(resolve => { onAbort = () => { expired = true; stop?.(); resolve({ kind: 'unavailable' }); };
            stopLocate = onAbort; timer = setTimeout(onAbort, timeoutMs); signal?.addEventListener('abort', onAbort, { once: true }); }),
        ]);
      } catch { return { kind: 'unavailable' }; }
      finally { expired = true; locating = false; if (timer) clearTimeout(timer);
        if (onAbort) signal?.removeEventListener('abort', onAbort); if (stopLocate === onAbort) stopLocate = null; }
    },
    cancel() { ++generation; activeArm = null; stop?.(); stopLocate?.(); stopPermission?.(); publish('off'); },
    dispose() { if (disposed) return; disposed = true; ++generation; activeArm = null; stop?.(); stopLocate?.(); stopPermission?.(); listeners.clear(); },
  };
  return api;
}
