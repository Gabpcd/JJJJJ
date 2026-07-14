import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { errorResponse, safeStringifyError } from '../_shared/errors.ts';
import { corsHeaders, jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';
import {
  normalizeProfessionalIdentifier,
  personNameMatches,
  professionalIdentifierMatches,
} from '../_shared/verification-rules.ts';

const FHIR_ENDPOINT = 'https://gateway.api.esante.gouv.fr/fhir/v2/Practitioner';
const IDNPS_SYSTEM = 'urn:oid:1.2.250.1.71.4.2.1';
const G15_SYSTEM_FRAGMENT = 'TRE_G15-ProfessionSante';
const G15_OID = '1.2.250.1.71.1.2.7';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type IdentifierType = 'RPPS' | 'ADELI';

// Source primaire : TRE_G15-ProfessionSante (ANS). En particulier, le code 40
// désigne un chirurgien-dentiste et le code 86 un technicien de laboratoire.
const PROFESSION_INTERNE_PAR_CODE: Readonly<Record<string, string>> = {
  '10': 'MEDECIN',
  '21': 'PHARMACIEN',
  '26': 'AUDIOPROTHESISTE',
  '28': 'OPTICIEN',
  '31': 'ASSISTANT_DENTAIRE',
  '32': 'PHYSICIEN_MEDICAL',
  '35': 'AS',
  '36': 'AMBULANCIER',
  '37': 'AUXILIAIRE_PUERICULTURE',
  '38': 'PREPARATEUR_PHARMA',
  '39': 'PREPARATEUR_PHARMA',
  '40': 'DENTISTE',
  '50': 'SAGE_FEMME',
  '60': 'IDE',
  '69': 'IDE',
  '70': 'KINE',
  '80': 'PEDICURE',
  '86': 'TECHNICIEN_LABO',
  '91': 'ORTHOPHONISTE',
  '92': 'ORTHOPTISTE',
  '94': 'ERGOTHERAPEUTE',
  '95': 'DIETETICIEN',
  '96': 'PSYCHOMOTRICIEN',
  '98': 'MANIPULATEUR_RADIO',
};

const CODES_COMPATIBLES_PAR_PROFESSION: Readonly<Record<string, readonly string[]>> = {
  MEDECIN: ['10'],
  PHARMACIEN: ['21'],
  AUDIOPROTHESISTE: ['26'],
  OPTICIEN: ['28'],
  AS: ['35'],
  AUXILIAIRE_PUERICULTURE: ['37'],
  PREPARATEUR_PHARMA: ['38', '39'],
  DENTISTE: ['40'],
  SAGE_FEMME: ['50'],
  IDE: ['60', '69'],
  IBODE: ['60', '69'],
  IADE: ['60', '69'],
  KINE: ['70'],
  ORTHOPHONISTE: ['91'],
  ERGOTHERAPEUTE: ['94'],
  DIETETICIEN: ['95'],
  PSYCHOMOTRICIEN: ['96'],
  MANIPULATEUR_RADIO: ['98'],
};

interface FhirIdentifier {
  system?: string;
  value?: string;
}

interface FhirCoding {
  system?: string;
  code?: string;
  display?: string;
}

interface FhirPractitioner {
  resourceType?: string;
  active?: boolean;
  identifier?: FhirIdentifier[];
  name?: Array<{ use?: string; family?: string; given?: string[] }>;
  qualification?: Array<{ code?: { coding?: FhirCoding[] } }>;
}

interface AnnuaireResult {
  trouve: boolean;
  nom: string;
  prenom: string;
  professionCodes: string[];
  professionLabels: string[];
  professionsInternes: string[];
  specialiteCode: string | null;
  specialiteLabel: string | null;
  actif: boolean;
  source: string;
}

interface SoignantProfile {
  id: string;
  numero_rpps: string | null;
  numero_adeli: string | null;
  prenom: string | null;
  nom: string | null;
  profession: string | null;
  supprime_le: string | null;
  est_compte_test: boolean | null;
}

function matchNullableSnapshot(query: any, column: string, value: string | null) {
  return value === null ? query.is(column, null) : query.eq(column, value);
}

async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].slice(0, 16)
    .map((octet) => octet.toString(16).padStart(2, '0')).join('');
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs = 8_000): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function stringValue(value: unknown, maxLength = 200): string {
  return typeof value === 'string' ? value.trim().slice(0, maxLength) : '';
}

