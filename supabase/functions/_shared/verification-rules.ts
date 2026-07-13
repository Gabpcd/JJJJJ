/**
 * Règles déterministes appliquées après l'analyse documentaire par IA.
 *
 * L'IA extrait les champs ; ces helpers décident si une validation automatique
 * est possible. Une donnée absente renvoie `null` afin de basculer en revue
 * humaine plutôt que de valider par défaut.
 */

export function normalizeVerificationText(value: unknown): string {
  return String(value ?? '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

export const MAX_VERIFICATION_DOCUMENT_BYTES = 10 * 1024 * 1024;

export type VerificationDocumentMime =
  | 'application/pdf'
  | 'image/jpeg'
  | 'image/png'
  | 'image/webp';

export type VerificationDocumentFailure =
  | 'EMPTY'
  | 'TOO_LARGE'
  | 'UNSUPPORTED_MIME'
  | 'INVALID_SIGNATURE';

/**
 * Vérifie le type déclaré et la signature binaire avant tout envoi au modèle.
 * L'extension du nom de fichier n'est volontairement jamais utilisée.
 */
export function validateDocumentFile(
  bytes: Uint8Array,
  declaredMime: unknown,
  maxBytes = MAX_VERIFICATION_DOCUMENT_BYTES,
): { ok: true; mime: VerificationDocumentMime } | { ok: false; code: VerificationDocumentFailure } {
  if (bytes.byteLength === 0) return { ok: false, code: 'EMPTY' };
  if (!Number.isFinite(maxBytes) || maxBytes <= 0 || bytes.byteLength > maxBytes) {
    return { ok: false, code: 'TOO_LARGE' };
  }

  const mime = typeof declaredMime === 'string' ? declaredMime.trim().toLowerCase() : '';
  const supported = new Set<VerificationDocumentMime>([
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
  ]);
  if (!supported.has(mime as VerificationDocumentMime)) {
    return { ok: false, code: 'UNSUPPORTED_MIME' };
  }

  const startsWith = (signature: readonly number[]) =>
    bytes.byteLength >= signature.length && signature.every((value, index) => bytes[index] === value);
  const matchesSignature = mime === 'application/pdf'
    ? startsWith([0x25, 0x50, 0x44, 0x46, 0x2d]) // %PDF-
    : mime === 'image/jpeg'
      ? startsWith([0xff, 0xd8, 0xff])
      : mime === 'image/png'
        ? startsWith([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        : startsWith([0x52, 0x49, 0x46, 0x46])
          && bytes.byteLength >= 12
          && bytes[8] === 0x57
          && bytes[9] === 0x45
          && bytes[10] === 0x42
          && bytes[11] === 0x50; // RIFF....WEBP

  return matchesSignature
    ? { ok: true, mime: mime as VerificationDocumentMime }
    : { ok: false, code: 'INVALID_SIGNATURE' };
}

/** Accepte uniquement une date civile réelle au format exact YYYY-MM-DD. */
export function normalizeIsoCivilDate(value: unknown): string | null {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(parsed.getTime())) return null;
  return parsed.toISOString().slice(0, 10) === value ? value : null;
}

export type StrictAiVerificationQuality = {
  score: number | null;
  confidence: string | null;
  antifraudComplete: boolean;
  indicators: string[];
  highConfidence: boolean;
};

/**
 * Une validation automatique exige les deux signaux de confiance, sans
 * coercition de chaîne, ainsi qu'une liste antifraude présente et bien formée.
 */
export function strictAiVerificationQuality(analysis: unknown): StrictAiVerificationQuality {
  const record = analysis && typeof analysis === 'object'
    ? analysis as Record<string, unknown>
    : {};
  const rawScore = record.score_confiance;
  const score = typeof rawScore === 'number'
      && Number.isFinite(rawScore)
      && rawScore >= 0
      && rawScore <= 100
    ? rawScore
    : null;
  const confidence = typeof record.confiance === 'string' ? record.confiance : null;
  const rawIndicators = record.indices_falsification;
  const antifraudComplete = Array.isArray(rawIndicators)
    && rawIndicators.every((item) => typeof item === 'string' && item.trim().length > 0);
  const indicators = antifraudComplete
    ? (rawIndicators as string[]).map((item) => item.trim().slice(0, 500)).slice(0, 20)
    : [];

  return {
    score,
    confidence,
    antifraudComplete,
    indicators,
    highConfidence: confidence === 'HAUTE' && score !== null && score >= 85,
  };
}

function tokens(value: unknown): string[] {
  return normalizeVerificationText(value).split(' ').filter(Boolean);
}

function sameTokenSetOrContained(a: string[], b: string[]): boolean {
  if (a.length === 0 || b.length === 0) return false;
  const aSet = new Set(a);
  const bSet = new Set(b);
  const smaller = a.length <= b.length ? aSet : bSet;
  const larger = a.length <= b.length ? bSet : aSet;
  return [...smaller].every((token) => larger.has(token));
}

/** Compare une identité déclarée avec les champs réellement extraits du document. */
export function personNameMatches(
  expectedLastName: unknown,
  expectedFirstName: unknown,
  extractedLastName: unknown,
  extractedFirstName: unknown,
): boolean | null {
  const expectedLast = tokens(expectedLastName);
  const extractedLast = tokens(extractedLastName);
  if (expectedLast.length === 0 || extractedLast.length === 0) return null;

  const lastMatches = sameTokenSetOrContained(expectedLast, extractedLast);
  if (!lastMatches) return false;

  const expectedFirst = tokens(expectedFirstName);
  if (expectedFirst.length === 0) return null;
  const extractedFirst = tokens(extractedFirstName);
  if (extractedFirst.length === 0) return null;

  // Un préfixe de trois caractères est trop ambigu (Marie/Marion, Anne/Annie,
  // etc.). Une validation automatique exige au moins un prénom complet exact;
  // les variantes basculent en revue humaine.
  const firstMatches = expectedFirst.some((expected) => extractedFirst.includes(expected));
  return firstMatches;
}

const CORPORATE_STOP_WORDS = new Set([
  'sa', 'sas', 'sasu', 'sarl', 'eurl', 'sel', 'selarl', 'selas', 'scp', 'sci',
  'association', 'societe', 'ste', 'groupe', 'etablissement', 'etablissements',
  'centre', 'cabinet', 'clinique', 'hopital', 'hospitalier', 'hospitaliere',
  'medical', 'medicale', 'medico', 'maison', 'pole', 'sante',
]);

function corporateTokens(value: unknown): string[] {
  return tokens(value).filter((token) => !CORPORATE_STOP_WORDS.has(token) && token.length >= 2);
}

/**
 * Compare deux raisons sociales. Le résultat reste indéterminé si l'un des
 * libellés est absent ; une correspondance exige un noyau lexical commun.
 */
export function corporateNameMatches(expected: unknown, extracted: unknown): boolean | null {
  const a = corporateTokens(expected);
  const b = corporateTokens(extracted);
  if (a.length === 0 || b.length === 0) return null;

  // Un extrait monomot est trop ambigu pour une preuve juridique ou
  // financière (p. ex. « Paris », « Jean », « Santé »). Deux tokens
  // discriminants au minimum sont exigés, y compris pour une inclusion.
  if (a.length < 2 || b.length < 2) return null;
  if (sameTokenSetOrContained(a, b)) return true;

  const bSet = new Set(b);
  const shared = [...new Set(a.filter((token) => bSet.has(token)))];
  const denominator = Math.min(new Set(a).size, new Set(b).size);
  return shared.length >= 2 && denominator >= 2 && shared.length / denominator >= 0.8;
}

/**
 * La profession déclarée est la qualification qui doit être prouvée.
 * Une spécialisation infirmière prouve le diplôme IDE de base, mais l'inverse
 * n'est jamais vrai : un diplôme IDE seul ne prouve ni IADE ni IBODE.
 */
export function diplomaMatchesDeclaredProfession(
  declaredProfession: unknown,
  certifiedProfession: unknown,
): boolean | null {
  const declared = String(declaredProfession ?? '').trim().toUpperCase();
  const certified = String(certifiedProfession ?? '').trim().toUpperCase();
  if (!declared || !certified) return null;

  const allowedDiplomasByDeclaredProfession: Record<string, string[]> = {
    IDE: ['IDE', 'IADE', 'IBODE'],
    IADE: ['IADE'],
    IBODE: ['IBODE'],
  };
  return (allowedDiplomasByDeclaredProfession[declared] ?? [declared]).includes(certified);
}

export function normalizeProfessionalIdentifier(value: unknown): string {
  return String(value ?? '').replace(/\D/g, '');
}

export function professionalIdentifierMatches(expected: unknown, extracted: unknown): boolean | null {
  const expectedDigits = normalizeProfessionalIdentifier(expected);
  const extractedDigits = normalizeProfessionalIdentifier(extracted);
  if (!expectedDigits || !extractedDigits) return null;
  return expectedDigits === extractedDigits;
}

export function normalizeIban(value: unknown): string {
  return String(value ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

/** Validation ISO 13616 (structure + modulo 97), sans dépendance externe. */
export function isValidIban(value: unknown): boolean {
  const iban = normalizeIban(value);
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$/.test(iban)) return false;

  const rearranged = iban.slice(4) + iban.slice(0, 4);
  let remainder = 0;
  for (const char of rearranged) {
    const numeric = /[0-9]/.test(char) ? char : String(char.charCodeAt(0) - 55);
    for (const digit of numeric) remainder = (remainder * 10 + Number(digit)) % 97;
  }
  return remainder === 1;
}

export function ibanLast4(value: unknown): string | null {
  const iban = normalizeIban(value);
  return iban.length >= 4 ? iban.slice(-4) : null;
}

/** Retire les coordonnées bancaires complètes avant persistance et réponse. */
export function sanitizeBankAnalysis<T extends Record<string, unknown>>(analysis: T): T & {
  iban_last4: string | null;
  iban_valide: boolean;
} {
  const fullIban = normalizeIban(analysis.iban_extrait ?? analysis.iban ?? '');
  // Whitelist stricte : un modèle compromis ne doit pas pouvoir contourner
  // une blacklist en plaçant l'IBAN dans `raw_text`, `iban_detected`, un objet
  // imbriqué ou un autre champ inventé.
  const allowedBooleanKeys = [
    'est_rib', 'titulaire_correspond', 'document_lisible', 'document_complet',
    'type_correspond', 'nom_correspond', 'antifraude_complete',
  ];
  const allowedStringKeys = [
    'titulaire_extrait', 'banque', 'motif', 'motif_rejet', 'verdict',
    'type_detecte', 'date_expiration', 'date_emission', 'confiance',
    'nom_detecte', 'nom_extrait', 'prenom_extrait',
  ];

  const redactBankData = (value: string): string => value
    .replace(/\b[A-Z]{2}\s*\d{2}(?:[\s-]*[A-Z0-9]){11,30}\b/gi, '[IBAN MASQUÉ]')
    .replace(/\b(?:\d[\s-]*){12,34}\b/g, '[COORDONNÉE BANCAIRE MASQUÉE]')
    .slice(0, 500);

  const sanitized: Record<string, unknown> = {};
  for (const key of allowedBooleanKeys) {
    if (typeof analysis[key] === 'boolean' || analysis[key] === null) sanitized[key] = analysis[key];
  }
  for (const key of allowedStringKeys) {
    if (typeof analysis[key] === 'string') sanitized[key] = redactBankData(analysis[key] as string);
    else if (analysis[key] === null) sanitized[key] = null;
  }
  const score = analysis.score_confiance;
  if (typeof score === 'number' && Number.isFinite(score) && score >= 0 && score <= 100) {
    sanitized.score_confiance = score;
  } else if (score === null) {
    sanitized.score_confiance = null;
  }
  if (Array.isArray(analysis.indices_falsification)) {
    sanitized.indices_falsification = analysis.indices_falsification
      .filter((item): item is string => typeof item === 'string')
      .slice(0, 10)
      .map(redactBankData);
  }
  sanitized.iban_last4 = ibanLast4(fullIban);
  sanitized.iban_valide = isValidIban(fullIban);
  return sanitized as T & { iban_last4: string | null; iban_valide: boolean };
}
