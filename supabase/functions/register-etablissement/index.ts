import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { errorResponse, safeStringifyError } from '../_shared/errors.ts';
import { colonnesAttribution, type AttributionInput } from '../_shared/attribution.ts';
import { corsHeaders, preflightResponse } from '../_shared/cors.ts';
import { corporateNameMatches } from '../_shared/verification-rules.ts';

// M7: Rate limiting - 5 requests per IP per 10 minutes
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT = 5;
const RATE_WINDOW_MS = 10 * 60 * 1000;

const TYPES_ETABLISSEMENT = new Set([
  'HOPITAL_PUBLIC', 'CLINIQUE_PRIVEE', 'EHPAD', 'SSIAD', 'HAD',
  'CENTRE_SANTE', 'LABO', 'IME', 'MAS', 'FAM', 'PHARMACIE_OFFICINE',
  'ESPIC', 'CABINET_MEDICAL', 'CABINET_DENTAIRE', 'CABINET_IDEL',
  'CABINET_SAGE_FEMME', 'CABINET_KINE', 'CABINET_ORTHO', 'CABINET_ERGO',
  'CABINET_PSYCHOMOT',
]);

const NAF_SANTE = new Set([
  '86.10Z', '86.21Z', '86.22A', '86.22B', '86.22C', '86.23Z',
  '86.90A', '86.90B', '86.90C', '86.90D', '86.90E', '86.90F',
  '87.10A', '87.10B', '87.10C', '87.20A', '87.20B', '87.30A',
  '87.30B', '87.90A', '87.90B', '88.10A', '88.10B', '88.10C',
  '47.73Z',
]);

type CoherenceIdentite = 'OK' | 'INCOHERENT' | null;

interface RegistreEtablissement {
  siret?: string | null;
  activite_principale?: string | null;
  etat_administratif?: string | null;
}

interface RegistreEntreprise {
  matching_etablissements?: RegistreEtablissement[] | null;
  siege?: RegistreEtablissement | null;
  nom_raison_sociale?: string | null;
  nom_complet?: string | null;
  activite_principale?: string | null;
  nature_juridique?: string | null;
  dirigeants?: unknown[] | null;
}

interface SiretVerification {
  trouve: boolean;
  raison_sociale: string | null;
  est_actif: boolean;
  est_sante: boolean;
  est_public: boolean;
  code_naf: string | null;
  categorie_juridique: string | null;
  dirigeants: unknown[] | null;
}

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
}

interface FinessVerification {
  trouve: boolean;
  raison_sociale: string | null;
  actif: boolean;
  siret: string | null;
  categorie: string | null;
  secteur: string | null;
  est_public: boolean;
}

function texte(value: unknown, maxLength: number): string {
  return typeof value === 'string' ? value.trim().slice(0, maxLength) : '';
}

function chiffres(value: unknown): string {
  return typeof value === 'string' ? value.replace(/\D/g, '') : '';
}

function siretLuhnValide(siret: string): boolean {
  if (!/^\d{14}$/.test(siret) || /^0+$/.test(siret)) return false;
  let somme = 0;
  for (let index = 0; index < siret.length; index += 1) {
    let chiffre = Number(siret[index]);
    if (index % 2 === 0) {
      chiffre *= 2;
      if (chiffre > 9) chiffre -= 9;
    }
    somme += chiffre;
  }
  return somme % 10 === 0;
}

function normaliserNaf(value: unknown): string {
  const brut = texte(value, 8).toUpperCase();
  return brut.length === 5 && !brut.includes('.')
    ? `${brut.slice(0, 2)}.${brut.slice(2)}`
    : brut;
}

function trouverSiretExact(
  resultats: RegistreEntreprise[],
  siret: string,
): { entreprise: RegistreEntreprise; etablissement: RegistreEtablissement } | null {
  for (const entreprise of resultats) {
    for (const etablissement of entreprise.matching_etablissements || []) {
      if (chiffres(etablissement.siret) === siret) return { entreprise, etablissement };
    }
    if (entreprise.siege && chiffres(entreprise.siege.siret) === siret) {
      return { entreprise, etablissement: entreprise.siege };
    }
  }
  return null;
}

