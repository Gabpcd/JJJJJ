import { DocumentMediaError } from '../../ui/documents/adapters';
import type { DocumentOriginal } from '../../workflows/documents/types';

export const MAX_DOCUMENT_BYTES = 10 * 1024 * 1024;
export const DOCUMENT_MIMES = ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'] as const;
export const DOCUMENTS_STAGING_ORIGIN = 'https://mejpriaetwgtcstbgfid.supabase.co';
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const invalid = (message = 'Le fichier sélectionné est invalide.') => new DocumentMediaError('INVALID_FILE', message);

/** A bounded decoder for Expo's JPEG payload. Never derive MIME from an HEIC URI. */
export function decodePickerJpeg(value: unknown): Uint8Array {
  if (typeof value !== 'string' || !value.length || value.length > 4 * Math.ceil(MAX_DOCUMENT_BYTES / 3)
    || value.length % 4 !== 0 || /[^A-Za-z0-9+/=]/.test(value)) {
    throw invalid('La photo ne peut pas être lue. Choisissez une image de 10 Mo maximum.');
  }
  const padding = value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0;
  const firstPadding = value.indexOf('=');
  if (firstPadding !== -1 && firstPadding !== value.length - padding) throw invalid();
  const size = value.length / 4 * 3 - padding;
  if (!size || size > MAX_DOCUMENT_BYTES) throw invalid('Choisissez un fichier non vide de 10 Mo maximum.');
  // Reject non-canonical padding rather than accepting different encodings of the same bytes.
  if ((padding === 2 && (alphabet.indexOf(value[value.length - 3]!) & 15) !== 0)
    || (padding === 1 && (alphabet.indexOf(value[value.length - 2]!) & 3) !== 0)) throw invalid();
  const bytes = new Uint8Array(size); let offset = 0;
  for (let index = 0; index < value.length; index += 4) {
    const n = (alphabet.indexOf(value[index]!) << 18) | (alphabet.indexOf(value[index + 1]!) << 12)
      | ((value[index + 2] === '=' ? 0 : alphabet.indexOf(value[index + 2]!)) << 6)
      | (value[index + 3] === '=' ? 0 : alphabet.indexOf(value[index + 3]!));
    bytes[offset++] = (n >>> 16) & 255;
    if (offset < size) bytes[offset++] = (n >>> 8) & 255;
    if (offset < size) bytes[offset++] = n & 255;
  }
  if (bytes.length < 3 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    bytes.fill(0); throw invalid('La photo doit contenir un véritable JPEG. Son nom seul ne suffit pas.');
  }
  return bytes;
}

export function jpegCopyName(sourceName?: string | null): string {
  const stem = (sourceName ?? 'photo').split(/[\\/]/).pop()!.replace(/\.[^.]*$/, '').trim();
  return `${(stem || 'photo').slice(0, 230)}.jpg`;
}

/** Used only for fresh native-picker results; never for unbound Android recovery results. */
export function isCacheDescendant(uri: string, cacheUri: string): boolean {
  try {
    const target = new URL(uri); const cache = new URL(cacheUri);
    if (target.protocol !== 'file:' || cache.protocol !== 'file:' || target.host !== cache.host
      || target.search || target.hash || target.username || target.password || /%(?:2e|2f|5c)/i.test(uri)) return false;
    const path = decodeURIComponent(target.pathname); const root = decodeURIComponent(cache.pathname).replace(/\/+$/, '');
    if (path.includes('\\') || /(?:^|\/)\.\.?($|\/)/.test(path) || uri.includes('/../') || uri.includes('/./')) return false;
    return path.startsWith(`${root}/`) && path.length > root.length + 1;
  } catch { return false; }
}

export function assertLocalDocumentUri(uri: string): void {
  if (typeof uri !== 'string' || !/^(?:file|content):\/\//.test(uri) || /[\r\n\0]/.test(uri)) {
    throw invalid('Le fichier doit être sélectionné depuis cet appareil.');
  }
}

/** Revalidate the exact artifact at the last boundary before handing it to the OS. */
export function validateOriginalForOpening(original: DocumentOriginal, userId: string, now = Date.now()): string {
  const fail = () => new DocumentMediaError('UNAVAILABLE', 'Ce lien de document n’est plus utilisable. Rechargez votre dossier.');
  if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(userId)
    || !DOCUMENT_MIMES.includes(original.mime as typeof DOCUMENT_MIMES[number])) throw fail();
  const deadline = Date.parse(original.expiresAt);
  if (!Number.isFinite(deadline) || deadline <= now + 5000 || deadline > now + 3600_000) throw fail();
  try {
    const url = new URL(original.uri);
    const prefix = `/storage/v1/object/sign/jolene-documents/${userId}/documents/`;
    const remainder = url.pathname.slice(prefix.length);
    if (url.origin !== DOCUMENTS_STAGING_ORIGIN || !url.pathname.startsWith(prefix)
      || url.username || url.password || url.hash || /%(?:2e|2f|5c)/i.test(url.pathname)
      || !/^[A-Z][A-Z0-9_]{1,79}\/[A-Za-z0-9._-]+$/.test(remainder)
      || remainder.split('/').some(part => part === '.' || part === '..')
      || [...url.searchParams.keys()].length !== 1 || !url.searchParams.get('token')
      || [...url.searchParams.keys()][0] !== 'token' || /[\r\n\0]/.test(original.uri)) throw fail();
    return original.uri; // Never rewrite the signed URL or append viewer/redirect parameters.
  } catch { throw fail(); }
}
