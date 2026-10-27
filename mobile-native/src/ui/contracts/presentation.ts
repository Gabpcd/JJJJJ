import type { ContractContext, ContractDetails, ContractRecord, ContractRevision } from '../../workflows/contracts/types';

export const contractContextKey = (context: ContractContext, epoch: number) => JSON.stringify([
  context.kind, context.userId, context.kind === 'etablissement' ? context.etablissementId : null, epoch,
]);
export const revisionKey = (revision: ContractRevision | null) => revision
  ? JSON.stringify([revision.contractId, revision.sha256, revision.storagePath]) : null;
export function detailMatches(context: ContractContext, contractId: string, detail: ContractDetails) {
  return detail.userId === context.userId && detail.party === context.kind && detail.record.id === contractId
    && (context.kind === 'soignant' ? detail.record.soignant_id === context.userId : detail.record.etablissement_id === context.etablissementId);
}
const statuses: Record<string, string> = {
  BROUILLON: 'En préparation', EN_ATTENTE_SIGNATURES: 'Signatures attendues', SIGNE_ETABLISSEMENT: 'Signé par l’établissement',
  SIGNE_SOIGNANT: 'Signé par le soignant', SIGNE_COMPLET: 'Signé par les deux parties', ANNULE: 'Annulé', EXPIRE: 'Expiré', REFUSE: 'Refusé',
};
export const contractStatus = (status: string | null) => status ? statuses[status] ?? `Statut à vérifier : ${status}` : 'Statut à actualiser';
const types: Record<string, string> = { CDD: 'CDD', CDDU: 'CDDU', VACATION: 'Vacation', LIBERAL: 'Exercice libéral', REMPLACEMENT_LIBERAL: 'Remplacement libéral' };
export const contractType = (type: string) => types[type] ?? type;
export const contractDate = (value: string | null) => value && Number.isFinite(Date.parse(value))
  ? new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Paris' }).format(new Date(value)) : null;
export function partyStatus(record: ContractRecord, party: 'soignant' | 'etablissement') {
  const flag = party === 'soignant' ? record.signature_soignant : record.signature_etablissement;
  const at = party === 'soignant' ? record.signature_soignant_le : record.signature_etablissement_le;
  const signed = flag === true || !!at || record.statut === 'SIGNE_COMPLET'
    || record.statut === (party === 'soignant' ? 'SIGNE_SOIGNANT' : 'SIGNE_ETABLISSEMENT');
  return signed ? `Signé${contractDate(at) ? ` le ${contractDate(at)}` : ''}` : 'Signature non enregistrée';
}
export const originalMessage = (issue: ContractDetails['originalIssue']) => issue === 'unprepared'
  ? 'L’original du contrat n’est pas encore disponible.' : issue === 'incomplete'
    ? 'L’original du contrat est incomplet. Il ne peut pas être signé ici.'
    : issue === 'hash_mismatch' || issue === 'signature_mismatch'
      ? 'L’intégrité de l’original ne peut pas être confirmée. La signature est indisponible.'
      : 'L’original du contrat ne peut pas être consulté actuellement.';
