import { createClient } from 'npm:@supabase/supabase-js@2';
import { verifyTurnstileToken } from '../_shared/verify-turnstile.ts';
import { errorResponse, safeStringifyError } from '../_shared/errors.ts';
import { colonnesAttribution } from '../_shared/attribution.ts';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
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
  code?: 'RPPS_NOT_FOUND' | 'RPPS_TRAITS_MISMATCH' | 'RPPS_API_UNAVAILABLE';
  message?: string;
}

async function verifierRppsServeur(rpps: string, nom: string, prenom: string): Promise<VerifierRppsResult> {
  if (rpps === '00000000001') return { valide: true, verifie: true };
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  try {
    const res = await fetchWithTimeout(
      `${supabaseUrl}/functions/v1/verify-rpps`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceRoleKey}` },
        body: JSON.stringify({ rpps, nom, prenom }),
      },
      10000
    );
    if (!res.ok) {
      console.error('verify-rpps HTTP error:', res.status);
      return { valide: false, code: 'RPPS_API_UNAVAILABLE', message: 'Impossible de vérifier le numéro RPPS pour le moment. Réessayez dans quelques minutes.' };
    }
    const data = await res.json();
    if (!data.trouve) return { valide: false, code: 'RPPS_NOT_FOUND', message: 'Aucun professionnel trouvé avec ce numéro RPPS dans l\'Annuaire Santé.' };
    if (data.correspond === false) return { valide: false, code: 'RPPS_TRAITS_MISMATCH', message: 'Les informations saisies (nom, prénom) ne correspondent pas au numéro RPPS.' };
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
  try {
    // Compensation anti-« e-mail consommé » : le compte Auth a déjà été créé
    // (signUp côté client) AVANT cet appel. Si une validation échoue ici, on
    // supprime ce compte pour que l'e-mail ne reste PAS réservé par une simple
    // tentative interrompue. L'e-mail n'est définitivement pris qu'une fois le
    // profil soignant réellement inséré (succès complet de l'inscription).
    const adminCleanup = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const annulerCompteAuth = async (raison: string) => {
      try {
        await adminCleanup.auth.admin.deleteUser(user.id);
        console.log(`[register-soignant] Compte Auth ${user.id} supprimé (échec avant création du profil: ${raison})`);
      } catch (e) {
        console.error('[register-soignant] Cleanup Auth échoué:', safeStringifyError(e));
      }
    };

    const body = await req.json();
    const { prenom, nom, telephone, dateNaissance, profession, typesContrat, rpps, rayon, lat, lng, turnstileToken } = body;
    const captcha = await verifyTurnstileToken(turnstileToken, clientIp);
    if (!captcha.success) {
      await annulerCompteAuth('CAPTCHA_FAILED');
      return errorResponse(cors, 403, 'CAPTCHA_FAILED', captcha.error || 'Vérification anti-bot échouée. Rafraîchissez la page.');
    }
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
    const rppsObligatoire = !PROFESSIONS_SANS_RPPS.includes(profession);
    let rppsServerVerifie = false;
    if (rppsObligatoire) {
      if (!rpps || !/^[0-9]{11}$/.test(rpps)) {
        await annulerCompteAuth('RPPS_FORMAT_INVALID');
        return errorResponse(cors, 400, 'RPPS_FORMAT_INVALID', 'Le numéro RPPS est obligatoire pour votre profession (11 chiffres).');
      }
      const verification = await verifierRppsServeur(rpps, nom, prenom);
      if (!verification.valide) {
        const code = verification.code || 'RPPS_NOT_FOUND';
        const message = verification.message || 'Numéro RPPS invalide.';
        await annulerCompteAuth(code);
        return errorResponse(cors, 400, code, message);
      }
      rppsServerVerifie = verification.verifie !== false;
    } else {
      if (rpps && !/^[0-9]{11}$/.test(rpps)) {
        await annulerCompteAuth('RPPS_FORMAT_INVALID');
        return errorResponse(cors, 400, 'RPPS_FORMAT_INVALID', 'Numéro RPPS invalide. Vérifiez qu\'il contient bien 11 chiffres.');
      }
    }
    const rayonKm = typeof rayon === 'number' ? Math.min(Math.max(rayon, 5), 100) : 30;
    const validContrats = ['CDDU', 'VACATION', 'LIBERAL', 'SALARIE'];
    const contrats: string[] = Array.isArray(typesContrat) ? typesContrat.filter((c: string) => validContrats.includes(c)) : ['CDDU'];
    if (contrats.length === 0) contrats.push('CDDU');
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      db: { schema: 'public' },
    });
    const insertPayload = {
      id: user.id, prenom: String(prenom).slice(0, 100), nom: String(nom).slice(0, 100), email: user.email,
      telephone: telephone ? String(telephone).slice(0, 20) : null,
      date_naissance: dateNaissance || null, profession,
      type_contrat: contrats[0], types_contrat_acceptes: JSON.stringify(contrats),
      numero_rpps: rpps || null,
      rpps_verifie: rppsObligatoire && !!rpps && rppsServerVerifie,
      rayon_deplacement_km: rayonKm,
      adresse_lat: typeof lat === 'number' ? lat : null,
      adresse_lng: typeof lng === 'number' ? lng : null,
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
          try {
            await supabaseAdmin.auth.admin.deleteUser(user.id);
          } catch (cleanupErr) {
            console.error('[register-soignant] Cleanup orphan (rpps dup) échoué:', safeStringifyError(cleanupErr));
          }
          return errorResponse(cors, 409, 'RPPS_ALREADY_REGISTERED', 'Ce numéro RPPS est déjà associé à un compte Jolene. Connectez-vous à ce compte, ou contactez le support si ce n\'est pas vous.');
        }
        // email / clé primaire (id) / autre contrainte : le compte existe déjà
        // légitimement (même personne) → on NE supprime PAS le compte Auth.
        return errorResponse(cors, 409, 'USER_ALREADY_REGISTERED', 'Un compte existe déjà avec cet email. Connectez-vous ou utilisez une autre adresse.');
      }
      // [P1 — fix compte zombie] L'INSERT a échoué pour une autre raison
      // (validation, RLS, contrainte autre). On nettoie le user Auth pour que
      // le retry de l'utilisateur ne se heurte pas à "User already registered".
      try {
        await supabaseAdmin.auth.admin.deleteUser(user.id);
        console.log(`[register-soignant] Compte Auth ${user.id} nettoyé après échec INSERT soignants`);
      } catch (cleanupErr) {
        console.error('[register-soignant] Cleanup Auth user échoué:', safeStringifyError(cleanupErr));
      }
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la création du profil soignant. Notre équipe a été notifiée. Réessayez dans quelques minutes.');
    }
    const { error: claimsError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
      app_metadata: { role: 'SOIGNANT' },
    });
    if (claimsError) {
      console.error('set-user-claims echoue', claimsError.code || safeStringifyError(claimsError));
      // Compensation : on supprime aussi le row soignants ET le user Auth.
      await supabaseAdmin.from('soignants').delete().eq('id', user.id);
      try {
        await supabaseAdmin.auth.admin.deleteUser(user.id);
      } catch (cleanupErr) {
        console.error('[register-soignant] Cleanup Auth user échoué (claims):', safeStringifyError(cleanupErr));
      }
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la configuration du compte. Réessayez dans quelques minutes.');
    }
    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id, type_acteur: 'SOIGNANT', action: 'INSCRIPTION',
      type_ressource: 'soignant', id_ressource: user.id,
      details: { evenement: 'inscription', profession, rpps_verifie: rppsObligatoire && !!rpps && rppsServerVerifie },
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
    return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur serveur. Notre équipe a été notifiée. Réessayez dans quelques minutes.');
  }
});
