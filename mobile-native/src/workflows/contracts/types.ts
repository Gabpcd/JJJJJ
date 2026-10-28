export type ContractContext = { kind: 'soignant'; userId: string }
  | { kind: 'etablissement'; userId: string; etablissementId: string };
export type ContractParty = 'soignant' | 'etablissement';
export interface ContractRecord {
  id: string; mission_id: string; soignant_id: string; etablissement_id: string;
  numero_contrat: string; type_contrat: string; statut: string | null; cree_le: string | null;
  signature_soignant: boolean | null; signature_soignant_le: string | null;
  signature_etablissement: boolean | null; signature_etablissement_le: string | null;
}
export interface StoredContractRecord extends ContractRecord {
  contenu_html: string | null; hash_document: string | null; storage_path: string | null;
  contenu_html_rendu_le: string | null; mode_signature: string | null;
}
/** Explicit safe projection; never contains otp_code_hash, raw OTP, IP or user agent. */
export interface ContractSignature {
  id: string; contrat_id: string; signataire_user_id: string; signataire_role: ContractParty;
  statut_signature: string; signe_a: string | null; otp_valide_a: string | null;
  hash_document: string | null; cree_le: string | null;
}
export interface ContractRevision { contractId: string; sha256: string; storagePath: string }
export interface VerifiedContractOriginal extends ContractRevision {
  /** Exact original UTF-8 string. Do not normalize it or hash a sanitized/rendered substitute. */
  html: string; renderedAt: string; source: 'database-and-storage' | 'synthetic';
}
export interface ContractOriginalTransport {
  read(input: { contractId: string; storagePath: string; authorization: string; signal?: AbortSignal }): Promise<Uint8Array>;
}
export interface ContractOtpAdmission {
  expiresAt: number; canSend: boolean; canValidate: boolean; otpExpiresAt: number | null;
}
export interface ContractDetails {
  userId: string; party: ContractParty; record: StoredContractRecord; signatures: ContractSignature[];
  original: VerifiedContractOriginal | null;
  originalIssue: 'unprepared' | 'incomplete' | 'hash_mismatch' | 'signature_mismatch' | 'unavailable' | null;
  permissions: { read: true; sign: boolean }; isTestAccount: boolean;
  otpAdmission: ContractOtpAdmission | null;
}
export interface ContractPage { rows: ContractRecord[]; page: number; nextPage: number | null; total: number }
export interface ContractConsent { revision: ContractRevision; accepted: true }
export interface SignContractInput extends ContractConsent { code: string }
export interface ContractServerIssue {
  code: string; message: string; retryAt: string | null; attemptsRemaining: number | null;
}
export interface OtpRequestResult {
  /** queued = request recorded, never delivery to the phone or even provider acceptance. */
  kind: 'queued' | 'rejected' | 'unconfirmed'; delivery: 'unverified';
  contract: ContractDetails | null; phoneMasked: string | null; expiresAt: number | null;
  sendsRemaining: number | null; issue: ContractServerIssue | null; message: string;
}
export interface ContractSignResult {
  kind: 'confirmed' | 'already_signed' | 'rejected' | 'unconfirmed';
  contract: ContractDetails | null; issue: ContractServerIssue | null; message: string;
}
export interface ContractGateway {
  readonly mode: 'supabase' | 'demo';
  list(context: ContractContext, page?: number, signal?: AbortSignal): Promise<ContractPage>;
  read(context: ContractContext, contractId: string, signal?: AbortSignal): Promise<ContractDetails>;
  requestOtp(context: ContractContext, input: ContractConsent, signal?: AbortSignal): Promise<OtpRequestResult>;
  sign(context: ContractContext, input: SignContractInput, signal?: AbortSignal): Promise<ContractSignResult>;
}
export class ContractWorkflowError extends Error {
  constructor(readonly code: 'SESSION_CHANGED' | 'INVALID_SCOPE' | 'INVALID_INPUT' | 'BUSY' | 'UNAVAILABLE'
    | 'DOCUMENT_CHANGED' | 'ORIGINAL_UNAVAILABLE' | 'SIGNATURE_UNAVAILABLE' | 'TEST_NOT_ADMITTED', message: string) {
    super(message); this.name = 'ContractWorkflowError';
  }
}
