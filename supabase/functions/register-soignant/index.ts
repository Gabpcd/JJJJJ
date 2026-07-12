import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { errorResponse, safeStringifyError } from '../_shared/errors.ts';
import { colonnesAttribution } from '../_shared/attribution.ts';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "https://localhost" ||
    origin === "capacitor://localhost" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT = 5;
const RATE_WINDOW_MS = 10 * 60 * 1000;

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

// Professions SANS RPPS (pas dans l'Annuaire Santé) — DOIT rester synchronisé
// avec src/lib/constantes.ts PROFESSIONS_SANS_RPPS. AUXILIAIRE_PUERICULTURE
// (DEAP, ajouté Sprint 17) n'a pas de RPPS : l'oublier ici bloquait son
// inscription (RPPS_FORMAT_INVALID à tort).
const PROFESSIONS_SANS_RPPS = ['AS', 'AES', 'AUXILIAIRE_PUERICULTURE'];

async function fetchWithTimeout(url: string, init: RequestInit = {}, timeoutMs = 8000): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

interface VerifierRppsResult {
  valide: boolean;
  verifie?: boolean;
  code?: 'RPPS_NOT_FOUND' | 'RPPS_TRAITS_MISMATCH' | 'RPPS_PROFESSION_MISMATCH' | 'RPPS_API_UNAVAILABLE';
  message?: string;
}