async function querySiretInscription(siret: string): Promise<SiretVerification | null> {
  try {
    const url = `https://recherche-entreprises.api.gouv.fr/search?q=${encodeURIComponent(siret)}&mtm_campaign=jolene`;
    const response = await fetch(url, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(9_000),
    });
    if (!response.ok) return null;
    const payload = await response.json() as { results?: RegistreEntreprise[] };
    const exact = trouverSiretExact(Array.isArray(payload.results) ? payload.results : [], siret);
    if (!exact) {
      return {
        trouve: false,
        raison_sociale: null,
        est_actif: false,
        est_sante: false,
        est_public: false,
        code_naf: null,
        categorie_juridique: null,
        dirigeants: null,
      };
    }

    const codeNaf = normaliserNaf(
      exact.etablissement.activite_principale || exact.entreprise.activite_principale,
    );
    const categorieJuridique = texte(exact.entreprise.nature_juridique, 20) || null;
    return {
      trouve: true,
      raison_sociale: texte(
        exact.entreprise.nom_raison_sociale || exact.entreprise.nom_complet,
        300,
      ) || null,
      est_actif: exact.etablissement.etat_administratif === 'A',
      est_sante: NAF_SANTE.has(codeNaf),
      est_public: !!categorieJuridique && (categorieJuridique.startsWith('7') || categorieJuridique.startsWith('4')),
      code_naf: codeNaf || null,
      categorie_juridique: categorieJuridique,
      dirigeants: Array.isArray(exact.entreprise.dirigeants) ? exact.entreprise.dirigeants : null,
    };
  } catch (error) {
    console.warn('[register-etablissement] Registre SIRET indisponible:', safeStringifyError(error));
    return null;
  }
}

function checkRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return true;
  }
  if (entry.count >= RATE_LIMIT) return false;
  entry.count++;
  return true;
}

// Vérification FINESS via FHIR Annuaire Santé (même source que verify-finess) —
// inline ici pour pouvoir croiser raison sociale FINESS ↔ SIRET ↔ nom AVANT l'insert.
const FINESS_GATEWAY = 'https://gateway.api.esante.gouv.fr/fhir/v2/Organization';
const FINESS_SYSTEM = 'https://finess.esante.gouv.fr';
const SIRENE_SYSTEM = 'https://sirene.fr';

function identifiantFinessExact(identifier: FhirIdentifier, finess: string): boolean {
  const systeme = texte(identifier.system, 200).toLowerCase().replace(/\/$/, '');
  return (systeme === FINESS_SYSTEM || systeme.includes('finess'))
    && chiffres(identifier.value) === finess;
}

function extraireSiretFhir(organization: FhirOrganization): string | null {
  for (const identifier of organization.identifier || []) {
    const valeur = chiffres(identifier.value);
    if (valeur.length !== 14) continue;
    const systeme = texte(identifier.system, 200).toLowerCase().replace(/\/$/, '');
    const typeSiret = (identifier.type?.coding || []).some((coding) =>
      texte(coding.code, 50).toUpperCase() === 'SIRET'
      || texte(coding.display, 100).toUpperCase().includes('SIRET')
    );
    if (systeme === SIRENE_SYSTEM || systeme.includes('siret') || typeSiret) return valeur;
  }
  return null;
}