function buildFhirIdentifier(numero: string, type: IdentifierType): string {
  return `${type === 'RPPS' ? '8' : '0'}${numero}`;
}

function buildFhirIdentifierQuery(numero: string, type: IdentifierType): string {
  return `${IDNPS_SYSTEM}|${buildFhirIdentifier(numero, type)}`;
}

function identifierExact(practitioner: FhirPractitioner, numero: string, type: IdentifierType): boolean {
  const expected = buildFhirIdentifier(numero, type);
  return (practitioner.identifier || []).some((identifier) =>
    stringValue(identifier.system, 250).replace(/\/$/, '').toLowerCase() === IDNPS_SYSTEM
    && stringValue(identifier.value, 30) === expected
  );
}

function isProfessionCoding(coding: FhirCoding): boolean {
  const system = stringValue(coding.system, 300);
  return system.includes(G15_SYSTEM_FRAGMENT) || system.includes(G15_OID);
}

function extractAnnuaireResult(practitioner: FhirPractitioner, source: string): AnnuaireResult {
  const officialName = practitioner.name?.find((name) => name.use === 'official') || practitioner.name?.[0];
  const professionCodes: string[] = [];
  const professionLabels: string[] = [];
  let specialiteCode: string | null = null;
  let specialiteLabel: string | null = null;

  for (const qualification of practitioner.qualification || []) {
    for (const coding of qualification.code?.coding || []) {
      const code = stringValue(coding.code, 40);
      if (!code) continue;
      if (isProfessionCoding(coding) && /^\d{2}$/.test(code)) {
        if (!professionCodes.includes(code)) professionCodes.push(code);
        const label = stringValue(coding.display, 200);
        if (label && !professionLabels.includes(label)) professionLabels.push(label);
      } else if (!specialiteCode && /^(SM|SC|SF|SI)\d+$/i.test(code)) {
        specialiteCode = code;
        specialiteLabel = stringValue(coding.display, 200) || null;
      }
    }
  }

  return {
    trouve: true,
    nom: stringValue(officialName?.family, 120),
    prenom: (officialName?.given || []).map((item) => stringValue(item, 120)).filter(Boolean).join(' '),
    professionCodes,
    professionLabels,
    professionsInternes: professionCodes
      .map((code) => PROFESSION_INTERNE_PAR_CODE[code])
      .filter((value): value is string => !!value),
    specialiteCode,
    specialiteLabel,
    actif: practitioner.active === true,
    source,
  };
}

async function queryFhirAnnuaire(
  numero: string,
  type: IdentifierType,
  apiKey: string,
): Promise<AnnuaireResult> {
  const identifierParam = buildFhirIdentifierQuery(numero, type);
  const response = await fetchWithTimeout(
    `${FHIR_ENDPOINT}?identifier=${encodeURIComponent(identifierParam)}`,
    { headers: { Accept: 'application/fhir+json', 'ESANTE-API-KEY': apiKey } },
  );
  if (!response.ok) {
    const body = await response.text();
    console.error(`[verify-rpps] FHIR HTTP ${response.status}:`, body.slice(0, 300));
    throw new Error(`Annuaire Santé indisponible (HTTP ${response.status})`);
  }

  const bundle = await response.json() as { entry?: Array<{ resource?: FhirPractitioner }> };
  const exactPractitioners = (bundle.entry || [])
    .map((entry) => entry.resource)
    .filter((resource): resource is FhirPractitioner =>
      resource?.resourceType === 'Practitioner'
      && identifierExact(resource, numero, type)
    );
  if (exactPractitioners.length === 0) {
    return {
      trouve: false,
      nom: '',
      prenom: '',
      professionCodes: [],
      professionLabels: [],
      professionsInternes: [],
      specialiteCode: null,
      specialiteLabel: null,
      actif: false,
      source: 'FHIR Annuaire Santé v2',
    };
  }

  const practitioner = exactPractitioners.find((item) => item.active === true) || exactPractitioners[0];
  return extractAnnuaireResult(practitioner, 'FHIR Annuaire Santé v2');
}

