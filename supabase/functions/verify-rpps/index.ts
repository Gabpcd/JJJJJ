import { errorResponse, safeStringifyError } from '../_shared/errors.ts';
import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { corsHeaders, jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { verifyAdminOrServiceRole, verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';

async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].slice(0, 16)
    .map((octet) => octet.toString(16).padStart(2, '0')).join('');
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Methode non autorisee' }, 405);
  const cors = corsHeaders(req);
  const clientIp = getClientIp(req);
  if (applyRateLimit('verify-rpps', clientIp, { max: 10, windowMs: 60_000 })) {
    return jsonResponse(req, { ok: false, code: 'RATE_LIMITED', message: 'Trop de requêtes. Réessayez dans une minute.' }, 429);
  }
  try {
    // [BUG 1 fix] Auth devenue OPTIONNELLE : verify-rpps interroge un registre
    // public (Annuaire Santé FHIR). L'utilisateur en cours d'inscription
    // n'a PAS encore de session, donc exiger un JWT cassait la vérif RPPS
    // temps réel (401 → feedback visuel disparu).
    //
    // Le lookup temps reel precede signUp. Son token Turnstile ne doit surtout
    // pas etre consomme ici puis reutilise par Auth (token a usage unique).
    // La protection repose sur les quotas memoire + PostgreSQL ci-dessous.
    // Toute ecriture reste reservee au service-role ou au profil authentifie.
    const authHeader = req.headers.get('Authorization');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const token = authHeader?.startsWith('Bearer ') ? authHeader.replace('Bearer ', '') : '';
    const isServiceRole = !!token && token === serviceRoleKey;
    const isAnonKey = !!token && token === anonKey;
    let callerUid: string | null = null;
    if (token && !isServiceRole && !isAnonKey) {
      const auth = await verifyUserOrServiceRole(req);
      if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);
      callerUid = auth.userId;
    }

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || Array.isArray(body)) return jsonResponse(req, { error: 'Corps JSON invalide' }, 400);
    if (body && body.warm === true) {
      const adminAuth = await verifyAdminOrServiceRole(req);
      if (!adminAuth.ok) return jsonResponse(req, { error: adminAuth.error }, adminAuth.status);
      return jsonResponse(req, {
        warm: true,
        configured: !!Deno.env.get('ESANTE_FHIR_API_KEY'),
        endpoint: 'https://gateway.api.esante.gouv.fr/fhir/v2/Practitioner',
      });
    }
    const numeroRpps = String(body.numero_rpps || body.rpps || '').trim();
    const numeroAdeli = String(body.numero_adeli || body.adeli || '').trim();
    const prenom = typeof body.prenom === 'string' ? body.prenom : '';
    const nom = typeof body.nom === 'string' ? body.nom : '';
    const soignantId = typeof body.soignant_id === 'string' ? body.soignant_id : null;
    if (body.soignant_id && (!soignantId || !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(soignantId))) {
      return jsonResponse(req, { error: 'soignant_id invalide' }, 400);
    }
    if (soignantId && !isServiceRole && callerUid !== soignantId) {
      return jsonResponse(req, { error: 'Ecriture profil interdite' }, 403);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    if (!supabaseUrl || !serviceRoleKey) return jsonResponse(req, { error: 'Service indisponible' }, 503);
    if (!isServiceRole) {
      const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
      const { data: allowed, error: rateError } = await admin.rpc('fn_verifier_rate_limit', {
        p_cle: await fingerprint(clientIp === 'unknown'
          ? `unknown|${(req.headers.get('user-agent') || '').slice(0, 160)}`
          : clientIp),
        p_action: 'edge_verify_rpps',
        p_max_tentatives: 30,
        p_fenetre_secondes: 600,
      });
      if (rateError) return jsonResponse(req, { error: 'Service temporairement indisponible' }, 503);
      if (allowed !== true) return jsonResponse(req, { code: 'RATE_LIMITED', error: 'Quota de verification atteint' }, 429);
    }

    const isAdeliRequest = !numeroRpps && !!numeroAdeli;
    const numero = isAdeliRequest ? numeroAdeli : numeroRpps;
    const idType: IdentifierType = isAdeliRequest ? 'ADELI' : 'RPPS';
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
    const testModeActif = Deno.env.get('ALLOW_DEMO_IDENTIFIERS') === 'true';
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
    if (!isAdeliRequest && numero === '00000000001' && testModeActif) {
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

      const canWriteDb = isServiceRole || (!!callerUid && callerUid === soignantId);

      // Profession déclarée : du body (inscription) OU récupérée sur le soignant (re-vérif profil).
      let professionDeclaree = String(body.profession || '').trim();
      if (!professionDeclaree && soignantId && canWriteDb) {
        try {
          const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
          const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
          const sbA = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
          const { data: sg } = await sbA.from('soignants').select('profession').eq('id', soignantId).maybeSingle();
          if (sg?.profession) professionDeclaree = String(sg.profession);
        } catch { /* ignore */ }
      }
      // Contrôle profession AU MÊME TITRE que nom/prénom : tout mismatch clair bloque.
      const profCheck = professionCorrespondRpps(professionDeclaree, professionApi); // true|false|null
      const professionMismatch = profCheck === false;
      const correspond = correspondTraits && !professionMismatch;

      // On n'écrit rpps_verifie=true QUE si traits ET profession concordent.
      if (soignantId && correspond && canWriteDb) {
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
          await supabaseAdmin.from('soignants').update(updateFields as any).eq('id', soignantId);
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
