/** An authenticated caregiver context, independent of a completed professional profile. */
export interface DocumentContext { userId: string }

/** Picker/camera adapters supply decoded bytes, never a remote URL, base64 or a browser File. */
export interface NativeDocumentFile { name: string; mime: string; bytes: Uint8Array }

export interface DocumentProfile {
  id: string; profession: string | null; prenom: string | null; nom: string | null;
  type_exercice: string | null; rpps_verifie: boolean | null; adeli_verifie: boolean | null;
  attestation_sante_signee_le: string | null;
}

export interface CaregiverDocument {
  id: string; soignant_id: string; type_document: string; nom_fichier: string;
  /** Keep the server value; an unknown status must never become "verified". */
  statut_verification: string | null;
  valide_depuis: string | null; valide_jusqua: string | null; televerse_le: string | null;
  motif_rejet: string | null; est_critique: boolean | null; libelle: string | null;
  s3_cle: string; s3_bucket: 'jolene-documents'; type_mime: string | null; taille_octets: number | null;
  profession_certifiee: string | null; supprime_le: string | null; revoque_le: string | null;
}

export interface DocumentRequirement {
  id: string; profession: string; type_document: string; description: string | null;
  a_expiration: boolean | null; duree_validite_mois: number | null; est_critique: boolean | null;
  type_exercice_requis: string | null;
}

export interface DocumentDossier {
  userId: string; profile: DocumentProfile | null;
  documents: CaregiverDocument[]; requirements: DocumentRequirement[];
}

export interface UploadDocumentInput {
  typeDocument: string; label?: string; file: NativeDocumentFile;
  /** The active original shown in the UI, re-read before any replacement. */
  replacesDocumentId?: string;
  /** Retain before Storage begins, including if a subsequent abort/timeout hides its response. */
  onPrepared?: (receipt: { storageKey: string }) => void | Promise<void>;
  /** Local exact-receipt cleanup before Storage, also when preparation persisted then rejected. */
  onNotStarted?: (receipt: { storageKey: string }) => void | Promise<void>;
}

export interface DocumentOriginal { uri: string; mime: string; fileName: string; expiresAt: string }
export interface OriginalSigningTransport {
  sign(input: { storageKey: string; authorization: string; expiresIn: number; signal?: AbortSignal }): Promise<string>;
}

export interface DocumentMutationResult {
  kind: 'confirmed' | 'rejected' | 'unconfirmed';
  dossier: DocumentDossier | null; document: CaregiverDocument | null;
  message: string; warning?: string;
  /** Read-only reconciliation. Never automatically repeat an uncertain upload. */
  reconciliation?: { storageKey: string };
}

export interface DocumentGateway {
  readonly mode: 'supabase';
  readDossier(context: DocumentContext, signal?: AbortSignal): Promise<DocumentDossier>;
  getOriginal(context: DocumentContext, documentId: string, signal?: AbortSignal): Promise<DocumentOriginal>;
  upload(context: DocumentContext, input: UploadDocumentInput, signal?: AbortSignal): Promise<DocumentMutationResult>;
  reconcileUpload(context: DocumentContext, storageKey: string, signal?: AbortSignal): Promise<DocumentMutationResult>;
  verify(context: DocumentContext, documentId: string, signal?: AbortSignal): Promise<DocumentMutationResult>;
  requestReview(context: DocumentContext, documentId: string, motif: string, signal?: AbortSignal): Promise<DocumentMutationResult>;
  logicalDelete(context: DocumentContext, documentId: string, signal?: AbortSignal): Promise<DocumentMutationResult>;
}

export class DocumentWorkflowError extends Error {
  constructor(readonly code: 'SESSION_CHANGED' | 'INVALID_SCOPE' | 'INVALID_FILE' | 'INVALID_INPUT' | 'BUSY' | 'UNAVAILABLE', message: string) {
    super(message); this.name = 'DocumentWorkflowError';
  }
}
