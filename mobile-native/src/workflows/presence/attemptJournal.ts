import { PRESENCE_ID, isPresencePreExecutionRefusal } from './business';
import { isDefiniteTransactionRollback } from '../rpcOutcome';
import { PresenceWorkflowError, type PresenceAttemptJournal, type PresenceAttemptReceipt } from './types';

/** Supply raw Expo SecureStore with WHEN_UNLOCKED_THIS_DEVICE_ONLY; never auth's prefixed/chunked adapter. */
export interface PresenceSecureStorePort {
  getItemAsync(key: string): Promise<string | null>;
  setItemAsync(key: string, value: string): Promise<void>;
  deleteItemAsync(key: string): Promise<void>;
}
// Keep the original key so a v1 receipt cannot disappear during the v2 upgrade.
const PREFIX = 'jolene.native.presence.attempt.v1.';
const queues = new Map<string, Promise<void>>();
const MAX_BYTES = 64_000;
function failure(): never {
  throw new PresenceWorkflowError('JOURNAL_UNAVAILABLE', 'Le suivi sécurisé du pointage ne peut pas être vérifié. Aucun nouveau scan ne peut être envoyé.');
}
function keyFor(userId: string): string { if (!PRESENCE_ID.test(userId)) failure(); return `${PREFIX}${userId}`; }
function serialized<T>(key: string, operation: () => Promise<T>): Promise<T> {
  const prior = queues.get(key) ?? Promise.resolve();
  const next = prior.catch(() => undefined).then(operation);
  const tail = next.then(() => undefined, () => undefined); queues.set(key, tail);
  void tail.then(() => { if (queues.get(key) === tail) queues.delete(key); });
  return next;
}
function checked(raw: unknown, userId: string): PresenceAttemptReceipt {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) failure();
  const row = raw as Omit<PresenceAttemptReceipt, 'version' | 'phase'> & { version: number; phase?: unknown };
  const keys = ['version', 'userId', 'attemptId', 'sessionEpoch', 'terminalId', 'enteredCode', 'baselineProofIds', 'gps', 'rejectionCode'];
  if (row.version === 2) keys.push('phase');
  if (Object.keys(row).length !== keys.length || Object.keys(row).some(key => !keys.includes(key))
    || ![1, 2].includes(row.version) || row.version === 2 && (typeof row.phase !== 'string' || !['prepared', 'started', 'not_sent'].includes(row.phase))
    || row.userId !== userId || !PRESENCE_ID.test(row.attemptId)
    || !Number.isSafeInteger(row.sessionEpoch) || row.sessionEpoch < 0
    || typeof row.terminalId !== 'string' || !/^[A-Za-z0-9._:-]{1,160}$/.test(row.terminalId)
    || typeof row.enteredCode !== 'string' || !/^\d{6}$/.test(row.enteredCode)
    || !Array.isArray(row.baselineProofIds) || row.baselineProofIds.length > 1_000
    || row.baselineProofIds.some(id => typeof id !== 'string' || !PRESENCE_ID.test(id))
    || new Set(row.baselineProofIds).size !== row.baselineProofIds.length
    || !['available', 'denied', 'unavailable', 'not_requested'].includes(row.gps)
    || row.rejectionCode !== null && (!['P0002', '42501', '23514'].includes(row.rejectionCode) && !isPresencePreExecutionRefusal(row.rejectionCode)
      && !isDefiniteTransactionRollback(row.rejectionCode)
      || row.version === 2 && row.phase !== 'started')) failure();
  // A legacy receipt has no evidence that its RPC was not invoked. Never infer prepared.
  const phase = row.version === 1 ? 'started' : row.phase as PresenceAttemptReceipt['phase'];
  return { version: 2, phase, userId, attemptId: row.attemptId, sessionEpoch: row.sessionEpoch, terminalId: row.terminalId,
    enteredCode: row.enteredCode, baselineProofIds: [...row.baselineProofIds].sort(), gps: row.gps, rejectionCode: row.rejectionCode };
}
function immutable(receipt: PresenceAttemptReceipt): string { return JSON.stringify({ ...receipt, phase: null, rejectionCode: null }); }

/** One versioned slot per authenticated user. Corruption or storage errors fail closed. */
export function createPresenceAttemptJournal(storage: PresenceSecureStorePort): PresenceAttemptJournal {
  async function read(key: string, userId: string): Promise<PresenceAttemptReceipt | null> {
    let raw: string | null;
    try { raw = await storage.getItemAsync(key); } catch { failure(); }
    if (raw === null) return null;
    if (typeof raw !== 'string' || raw.length > MAX_BYTES) failure();
    try { return checked(JSON.parse(raw), userId); } catch { failure(); }
  }
  return {
    read(userId) { const key = keyFor(userId); return serialized(key, () => read(key, userId)); },
    write(userId, value) {
      const key = keyFor(userId); if (value.version !== 2) failure(); const receipt = checked(value, userId);
      return serialized(key, async () => {
        const previous = await read(key, userId);
        if (!previous && receipt.phase !== 'prepared'
          || previous && (immutable(previous) !== immutable(receipt)
            || previous.phase === 'started' && receipt.phase === 'prepared'
            || previous.phase === 'not_sent' && receipt.phase !== 'not_sent'
            || previous.rejectionCode !== null && (receipt.rejectionCode !== previous.rejectionCode || receipt.phase !== 'started'))) {
          throw new PresenceWorkflowError('RECONCILIATION_REQUIRED', 'Un autre pointage doit être réconcilié avant de continuer.');
        }
        const encoded = JSON.stringify(receipt); if (encoded.length > MAX_BYTES) failure();
        try { await storage.setItemAsync(key, encoded); } catch { failure(); }
        const after = await read(key, userId); if (!after || JSON.stringify(after) !== encoded) failure();
      });
    },
    clear(userId, expectedAttemptId, expectedPhase) {
      const key = keyFor(userId); if (!PRESENCE_ID.test(expectedAttemptId)) failure();
      return serialized(key, async () => {
        const previous = await read(key, userId); if (!previous) return;
        if (previous.attemptId !== expectedAttemptId || expectedPhase !== undefined && previous.phase !== expectedPhase) {
          throw new PresenceWorkflowError('RECONCILIATION_REQUIRED', 'Le reçu courant appartient à une autre tentative.');
        }
        try { await storage.deleteItemAsync(key); } catch { failure(); }
        if (await read(key, userId)) failure();
      });
    },
  };
}
