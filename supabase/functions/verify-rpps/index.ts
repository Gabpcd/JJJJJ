function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
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
    '10': 'MEDECIN',
    '21': 'PHARMACIEN',
    '26': 'AUDIOPROTHESISTE',
    '28': 'OPTICIEN',
    '40': 'PHARMACIEN',
    '50': 'SAGE_FEMME',
    '60': 'IDE',
    '69': 'IDE',
    '70': 'KINE',
    '80': 'PEDICURE',
    '86': 'AIDE_SOIGNANT',
    '91': 'ORTHOPHONISTE',
    '94': 'ERGOTHERAPEUTE',
    '96': 'PSYCHOMOTRICIEN',
    '98': 'MANIPULATEUR_RADIO',
  };
  return mapping[code || ''] || code || '';
}

async function queryFhirAnnuaire(rpps: string): Promise<{
  trouve: boolean;
  nom?: string;
  prenom?: string;
  professionCode?: string;
  professionLabel?: string;
  specialiteCode?: string;
  specialiteLabel?: string;
  actif?: boolean;
}> {
  // API FHIR Annuaire Santé v2 (ANS) — authentification via clé Gravitee.
  // La clé ESANTE_FHIR_API_KEY est obtenue sur portal.api.esante.gouv.fr.
  // Header officiel : ESANTE-API-KEY (cf. doc ansforge.github.io).
  const apiKey = Deno.env.get('ESANTE_FHIR_API_KEY') || '';
  if (!apiKey) {
    throw new Error('ESANTE_FHIR_API_KEY non configuré');
  }
  const FHIR_BASE = 'https://gateway.api.esante.gouv.fr/fhir/v2';
  const url = `${FHIR_BASE}/Practitioner?identifier=${rpps}`;

  const response = await fetchWithTimeout(url, {
    headers: {
      'Accept': 'application/fhir+json',
      'ESANTE-API-KEY': apiKey,
    },
  }, 8000);

  if (!response.ok) {
    const body = await response.text();
    console.error(`FHIR API error ${response.status}:`, body.slice(0, 500));
    throw new Error(`Annuaire Sante API indisponible (HTTP ${response.status})`);
  }

  const bundle = await response.json();

  if (!bundle.entry || bundle.entry.length === 0) {
    return { trouve: false };
  }

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
        if (!professionCode) {
          professionCode = code;
          professionLabel = display;
        }
      } else if (/^(SM|SC|SF|SI)[0-9]+$/.test(code)) {
        if (!specialiteCode) {
          specialiteCode = code;
          specialiteLabel = display;
        }
      }
    }
  }

  return {
    trouve: true,
    nom,
    prenom,
    professionCode,
    professionLabel,
    specialiteCode,
    specialiteLabel,
    actif: practitioner.active !== false,
  };
}

