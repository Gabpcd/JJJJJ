/**
 * Règles de sécurité déterministes du flux Pro Santé Connect.
 *
 * Sources ANS :
 * - UserInfo PSC : SubjectNameID/preferred_username portent l'identifiant
 *   national et SubjectRefPro.exercices[].codeProfession la profession ;
 *   https://esante.gouv.fr/ens/offre/pro-sante-connect/userinfo
 * - TRE_G15-ProfessionSante pour les codes de profession ;
 *   https://mos.esante.gouv.fr/NOS/TRE_G15-ProfessionSante/FHIR/
 * - un identifiant national RPPS est « 8 » + le RPPS à 11 chiffres, dont le
 *   dernier chiffre est une clé de Luhn.
 *   https://esante.gouv.fr/faq/quelle-est-le-lien-entre-l-identifiant-national-et-le-numero-rpps
 *
 * Ce module n'effectue aucun accès réseau : il valide uniquement les claims
 * déjà authentifiés par le callback OIDC.
 */

export type PscEnvironment = "sandbox" | "production";

export type JoleneProfession =
  | "IDE"
  | "AS"
  | "IBODE"
  | "IADE"
  | "SAGE_FEMME"
  | "KINE"
  | "MEDECIN"
  | "PHARMACIEN"
  | "MANIPULATEUR_RADIO"
  | "PREPARATEUR_PHARMA"
  | "DIETETICIEN"
  | "ERGOTHERAPEUTE"
  | "PSYCHOMOTRICIEN"
  | "ORTHOPHONISTE"
  | "DENTISTE"
  | "AUXILIAIRE_PUERICULTURE";

type UnknownRecord = Record<string, unknown>;

export type RppsEvidence =
  | { status: "verified"; rpps: string }
  | { status: "absent" }
  | { status: "invalid" };

export type EmailEvidence =
  | { status: "verified"; email: string }
  | { status: "absent" }
  | { status: "unverified" }
  | { status: "invalid" };

export interface ProfessionEvidence {
  profession: JoleneProfession;
  sourceCodes: string[];
}

const PSC_CODE_TO_JOLENE = Object.freeze<Record<string, JoleneProfession>>({
  // TRE_G15-ProfessionSante (codes actifs ou anciens encore susceptibles
  // d'être présents dans un jeton issu de l'historique RPPS).
  "10": "MEDECIN",
  "21": "PHARMACIEN",
  "35": "AS",
  "37": "AUXILIAIRE_PUERICULTURE",
  "38": "PREPARATEUR_PHARMA",
  "39": "PREPARATEUR_PHARMA",
  "40": "DENTISTE",
  "50": "SAGE_FEMME",
  "60": "IDE",
  "69": "IDE",
  "70": "KINE",
  "91": "ORTHOPHONISTE",
  "94": "ERGOTHERAPEUTE",
  "95": "DIETETICIEN",
  "96": "PSYCHOMOTRICIEN",
  "98": "MANIPULATEUR_RADIO",
});

function asRecord(value: unknown): UnknownRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as UnknownRecord
    : null;
}

function nonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function resolvePscEnvironment(
  value: string | undefined,
): PscEnvironment | null {
  return value === "sandbox" || value === "production" ? value : null;
}

export function mapPscProfessionCode(code: unknown): JoleneProfession | null {
  const normalized = typeof code === "number" && Number.isInteger(code)
    ? String(code)
    : nonEmptyString(code);
  if (!normalized || !/^\d{2}$/.test(normalized)) return null;
  return PSC_CODE_TO_JOLENE[normalized] ?? null;
}

function professionCodesFromClaims(claims: UnknownRecord): string[] {
  const subjectRefPro = asRecord(claims.SubjectRefPro);
  const exercices = Array.isArray(subjectRefPro?.exercices)
    ? subjectRefPro.exercices
    : [];
  const exerciseCodes = exercices
    .map(asRecord)
    .map((exercise) => nonEmptyString(exercise?.codeProfession))
    .filter((code): code is string => code !== null);

  if (exerciseCodes.length > 0) return exerciseCodes;
  const topLevelCode = nonEmptyString(claims.codeProfession);
  return topLevelCode ? [topLevelCode] : [];
}

/**
 * Une profession ne peut être déduite que d'un code ANS explicite. Les
 * libellés libres et les valeurs inconnues ne déclenchent aucun fallback.
 * Plusieurs exercices ne sont acceptés que s'ils aboutissent tous à la même
 * profession Jolene ; sinon une revue manuelle est nécessaire.
 */
export function extractPscProfession(
  ...claimSets: Array<UnknownRecord | null | undefined>
): ProfessionEvidence | null {
  const codes = claimSets.flatMap((claims) =>
    claims ? professionCodesFromClaims(claims) : []
  );
  const uniqueCodes = [...new Set(codes)];
  if (uniqueCodes.length === 0) return null;

  const mapped = uniqueCodes.map(mapPscProfessionCode);
  if (mapped.some((profession) => profession === null)) return null;
  const uniqueProfessions = [...new Set(mapped as JoleneProfession[])];
  if (uniqueProfessions.length !== 1) return null;

  return { profession: uniqueProfessions[0], sourceCodes: uniqueCodes };
}

