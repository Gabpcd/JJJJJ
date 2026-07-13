export const DOCUMENT_MIME_TYPES = [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
] as const;

export const IMAGE_DOCUMENT_MIME_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
] as const;

export type DocumentMime = (typeof DOCUMENT_MIME_TYPES)[number];
export type DocumentUploadFormat = 'SUPPORTED' | 'HEIC_UNSUPPORTED' | 'UNSUPPORTED';

export type DocumentUploadFailure =
  | 'EMPTY'
  | 'TOO_LARGE'
  | 'HEIC_UNSUPPORTED'
  | 'UNSUPPORTED'
  | 'INVALID_SIGNATURE';

export type DocumentUploadValidation =
  | { ok: true; mime: DocumentMime; extension: 'pdf' | 'jpg' | 'png' | 'webp' }
  | { ok: false; code: DocumentUploadFailure; message: string };

const MIME_BY_EXTENSION: Record<string, DocumentMime> = {
  pdf: 'application/pdf',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
};

const EXTENSION_BY_MIME: Record<DocumentMime, 'pdf' | 'jpg' | 'png' | 'webp'> = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

function extensionDuNom(name: string): string | null {
  const leaf = name.split(/[\\/]/).pop() || '';
  const match = leaf.match(/\.([a-z0-9]+)$/i);
  return match?.[1]?.toLowerCase() || null;
}

function mimeDeclare(type: string): string {
  return type.trim().toLowerCase();
}

function estMimeDocument(value: string): value is DocumentMime {
  return (DOCUMENT_MIME_TYPES as readonly string[]).includes(value);
}

/**
 * Classe un fichier avant téléversement. Le serveur revérifie ensuite sa
 * signature binaire ; ce contrôle client sert à donner une erreur immédiate et
 * compréhensible, notamment pour les photos HEIC non acceptées par l'API IA.
 */
export function classerFormatDocument(file: Pick<File, 'name' | 'type'>): DocumentUploadFormat {
  const mime = mimeDeclare(file.type);
  const extension = extensionDuNom(file.name);
  if (/^image\/hei[cf]$/i.test(mime) || extension === 'heic' || extension === 'heif') {
    return 'HEIC_UNSUPPORTED';
  }

  const mimeExtension = extension ? MIME_BY_EXTENSION[extension] : undefined;
  const mimeGenerique = !mime || mime === 'application/octet-stream';
  if (mimeGenerique) return mimeExtension ? 'SUPPORTED' : 'UNSUPPORTED';

  if (!estMimeDocument(mime)) return 'UNSUPPORTED';
  // Quand une extension est présente, elle doit confirmer le MIME déclaré.
  // Cela évite par exemple qu'un PDF soit envoyé comme photo JPEG (ou inversement).
  if (extension && (!mimeExtension || mimeExtension !== mime)) {
    return 'UNSUPPORTED';
  }
  return 'SUPPORTED';
}

function detecterMimeParSignature(bytes: Uint8Array): DocumentMime | null {
  const startsWith = (signature: readonly number[]) =>
    bytes.byteLength >= signature.length && signature.every((value, index) => bytes[index] === value);

  if (startsWith([0x25, 0x50, 0x44, 0x46, 0x2d])) return 'application/pdf'; // %PDF-
  if (startsWith([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (startsWith([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'image/png';
  if (
    startsWith([0x52, 0x49, 0x46, 0x46])
    && bytes.byteLength >= 12
    && bytes[8] === 0x57
    && bytes[9] === 0x45
    && bytes[10] === 0x42
    && bytes[11] === 0x50
  ) return 'image/webp';
  return null;
}

async function lireEntete(file: File): Promise<Uint8Array> {
  const slice = file.slice(0, 12);
  if (typeof slice.arrayBuffer === 'function') {
    return new Uint8Array(await slice.arrayBuffer());
  }
  // FileReader couvre les WebView plus anciennes et l'environnement jsdom des tests.
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error || new Error('Lecture impossible'));
    reader.onload = () => {
      if (!(reader.result instanceof ArrayBuffer)) {
        reject(new Error('Lecture impossible'));
        return;
      }
      resolve(new Uint8Array(reader.result));
    };
    reader.readAsArrayBuffer(slice);
  });
}

/**
 * Contrôle déterministe juste avant l'upload : taille, MIME, extension puis
 * signature binaire. Les Edge Functions refont le même contrôle côté serveur.
 */
export async function verifierFichierDocument(
  file: File,
  options: {
    maxBytes?: number;
    allowedMimes?: readonly DocumentMime[];
  } = {},
): Promise<DocumentUploadValidation> {
  const maxBytes = options.maxBytes ?? 10 * 1024 * 1024;
  const allowedMimes = options.allowedMimes ?? DOCUMENT_MIME_TYPES;

  if (file.size === 0) {
    return { ok: false, code: 'EMPTY', message: 'Le fichier sélectionné est vide.' };
  }
  if (file.size > maxBytes) {
    const maxMo = Math.floor(maxBytes / (1024 * 1024));
    return { ok: false, code: 'TOO_LARGE', message: `Le fichier ne doit pas dépasser ${maxMo} Mo.` };
  }

  const format = classerFormatDocument(file);
  if (format === 'HEIC_UNSUPPORTED') {
    return {
      ok: false,
      code: 'HEIC_UNSUPPORTED',
      message: 'Le format HEIC/HEIF ne peut pas être vérifié. Prenez une photo depuis Jolene ou choisissez un PDF, JPEG, PNG ou WebP.',
    };
  }
  if (format === 'UNSUPPORTED') {
    return {
      ok: false,
      code: 'UNSUPPORTED',
      message: 'Format non pris en charge, ou extension et type de fichier incohérents. Utilisez un PDF, JPEG, PNG ou WebP.',
    };
  }

  const extension = extensionDuNom(file.name);
  const declared = mimeDeclare(file.type);
  const expectedMime = estMimeDocument(declared)
    ? declared
    : extension
      ? MIME_BY_EXTENSION[extension]
      : undefined;
  if (!expectedMime || !allowedMimes.includes(expectedMime)) {
    return { ok: false, code: 'UNSUPPORTED', message: 'Ce type de fichier n’est pas autorisé ici.' };
  }

  let detectedMime: DocumentMime | null = null;
  try {
    const header = await lireEntete(file);
    detectedMime = detecterMimeParSignature(header);
  } catch {
    return { ok: false, code: 'INVALID_SIGNATURE', message: 'Impossible de lire le fichier sélectionné.' };
  }
  if (!detectedMime || detectedMime !== expectedMime || !allowedMimes.includes(detectedMime)) {
    return {
      ok: false,
      code: 'INVALID_SIGNATURE',
      message: 'Le contenu du fichier ne correspond pas au format annoncé. Exportez-le à nouveau en PDF, JPEG, PNG ou WebP.',
    };
  }

  return { ok: true, mime: detectedMime, extension: EXTENSION_BY_MIME[detectedMime] };
}

/** Produit un segment de chemin sans séparateur, sans `..` et de taille bornée. */
export function sanitiserNomFichier(name: string, mime: DocumentMime): string {
  const leaf = name.split(/[\\/]/).pop() || 'document';
  const extension = extensionDuNom(leaf);
  const sansExtension = extension ? leaf.slice(0, -(extension.length + 1)) : leaf;
  const base = sansExtension
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'document';
  return `${base}.${EXTENSION_BY_MIME[mime]}`;
}