import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyTurnstileToken } from "../_shared/verify-turnstile.ts";

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  const clientIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  if (isRateLimited(clientIp)) {
    return new Response(JSON.stringify({ error: 'Trop de requetes' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    if (!authHeader?.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'Non autorise' }), {
        status: 401,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }
    const token = authHeader.replace('Bearer ', '');
    const isServiceRole = token === serviceRoleKey;
    const isAnonKey = token === anonKey;
    if (!isServiceRole && !isAnonKey) {
      const supabaseAuth = createClient(
        Deno.env.get('SUPABASE_URL')!,
        anonKey,
      );
      const { data: { user }, error: authErr } = await supabaseAuth.auth.getUser(token);
      if (authErr || !user) {
        return new Response(JSON.stringify({ error: 'Token invalide' }), {
          status: 401,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    const body = await req.json();
    // Warm ping admin healthcheck — pas d'effet de bord, juste retourne statut config.
    if (body && body.warm === true) {
      return new Response(JSON.stringify({
        warm: true,
        configured: !!Deno.env.get('ESANTE_FHIR_API_KEY'),
        endpoint: 'https://gateway.api.esante.gouv.fr/fhir/v2/Practitioner',
      }), {
        status: 200,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const { numero_rpps, rpps, prenom, nom, soignant_id, turnstileToken } = body;
    const numeroRpps = String(numero_rpps || rpps || '').trim();

    const captchaRequis = !isServiceRole && (!isAnonKey || !!soignant_id);
    if (captchaRequis) {
      const captcha = await verifyTurnstileToken(turnstileToken, clientIp);
      if (!captcha.success) {
        return new Response(JSON.stringify({ error: captcha.error }), {
          status: 403,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    if (!numeroRpps || numeroRpps.length !== 11 || !/^[0-9]+$/.test(numeroRpps)) {
      return new Response(JSON.stringify({ error: 'Numero RPPS invalide (11 chiffres requis)' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const TEST_PREFIX = '00100';
    const ENVIRONMENT = Deno.env.get('ENVIRONMENT') || 'development';
    const testModeActif = ENVIRONMENT !== 'production';

    if (numeroRpps.startsWith(TEST_PREFIX) && testModeActif) {
      const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
      const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
      const supabaseAdmin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
      const { data: testRow, error: testErr } = await supabaseAdmin
        .from('rpps_test')
        .select('rpps, prenom, nom, profession, specialite_medicale')
        .eq('rpps', numeroRpps)
        .maybeSingle();

      if (testErr) {
        console.error('Erreur lookup rpps_test:', testErr);
        return new Response(JSON.stringify({ error: 'Erreur consultation rpps_test' }), {
          status: 500,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }

      if (!testRow) {
        return new Response(JSON.stringify({
          trouve: false, correspond: false, nom_api: null, prenom_api: null, profession_api: null,
          source: 'Mode test (rpps_test)',
        }), {
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }

      const nomNorm = normalize(testRow.nom);
      const prenomNorm = normalize(testRow.prenom);
      const nomFourni = normalize(nom || '');
      const prenomFourni = normalize(prenom || '');
      const nomCorrespond = !nomFourni || nomNorm.includes(nomFourni) || nomFourni.includes(nomNorm);
      const prenomCorrespond = !prenomFourni || prenomNorm.slice(0, 3) === prenomFourni.slice(0, 3);
      const correspond = nomCorrespond && prenomCorrespond;

      if (soignant_id && correspond) {
        try {
          const updateFields: Record<string, unknown> = {
            rpps_verifie: true,
            rpps_verifie_le: new Date().toISOString(),
            rpps_nom_api: testRow.nom,
            rpps_prenom_api: testRow.prenom,
            rpps_profession_api: testRow.profession,
          };
          if (testRow.specialite_medicale) {
            updateFields.specialite_medicale = testRow.specialite_medicale;
            updateFields.specialite_code = testRow.specialite_medicale;
            updateFields.specialite_source = 'RPPS';
            updateFields.specialite_verifiee = true;
            updateFields.specialite_verifiee_le = new Date().toISOString();
          }
          await supabaseAdmin.from('soignants').update(updateFields as any).eq('id', soignant_id);
        } catch (dbErr) {
          console.error('Erreur sauvegarde RPPS test sur soignant:', dbErr);
        }
      }

      return new Response(JSON.stringify({
        trouve: true, correspond, rpps: numeroRpps,
        nom_api: testRow.nom, prenom_api: testRow.prenom, profession_api: testRow.profession,
        specialite_code: testRow.specialite_medicale ?? null,
        specialite_label: testRow.specialite_medicale ?? null,
        actif: true, source: 'Mode test (rpps_test)',
      }), {
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    if (numeroRpps === '00000000001') {
      return new Response(JSON.stringify({
        trouve: true, correspond: true, rpps: numeroRpps,
        nom_api: 'PICARD', prenom_api: 'Gabrielle', profession_api: 'IDE',
        actif: true, source: 'Mode test (legacy)',
      }), {
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Si la clé API n'est pas configurée, retour gracieux : format valide,
    // vérification différée (admin reverra manuellement).
    if (!Deno.env.get('ESANTE_FHIR_API_KEY')) {
      console.warn('verify-rpps: ESANTE_FHIR_API_KEY non configuré, dégradation gracieuse');
      return new Response(JSON.stringify({
        trouve: true, correspond: null, nom_api: null, prenom_api: null, profession_api: null,
        fhir_indisponible: true, source: 'Format RPPS valide — vérification ANS différée',
      }), {
        status: 200,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    try {
      const result = await queryFhirAnnuaire(numeroRpps);

      if (!result.trouve) {
        return new Response(JSON.stringify({
          trouve: false, correspond: false, nom_api: null, prenom_api: null, profession_api: null,
          source: 'FHIR Annuaire Sante',
        }), {
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }

      const nomNorm = normalize(result.nom || '');
      const prenomNorm = normalize(result.prenom || '');
      const nomFourni = normalize(nom || '');
      const prenomFourni = normalize(prenom || '');
      const nomCorrespond = !nomFourni || nomNorm.includes(nomFourni) || nomFourni.includes(nomNorm);
      const prenomCorrespond = !prenomFourni || prenomNorm.slice(0, 3) === prenomFourni.slice(0, 3);
      const correspond = nomCorrespond && prenomCorrespond;

      if (soignant_id && correspond) {
        try {
          const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
          const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
          const supabaseAdmin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
          const updateFields: Record<string, unknown> = {
            rpps_verifie: true,
            rpps_verifie_le: new Date().toISOString(),
            rpps_nom_api: result.nom,
            rpps_prenom_api: result.prenom,
            rpps_profession_api: result.professionLabel || mapProfessionCode(result.professionCode),
          };
          if (result.specialiteCode) {
            updateFields.specialite_medicale = result.specialiteCode;
            updateFields.specialite_code = result.specialiteCode;
            updateFields.specialite_source = 'RPPS';
            updateFields.specialite_verifiee = true;
            updateFields.specialite_verifiee_le = new Date().toISOString();
          }
          await supabaseAdmin.from('soignants').update(updateFields as any).eq('id', soignant_id);
        } catch (dbErr) {
          console.error('Erreur sauvegarde RPPS sur soignant:', dbErr);
        }
      }

      return new Response(JSON.stringify({
        trouve: true, correspond,
        nom_api: result.nom, prenom_api: result.prenom,
        profession_api: result.professionLabel || mapProfessionCode(result.professionCode),
        specialite_code: result.specialiteCode ?? null,
        specialite_label: result.specialiteLabel ?? null,
        actif: result.actif, source: 'FHIR Annuaire Sante v2',
      }), {
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });

    } catch (fhirError) {
      console.error('Erreur API FHIR Annuaire Sante:', fhirError);
      return new Response(JSON.stringify({
        trouve: true, correspond: null, nom_api: null, prenom_api: null, profession_api: null,
        fhir_indisponible: true, source: 'Format RPPS valide - verification ANS differee',
      }), {
        status: 200,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

  } catch (error) {
    console.error('Erreur verify-rpps:', error);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), {
      status: 500,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
