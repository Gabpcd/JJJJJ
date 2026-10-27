import type { DocumentMediaAdapter, DocumentSource } from '../../ui/documents/adapters';
import type { NativeDocumentFile } from '../../workflows/documents/types';

export interface DocumentMediaScope { readonly userId: string; readonly epoch: number }
export interface ManagedDocumentMediaAdapter extends DocumentMediaAdapter {
  /** Discard Android activity-recovery results; never return them as a fresh selection. */
  prepare(): Promise<void>;
  /** Call synchronously on session replacement/unmount, then await cleanup separately. */
  dispose(): Promise<void>;
}
export interface PickedDocumentAsset { uri: string; name?: string | null; mime?: string | null; base64?: string | null }
export interface OwnedDocumentCopy { uri: string; release(): Promise<void> }
/** Injectable native boundary. No network upload and no credentials in these ports. */
export interface DocumentMediaPorts {
  platform: 'ios' | 'android';
  requestCameraPermission(): Promise<boolean>;
  choose(source: DocumentSource): Promise<PickedDocumentAsset | null>;
  discardPendingResult(): Promise<void>;
  readLocalDocument(uri: string): Promise<Uint8Array>;
  createPrivateCopy(file: NativeDocumentFile): Promise<OwnedDocumentCopy>;
  cleanupPickedAsset(asset: PickedDocumentAsset): Promise<void>;
  cleanup(): Promise<void>;
  openSystemDocument(uri: string): Promise<'opened' | 'cancel' | 'dismiss' | 'locked'>;
  /** Only supplied on iOS. Android Custom Tabs has no supported forced-close API. */
  dismissSystemDocument?: () => Promise<void>;
}
