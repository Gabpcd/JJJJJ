import type { DocumentUploadJournal, PendingDocumentUpload } from '../../ui/documents/adapters';
import { checkedUploadReceipt, mergeUploadReceipt } from './uploadRecovery';

export const DEMO_DOCUMENT_USER_IDS = ['demo-soignant', 'demo-inscription'] as const;
export function assertDemoDocumentUser(userId: string): void {
  if (!(DEMO_DOCUMENT_USER_IDS as readonly string[]).includes(userId)) throw new Error('Ce compte ne fait pas partie de la démonstration documentaire.');
}
function checked(userId: string, receipt: PendingDocumentUpload): PendingDocumentUpload {
  assertDemoDocumentUser(userId);
  const path = receipt?.storageKey;
  if (typeof path !== 'string' || path.length > 512 || path.includes('..')) throw new Error('Reçu de démonstration invalide.');
  const parts = path.split('/');
  if (parts.length !== 4 || parts[0] !== userId || parts[1] !== 'documents'
    || !/^[A-Z][A-Z0-9_]{1,79}$/.test(parts[2] ?? '') || !/^demo-[A-Za-z0-9._-]+$/.test(parts[3] ?? '')) throw new Error('Reçu de démonstration invalide.');
  return checkedUploadReceipt(userId, receipt, true);
}

/** One explicit demo runtime instance. In-memory only; retained across screens and demo logout. */
export function createDemoDocumentUploadJournal(): DocumentUploadJournal {
  const receipts = new Map<string, PendingDocumentUpload>();
  const queues = new Map<string, Promise<unknown>>();
  const serial = <T>(userId: string, action: () => T): Promise<T> => {
    assertDemoDocumentUser(userId);
    const next = (queues.get(userId) ?? Promise.resolve()).catch(() => undefined).then(action);
    queues.set(userId, next);
    void next.finally(() => { if (queues.get(userId) === next) queues.delete(userId); }).catch(() => undefined);
    return next;
  };
  return {
    read(userId) { return serial(userId, () => receipts.has(userId) ? checked(userId, receipts.get(userId)!) : null); },
    write(userId, value) {
      const receipt = checked(userId, value);
      return serial(userId, () => {
        const previous = receipts.get(userId);
        receipts.set(userId, mergeUploadReceipt(previous ?? null, receipt));
      });
    },
    clear(userId, storageKey) {
      const expected = checked(userId, { storageKey });
      return serial(userId, () => {
        const previous = receipts.get(userId);
        if (!previous) return;
        if (previous.storageKey !== expected.storageKey) throw new Error('Le reçu d’un autre envoi fictif est conservé.');
        receipts.delete(userId);
      });
    },
  };
}