async function queryFinessInscription(
  finess: string,
  apiKey: string,
): Promise<FinessVerification | null> {
  try {
    const identifier = `${FINESS_SYSTEM}|${finess}`;
    const url = `${FINESS_GATEWAY}?identifier=${encodeURIComponent(identifier)}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 9_000);
    let response: Response;
    try {
      response = await fetch(url, {
        headers: { Accept: 'application/fhir+json', 'ESANTE-API-KEY': apiKey },
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }
    if (!response.ok) return null;
    const bundle = await response.json() as {
      entry?: Array<{ resource?: FhirOrganization }>;
    };
    const organizations = (bundle.entry || [])
      .map((entry) => entry.resource)
      .filter((resource): resource is FhirOrganization =>
        resource?.resourceType === 'Organization'
        && (resource.identifier || []).some((id) => identifiantFinessExact(id, finess))
      );
    if (organizations.length === 0) {
      return {
        trouve: false,
        raison_sociale: null,
        actif: false,
        siret: null,
        categorie: null,
        secteur: null,
        est_public: false,
      };
    }
    const org = organizations.find((item) => item.active === true) || organizations[0];
    let categorie: string | null = null, secteur: string | null = null;
    for (const ty of org.type || []) {
      for (const c of ty.coding || []) {
        const sys = String(c.system || '');
        if (sys.includes('TRE_R66-CategorieEtablissement') && !categorie) {
          categorie = texte(c.display || c.code, 300) || null;
        }
        if (sys.includes('TRE_R02-SecteurActivite') && !secteur) {
          secteur = texte(c.display || c.code, 300) || null;
        }
      }
    }
    return {
      trouve: true,
      raison_sociale: texte(org.name, 300) || null,
      actif: org.active === true,
      siret: extraireSiretFhir(org),
      categorie,
      secteur,
      est_public: /public/i.test(secteur || ''),
    };
  } catch (error) {
    console.warn('[register-etablissement] Annuaire FINESS indisponible:', safeStringifyError(error));
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);

  const cors = corsHeaders(req);

  if (req.method !== 'POST') {
    return errorResponse(cors, 405, 'METHOD_NOT_ALLOWED', 'Méthode non autorisée.');
  }

  // M7: Rate limiting
  const clientIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  if (!checkRateLimit(clientIp)) {
    return errorResponse(cors, 429, 'RATE_LIMITED', 'Trop de tentatives. Réessayez dans quelques minutes.');
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return errorResponse(cors, 503, 'SERVER_NOT_CONFIGURED', 'Inscription momentanément indisponible.');
  }

  // 1. Authenticate caller via JWT
  const authHeader = req.headers.get('Authorization') || '';
  const bearerMatch = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!bearerMatch) {
    return errorResponse(cors, 401, 'UNAUTHORIZED', 'Non authentifié.');
  }

  const token = bearerMatch[1].trim();
  if (!token || token === serviceRoleKey) {
    return errorResponse(cors, 401, 'UNAUTHORIZED', 'Une session utilisateur est requise.');
  }
  const supabaseAuth = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return errorResponse(cors, 401, 'INVALID_TOKEN', 'Session invalide. Reconnectez-vous et réessayez.');
  }

  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    db: { schema: 'public' },
  });
  let suppressionAuthAutorisee = false;
  let inscriptionFinalisee = false;
  const claimToken = crypto.randomUUID();
  const annulerCompteAuth = async (raison: string) => {
    // Ne jamais supprimer un compte existant qui rappelle l'endpoint. Seule la
    // reservation fraiche possedee par cette requete autorise la compensation.
    if (!suppressionAuthAutorisee || inscriptionFinalisee) return;
    try {
      const { error } = await supabaseAdmin.auth.admin.deleteUser(user.id);
      if (error) throw error;
      console.log(`[register-etablissement] Compte Auth ${user.id} supprimé (échec avant création du profil: ${raison})`);
    } catch (cleanupErr) {
      console.error('[register-etablissement] Cleanup Auth user échoué:', safeStringifyError(cleanupErr));
    }
  };

  try {
    const { data: reservation, error: reservationError } = await supabaseAdmin.rpc(
      'fn_reserver_type_compte',
      { p_user_id: user.id, p_type_compte: 'ETABLISSEMENT', p_claim_token: claimToken },
    );
    if (reservationError || !reservation || typeof reservation !== 'object') {
      console.error('[register-etablissement] Reservation type compte echouee:', reservationError?.code || 'INVALID_RESULT');
      return errorResponse(cors, 503, 'ACCOUNT_RESERVATION_UNAVAILABLE', 'Inscription momentanément indisponible. Réessayez dans quelques minutes.');
    }
    const reservationResult = reservation as Record<string, unknown>;
    if (reservationResult.allowed !== true) {
      const code = String(reservationResult.code || 'ACCOUNT_TYPE_MISMATCH');
      const status = code === 'ACCOUNT_AUTH_INACTIVE' ? 401 : 409;
      const message = code === 'ACCOUNT_ALREADY_REGISTERED'
        ? 'Ce compte établissement existe déjà. Connectez-vous pour continuer.'
        : code === 'ACCOUNT_REGISTRATION_IN_PROGRESS'
          ? 'Une inscription est déjà en cours pour ce compte. Patientez quelques instants puis réessayez.'
          : 'Ce compte est déjà associé à un autre espace Jolene. Utilisez une autre adresse ou contactez le support.';
      return errorResponse(cors, status, code, message);
    }
    suppressionAuthAutorisee = reservationResult.fresh === true;

    const rawBody = await req.json().catch(() => null);
    if (!rawBody || typeof rawBody !== 'object' || Array.isArray(rawBody)) {
      await annulerCompteAuth('INVALID_JSON');
      return errorResponse(cors, 400, 'INVALID_JSON', 'Corps de requête invalide.');
    }
    const body = rawBody as Record<string, unknown>;
    const nom = texte(body.nom, 200);
    const siret = texte(body.siret, 20).replace(/\s/g, '');
    const finess = texte(body.finess, 20).replace(/\s/g, '');
    const type = texte(body.type, 50).toUpperCase();
    const adresseRue = texte(body.adresse_rue, 300);
    const adresseVille = texte(body.adresse_ville, 150);
    const adresseCodePostal = texte(body.adresse_code_postal, 10);
    const adresseDepartement = texte(body.adresse_departement, 3);
    const telephoneContact = texte(body.telephone_contact, 30);
    const emailContact = texte(body.email_contact, 254) || user.email || '';
    const attribution = body.attribution
      && typeof body.attribution === 'object'
      && !Array.isArray(body.attribution)
      ? body.attribution as AttributionInput
      : null;
    const adresseLat = typeof body.adresse_lat === 'number'
      && Number.isFinite(body.adresse_lat)
      && body.adresse_lat >= -90 && body.adresse_lat <= 90
      ? body.adresse_lat : null;
    const adresseLng = typeof body.adresse_lng === 'number'
      && Number.isFinite(body.adresse_lng)
      && body.adresse_lng >= -180 && body.adresse_lng <= 180
      ? body.adresse_lng : null;

    // Token Turnstile a usage unique deja consomme par Auth signUp. Ne pas le
    // soumettre une seconde fois a Siteverify (`timeout-or-duplicate`).

    // Validate required fields
    if (!nom || !siret || !type || !adresseVille) {
      await annulerCompteAuth('MISSING_REQUIRED_FIELDS');
      return errorResponse(cors, 400, 'MISSING_REQUIRED_FIELDS', 'Champs obligatoires manquants.', {
        champs_manquants: [!nom && 'nom', !siret && 'siret', !type && 'type', !adresseVille && 'adresse_ville'].filter(Boolean),
      });
    }

    if (!/^\d{14}$/.test(siret)) {
      await annulerCompteAuth('SIRET_FORMAT_INVALID');
      return errorResponse(cors, 400, 'SIRET_FORMAT_INVALID', 'Le SIRET doit contenir 14 chiffres.');
    }
    if (!siretLuhnValide(siret)) {
      await annulerCompteAuth('SIRET_CHECKSUM_INVALID');
      return errorResponse(cors, 400, 'SIRET_CHECKSUM_INVALID', 'SIRET invalide (checksum incorrecte).');
    }
    if (finess && !/^\d{9}$/.test(finess)) {
      await annulerCompteAuth('FINESS_FORMAT_INVALID');
      return errorResponse(cors, 400, 'FINESS_FORMAT_INVALID', 'Le FINESS doit contenir exactement 9 chiffres.');
    }

    if (!TYPES_ETABLISSEMENT.has(type)) {
      await annulerCompteAuth('TYPE_ETABLISSEMENT_INVALID');
      return errorResponse(cors, 400, 'TYPE_ETABLISSEMENT_INVALID', 'Type d’établissement invalide.');
    }
    if (adresseCodePostal && !/^\d{5}$/.test(adresseCodePostal)) {
      await annulerCompteAuth('POSTAL_CODE_INVALID');
      return errorResponse(cors, 400, 'POSTAL_CODE_INVALID', 'Le code postal doit contenir 5 chiffres.');
    }
    if (telephoneContact && !/^\+?[0-9\s.-]{8,20}$/.test(telephoneContact)) {
      await annulerCompteAuth('PHONE_INVALID');
      return errorResponse(cors, 400, 'PHONE_INVALID', 'Le numéro de téléphone est invalide.');
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailContact)) {
      await annulerCompteAuth('EMAIL_INVALID');
      return errorResponse(cors, 400, 'EMAIL_INVALID', 'L’adresse e-mail de contact est invalide.');
    }

    // Les registres officiels ne valident que les preuves unitaires. Ils ne
    // peuvent jamais, à eux seuls, promouvoir le compte ni ouvrir la publication.
    const siretVerification = await querySiretInscription(siret);
    const nomCorrespondAuSiret = siretVerification?.trouve
      ? corporateNameMatches(nom, siretVerification.raison_sociale)
      : null;
    const siretVerifie = !!(
      siretVerification?.trouve
      && siretVerification.est_actif
      && siretVerification.est_sante
      && nomCorrespondAuSiret === true
    );
    const coherenceIdentite: CoherenceIdentite = nomCorrespondAuSiret === true
      ? 'OK'
      : nomCorrespondAuSiret === false ? 'INCOHERENT' : null;

    let finessResult: Awaited<ReturnType<typeof queryFinessInscription>> = null;
    const finessApiKey = Deno.env.get('ESANTE_FHIR_API_KEY') || '';
    if (finess && finessApiKey) {
      finessResult = await queryFinessInscription(finess, finessApiKey);
    }
    const finessRs = finessResult?.trouve ? (finessResult.raison_sociale ?? null) : null;
    // Un FINESS actif mais non relié au SIRET exact reste à contrôler. Un nom
    // approchant n'est pas une preuve suffisante pour une validation automatique.
    const finessVerifie = !!(
      finess
      && siretVerifie
      && finessResult?.trouve
      && finessResult.actif
      && finessResult.siret === siret
    );
    const statutVerification = 'EN_COURS' as const;
    const maintenant = new Date().toISOString();

    // 2. Insert into etablissements table
    const insertPayload = {
      id: user.id,
      nom,
      siret,
      finess: finess || null,
      finess_verifie: finessVerifie,
      finess_verifie_le: finessVerifie ? maintenant : null,
      finess_raison_sociale: finessRs,
      finess_categorie: finessResult?.categorie ?? null,
      finess_secteur: finessResult?.secteur ?? null,
      finess_est_public: finessResult?.est_public ?? null,
      type,
      adresse_rue: adresseRue || 'Non renseigné',
      adresse_ville: adresseVille,
      adresse_code_postal: adresseCodePostal || '00000',
      adresse_departement: adresseDepartement || null,
      email_contact: emailContact,
      telephone_contact: telephoneContact || null,
      adresse_lat: adresseLat,
      adresse_lng: adresseLng,
      siret_verifie: siretVerifie,
      siret_verifie_le: siretVerifie ? maintenant : null,
      siret_est_actif: siretVerification?.est_actif ?? null,
      siret_code_naf: siretVerification?.code_naf ?? null,
      siret_raison_sociale: siretVerification?.raison_sociale ?? null,
      siret_categorie_juridique: siretVerification?.categorie_juridique ?? null,
      dirigeants: siretVerification?.dirigeants ?? null,
      est_secteur_public: siretVerification?.est_public ?? false,
      coherence_identite: coherenceIdentite,
      statut_verification: statutVerification,
      peut_publier_missions: false,
      verifie_le: null,
      verifie_par: null,
      ...colonnesAttribution(attribution, req),
    };

    const { error: insertError } = await supabaseAdmin
      .from('etablissements')
      .insert(insertPayload);

    if (insertError) {
      console.error('INSERT etablissements échoué', insertError.code || safeStringifyError(insertError));
      const msg = (insertError.message || '').toLowerCase();
      const estSiretDuplique = msg.includes('duplicate key') && msg.includes('siret');
      const estProfilDuplique = msg.includes('duplicate key')
        && (msg.includes('etablissements_pkey') || msg.includes('(id)'));
      if (!estProfilDuplique) await annulerCompteAuth(estSiretDuplique ? 'SIRET_ALREADY_REGISTERED' : 'INSERT_ETABLISSEMENT_FAILED');
      if (estSiretDuplique) {
        return errorResponse(cors, 409, 'SIRET_ALREADY_REGISTERED', 'Ce numéro SIRET est déjà enregistré. S\'il s\'agit de votre établissement, connectez-vous ; sinon vérifiez le numéro saisi.');
      }
      if (estProfilDuplique) {
        return errorResponse(cors, 409, 'USER_ALREADY_REGISTERED', 'Ce compte établissement existe déjà. Connectez-vous pour continuer.');
      }
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la création du profil établissement. Réessayez dans quelques minutes.');
    }

    // 3. Set app_metadata role — server-side, no client involvement
    const { error: claimsError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
      app_metadata: { ...(user.app_metadata || {}), role: 'ADMIN_ETABLISSEMENT', etablissement_id: user.id },
    });

    if (claimsError) {
      console.error('set-user-claims échoué', claimsError.code || safeStringifyError(claimsError));
      await supabaseAdmin.from('etablissements').delete().eq('id', user.id);
      await annulerCompteAuth('SET_CLAIMS_FAILED');
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la configuration du compte. Réessayez dans quelques minutes.');
    }

    const { data: typeFinalise, error: finalisationError } = await supabaseAdmin.rpc(
      'fn_finaliser_type_compte',
      { p_user_id: user.id, p_type_compte: 'ETABLISSEMENT', p_claim_token: claimToken },
    );
    if (finalisationError || typeFinalise !== true) {
      console.error('[register-etablissement] Finalisation type compte echouee:', finalisationError?.code || 'INVALID_RESULT');
      await supabaseAdmin.from('etablissements').delete().eq('id', user.id);
      await annulerCompteAuth('ACCOUNT_TYPE_FINALIZATION_FAILED');
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la configuration du compte. Réessayez dans quelques minutes.');
    }
    inscriptionFinalisee = true;

    // 4. Audit inscription + CGU + L1: CGV consent
    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id,
      type_acteur: 'ADMIN_ETABLISSEMENT',
      action: 'INSCRIPTION',
      type_ressource: 'etablissement',
      id_ressource: user.id,
      details: {
        evenement: 'inscription',
        type,
        siret_verifie: siretVerifie,
        finess_fourni: !!finess,
        finess_verifie: finessVerifie,
        statut_verification: statutVerification,
      },
      navigateur_acteur: texte(body.navigateur, 500) || null,
    });

    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id,
      type_acteur: 'ADMIN_ETABLISSEMENT',
      action: 'RGPD_CONSENTEMENT_DONNE',
      type_ressource: 'etablissement',
      id_ressource: user.id,
      details: { type: 'inscription', cgu: true, confidentialite: true, cgv: true },
      navigateur_acteur: texte(body.navigateur, 500) || null,
    });

    // 5. Email bienvenue (best-effort — ne bloque pas l'inscription)
    try {
      await supabaseAdmin.functions.invoke('send-email', {
        body: {
          type: 'BIENVENUE_ETABLISSEMENT',
          destinataire_id: user.id,
          data: {
            nom_etablissement: String(nom).slice(0, 200),
            type_etablissement: type,
            lien_dashboard: 'https://jolene.app/etablissement',
          },
        },
      });
    } catch (emailErr) {
      console.warn('[register-etablissement] Email bienvenue non envoyé (best-effort):', safeStringifyError(emailErr));
    }

    // 6. Planifier la série onboarding J0/J1/J3/J7 (best-effort)
    try {
      await supabaseAdmin.rpc('fn_planifier_serie_onboarding', {
        p_utilisateur_id: user.id,
        p_serie: 'ETAB_ONBOARDING',
      });
    } catch (serieErr) {
      console.warn('[register-etablissement] Planification série onboarding échouée (best-effort):', safeStringifyError(serieErr));
    }

    return new Response(JSON.stringify({
      ok: true,
      success: true,
      etablissement_id: user.id,
      auto_verifie: false,
      statut_verification: statutVerification,
      peut_publier_missions: false,
      siret_verifie: siretVerifie,
      finess_verifie: finessVerifie,
      coherence_identite: coherenceIdentite,
      siret_raison_sociale: siretVerification?.raison_sociale ?? null,
      verification_complete_requise: true,
    }), {
      status: 200,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('register-etablissement error:', safeStringifyError(err));
    await annulerCompteAuth('UNEXPECTED_ERROR');
    return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur serveur. Notre équipe a été notifiée. Réessayez dans quelques minutes.');
  }
});
