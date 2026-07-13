// verify-finess — Vérification FINESS établissement via l'API FHIR Annuaire Santé.
//
// Deux usages sont volontairement distincts :
//   - sans etablissement_id : aperçu public en lecture seule pendant l'inscription ;
//   - avec etablissement_id : vérification authentifiée, recoupée avec le profil
//     courant avant toute écriture de finess_verifie.

import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { canManageEstablishment } from '../_shared/etablissement-auth.ts';
import { corporateNameMatches, normalizeVerificationText } from '../_shared/verification-rules.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';

async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].slice(0, 16)
    .map((octet) => octet.toString(16).padStart(2, '0')).join('');
}

async function fetchWithTimeout(url: string, init: RequestInit, ms: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

const GATEWAY = 'https://gateway.api.esante.gouv.fr/fhir/v2/Organization';
const FINESS_SYSTEM = 'https://finess.esante.gouv.fr';
const SIRENE_SYSTEM = 'https://sirene.fr';
const SYS_SECTEUR = 'TRE_R02-SecteurActivite';
const SYS_CATEGORIE = 'TRE_R66-CategorieEtablissement';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface FhirIdentifier {
  system?: string;
  value?: string;
  type?: { coding?: Array<{ code?: string; display?: string }> };
}

interface FhirOrganization {
  resourceType?: string;
  identifier?: FhirIdentifier[];
  name?: string;
  active?: boolean;
  address?: Array<{ line?: string[]; city?: string; postalCode?: string }>;
  type?: Array<{ coding?: Array<{ system?: string; code?: string; display?: string }> }>;
  partOf?: { reference?: string };
}

interface FinessResult {
  trouve: boolean;
  raison_sociale?: string | null;
  actif?: boolean;
  adresse?: { ligne?: string; ville?: string; cp?: string } | null;
  siret?: string | null;
  categorie_code?: string | null;
  categorie_label?: string | null;
  secteur_code?: string | null;
  secteur_label?: string | null;
  est_public?: boolean;
  ej_reference?: string | null;
}

interface EtablissementCourant {
  id: string;
  verification_source_version: number | string;
  nom: string | null;
  finess: string | null;
  siret: string | null;
  siret_verifie: boolean | null;
  siret_raison_sociale: string | null;
  adresse_rue: string | null;
  adresse_ville: string | null;
  adresse_code_postal: string | null;
}

interface RecoupementFiness {
  coherent: boolean;
  mode: 'SIRET_EXACT' | 'RAISON_SOCIALE_ADRESSE' | null;
  motif: string | null;
  siret_verifie: boolean;
  siret_correspond: boolean | null;
  raison_sociale_correspond: boolean | null;
  code_postal_correspond: boolean | null;
  localite_correspond: boolean | null;
  adresse_correspond: boolean | null;
}

function digits(value: unknown): string {
  return String(value ?? '').replace(/\D/g, '');
}

function identifierTypeContains(identifier: FhirIdentifier, expected: string): boolean {
  const needle = expected.toUpperCase();
  return (identifier.type?.coding || []).some((coding) =>
    String(coding.code || '').toUpperCase() === needle
    || String(coding.display || '').toUpperCase().includes(needle)
  );
}

function isFinessIdentifier(identifier: FhirIdentifier, expectedFiness: string): boolean {
  const system = String(identifier.system || '').toLowerCase().replace(/\/$/, '');
  const systemIsFiness = system === FINESS_SYSTEM || system.includes('finess');
  return systemIsFiness && digits(identifier.value) === expectedFiness;
}

function extractSiret(org: FhirOrganization): string | null {
  for (const identifier of org.identifier || []) {
    const value = digits(identifier.value);
    if (value.length !== 14) continue;
    const system = String(identifier.system || '').toLowerCase().replace(/\/$/, '');
    if (system === SIRENE_SYSTEM || system.includes('siret') || identifierTypeContains(identifier, 'SIRET')) {
      return value;
    }
  }
  return null;
}

function exactNormalizedText(a: unknown, b: unknown): boolean | null {
  const left = normalizeVerificationText(a);
  const right = normalizeVerificationText(b);
  if (!left || !right) return null;
  return left === right;
}

const ADDRESS_STOP_WORDS = new Set([
  'rue', 'avenue', 'av', 'boulevard', 'bd', 'route', 'chemin', 'allee', 'place',
  'impasse', 'de', 'du', 'des', 'la', 'le', 'les', 'l', 'd', 'cedex',
]);

function addressTokens(value: unknown): string[] {
  return normalizeVerificationText(value).split(' ')
    .filter((token) => token.length >= 2 && !ADDRESS_STOP_WORDS.has(token));
}

function addressLineMatches(a: unknown, b: unknown): boolean | null {
  const left = addressTokens(a);
  const right = addressTokens(b);
  if (left.length === 0 || right.length === 0) return null;
  const leftSet = new Set(left);
  const rightSet = new Set(right);
  const smaller = left.length <= right.length ? leftSet : rightSet;
  const larger = left.length <= right.length ? rightSet : leftSet;
  return [...smaller].every((token) => larger.has(token));
}

function recouperAvecEtablissement(
  etablissement: EtablissementCourant,
  result: FinessResult,
): RecoupementFiness {
  const currentSiret = digits(etablissement.siret);
  const fhirSiret = digits(result.siret);
  const siretCorrespond = fhirSiret.length === 14 && currentSiret.length === 14
    ? fhirSiret === currentSiret
    : null;

  const nameCandidates = [etablissement.siret_raison_sociale, etablissement.nom]
    .filter((value): value is string => !!value?.trim());
  const nameVerdicts = nameCandidates.map((candidate) =>
    corporateNameMatches(candidate, result.raison_sociale)
  );
  const raisonSocialeCorrespond = nameVerdicts.some((value) => value === true)
    ? true
    : nameVerdicts.some((value) => value === false) ? false : null;

  const currentPostalCode = digits(etablissement.adresse_code_postal);
  const fhirPostalCode = digits(result.adresse?.cp);
  const codePostalCorrespond = currentPostalCode.length === 5
      && currentPostalCode !== '00000'
      && fhirPostalCode.length === 5
    ? currentPostalCode === fhirPostalCode
    : null;
  const localiteCorrespond = exactNormalizedText(etablissement.adresse_ville, result.adresse?.ville);
  const ligneCorrespond = addressLineMatches(etablissement.adresse_rue, result.adresse?.ligne);
  const adresseCorrespond = codePostalCorrespond === true
    && ligneCorrespond === true
    && localiteCorrespond !== false;

  const siretVerifie = etablissement.siret_verifie === true;
  const contradictionSiret = siretCorrespond === false;
  const lienSiretFort = siretVerifie && siretCorrespond === true;
  // Une concordance de nom/adresse reste un signal utile pour la revue, mais
  // ne suffit jamais à auto-valider un FINESS : plusieurs sites d'un même
  // groupe peuvent partager un libellé et une adresse proche. Le rattachement
  // automatique exige le SIRET exact publié par l'Annuaire Santé.
  const coherent = lienSiretFort;
  const mode = lienSiretFort ? 'SIRET_EXACT' : null;

  let motif: string | null = null;
  if (!siretVerifie) {
    motif = "Le SIRET de l'établissement doit d'abord être vérifié.";
  } else if (contradictionSiret) {
    motif = "Le SIRET publié pour ce FINESS ne correspond pas à l'établissement.";
  } else if (!coherent) {
    motif = "L'Annuaire Santé ne publie pas un SIRET exact permettant de relier automatiquement ce FINESS à l'établissement ; une revue est requise.";
  }

  return {
    coherent,
    mode,
    motif,
    siret_verifie: siretVerifie,
    siret_correspond: siretCorrespond,
    raison_sociale_correspond: raisonSocialeCorrespond,
    code_postal_correspond: codePostalCorrespond,
    localite_correspond: localiteCorrespond,
    adresse_correspond: adresseCorrespond,
  };
}

async function queryFiness(finess: string, apiKey: string): Promise<FinessResult> {
  const identifier = `${FINESS_SYSTEM}|${finess}`;
  const url = `${GATEWAY}?identifier=${encodeURIComponent(identifier)}`;
  const response = await fetchWithTimeout(url, {
    headers: { Accept: 'application/fhir+json', 'ESANTE-API-KEY': apiKey },
  }, 9000);
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Annuaire Sante indisponible (HTTP ${response.status}): ${body.slice(0, 200)}`);
  }

  const bundle = await response.json() as {
    entry?: Array<{ resource?: FhirOrganization }>;
  };
  const exactOrganizations = (bundle.entry || [])
    .map((entry) => entry.resource)
    .filter((resource): resource is FhirOrganization =>
      resource?.resourceType === 'Organization'
      && (resource.identifier || []).some((id) => isFinessIdentifier(id, finess))
    );
  if (exactOrganizations.length === 0) return { trouve: false };

  // En cas de doublon historique, préférer explicitement la ressource active.
  const org = exactOrganizations.find((resource) => resource.active === true) || exactOrganizations[0];
  const firstAddress = org.address?.[0];
  const adresse = firstAddress
    ? {
        ligne: (firstAddress.line || []).join(' ') || undefined,
        ville: firstAddress.city,
        cp: firstAddress.postalCode,
      }
    : null;

  let categorieCode: string | null = null;
  let categorieLabel: string | null = null;
  let secteurCode: string | null = null;
  let secteurLabel: string | null = null;
  for (const type of org.type || []) {
    for (const coding of type.coding || []) {
      const system = String(coding.system || '');
      if (system.includes(SYS_CATEGORIE) && !categorieCode) {
        categorieCode = coding.code || null;
        categorieLabel = coding.display || null;
      }
      if (system.includes(SYS_SECTEUR) && !secteurCode) {
        secteurCode = coding.code || null;
        secteurLabel = coding.display || null;
      }
    }
  }
  const estPublic = secteurCode === 'SA01' || /public/i.test(secteurLabel || '');

  return {
    trouve: true,
    raison_sociale: org.name || null,
    actif: org.active === true,
    adresse,
    siret: extractSiret(org),
    categorie_code: categorieCode,
    categorie_label: categorieLabel,
    secteur_code: secteurCode,
    secteur_label: secteurLabel,
    est_public: estPublic,
    ej_reference: org.partOf?.reference || null,
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);
  if (req.method !== 'POST') return jsonResponse(req, { ok: false, code: 'METHOD_NOT_ALLOWED', error: 'Methode non autorisee' }, 405);

  const ip = getClientIp(req);
  if (applyRateLimit('verify-finess', ip, { max: 10, windowMs: 60_000 })) {
    return jsonResponse(req, { ok: false, code: 'RATE_LIMITED', error: 'Trop de verifications.' }, 429);
  }

  try {
    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || Array.isArray(body)) {
      return jsonResponse(req, { ok: false, code: 'INVALID_JSON', error: 'Corps JSON invalide' }, 400);
    }

    const apiKey = Deno.env.get('ESANTE_FHIR_API_KEY') || '';
    if (body.warm === true) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) return jsonResponse(req, { ok: false, error: adminAuth.error }, adminAuth.status);
      return jsonResponse(req, { ok: true, warm: true, configured: !!apiKey, endpoint: GATEWAY });
    }

    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    if (!serviceRoleKey || !supabaseUrl) {
      return jsonResponse(req, { ok: false, code: 'SERVER_NOT_CONFIGURED', error: 'Service indisponible' }, 503);
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const finess = digits(body.finess);
    if (finess.length !== 9) {
      return jsonResponse(req, { ok: false, code: 'FINESS_INVALID', error: 'FINESS invalide : 9 chiffres attendus.' }, 400);
    }

    const etablissementId = String(body.etablissement_id || '').trim();
    let etablissement: EtablissementCourant | null = null;
    let callerId: string | null = null;
    let isServiceRole = false;

    if (etablissementId) {
      if (!UUID_RE.test(etablissementId)) {
        return jsonResponse(req, { ok: false, code: 'ETABLISSEMENT_ID_INVALID', error: 'Identifiant établissement invalide.' }, 400);
      }
      const auth = await verifyUserOrServiceRole(req);
      if (!auth.ok) return jsonResponse(req, { ok: false, error: auth.error }, auth.status);
      callerId = auth.userId;
      isServiceRole = auth.isServiceRole;

      if (!auth.isServiceRole && !(await canManageEstablishment(admin, auth.userId, etablissementId))) {
        const adminAuth = await verifyAdminOrServiceRole(req);
        if (!adminAuth.ok) return jsonResponse(req, { ok: false, error: adminAuth.error }, adminAuth.status);
      }

      const { data, error } = await admin.from('etablissements')
        .select('id, verification_source_version, nom, finess, siret, siret_verifie, siret_raison_sociale, adresse_rue, adresse_ville, adresse_code_postal')
        .eq('id', etablissementId)
        .maybeSingle();
      if (error) {
        console.error('[verify-finess] lecture établissement impossible', error.code || error.message);
        return jsonResponse(req, { ok: false, code: 'ETABLISSEMENT_READ_FAILED', error: 'Vérification temporairement indisponible.' }, 503);
      }
      if (!data) {
        return jsonResponse(req, { ok: false, code: 'ETABLISSEMENT_NOT_FOUND', error: 'Établissement introuvable.' }, 404);
      }
      etablissement = data as EtablissementCourant;
    }

    // Quota persistant en plus du garde-fou mémoire. Les appels internes avec
    // service-role sont déjà authentifiés par égalité stricte du secret.
    if (!isServiceRole) {
      const rateIdentity = callerId
        ? `user|${callerId}|${etablissementId || 'preview'}`
        : `public|${ip === 'unknown' ? (req.headers.get('user-agent') || '').slice(0, 160) : ip}`;
      const { data: allowed, error: rateError } = await admin.rpc('fn_verifier_rate_limit', {
        p_cle: await fingerprint(rateIdentity),
        p_action: 'edge_verify_finess',
        p_max_tentatives: 30,
        p_fenetre_secondes: 600,
      });
      if (rateError) {
        console.error('[verify-finess] rate limit persistant indisponible', rateError.code || rateError.message);
        return jsonResponse(req, { ok: false, code: 'RATE_LIMIT_UNAVAILABLE', error: 'Service temporairement indisponible' }, 503);
      }
      if (allowed !== true) {
        return jsonResponse(req, { ok: false, code: 'RATE_LIMITED', error: 'Quota de verification atteint' }, 429);
      }
    }

    if (!apiKey) {
      return jsonResponse(req, {
        ok: false,
        code: 'ANNUAIRE_NOT_CONFIGURED',
        fhir_indisponible: true,
        source: 'Format FINESS valide - vérification ANS différée',
      });
    }

    let result: FinessResult;
    try {
      result = await queryFiness(finess, apiKey);
    } catch (error) {
      console.error('[verify-finess] Annuaire Sante indisponible', error instanceof Error ? error.message : String(error));
      return jsonResponse(req, {
        ok: false,
        code: 'ANNUAIRE_UNAVAILABLE',
        fhir_indisponible: true,
        source: 'Annuaire Santé indisponible',
      });
    }

    const persistVerification = async (verified: boolean, found: boolean): Promise<Response | null> => {
      if (!etablissement || !etablissementId) return null;
      if (!isServiceRole) {
        const encoreGestionnaire = !!callerId
          && await canManageEstablishment(admin, callerId, etablissementId);
        if (!encoreGestionnaire) {
          const adminAuth = await verifyAdminOrServiceRole(req);
          if (!adminAuth.ok) {
            return jsonResponse(req, {
              ok: false,
              code: 'AUTHORIZATION_CHANGED',
              error: "L'autorisation de gérer cet établissement a changé pendant la vérification.",
            }, 403);
          }
        }
      }
      // La RPC verrouille la ligne, vérifie la version observée avant l'appel
      // FHIR, puis remplace le numéro et son verdict dans la même transaction.
      const { data: updated, error: updateError } = await admin.rpc(
        'fn_appliquer_verification_finess_etablissement',
        {
          p_etablissement_id: etablissementId,
          p_version_attendue: Number(etablissement.verification_source_version),
          p_finess_source_attendu: etablissement.finess ?? null,
          p_finess_nouveau: finess,
          p_trouve: found,
          p_verifie: verified,
          p_raison_sociale: found ? result.raison_sociale ?? null : null,
          p_categorie: found ? result.categorie_label ?? null : null,
          p_secteur: found ? result.secteur_label ?? null : null,
          p_est_public: found ? result.est_public ?? null : null,
        },
      );

      if (updateError) {
        console.error('[verify-finess] mise à jour établissement impossible', updateError.code || updateError.message);
        const duplicate = updateError.code === '23505';
        return jsonResponse(req, {
          ok: false,
          code: duplicate ? 'FINESS_ALREADY_USED' : 'FINESS_UPDATE_FAILED',
          error: duplicate
            ? 'Ce numéro FINESS est déjà rattaché à un autre établissement.'
            : "La vérification FINESS n'a pas pu être enregistrée.",
        }, duplicate ? 409 : 503);
      }
      if (updated !== true) {
        return jsonResponse(req, {
          ok: false,
          code: 'VERIFICATION_SOURCE_CHANGED',
          error: 'Le FINESS ou le profil a changé pendant la vérification. Relancez le contrôle.',
        }, 409);
      }
      return null;
    };

    if (!result.trouve) {
      const persistenceError = await persistVerification(false, false);
      if (persistenceError) return persistenceError;
      return jsonResponse(req, {
        ok: true,
        trouve: false,
        finess,
        verifie: false,
        ecrit: !!etablissement,
        revue_manuelle: !!etablissement,
        motif: "FINESS introuvable dans l'Annuaire Santé.",
        source: 'FHIR Annuaire Santé v2 (Organization)',
      });
    }

    // L'aperçu d'inscription reste strictement en lecture seule. Il confirme
    // seulement l'existence et l'activité de la ressource publique.
    if (!etablissement) {
      return jsonResponse(req, {
        ok: true,
        trouve: true,
        finess,
        verifie: result.actif === true,
        ecrit: false,
        raison_sociale: result.raison_sociale,
        actif: result.actif,
        adresse: result.adresse,
        categorie: result.categorie_label,
        secteur: result.secteur_label,
        est_public: result.est_public,
        source: 'FHIR Annuaire Santé v2 (Organization)',
      });
    }

    const recoupement = recouperAvecEtablissement(etablissement, result);
    const verified = result.actif === true && recoupement.coherent;
    const persistenceError = await persistVerification(verified, true);
    if (persistenceError) return persistenceError;

    if (verified) {
      const { error: rattachementError } = await admin.rpc('fn_evaluer_rattachement_etablissement', {
        p_etablissement_id: etablissementId,
      });
      if (rattachementError) {
        // La vérification FINESS est acquise ; la réévaluation du rattachement
        // reste un traitement séparé et ne doit pas inverser ce verdict.
        console.error('[verify-finess] réévaluation rattachement impossible', rattachementError.code || rattachementError.message);
      }
    }

    const motif = result.actif !== true
      ? "Cet établissement n'est pas actif dans l'Annuaire Santé."
      : recoupement.motif;

    return jsonResponse(req, {
      ok: true,
      trouve: true,
      finess,
      verifie: verified,
      ecrit: true,
      revue_manuelle: !verified,
      motif,
      raison_sociale: result.raison_sociale,
      actif: result.actif,
      adresse: result.adresse,
      categorie: result.categorie_label,
      secteur: result.secteur_label,
      est_public: result.est_public,
      mode_recoupement: recoupement.mode,
      recoupement: {
        siret_verifie: recoupement.siret_verifie,
        siret_correspond: recoupement.siret_correspond,
        raison_sociale_correspond: recoupement.raison_sociale_correspond,
        code_postal_correspond: recoupement.code_postal_correspond,
        localite_correspond: recoupement.localite_correspond,
        adresse_correspond: recoupement.adresse_correspond,
      },
      source: 'FHIR Annuaire Santé v2 (Organization)',
    });
  } catch (error) {
    console.error('[verify-finess] erreur', error instanceof Error ? error.message : String(error));
    return jsonResponse(req, {
      ok: false,
      code: 'UNEXPECTED_ERROR',
      fhir_indisponible: true,
      source: 'Erreur appel FHIR',
    }, 500);
  }
});
