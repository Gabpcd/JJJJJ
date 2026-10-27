import type { CaregiverDocument, PendingDocumentUpload } from './types';

export const proofClass = (type: string) => ['CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR'].includes(type) ? 'IDENTITE_OFFICIELLE' : type;
export const currentProofIds = (documents: CaregiverDocument[], type: string) => documents
  .filter(row => !row.supprime_le && !row.revoque_le && proofClass(row.type_document) === proofClass(type)).map(row => row.id).sort();
export const sameProofIds = (documents: CaregiverDocument[], receipt: PendingDocumentUpload) => !!receipt.registration
  && JSON.stringify(currentProofIds(documents, receipt.storageKey.split('/')[2]!)) === JSON.stringify(receipt.registration.previousIds);

/** Snapshot and whitelist durable recovery data; no bytes, URL, token or provider payload. */
export function checkedUploadReceipt(userId: string, input: PendingDocumentUpload, demo = false): PendingDocumentUpload {
  const invalid = () => { throw new Error('Le suivi du dernier envoi ne peut pas être vérifié. Aucun nouvel envoi ne sera lancé.'); };
  const path = input?.storageKey;
  if (typeof path !== 'string' || path.length > 512 || Object.keys(input).some(key => !['storageKey', 'registration'].includes(key))) return invalid();
  const parts = path.split('/');
  if (parts.length !== 4 || parts[0] !== userId || parts[1] !== 'documents' || path.includes('..')
    || !/^[A-Z][A-Z0-9_]{1,79}$/.test(parts[2] ?? '') || !/^[A-Za-z0-9._-]+$/.test(parts[3] ?? '')) return invalid();
  const r = input.registration;
  if (!Object.hasOwn(input, 'registration')) return { storageKey: path };
  if (!r || typeof r !== 'object') return invalid();
  const id = demo ? /^demo-[A-Za-z0-9_-]+$/ : /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!['prepared', 'started', 'refused'].includes(r.phase)
    || Object.keys(r).some(key => !['phase', 'name', 'mime', 'size', 'label', 'previousIds'].includes(key))
    || typeof r.name !== 'string' || !r.name.trim() || r.name.length > 255
    || !['application/pdf', 'image/jpeg', 'image/png', 'image/webp'].includes(r.mime)
    || !Number.isInteger(r.size) || r.size < 1 || r.size > 10485760 || typeof r.label !== 'string' || r.label.length > 500
    || !Array.isArray(r.previousIds) || r.previousIds.length > 8 || r.previousIds.some(value => typeof value !== 'string' || !id.test(value))
    || new Set(r.previousIds).size !== r.previousIds.length) return invalid();
  return { storageKey: path, registration: { phase: r.phase, name: r.name, mime: r.mime, size: r.size,
    label: r.label, previousIds: [...r.previousIds].sort() } };
}

/** Same-key writes cannot downgrade the durable pre-RPC barrier or alter its arguments. */
export function mergeUploadReceipt(previous: PendingDocumentUpload | null, next: PendingDocumentUpload): PendingDocumentUpload {
  if (!previous) return next;
  if (previous.storageKey !== next.storageKey) throw new Error('Un autre envoi reste à vérifier.');
  if (!next.registration) return previous;
  if (!previous.registration) throw new Error('Le reçu ancien ne permet pas de reconstruire l’enregistrement.');
  const { phase: before, ...oldMetadata } = previous.registration;
  const { phase: after, ...newMetadata } = next.registration;
  const order = { prepared: 0, started: 1, refused: 2 };
  if (order[after] < order[before] || JSON.stringify(oldMetadata) !== JSON.stringify(newMetadata)) throw new Error('Le suivi de cet envoi a changé.');
  return next;
}
