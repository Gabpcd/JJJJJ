import type { NativeAccountContext } from '../account/types';
import type { PresenceContext } from '../workflows/presence/types';
import type { PresenceScreenGateway } from '../ui/presence/types';
import type { ManagedPresenceSensors, PresenceSensorScope } from '../media/presence/types';

export function nativePresenceContext(account: NativeAccountContext | null, epoch: number): PresenceContext | null {
  if (!Number.isSafeInteger(epoch) || epoch < 0) return null;
  return account?.kind === 'soignant' ? { kind: 'soignant', userId: account.userId, epoch }
    : account?.kind === 'etablissement' ? { kind: 'etablissement', userId: account.userId, epoch, etablissementId: account.etablissementId } : null;
}
export function presenceScenario(mode: 'demo' | 'staging', raw: string | undefined): boolean {
  const flag = raw?.trim() ?? '';
  if (!['', '0', '1'].includes(flag) || flag === '1' && mode !== 'demo')
    throw new Error('Le scénario de pointage fictif est réservé au mode Démonstration et doit être activé avec 1.');
  return flag === '1';
}
function key(context: PresenceContext): string {
  return JSON.stringify([context.kind, context.userId, context.epoch, context.kind === 'etablissement' ? context.etablissementId : null]);
}
const interrupted = () => Object.assign(new Error('Votre session de pointage a changé.'), { name: 'AbortError' });
export interface NativePresenceSession {
  readonly context: PresenceContext;
  readonly gateway: PresenceScreenGateway;
  readonly sensors?: ManagedPresenceSensors;
  /** Read from the existing account record; never grants or persists consent. */
  readGpsConsent(signal?: AbortSignal): Promise<boolean>;
}
export interface NativePresenceRuntime {
  session(context: PresenceContext): NativePresenceSession;
  invalidateSession(): void;
  cancelSensors(): void;
  /** Only sensors are disposed. A durable unresolved scan is never erased here. */
  releaseSession(): void;
}

/** One active bundle per verified account/epoch, with exactly the same sensors for gateway and screen. */
export function createPresenceRuntime(input: {
  currentSession: () => PresenceContext | null;
  createSession(context: PresenceContext, isCurrent: (scope: PresenceSensorScope) => boolean): Omit<NativePresenceSession, 'context'>;
}): NativePresenceRuntime {
  let active: NativePresenceSession | null = null; let generation = 0;
  const isContextCurrent = (context: PresenceContext) => {
    const current = input.currentSession();
    return !!current && key(current) === key(context);
  };
  const release = () => {
    const previous = active; active = null; ++generation;
    previous?.sensors?.dispose();
  };
  return {
    session(context) {
      if (!isContextCurrent(context)) throw interrupted();
      if (active && key(active.context) !== key(context)) release();
      if (!active) {
        const ownedContext = Object.freeze({ ...context }); const ownedGeneration = generation;
        const isCurrent = (scope: PresenceSensorScope) => scope.userId === ownedContext.userId
          && scope.epoch === ownedContext.epoch && ownedGeneration === generation && isContextCurrent(ownedContext);
        const bundle = input.createSession(ownedContext, isCurrent);
        if (!isContextCurrent(ownedContext)) { bundle.sensors?.dispose(); throw interrupted(); }
        active = { ...bundle, context: ownedContext, async readGpsConsent(signal) {
          if (ownedGeneration !== generation || !isContextCurrent(ownedContext) || signal?.aborted) throw interrupted();
          const consent = await bundle.readGpsConsent(signal);
          if (ownedGeneration !== generation || !isContextCurrent(ownedContext) || signal?.aborted) throw interrupted();
          return consent === true;
        } };
      }
      return active;
    },
    invalidateSession() { if (active && !isContextCurrent(active.context)) release(); },
    cancelSensors() { active?.sensors?.cancel(); },
    releaseSession: release,
  };
}