function professionCompatible(profession: string, result: AnnuaireResult): boolean {
  const declared = profession.toUpperCase().trim();
  const expectedCodes = CODES_COMPATIBLES_PAR_PROFESSION[declared];
  if (!expectedCodes || expectedCodes.length === 0) return false;
  return result.professionCodes.some((code) => expectedCodes.includes(code))
    || result.professionsInternes.includes(declared);
}

function emptyResult(source: string): AnnuaireResult {
  return {
    trouve: false,
    nom: '',
    prenom: '',
    professionCodes: [],
    professionLabels: [],
    professionsInternes: [],
    specialiteCode: null,
    specialiteLabel: null,
    actif: false,
    source,
  };
}

async function queryDemoProfile(
  supabaseUrl: string,
  serviceRoleKey: string,
  profile: SoignantProfile,
  numero: string,
  type: IdentifierType,
): Promise<AnnuaireResult | null> {
  const demoIdentifiersEnabled = Deno.env.get('ALLOW_DEMO_IDENTIFIERS') === 'true';
  if (
    type !== 'RPPS'
    || !demoIdentifiersEnabled
    || profile.est_compte_test !== true
  ) return null;

  if (numero === '00000000001') {
    return {
      ...emptyResult('Mode test contrôlé'),
      trouve: true,
      nom: 'PICARD',
      prenom: 'Gabrielle',
      professionsInternes: ['IDE'],
      actif: true,
    };
  }
  if (!numero.startsWith('00100')) return null;

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await admin.from('rpps_test')
    .select('rpps, prenom, nom, profession, specialite_medicale')
    .eq('rpps', numero)
    .maybeSingle();
  if (error) throw new Error(`Lecture rpps_test impossible: ${error.code || error.message}`);
  if (!data) return emptyResult('Mode test contrôlé');
  const profession = stringValue(data.profession, 80).toUpperCase();
  return {
    ...emptyResult('Mode test contrôlé'),
    trouve: true,
    nom: stringValue(data.nom, 120),
    prenom: stringValue(data.prenom, 120),
    professionsInternes: profession ? [profession] : [],
    specialiteCode: stringValue(data.specialite_medicale, 80) || null,
    specialiteLabel: stringValue(data.specialite_medicale, 200) || null,
    actif: true,
  };
}