function normaliserProf(s: string): string {
  return (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
}
// Tokens reconnaissant la profession renvoyée par l'Annuaire (profession_api =
// libellé FHIR OU code interne). Familles regroupées : IDE/IBODE/IADE = infirmier.
const PROFESSION_TOKENS: Record<string, string[]> = {
  MEDECIN: ['medecin'],
  IDE: ['infirmier', 'ide'], IBODE: ['infirmier', 'ide'], IADE: ['infirmier', 'ide'],
  SAGE_FEMME: ['sage-femme', 'sage femme', 'sage_femme', 'maieut'],
  KINE: ['kine', 'masseur'],
  PHARMACIEN: ['pharmacien'],
  DENTISTE: ['dentiste', 'odontolog'],
  MANIPULATEUR_RADIO: ['manipulateur', 'electroradio', 'radio'],
  ERGOTHERAPEUTE: ['ergoth'],
  PSYCHOMOTRICIEN: ['psychomot'],
  ORTHOPHONISTE: ['orthophon'],
  DIETETICIEN: ['dieteti'],
  PREPARATEUR_PHARMA: ['preparateur'],
};
// Cohérence profession déclarée ↔ profession de l'Annuaire. On NE bloque que si
// la profession renvoyée est connue ET clairement différente (sinon on laisse passer).
function professionCoherenteRpps(declaree: string, apiValue: string): boolean {
  const tokens = PROFESSION_TOKENS[declaree];
  if (!tokens) return true;
  const v = normaliserProf(apiValue);
  if (!v) return true;
  return tokens.some((t) => v.includes(normaliserProf(t)));
}

async function verifierRppsServeur(
  rpps: string,
  nom: string,
  prenom: string,
  profession: string,
  autoriserIdentifiantDemo = false,
): Promise<VerifierRppsResult> {
  if (rpps === '00000000001' && autoriserIdentifiantDemo) {
    return { valide: true, verifie: true };
  }
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  try {
    const res = await fetchWithTimeout(
      `${supabaseUrl}/functions/v1/verify-rpps`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceRoleKey}` },
        body: JSON.stringify({ rpps, nom, prenom, profession }),
      },
      10000
    );
    if (!res.ok) {
      console.error('verify-rpps HTTP error:', res.status);
      return { valide: false, code: 'RPPS_API_UNAVAILABLE', message: 'Impossible de vérifier le numéro RPPS pour le moment. Réessayez dans quelques minutes.' };
    }
    const data = await res.json();
    if (!data.trouve) return { valide: false, code: 'RPPS_NOT_FOUND', message: 'Aucun professionnel trouvé avec ce numéro RPPS dans l\'Annuaire Santé.' };
    // correspond_traits = nom/prénom seul (verify-rpps replie désormais la profession dans `correspond`).
    const traitsMismatch = (data.correspond_traits ?? data.correspond) === false;
    if (traitsMismatch) return { valide: false, code: 'RPPS_TRAITS_MISMATCH', message: 'Les informations saisies (nom, prénom) ne correspondent pas au numéro RPPS.' };
    if (data.code === 'RPPS_PROFESSION_MISMATCH' || (data.profession_api && !professionCoherenteRpps(profession, String(data.profession_api)))) {
      return { valide: false, code: 'RPPS_PROFESSION_MISMATCH', message: `Ce numéro RPPS correspond à la profession « ${data.profession_api} », différente de celle que vous avez déclarée.` };
    }
    if (data.fhir_indisponible) return { valide: true, verifie: false };
    return { valide: true, verifie: true };
  } catch (err) {
    console.error('RPPS verification error:', safeStringifyError(err));
    return { valide: false, code: 'RPPS_API_UNAVAILABLE', message: 'Impossible de vérifier le numéro RPPS pour le moment. Réessayez dans quelques minutes.' };
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders(req) });
  const cors = corsHeaders(req);
  const clientIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  if (!checkRateLimit(clientIp)) {
    return errorResponse(cors, 429, 'RATE_LIMITED', 'Trop de tentatives. Réessayez dans quelques minutes.');
  }
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse(cors, 401, 'UNAUTHORIZED', 'Non authentifié.');
  }
  const token = authHeader.replace('Bearer ', '');
  const supabaseAuth = createClient(supabaseUrl, anonKey);
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
    // La compensation ne s'applique qu'au user Auth fraichement cree et
    // reserve atomiquement par CETTE inscription. Elle ne doit jamais pouvoir
    // supprimer un compte existant qui rappelle l'endpoint.
    if (!suppressionAuthAutorisee || inscriptionFinalisee) return;
    try {
      const { error } = await supabaseAdmin.auth.admin.deleteUser(user.id);
      if (error) throw error;
      console.log(`[register-soignant] Compte Auth ${user.id} supprimé (échec avant création du profil: ${raison})`);
    } catch (e) {
      console.error('[register-soignant] Cleanup Auth échoué:', safeStringifyError(e));
    }
  };

  try {
    // Reservation DB atomique : un meme auth.users.id ne peut pas devenir a la
    // fois soignant et etablissement, meme si les deux endpoints sont appeles
    // en concurrence. La RPC service-role refuse aussi tout compte deja finalise.
    const { data: reservation, error: reservationError } = await supabaseAdmin.rpc(
      'fn_reserver_type_compte',
      { p_user_id: user.id, p_type_compte: 'SOIGNANT', p_claim_token: claimToken },
    );
    if (reservationError || !reservation || typeof reservation !== 'object') {
      console.error('[register-soignant] Reservation type compte echouee:', reservationError?.code || 'INVALID_RESULT');
      return errorResponse(cors, 503, 'ACCOUNT_RESERVATION_UNAVAILABLE', 'Inscription momentanément indisponible. Réessayez dans quelques minutes.');
    }
    const reservationResult = reservation as Record<string, unknown>;
    if (reservationResult.allowed !== true) {
      const code = String(reservationResult.code || 'ACCOUNT_TYPE_MISMATCH');
      const status = code === 'ACCOUNT_AUTH_INACTIVE' ? 401 : 409;
      const message = code === 'ACCOUNT_ALREADY_REGISTERED'
        ? 'Ce compte soignant existe déjà. Connectez-vous pour continuer.'
        : code === 'ACCOUNT_REGISTRATION_IN_PROGRESS'
          ? 'Une inscription est déjà en cours pour ce compte. Patientez quelques instants puis réessayez.'
          : 'Ce compte est déjà associé à un autre espace Jolene. Utilisez une autre adresse ou contactez le support.';
      return errorResponse(cors, status, code, message);
    }
    suppressionAuthAutorisee = reservationResult.fresh === true;

    const body = await req.json();
    const { prenom, nom, telephone, dateNaissance, profession, typesContrat, rpps, rayon, lat, lng, est_etudiant, etudiant_details } = body;
    // Le token Turnstile est a usage unique et a deja ete valide par
    // supabase.auth.signUp. Le revalider ici ferait echouer toute inscription
    // legitime (`timeout-or-duplicate`). Le JWT utilisateur verifie ci-dessus
    // prouve que l'etape Auth protegee a reussi.
    if (!prenom || !nom || !profession) {
      await annulerCompteAuth('MISSING_REQUIRED_FIELDS');
      return errorResponse(cors, 400, 'MISSING_REQUIRED_FIELDS', 'Champs obligatoires manquants (prénom, nom, profession).', { champs_manquants: [!prenom && 'prenom', !nom && 'nom', !profession && 'profession'].filter(Boolean) });
    }
    if (!dateNaissance) {
      await annulerCompteAuth('MISSING_DATE_NAISSANCE');
      return errorResponse(cors, 400, 'MISSING_REQUIRED_FIELDS', 'Date de naissance requise.', { champs_manquants: ['dateNaissance'] });
    }
    {
      const birth = new Date(dateNaissance);
      const today = new Date();
      const age = today.getFullYear() - birth.getFullYear();
      const monthDiff = today.getMonth() - birth.getMonth();
      const dayDiff = today.getDate() - birth.getDate();
      const actualAge = monthDiff < 0 || (monthDiff === 0 && dayDiff < 0) ? age - 1 : age;
      if (actualAge < 18) {
        await annulerCompteAuth('UNDERAGE');
        return errorResponse(cors, 400, 'UNDERAGE', 'Vous devez avoir au moins 18 ans pour vous inscrire.');
      }
    }
    // RPPS EXIGÉ uniquement pour les professions « Ordre historique » (médecin,
    // dentiste, sage-femme, pharmacien) qui connaissent/utilisent leur numéro.
    // Pour les autres (IDE + paramédicaux récemment migrés au RPPS), il est
    // OPTIONNEL : le diplôme sert de preuve, vérification différée (rpps_verifie
    // = false). AS/AES/aux. puériculture : pas de RPPS du tout.
    const PROFESSIONS_RPPS_REQUIS = ['MEDECIN', 'DENTISTE', 'SAGE_FEMME', 'PHARMACIEN'];
    const rppsRequis = PROFESSIONS_RPPS_REQUIS.includes(profession);
    let rppsServerVerifie = false;
    if (rpps && !/^[0-9]{11}$/.test(rpps)) {
      // Si un numéro est saisi, il doit être bien formé (erreur client claire).
      await annulerCompteAuth('RPPS_FORMAT_INVALID');
      return errorResponse(cors, 400, 'RPPS_FORMAT_INVALID', 'Numéro RPPS invalide (11 chiffres attendus).');
    }
    if (rppsRequis && !rpps) {
      await annulerCompteAuth('RPPS_REQUIS');
      return errorResponse(cors, 400, 'RPPS_FORMAT_INVALID', 'Le numéro RPPS est obligatoire pour votre profession (11 chiffres).');
    }
    if (rpps) {
      // RPPS fourni : on le vérifie. On NE bloque QUE l'usurpation (le numéro
      // correspond à une AUTRE identité). Introuvable / annuaire indisponible →
      // inscription autorisée, vérification différée.
      const identifiantDemoAutorise = Deno.env.get('ALLOW_DEMO_IDENTIFIERS') === 'true'
        && !!user.email?.toLowerCase().endsWith('@jolene-demo.dev');
      const verification = await verifierRppsServeur(
        rpps,
        nom,
        prenom,
        profession,
        identifiantDemoAutorise,
      );
      if (verification.code === 'RPPS_TRAITS_MISMATCH') {
        await annulerCompteAuth('RPPS_TRAITS_MISMATCH');
        return errorResponse(cors, 400, 'RPPS_TRAITS_MISMATCH', verification.message || 'Ce numéro RPPS ne correspond pas à votre identité.');
      }
      if (verification.code === 'RPPS_PROFESSION_MISMATCH') {
        await annulerCompteAuth('RPPS_PROFESSION_MISMATCH');
        return errorResponse(cors, 400, 'RPPS_PROFESSION_MISMATCH', verification.message || 'Ce numéro RPPS correspond à une autre profession que celle déclarée.');
      }
      rppsServerVerifie = verification.valide && verification.verifie !== false;
    }
    const rayonKm = typeof rayon === 'number' ? Math.min(Math.max(rayon, 5), 100) : 30;
    const validContrats = ['CDD', 'VACATION', 'LIBERAL', 'SALARIE'];
    const contrats: string[] = Array.isArray(typesContrat) ? typesContrat.filter((c: string) => validContrats.includes(c)) : ['CDD'];
    if (contrats.length === 0) contrats.push('CDD');
    const insertPayload = {
      id: user.id, prenom: String(prenom).slice(0, 100), nom: String(nom).slice(0, 100), email: user.email,
      telephone: telephone ? String(telephone).slice(0, 20) : null,
      date_naissance: dateNaissance || null, profession,
      type_contrat: contrats[0], types_contrat_acceptes: JSON.stringify(contrats),
      numero_rpps: rpps || null,
      rpps_verifie: !!rpps && rppsServerVerifie,
      rayon_deplacement_km: rayonKm,
      adresse_lat: typeof lat === 'number' ? lat : null,
      adresse_lng: typeof lng === 'number' ? lng : null,
      est_etudiant: est_etudiant === true,
      etudiant_details: (typeof etudiant_details === 'string' && etudiant_details.trim()) ? etudiant_details.trim().slice(0, 120) : null,
      ...colonnesAttribution(body.attribution, req),
    };
    const { error: insertError } = await supabaseAdmin.from('soignants').insert(insertPayload);
    if (insertError) {
      console.error('INSERT soignants echoue', insertError.code || safeStringifyError(insertError));
      const msg = insertError.message || '';
      if (msg.includes('duplicate key')) {
        const m = msg.toLowerCase();
        // On différencie la contrainte unique violée pour renvoyer un message
        // JUSTE (avant : "email déjà utilisé" pour TOUTE collision, même quand
        // c'était le RPPS — message trompeur).
        if (m.includes('numero_rpps') || m.includes('numero_adeli')) {
          // Le RPPS/ADELI appartient à un AUTRE compte. Le compte Auth qu'on
          // vient de créer (e-mail neuf) est désormais orphelin → on le nettoie
          // pour que l'utilisateur puisse réessayer avec le même e-mail (même
          // logique anti-orphelin que register-etablissement).
          await annulerCompteAuth('RPPS_ALREADY_REGISTERED');
          return errorResponse(cors, 409, 'RPPS_ALREADY_REGISTERED', 'Ce numéro RPPS est déjà associé à un compte Jolene. Connectez-vous à ce compte, ou contactez le support si ce n\'est pas vous.');
        }
        // email / clé primaire (id) / autre contrainte : le compte existe déjà
        // légitimement (même personne) → on NE supprime PAS le compte Auth.
        return errorResponse(cors, 409, 'USER_ALREADY_REGISTERED', 'Un compte existe déjà avec cet email. Connectez-vous ou utilisez une autre adresse.');
      }
      // [P1 — fix compte zombie] L'INSERT a échoué pour une autre raison
      // (validation, RLS, contrainte autre). On nettoie le user Auth pour que
      // le retry de l'utilisateur ne se heurte pas à "User already registered".
      await annulerCompteAuth('INSERT_SOIGNANT_FAILED');
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la création du profil soignant. Notre équipe a été notifiée. Réessayez dans quelques minutes.');
    }
    const { error: claimsError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
      app_metadata: { ...(user.app_metadata || {}), role: 'SOIGNANT' },
    });
    if (claimsError) {
      console.error('set-user-claims echoue', claimsError.code || safeStringifyError(claimsError));
      // Compensation : on supprime aussi le row soignants ET le user Auth.
      await supabaseAdmin.from('soignants').delete().eq('id', user.id);
      await annulerCompteAuth('SET_CLAIMS_FAILED');
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la configuration du compte. Réessayez dans quelques minutes.');
    }
    const { data: typeFinalise, error: finalisationError } = await supabaseAdmin.rpc(
      'fn_finaliser_type_compte',
      { p_user_id: user.id, p_type_compte: 'SOIGNANT', p_claim_token: claimToken },
    );
    if (finalisationError || typeFinalise !== true) {
      console.error('[register-soignant] Finalisation type compte echouee:', finalisationError?.code || 'INVALID_RESULT');
      await supabaseAdmin.from('soignants').delete().eq('id', user.id);
      await annulerCompteAuth('ACCOUNT_TYPE_FINALIZATION_FAILED');
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la configuration du compte. Réessayez dans quelques minutes.');
    }
    inscriptionFinalisee = true;
    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id, type_acteur: 'SOIGNANT', action: 'INSCRIPTION',
      type_ressource: 'soignant', id_ressource: user.id,
      details: { evenement: 'inscription', profession, rpps_verifie: !!rpps && rppsServerVerifie },
      navigateur_acteur: body.navigateur || null,
    });
    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id, type_acteur: 'SOIGNANT', action: 'RGPD_CONSENTEMENT_DONNE',
      type_ressource: 'soignant', id_ressource: user.id,
      details: { type: 'inscription', cgu: true, confidentialite: true },
      navigateur_acteur: body.navigateur || null,
    });
    try {
      await supabaseAdmin.functions.invoke('send-email', {
        body: { type: 'BIENVENUE_SOIGNANT', destinataire_id: user.id,
          data: { prenom: String(prenom).slice(0, 100), nom: String(nom).slice(0, 100), profession, lien_dashboard: 'https://jolene.app/soignant' } },
      });
    } catch (emailErr) {
      console.warn('[register-soignant] Email bienvenue non envoye (best-effort):', safeStringifyError(emailErr));
    }
    try {
      await supabaseAdmin.rpc('fn_planifier_serie_onboarding', { p_utilisateur_id: user.id, p_serie: 'SOIGNANT_ONBOARDING' });
    } catch (serieErr) {
      console.warn('[register-soignant] Planification serie onboarding echouee (best-effort):', safeStringifyError(serieErr));
    }
    return new Response(JSON.stringify({ ok: true, success: true, soignant_id: user.id }), {
      status: 200, headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('register-soignant error:', safeStringifyError(err));
    await annulerCompteAuth('UNEXPECTED_ERROR');
    return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur serveur. Notre équipe a été notifiée. Réessayez dans quelques minutes.');
  }
});