export function isValidLuhn(value: string): boolean {
  if (!/^\d+$/.test(value)) return false;
  let sum = 0;
  let doubleDigit = false;
  for (let i = value.length - 1; i >= 0; i -= 1) {
    let digit = Number(value[i]);
    if (doubleDigit) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
    doubleDigit = !doubleDigit;
  }
  return sum % 10 === 0;
}

export function normalizeRpps(value: unknown): string | null {
  const raw = nonEmptyString(value);
  if (!raw || !/^\d+$/.test(raw)) return null;
  const rpps = raw.length === 12 && raw.startsWith("8")
    ? raw.slice(1)
    : raw.length === 11
    ? raw
    : null;
  return rpps && !/^0{11}$/.test(rpps) && isValidLuhn(rpps) ? rpps : null;
}

function pushNationalIdCandidate(
  candidates: unknown[],
  malformedRpps: { value: boolean },
  value: unknown,
): void {
  const raw = nonEmptyString(value);
  if (!raw) return;

  // Les identifiants nationaux non RPPS (préfixe autre que 8), ainsi que les
  // identifiants techniques de BAS, ne constituent pas une preuve RPPS.
  if (raw.startsWith("8") && !/^8\d{11}$/.test(raw)) {
    malformedRpps.value = true;
    return;
  }
  const claimsRpps = /^\d{11}$/.test(raw) || /^8\d{11}$/.test(raw);
  if (!claimsRpps) return;
  const normalized = normalizeRpps(raw);
  if (!normalized) malformedRpps.value = true;
  else candidates.push(normalized);
}

function collectRppsCandidates(
  claims: UnknownRecord,
  candidates: unknown[],
  malformedRpps: { value: boolean },
): void {
  pushNationalIdCandidate(candidates, malformedRpps, claims.SubjectNameID);
  pushNationalIdCandidate(candidates, malformedRpps, claims.preferred_username);
  pushNationalIdCandidate(
    candidates,
    malformedRpps,
    claims.numeroIdentificationPP,
  );

  const subjectRefPro = asRecord(claims.SubjectRefPro);
  pushNationalIdCandidate(
    candidates,
    malformedRpps,
    subjectRefPro?.numeroIdentificationPP,
  );

  if (Array.isArray(claims.otherIds)) {
    for (const rawOtherId of claims.otherIds) {
      const otherId = asRecord(rawOtherId);
      const origin = nonEmptyString(otherId?.origine)?.toUpperCase();
      if (origin !== "RPPS") continue;
      const raw = nonEmptyString(otherId?.identifiant);
      if (!raw) {
        malformedRpps.value = true;
        continue;
      }
      const normalized = normalizeRpps(raw);
      if (!normalized) malformedRpps.value = true;
      else candidates.push(normalized);
    }
  }
}

/**
 * Retourne une preuve RPPS uniquement pour un identifiant complet et valide.
 * Toute contradiction entre deux claims RPPS authentifiés invalide la preuve.
 */
export function extractRppsEvidence(
  ...claimSets: Array<UnknownRecord | null | undefined>
): RppsEvidence {
  const candidates: unknown[] = [];
  const malformedRpps = { value: false };
  for (const claims of claimSets) {
    if (claims) collectRppsCandidates(claims, candidates, malformedRpps);
  }
  if (malformedRpps.value) return { status: "invalid" };
  const unique = [...new Set(candidates as string[])];
  if (unique.length === 0) return { status: "absent" };
  if (unique.length !== 1) return { status: "invalid" };
  return { status: "verified", rpps: unique[0] };
}

function normalizeEmail(value: unknown): string | null {
  const email = nonEmptyString(value)?.toLowerCase() ?? null;
  if (!email || email.length > 254) return null;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

/**
 * L'email n'est une clé de rapprochement que si l'émetteur OIDC a fourni le
 * booléen strict `email_verified: true`. Une chaîne "true" ne suffit pas.
 */
export function extractVerifiedEmail(
  ...claimSets: Array<UnknownRecord | null | undefined>
): EmailEvidence {
  const observedEmails: string[] = [];
  const verifiedEmails: string[] = [];
  let hasEmailClaim = false;
  let hasExplicitUnverifiedClaim = false;

  for (const claims of claimSets) {
    if (
      !claims || claims.email === undefined || claims.email === null ||
      claims.email === ""
    ) continue;
    hasEmailClaim = true;
    const email = normalizeEmail(claims.email);
    if (!email) return { status: "invalid" };
    observedEmails.push(email);
    if (claims.email_verified === true) verifiedEmails.push(email);
    if (claims.email_verified === false) hasExplicitUnverifiedClaim = true;
  }

  if (!hasEmailClaim) return { status: "absent" };
  if (new Set(observedEmails).size !== 1) return { status: "invalid" };
  if (verifiedEmails.length === 0) return { status: "unverified" };
  if (hasExplicitUnverifiedClaim) return { status: "invalid" };
  if (new Set(verifiedEmails).size !== 1) return { status: "invalid" };
  return { status: "verified", email: verifiedEmails[0] };
}

/** PSC code 60 atteste la profession infirmière, pas la spécialité IADE/IBODE. */
export function isProfessionCompatible(
  existing: unknown,
  pscProfession: JoleneProfession,
): boolean {
  if (existing === pscProfession) return true;
  return pscProfession === "IDE" &&
    (existing === "IADE" || existing === "IBODE");
}
