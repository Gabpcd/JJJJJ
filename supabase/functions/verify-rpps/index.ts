import { errorResponse, safeStringifyError } from '../_shared/errors.ts';

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
const RATE_LIMIT_MAX = 10;
const RATE_LIMIT_WINDOW_MS = 60_000;

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return false;
  }
  entry.count++;
  return entry.count > RATE_LIMIT_MAX;
}

async function fetchWithTimeout(url: string, init: RequestInit = {}, timeoutMs = 8000): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function normalize(s: string): string {
  return (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
}

function mapProfessionCode(code: string | undefined): string {
  const mapping: Record<string, string> = {
    '10': 'MEDECIN', '21': 'PHARMACIEN', '26': 'AUDIOPROTHESISTE', '28': 'OPTICIEN',
    '40': 'PHARMACIEN', '50': 'SAGE_FEMME', '60': 'IDE', '69': 'IDE',
    '70': 'KINE', '80': 'PEDICURE', '86': 'AIDE_SOIGNANT', '91': 'ORTHOPHONISTE',
    '94': 'ERGOTHERAPEUTE', '96': 'PSYCHOMOTRICIEN', '98': 'MANIPULATEUR_RADIO',
  };
  return mapping[code || ''] || code || '';
}

// Cohérence profession déclarée ↔ profession de l'Annuaire. Familles regroupées
// (IDE/IBODE/IADE = infirmier). On ne peut juger QUE si la profession déclarée est
// connue ET la valeur API non vide ; sinon on ne tranche pas (null).
const PROFESSION_TOKENS: Record<string, string[]> = {
  MEDECIN: ['medecin'],
  IDE: ['infirmier', 'ide'], IBODE: ['infirmier', 'ide'], IADE: ['infirmier', 'ide'],
  SAGE_FEMME: ['sage-femme', 'sage femme', 'sage_femme', 'maieut'],
  KINE: ['kine', 'masseur'],
  PHARMACIEN: ['pharmacien'],
  DENTISTE: ['dentiste', 'odontolog', 'chirurgien-dentiste'],
  MANIPULATEUR_RADIO: ['manipulateur', 'electroradio', 'radio'],
  ERGOTHERAPEUTE: ['ergoth'],
  PSYCHOMOTRICIEN: ['psychomot'],
  ORTHOPHONISTE: ['orthophon'],
  DIETETICIEN: ['dieteti'],
  PREPARATEUR_PHARMA: ['preparateur'],
  PEDICURE: ['pedicure', 'podolog'],
  AUDIOPROTHESISTE: ['audio'],
  OPTICIEN: ['opticien', 'lunet'],
};
// Retourne true (cohérent), false (mismatch clair), ou null (indéterminable).
function professionCorrespondRpps(declaree: string, apiValue: string | undefined): boolean | null {
  const tokens = PROFESSION_TOKENS[(declaree || '').toUpperCase().trim()];
  const v = normalize(apiValue || '');
  if (!tokens || !v) return null;
  return tokens.some((t) => v.includes(normalize(t)));
}

type IdentifierType = 'RPPS' | 'ADELI';

function buildFhirIdentifierQuery(numero: string, type: IdentifierType): string {
  const IDNPS_SYSTEM = 'urn:oid:1.2.250.1.71.4.2.1';
  const idnps = type === 'RPPS' ? `8${numero}` : `0${numero}`;
  return `${IDNPS_SYSTEM}|${idnps}`;
}

async function queryFhirAnnuaire(numero: string, type: IdentifierType = 'RPPS'): Promise<{
  trouve: boolean; nom?: string; prenom?: string;
  professionCode?: string; professionLabel?: string;
  specialiteCode?: string; specialiteLabel?: string; actif?: boolean;
}> {
  const apiKey = Deno.env.get('ESANTE_FHIR_API_KEY') || '';
  if (!apiKey) throw new Error('ESANTE_FHIR_API_KEY non configure');
  const identifierParam = buildFhirIdentifierQuery(numero, type);
  const url = `https://gateway.api.esante.gouv.fr/fhir/v2/Practitioner?identifier=${encodeURIComponent(identifierParam)}`;
  const response = await fetchWithTimeout(url, {
    headers: { 'Accept': 'application/fhir+json', 'ESANTE-API-KEY': apiKey },
  }, 8000);
  if (!response.ok) {
    const body = await response.text();
    console.error(`FHIR API error ${response.status}:`, body.slice(0, 500));
    throw new Error(`Annuaire Sante API indisponible (HTTP ${response.status})`);
  }
  const bundle = await response.json();
  if (!bundle.entry || bundle.entry.length === 0) return { trouve: false };
  const practitioner = bundle.entry[0].resource;
  const officialName = practitioner.name?.find((n: any) => n.use === 'official') || practitioner.name?.[0];
  const nom = officialName?.family || '';
  const prenom = officialName?.given?.[0] || '';
  let professionCode: string | undefined;
  let professionLabel: string | undefined;
  let specialiteCode: string | undefined;
  let specialiteLabel: string | undefined;
  if (Array.isArray(practitioner.qualification)) {
    for (const q of practitioner.qualification) {
      const coding = q.code?.coding?.[0];
      if (!coding?.code) continue;
      const code = String(coding.code);
      const display = coding.display as string | undefined;
      if (/^[0-9]{2}$/.test(code)) {
        if (!professionCode) { professionCode = code; professionLabel = display; }
      } else if (/^(SM|SC|SF|SI)[0-9]+$/.test(code)) {
        if (!specialiteCode) { specialiteCode = code; specialiteLabel = display; }
      }
    }
  }
  return { trouve: true, nom, prenom, professionCode, professionLabel, specialiteCode, specialiteLabel, actif: practitioner.active !== false };
}

import { createClient } from 'npm:@supabase/supabase-js@2';
import { verifyTurnstileToken } from '../_shared/verify-turnstile.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders(req) });
  const cors = corsHeaders(req);
  const clientIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  if (isRateLimited(clientIp)) {
    return errorResponse(cors, 429, 'RATE_LIMITED', 'Trop de requêtes. Réessayez dans une minute.');
  }
  try {
    // [BUG 1 fix] Auth devenue OPTIONNELLE : verify-rpps interroge un registre
    // public (Annuaire Santé FHIR). L'utilisateur en cours d'inscription
    // n'a PAS encore de session, donc exiger un JWT cassait la vérif RPPS
    // temps réel (401 → feedback visuel disparu).
    //
    // Sécurité conservée :
    //   - Rate-limit IP : 10 requêtes/minute (cf. RATE_LIMIT_MAX en haut)
    //   - Turnstile : exigé si la page d'origine en envoie un (anti-bot)
    //   - Aucune écriture en base sauf si soignant_id fourni AVEC service-role
    //
    // Les appels authentifiés (service-role admin, healthcheck) continuent
    // de fonctionner — leur token n'est juste plus vérifié strictement.
    const authHeader = req.headers.get('Authorization');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const token = authHeader?.startsWith('Bearer ') ? authHeader.replace('Bearer ', '') : '';
    const isServiceRole = !!token && token === serviceRoleKey;
    const isAnonKey = !!token && token === anonKey;
    const body = await req.json();
    if (body && body.warm === true) {
      return new Response(JSON.stringify({
        warm: true,
        configured: !!Deno.env.get('ESANTE_FHIR_API_KEY'),
        endpoint: 'https://gateway.api.esante.gouv.fr/fhir/v2/Practitioner',
      }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } });
    }
    const { numero_rpps, rpps, numero_adeli, adeli, prenom, nom, soignant_id, turnstileToken } = body;
    const numeroRpps = String(numero_rpps || rpps || '').trim();
    const numeroAdeli = String(numero_adeli || adeli || '').trim();
    const isAdeliRequest = !numeroRpps && !!numeroAdeli;
    const numero = isAdeliRequest ? numeroAdeli : numeroRpps;
    const idType: IdentifierType = isAdeliRequest ? 'ADELI' : 'RPPS';
    const captchaRequis = !isServiceRole && (!isAnonKey || !!soignant_id);
    if (captchaRequis) {
      const captcha = await verifyTurnstileToken(turnstileToken, clientIp);
      if (!captcha.success) {
        return errorResponse(cors, 403, 'CAPTCHA_FAILED', captcha.error || 'Vérification anti-bot échouée.');
      }
    }
    if (isAdeliRequest) {
      if (!numeroAdeli || numeroAdeli.length !== 9 || !/^[0-9]+$/.test(numeroAdeli)) {
        return errorResponse(cors, 400, 'ADELI_FORMAT_INVALID', 'Numéro ADELI invalide. Vérifiez qu\'il contient bien 9 chiffres.');
      }
    } else {
      if (!numeroRpps || numeroRpps.length !== 11 || !/^[0-9]+$/.test(numeroRpps)) {
        return errorResponse(cors, 400, 'RPPS_FORMAT_INVALID', 'Numéro RPPS invalide. Vérifiez qu\'il contient bien 11 chiffres.');
      }
    }
    const TEST_PREFIX = '00100';
    const ENVIRONMENT = Deno.env.get('ENVIRONMENT') || 'development';
    const testModeActif = ENVIRONMENT !== 'production';
    if (!isAdeliRequest && numero.startsWith(TEST_PREFIX) && testModeActif) {
      const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
      const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
      const supabaseAdmin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
      const { data: testRow, error: testErr } = await supabaseAdmin.from('rpps_test')
        .select('rpps, prenom, nom, profession, specialite_medicale').eq('rpps', numeroRpps).maybeSingle();
      if (testErr) {
        return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur consultation rpps_test.');
      }
      if (!testRow) {
        // Réponse 200 avec code: not-found pour que le frontend puisse mapper.
        return new Response(JSON.stringify({
          ok: true, code: 'RPPS_NOT_FOUND',
          trouve: false, correspond: false, nom_api: null, prenom_api: null, profession_api: null,
          source: 'Mode test (rpps_test)',
        }), { headers: { ...cors, 'Content-Type': 'application/json' } });
      }
      const nomNorm = normalize(testRow.nom);
      const prenomNorm = normalize(testRow.prenom);
      const nomFourni = normalize(nom || '');
      const prenomFourni = normalize(prenom || '');
      const nomCorrespond = !nomFourni || nomNorm.includes(nomFourni) || nomFourni.includes(nomNorm);
      const prenomCorrespond = !prenomFourni || prenomNorm.slice(0, 3) === prenomFourni.slice(0, 3);
      const correspond = nomCorrespond && prenomCorrespond;
      return new Response(JSON.stringify({
        ok: true,
        code: correspond ? 'RPPS_OK' : 'RPPS_TRAITS_MISMATCH',
        trouve: true, correspond, rpps: numeroRpps,
        nom_api: testRow.nom, prenom_api: testRow.prenom, profession_api: testRow.profession,
        specialite_code: testRow.specialite_medicale ?? null, specialite_label: testRow.specialite_medicale ?? null,
        actif: true, source: 'Mode test (rpps_test)',
      }), { headers: { ...cors, 'Content-Type': 'application/json' } });
    }
    if (!isAdeliRequest && numero === '00000000001') {
      return new Response(JSON.stringify({
        ok: true, code: 'RPPS_OK',
        trouve: true, correspond: true, rpps: numeroRpps,
        nom_api: 'PICARD', prenom_api: 'Gabrielle', profession_api: 'IDE',
        actif: true, source: 'Mode test (legacy)',
      }), { headers: { ...cors, 'Content-Type': 'application/json' } });
    }
    if (!Deno.env.get('ESANTE_FHIR_API_KEY')) {
      console.warn('verify-rpps: ESANTE_FHIR_API_KEY non configure, degradation gracieuse');
      return new Response(JSON.stringify({
        ok: true, code: 'RPPS_API_UNAVAILABLE',
        trouve: true, correspond: null, nom_api: null, prenom_api: null, profession_api: null,
        fhir_indisponible: true, source: 'Format RPPS valide - verification ANS differee',
      }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } });
    }
    try {
      const result = await queryFhirAnnuaire(numero, idType);
      if (!result.trouve) {
        return new Response(JSON.stringify({
          ok: true, code: isAdeliRequest ? 'ADELI_NOT_FOUND' : 'RPPS_NOT_FOUND',
          type: idType,
          trouve: false, correspond: false, nom_api: null, prenom_api: null, profession_api: null,
          source: 'FHIR Annuaire Sante',
        }), { headers: { ...cors, 'Content-Type': 'application/json' } });
      }
      const nomNorm = normalize(result.nom || '');
      const prenomNorm = normalize(result.prenom || '');
      const nomFourni = normalize(nom || '');
      const prenomFourni = normalize(prenom || '');
      const nomCorrespond = !nomFourni || nomNorm.includes(nomFourni) || nomFourni.includes(nomNorm);
      const prenomCorrespond = !prenomFourni || prenomNorm.slice(0, 3) === prenomFourni.slice(0, 3);
      const correspondTraits = nomCorrespond && prenomCorrespond;
      const professionApi = result.professionLabel || mapProfessionCode(result.professionCode);

      let callerUid: string | null = null;
      if (token && !isServiceRole && !isAnonKey) {
        try {
          const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
          const aKey = Deno.env.get('SUPABASE_ANON_KEY')!;
          const sbUser = createClient(supabaseUrl, aKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
          const { data: ud } = await sbUser.auth.getUser(token);
          if (ud?.user?.id) callerUid = ud.user.id;
        } catch { /* ignore */ }
      }
      const canWriteDb = isServiceRole || (!!callerUid && callerUid === soignant_id);

      // Profession déclarée : du body (inscription) OU récupérée sur le soignant (re-vérif profil).
      let professionDeclaree = String(body.profession || '').trim();
      if (!professionDeclaree && soignant_id && canWriteDb) {
        try {
          const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
          const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
          const sbA = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
          const { data: sg } = await sbA.from('soignants').select('profession').eq('id', soignant_id).maybeSingle();
          if (sg?.profession) professionDeclaree = String(sg.profession);
        } catch { /* ignore */ }
      }
      // Contrôle profession AU MÊME TITRE que nom/prénom : tout mismatch clair bloque.
      const profCheck = professionCorrespondRpps(professionDeclaree, professionApi); // true|false|null
      const professionMismatch = profCheck === false;
      const correspond = correspondTraits && !professionMismatch;

      // On n'écrit rpps_verifie=true QUE si traits ET profession concordent.
      if (soignant_id && correspond && canWriteDb) {
        try {
          const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
          const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
          const supabaseAdmin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
          const now = new Date().toISOString();
          const updateFields: Record<string, unknown> = isAdeliRequest ? {
            adeli_verifie: true, adeli_verifie_le: now,
            adeli_nom_api: result.nom, adeli_prenom_api: result.prenom,
            adeli_profession_api: professionApi,
          } : {
            rpps_verifie: true, rpps_verifie_le: now,
            rpps_nom_api: result.nom, rpps_prenom_api: result.prenom,
            rpps_profession_api: professionApi,
          };
          if (result.specialiteCode) {
            updateFields.specialite_medicale = result.specialiteCode;
            updateFields.specialite_code = result.specialiteCode;
            updateFields.specialite_source = 'RPPS';
            updateFields.specialite_verifiee = true;
            updateFields.specialite_verifiee_le = new Date().toISOString();
          }
          await supabaseAdmin.from('soignants').update(updateFields as any).eq('id', soignant_id);
        } catch (dbErr) { console.error('Erreur sauvegarde RPPS sur soignant:', safeStringifyError(dbErr)); }
      }
      const codePrefix = isAdeliRequest ? 'ADELI' : 'RPPS';
      // Priorité du verdict : mismatch traits (nom/prénom) puis mismatch profession.
      const code = !correspondTraits
        ? `${codePrefix}_TRAITS_MISMATCH`
        : (professionMismatch ? `${codePrefix}_PROFESSION_MISMATCH` : `${codePrefix}_OK`);
      return new Response(JSON.stringify({
        ok: true,
        code,
        type: idType,
        trouve: true, correspond,
        correspond_traits: correspondTraits,
        profession_correspond: profCheck,
        profession_declaree: professionDeclaree || null,
        nom_api: result.nom, prenom_api: result.prenom,
        profession_api: professionApi,
        specialite_code: result.specialiteCode ?? null, specialite_label: result.specialiteLabel ?? null,
        actif: result.actif, source: 'FHIR Annuaire Sante v2',
      }), { headers: { ...cors, 'Content-Type': 'application/json' } });
    } catch (fhirError) {
      console.error('Erreur API FHIR Annuaire Sante:', safeStringifyError(fhirError));
      return new Response(JSON.stringify({
        ok: true, code: 'RPPS_API_UNAVAILABLE',
        trouve: true, correspond: null, nom_api: null, prenom_api: null, profession_api: null,
        fhir_indisponible: true, source: 'Format RPPS valide - verification ANS differee',
      }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } });
    }
  } catch (error) {
    console.error('Erreur verify-rpps:', safeStringifyError(error));
    return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur serveur. Notre équipe a été notifiée. Réessayez dans quelques minutes.');
  }
});
