import { sanitiserNomFichier, verifierFichierDocument, type DocumentMime } from '../../../../src/lib/documentUpload';
import { DocumentWorkflowError, type NativeDocumentFile } from './types';

export interface ValidatedDocumentBytes {
  originalName: string; safeName: string; mime: DocumentMime; size: number; bytes: ArrayBuffer;
}

/** No FileReader/Blob constructor or native dependency; reuse the same binary validator as web. */
export async function validateDocumentBytes(input: NativeDocumentFile): Promise<ValidatedDocumentBytes> {
  if (!input || typeof input.name !== 'string' || !input.name.trim() || input.name.length > 255
    || typeof input.mime !== 'string' || !(input.bytes instanceof Uint8Array)) {
    throw new DocumentWorkflowError('INVALID_FILE', 'Le fichier sélectionné est invalide.');
  }
  // Bound the allocation before copying. Copy the view, not its backing buffer or adjacent bytes.
  if (input.bytes.byteLength === 0 || input.bytes.byteLength > 10 * 1024 * 1024) {
    throw new DocumentWorkflowError('INVALID_FILE', 'Choisissez un fichier non vide de 10 Mo maximum.');
  }
  const originalName = input.name.trim();
  const mime = input.mime;
  const bytes = new Uint8Array(input.bytes).buffer;
  const readable = {
    name: originalName, type: mime, size: bytes.byteLength,
    slice: (start: number, end: number) => ({ arrayBuffer: async () => bytes.slice(start, end) }),
  } as unknown as File;
  const validation = await verifierFichierDocument(readable);
  if (!validation.ok) throw new DocumentWorkflowError('INVALID_FILE', validation.message);
  return { originalName, safeName: sanitiserNomFichier(originalName, validation.mime),
    mime: validation.mime, size: bytes.byteLength, bytes };
}
