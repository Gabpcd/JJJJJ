import { contientVariablesContratNonRendues } from '../../../../src/lib/contratMissionUi';
import { ContractWorkflowError, type ContractDetails, type ContractParty, type ContractRevision,
  type ContractServerIssue, type ContractSignature, type StoredContractRecord, type VerifiedContractOriginal } from './types';

export const CONTRACTS_STAGING_ORIGIN = 'https://mejpriaetwgtcstbgfid.supabase.co';
export const CONTRACT_ID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
export const CONTRACT_SHA256 = /^[0-9a-f]{64}$/;
export const MAX_CONTRACT_BYTES = 5 * 1024 * 1024;
export const SIGNABLE_STATUSES = ['BROUILLON', 'EN_ATTENTE_SIGNATURES', 'SIGNE_SOIGNANT', 'SIGNE_ETABLISSEMENT'] as const;

export function hasPartySignature(contract: StoredContractRecord, party: ContractParty): boolean {
  return party === 'soignant' ? contract.signature_soignant === true || !!contract.signature_soignant_le
    || contract.statut === 'SIGNE_SOIGNANT' || contract.statut === 'SIGNE_COMPLET'
    : contract.signature_etablissement === true || !!contract.signature_etablissement_le
      || contract.statut === 'SIGNE_ETABLISSEMENT' || contract.statut === 'SIGNE_COMPLET';
}
export function canOfferSignature(details: ContractDetails): boolean {
  return !!details.original && details.permissions.sign && details.isTestAccount
    && SIGNABLE_STATUSES.some(status => status === details.record.statut)
    && !hasPartySignature(details.record, details.party);
}
export function matchingRevision(original: VerifiedContractOriginal | null, revision: ContractRevision): boolean {
  return !!original && original.contractId === revision.contractId && original.sha256 === revision.sha256
    && original.storagePath === revision.storagePath;
}

