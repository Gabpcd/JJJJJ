import type { DocumentGateway, DocumentOriginal, NativeDocumentFile } from '../../workflows/documents/types';

/** Demo is a separate in-memory implementation, never a fallback after a TEST error. */
export type DocumentScreenGateway = Omit<DocumentGateway, 'mode'> & { readonly mode: 'demo' | 'supabase' };
export type DocumentSource = 'camera' | 'library' | 'file';
export interface DocumentSelection {
  file: NativeDocumentFile;
  /** Optional local cache URI only. Never a provider URL or an embedded browser. */
  localPreviewUri?: string;
}
export interface PendingDocumentUpload { storageKey: string }
/** Owned by the runtime, outside the screen. Persist before uploading; isolate by account. */
export interface DocumentUploadJournal {
  read(userId: string): Promise<PendingDocumentUpload | null>;
  /** Persist, refusing to overwrite a different unresolved receipt. */
  write(userId: string, pending: PendingDocumentUpload): Promise<void>;
  /** Serialized comparison: never remove a receipt for a different storage key. */
  clear(userId: string, expectedStorageKey: string): Promise<void>;
}
export interface DocumentMediaAdapter {
  /** Only expose capabilities actually implemented by the device adapter. */
  readonly sources: readonly DocumentSource[];
  /** null means the person cancelled; permission denial must throw a user-safe error. */
  pick(source: DocumentSource, signal: AbortSignal): Promise<DocumentSelection | null>;
  /** Release only temporary files created by the adapter, never the person's original. */
  release?(selection: DocumentSelection): void | Promise<void>;
  /** Open the exact signed original using the supplied system viewer. Never an app WebView. */
  open?(original: DocumentOriginal, signal: AbortSignal): Promise<void>;
}
export class DocumentMediaError extends Error {
  constructor(readonly code: 'PERMISSION_DENIED' | 'UNAVAILABLE' | 'INVALID_FILE', message: string) {
    super(message); this.name = 'DocumentMediaError';
  }
}