async function setVerificationFalse(
  supabaseUrl: string,
  serviceRoleKey: string,
  profile: SoignantProfile,
  numero: string,
  type: IdentifierType,
): Promise<boolean> {
  const fields = type === 'RPPS'
    ? { rpps_verifie: false, rpps_verifie_le: null, tous_documents_valides: false }
    : { adeli_verifie: false, adeli_verifie_le: null, tous_documents_valides: false };
  const numberColumn = type === 'RPPS' ? 'numero_rpps' : 'numero_adeli';
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await admin.from('soignants')
    .update(fields)
    .eq('id', profile.id)
    .eq(numberColumn, numero)
    .select('id')
    .maybeSingle();
  if (error || !data) {
    console.error('[verify-rpps] révocation impossible:', error?.code || error?.message || 'ROW_NOT_FOUND');
    return false;
  }
  const { error: recalcError } = await admin.rpc(
    'fn_calculer_tous_documents_valides',
    { p_soignant_id: profile.id },
  );
  if (recalcError) {
    // Le cache a deja ete positionne a false par l'UPDATE ci-dessus : une
    // panne de recalcul reste donc fail-closed, sans restaurer une preuve radiee.
    console.error('[verify-rpps] recalcul documentaire impossible:', recalcError.code || recalcError.message);
  }
  return true;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);
  if (req.method !== 'POST') {
    return jsonResponse(req, { ok: false, code: 'METHOD_NOT_ALLOWED', error: 'Méthode non autorisée' }, 405);
  }

  const cors = corsHeaders(req);
  const clientIp = getClientIp(req);
  if (applyRateLimit('verify-rpps', clientIp, { max: 10, windowMs: 60_000 })) {
    return errorResponse(cors, 429, 'RATE_LIMITED', 'Trop de requêtes. Réessayez dans une minute.');
  }

  try {
    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || Array.isArray(body)) {
      return errorResponse(cors, 400, 'INVALID_JSON', 'Corps JSON invalide.');
    }

    if (body.warm === true) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) return errorResponse(cors, adminAuth.status, 'UNAUTHORIZED', adminAuth.error);
      return jsonResponse(req, {
        ok: true,
        warm: true,
        configured: !!Deno.env.get('ESANTE_FHIR_API_KEY'),
        endpoint: FHIR_ENDPOINT,
      });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
    const publishableKey = Deno.env.get('SUPABASE_PUBLISHABLE_KEY') || Deno.env.get('SB_PUBLISHABLE_KEY') || '';
    if (!supabaseUrl || !serviceRoleKey) {
      return errorResponse(cors, 503, 'SERVER_NOT_CONFIGURED', 'Service de vérification indisponible.');
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const authHeader = req.headers.get('Authorization') || '';
    const bearer = authHeader.replace(/^Bearer\s+/i, '').trim();
    const isPublicCredential = !bearer || bearer === anonKey || (!!publishableKey && bearer === publishableKey);
    let callerId: string | null = null;
    let isServiceRole = false;
    if (!isPublicCredential) {
      const auth = await verifyUserOrServiceRole(req);
      if (!auth.ok) return errorResponse(cors, auth.status, 'UNAUTHORIZED', auth.error);
      callerId = auth.userId;
      isServiceRole = auth.isServiceRole;
    }

    const soignantId = stringValue(body.soignant_id, 50) || null;
    if (soignantId && !UUID_RE.test(soignantId)) {
      return errorResponse(cors, 400, 'SOIGNANT_ID_INVALID', 'Identifiant soignant invalide.');
    }

    let profile: SoignantProfile | null = null;
    if (soignantId) {
      if (isPublicCredential) {
        return errorResponse(cors, 401, 'AUTH_REQUIRED', 'Une session utilisateur est requise.');
      }
      if (!isServiceRole && callerId !== soignantId) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return errorResponse(cors, adminAuth.status, 'FORBIDDEN', adminAuth.error);
      }

      const { data, error } = await admin.from('soignants')
        .select('id, numero_rpps, numero_adeli, prenom, nom, profession, supprime_le, est_compte_test')
        .eq('id', soignantId)
        .maybeSingle();
      if (error) {
        console.error('[verify-rpps] lecture profil impossible:', error.code || error.message);
        return errorResponse(cors, 503, 'PROFILE_READ_FAILED', 'Vérification temporairement indisponible.');
      }
      if (!data || data.supprime_le) {
        return errorResponse(cors, 404, 'PROFILE_NOT_FOUND', 'Profil soignant introuvable.');
      }
      profile = data as SoignantProfile;
    }

    if (!isServiceRole) {
      const rateIdentity = callerId
        ? `user|${callerId}`
        : `public|${clientIp === 'unknown' ? (req.headers.get('user-agent') || '').slice(0, 160) : clientIp}`;
      const { data: allowed, error: rateError } = await admin.rpc('fn_verifier_rate_limit', {
        p_cle: await fingerprint(rateIdentity),
        p_action: 'edge_verify_rpps',
        p_max_tentatives: 30,
        p_fenetre_secondes: 600,
      });
      if (rateError) {
        console.error('[verify-rpps] rate-limit persistant indisponible:', rateError.code || rateError.message);
        return errorResponse(cors, 503, 'RATE_LIMIT_UNAVAILABLE', 'Service temporairement indisponible.');
      }
      if (allowed !== true) {
        return errorResponse(cors, 429, 'RATE_LIMITED', 'Quota de vérification atteint.');
      }
    }

    const requestedRpps = (stringValue(body.numero_rpps, 30) || stringValue(body.rpps, 30)).replace(/\s/g, '');
    const requestedAdeli = (stringValue(body.numero_adeli, 30) || stringValue(body.adeli, 30)).replace(/\s/g, '');
    if (requestedRpps && requestedAdeli) {
      return errorResponse(cors, 400, 'IDENTIFIER_AMBIGUOUS', 'Fournissez un RPPS ou un ADELI, pas les deux.');
    }

    let type: IdentifierType;
    let numero: string;
    let nom: string;
    let prenom: string;
    let profession: string;
    if (profile) {
      const persistedRpps = normalizeProfessionalIdentifier(profile.numero_rpps);
      const persistedAdeli = normalizeProfessionalIdentifier(profile.numero_adeli);
      type = requestedAdeli ? 'ADELI' : requestedRpps ? 'RPPS' : persistedRpps ? 'RPPS' : 'ADELI';
      numero = type === 'RPPS' ? persistedRpps : persistedAdeli;
      const requested = type === 'RPPS' ? requestedRpps : requestedAdeli;
      if (
        requested
        && (requested !== numero || professionalIdentifierMatches(numero, requested) !== true)
      ) {
        return errorResponse(cors, 409, 'IDENTIFIER_PROFILE_MISMATCH', 'Le numéro demandé ne correspond pas au profil.');
      }
      nom = stringValue(profile.nom, 120);
      prenom = stringValue(profile.prenom, 120);
      profession = stringValue(profile.profession, 80).toUpperCase();
    } else {
      type = requestedAdeli ? 'ADELI' : 'RPPS';
      numero = type === 'RPPS' ? requestedRpps : requestedAdeli;
      nom = stringValue(body.nom, 120);
      prenom = stringValue(body.prenom, 120);
      profession = stringValue(body.profession, 80).toUpperCase();
    }

    const expectedLength = type === 'RPPS' ? 11 : 9;
    if (!new RegExp(`^\\d{${expectedLength}}$`).test(numero)) {
      return errorResponse(
        cors,
        400,
        `${type}_FORMAT_INVALID`,
        `Numéro ${type} invalide : ${expectedLength} chiffres attendus.`,
      );
    }
    if (!nom || !prenom) {
      if (profile && !(await setVerificationFalse(supabaseUrl, serviceRoleKey, profile, numero, type))) {
        return errorResponse(cors, 503, 'VERIFICATION_STATE_UPDATE_FAILED', 'Impossible de sécuriser l’état de vérification.');
      }
      return errorResponse(cors, 422, 'IDENTITY_INCOMPLETE', 'Le nom et le prénom complets sont requis.');
    }
    if (!profession || !CODES_COMPATIBLES_PAR_PROFESSION[profession]) {
      if (profile && !(await setVerificationFalse(supabaseUrl, serviceRoleKey, profile, numero, type))) {
        return errorResponse(cors, 503, 'VERIFICATION_STATE_UPDATE_FAILED', 'Impossible de sécuriser l’état de vérification.');
      }
      return errorResponse(cors, 422, 'PROFESSION_UNSUPPORTED', 'La profession du profil ne permet pas une vérification automatique.');
    }

    let result: AnnuaireResult | null = profile
      ? await queryDemoProfile(supabaseUrl, serviceRoleKey, profile, numero, type)
      : null;
    if (!result) {
      const apiKey = Deno.env.get('ESANTE_FHIR_API_KEY') || '';
      if (!apiKey) {
        return errorResponse(cors, 503, 'RPPS_API_UNAVAILABLE', 'Annuaire Santé temporairement indisponible.');
      }
      try {
        result = await queryFhirAnnuaire(numero, type, apiKey);
      } catch (error) {
        console.error('[verify-rpps] appel Annuaire Santé impossible:', safeStringifyError(error));
        return errorResponse(cors, 503, 'RPPS_API_UNAVAILABLE', 'Annuaire Santé temporairement indisponible.');
      }
    }

    const codePrefix = type;
    if (!result.trouve) {
      if (profile && !(await setVerificationFalse(supabaseUrl, serviceRoleKey, profile, numero, type))) {
        return errorResponse(cors, 503, 'VERIFICATION_STATE_UPDATE_FAILED', 'Impossible de sécuriser l’état de vérification.');
      }
      return jsonResponse(req, {
        ok: true,
        code: `${codePrefix}_NOT_FOUND`,
        type,
        trouve: false,
        correspond: false,
        correspond_traits: false,
        profession_correspond: false,
        actif: false,
        source: result.source,
      });
    }

    const identityComplete = !!result.nom && !!result.prenom;
    const traitsMatch = identityComplete
      && personNameMatches(nom, prenom, result.nom, result.prenom) === true;
    const professionMatch = professionCompatible(profession, result);
    const actif = result.actif === true;
    const correspond = actif && traitsMatch && professionMatch;

    if (profile && !correspond && !(await setVerificationFalse(supabaseUrl, serviceRoleKey, profile, numero, type))) {
      return errorResponse(cors, 503, 'VERIFICATION_STATE_UPDATE_FAILED', 'Impossible de sécuriser l’état de vérification.');
    }

    // Statut actif manquant ou faux : échec HTTP explicite. Le service
    // d'inscription appelant ne doit jamais confondre « trouvé » avec « autorisé
    // à exercer » et promouvoir le profil sur la seule présence dans l'annuaire.
    if (!actif) {
      return jsonResponse(req, {
        ok: false,
        code: `${codePrefix}_INACTIVE`,
        message: `Ce numéro ${type} correspond à un professionnel inactif.`,
        error: `Ce numéro ${type} correspond à un professionnel inactif.`,
        type,
        trouve: true,
        correspond: false,
        correspond_traits: traitsMatch,
        profession_correspond: professionMatch,
        actif: false,
        source: result.source,
      }, 422);
    }

    if (profile && correspond) {
      const now = new Date().toISOString();
      const fields: Record<string, unknown> = type === 'RPPS'
        ? {
            rpps_verifie: true,
            rpps_verifie_le: now,
            rpps_nom_api: result.nom,
            rpps_prenom_api: result.prenom,
            rpps_profession_api: result.professionLabels[0]
              || result.professionsInternes[0]
              || null,
          }
        : {
            adeli_verifie: true,
            adeli_verifie_le: now,
            adeli_nom_api: result.nom,
            adeli_prenom_api: result.prenom,
            adeli_profession_api: result.professionLabels[0]
              || result.professionsInternes[0]
              || null,
          };
      if (result.specialiteCode) {
        fields.specialite_medicale = result.specialiteCode;
        fields.specialite_code = result.specialiteCode;
        fields.specialite_source = 'RPPS';
        fields.specialite_verifiee = true;
        fields.specialite_verifiee_le = now;
      }
      const numberColumn = type === 'RPPS' ? 'numero_rpps' : 'numero_adeli';
      const persistedNumber = type === 'RPPS' ? profile.numero_rpps : profile.numero_adeli;
      let updateQuery = admin.from('soignants')
        .update(fields)
        .eq('id', profile.id)
        .is('supprime_le', null);
      updateQuery = matchNullableSnapshot(updateQuery, numberColumn, persistedNumber);
      updateQuery = matchNullableSnapshot(updateQuery, 'prenom', profile.prenom);
      updateQuery = matchNullableSnapshot(updateQuery, 'nom', profile.nom);
      updateQuery = matchNullableSnapshot(updateQuery, 'profession', profile.profession);
      const { data, error } = await updateQuery
        .select('id')
        .maybeSingle();
      if (error || !data) {
        console.error('[verify-rpps] sauvegarde impossible ou profil modifié:', error?.code || error?.message || 'SNAPSHOT_CHANGED');
        return errorResponse(cors, 409, 'PROFILE_CHANGED_DURING_VERIFICATION',
          'Le profil a changé pendant la vérification. Relancez le contrôle.');
      }
    }

    const code = !traitsMatch
      ? `${codePrefix}_TRAITS_MISMATCH`
      : !professionMatch
        ? `${codePrefix}_PROFESSION_MISMATCH`
        : `${codePrefix}_OK`;
    return jsonResponse(req, {
      ok: true,
      code,
      type,
      trouve: true,
      correspond,
      correspond_traits: traitsMatch,
      profession_correspond: professionMatch,
      profession_declaree: profession,
      nom_api: result.nom || null,
      prenom_api: result.prenom || null,
      profession_api: result.professionLabels[0]
        || result.professionsInternes[0]
        || null,
      profession_code: result.professionCodes[0] || null,
      specialite_code: result.specialiteCode,
      specialite_label: result.specialiteLabel,
      actif,
      source: result.source,
    });
  } catch (error) {
    console.error('[verify-rpps] erreur inattendue:', safeStringifyError(error));
    return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur serveur. Réessayez dans quelques minutes.');
  }
});