/** Hash is injected: Expo Crypto in native runtime, node:crypto only in transport tests. */
export async function inspectOriginal(record: StoredContractRecord, signatures: ContractSignature[],
  digestUtf8: (html: string) => Promise<string>, storageBytes: Uint8Array): Promise<Pick<ContractDetails, 'original' | 'originalIssue'>> {
  if (!record.contenu_html || !record.storage_path || !record.hash_document || !record.contenu_html_rendu_le) {
    return { original: null, originalIssue: 'unprepared' };
  }
  if (!record.contenu_html.trim() || contientVariablesContratNonRendues(record.contenu_html)) {
    return { original: null, originalIssue: 'incomplete' };
  }
  const expected = exactUtf8(record.contenu_html);
  if (storageBytes.length !== expected.length || storageBytes.some((byte, index) => byte !== expected[index])) {
    return { original: null, originalIssue: 'hash_mismatch' };
  }
  if (!CONTRACT_SHA256.test(record.hash_document) || await digestUtf8(record.contenu_html) !== record.hash_document) {
    return { original: null, originalIssue: 'hash_mismatch' };
  }
  if (signatures.some(signature => (signature.statut_signature === 'signe' || !!signature.signe_a || !!signature.otp_valide_a)
    && signature.hash_document !== record.hash_document)) return { original: null, originalIssue: 'signature_mismatch' };
  return { original: Object.freeze({ contractId: record.id, html: record.contenu_html, sha256: record.hash_document,
    storagePath: record.storage_path, renderedAt: record.contenu_html_rendu_le, source: 'database-and-storage' as const }), originalIssue: null };
}
/** Portable UTF-8 encoding, without browser globals or replacement of malformed surrogates. */
export function exactUtf8(value: string): Uint8Array {
  if (value.length > MAX_CONTRACT_BYTES) throw new ContractWorkflowError('ORIGINAL_UNAVAILABLE', 'Le document dépasse la taille lisible par ce parcours.');
  let size = 0;
  for (let index = 0; index < value.length; index += 1) {
    let point = value.charCodeAt(index);
    if (point >= 0xd800 && point <= 0xdbff) {
      const low = value.charCodeAt(++index);
      if (!(low >= 0xdc00 && low <= 0xdfff)) throw new ContractWorkflowError('ORIGINAL_UNAVAILABLE', 'L’encodage de l’original est incohérent.');
      point = 0x10000 + ((point - 0xd800) << 10) + low - 0xdc00;
    } else if (point >= 0xdc00 && point <= 0xdfff) throw new ContractWorkflowError('ORIGINAL_UNAVAILABLE', 'L’encodage de l’original est incohérent.');
    size += point < 0x80 ? 1 : point < 0x800 ? 2 : point < 0x10000 ? 3 : 4;
    if (size > MAX_CONTRACT_BYTES) throw new ContractWorkflowError('ORIGINAL_UNAVAILABLE', 'Le document dépasse la taille lisible par ce parcours.');
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (let index = 0; index < value.length; index += 1) {
    const point = value.codePointAt(index)!; if (point > 0xffff) index += 1;
    if (point < 0x80) bytes[offset++] = point;
    else if (point < 0x800) { bytes[offset++] = 0xc0 | (point >> 6); bytes[offset++] = 0x80 | (point & 63); }
    else if (point < 0x10000) {
      bytes[offset++] = 0xe0 | (point >> 12); bytes[offset++] = 0x80 | ((point >> 6) & 63); bytes[offset++] = 0x80 | (point & 63);
    } else {
      bytes[offset++] = 0xf0 | (point >> 18); bytes[offset++] = 0x80 | ((point >> 12) & 63);
      bytes[offset++] = 0x80 | ((point >> 6) & 63); bytes[offset++] = 0x80 | (point & 63);
    }
  }
  return bytes;
}
export function validContractStoragePath(path: string, contractId: string): boolean {
  const parts = typeof path === 'string' ? path.split('/') : [];
  return CONTRACT_ID.test(contractId) && parts.length === 2 && parts[0] === contractId
    && /^[A-Za-z0-9_-]+\.html$/.test(parts[1] ?? '') && path.length <= 255;
}
export function assertConsent(input: { revision: ContractRevision; accepted: true }): void {
  if (input?.accepted !== true || !input.revision || !CONTRACT_ID.test(input.revision.contractId)
    || !CONTRACT_SHA256.test(input.revision.sha256) || typeof input.revision.storagePath !== 'string'
    || !input.revision.storagePath.trim()) {
    throw new ContractWorkflowError('INVALID_INPUT', 'Lisez le contrat affiché et acceptez ses termes avant de signer.');
  }
}
const messages: Record<string, string> = {
  NON_AUTHENTIFIE: 'Votre session a expiré. Reconnectez-vous.', NON_AUTORISE: 'Vous n’êtes pas autorisé à signer ce contrat.',
  CONTRAT_INTROUVABLE: 'Le contrat est indisponible. Rechargez votre liste.', CONTRAT_INACTIF: 'Ce contrat ne peut plus être signé.',
  CONTRAT_DEJA_COMPLET: 'Les deux parties ont déjà signé ce contrat.', DEJA_SIGNE: 'Votre signature est déjà enregistrée.',
  TELEPHONE_MANQUANT: 'Complétez le numéro de téléphone du profil avant de demander un code.',
  TROP_DE_SMS: 'La limite d’envoi de codes est atteinte. Réessayez plus tard.',
  TROP_DE_SMS_IP: 'La limite d’envoi de codes depuis cette connexion est atteinte. Réessayez plus tard.',
  OTP_NON_DEMANDE: 'Demandez un code de signature avant de continuer.', OTP_EXPIRE: 'Le code a expiré. Un nouvel envoi doit être demandé explicitement.',
  OTP_INCORRECT: 'Le code saisi est incorrect.', TROP_DE_TENTATIVES: 'La limite de tentatives est atteinte. Demandez un nouveau code.',
  HASH_DOCUMENT_CHANGE: 'Le document a changé ou sa preuve est indisponible. Rechargez le contrat avant de signer.',
  CONFIGURATION_SMS_INDISPONIBLE: 'L’envoi du code est actuellement indisponible.',
  SMS_RECETTE_INDISPONIBLE: 'L’envoi du code n’est pas autorisé pour cette recette TEST.',
};
export function serverIssue(data: unknown): ContractServerIssue | null {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  const value = data as Record<string, unknown>;
  if (value.success !== false && !value.error_code && !value.error) return null;
  const code = typeof value.error_code === 'string' && /^[A-Z0-9_]{1,80}$/.test(value.error_code) ? value.error_code : 'REFUS_SERVEUR';
  return { code, message: messages[code] ?? 'Le serveur a refusé cette demande. Rechargez le contrat avant de continuer.',
    retryAt: typeof value.reset_le === 'string' && Number.isFinite(Date.parse(value.reset_le)) ? value.reset_le : null,
    attemptsRemaining: Number.isInteger(value.tentatives_restantes) && Number(value.tentatives_restantes) >= 0
      && Number(value.tentatives_restantes) <= 5 ? Number(value.tentatives_restantes) : null };
}
