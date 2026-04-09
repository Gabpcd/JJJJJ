import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.jolene.app" ||
    origin === "https://jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://app.jolene.app";
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

// Rate limiting simple en mémoire (par IP, 10 req/min)
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

/** Normalise une chaîne pour comparaison (minuscule, sans accents, sans espaces superflus) */
function normalize(s: string): string {
  return (s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
}

/** Mapping des codes profession FHIR → codes internes */
function mapProfessionCode(code: string | undefined): string {
  const mapping: Record<string, string> = {
    '10': 'MEDECIN',
    '21': 'PHARMACIEN',
    '26': 'AUDIOPROTHESISTE',
    '28': 'OPTICIEN',
    '40': 'PHARMACIEN',
    '50': 'SAGE_FEMME',
    '60': 'IDE',
    '69': 'IDE',   // Infirmier psychiatrique
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

/**
 * Interroge l'API FHIR officielle de l'Annuaire Santé (ANS).
 * Endpoint : https://gateway.api.esante.gouv.fr/fhir/v1/Practitioner
 * Documentation : https://ansforge.github.io/annuaire-sante-fhir-documentation/
 */
async function queryFhirAnnuaire(rpps: string): Promise<{
  trouve: boolean;
  nom?: string;
  prenom?: string;
  professionCode?: string;
  professionLabel?: string;
  actif?: boolean;
}> {
  const FHIR_BASE = 'https://gateway.api.esante.gouv.fr/fhir/v1';
  const url = `${FHIR_BASE}/Practitioner?identifier=${rpps}&_format=json`;

  const response = await fetchWithTimeout(url, {
    headers: {
      'Accept': 'application/fhir+json',
      'User-Agent': 'Jolene/1.0',
    },
  }, 8000);

  if (!response.ok) {
    const body = await response.text();
    console.error(`FHIR API error ${response.status}:`, body.slice(0, 500));
    throw new Error(`Annuaire Santé API indisponible (HTTP ${response.status})`);
  }

  const bundle = await response.json();

  // FHIR Bundle — check if any entries match
  if (!bundle.entry || bundle.entry.length === 0) {
    return { trouve: false };
  }

  const practitioner = bundle.entry[0].resource;

  // Extract name (FHIR HumanName)
  const officialName = practitioner.name?.find((n: any) => n.use === 'official') || practitioner.name?.[0];
  const nom = officialName?.family || '';
  const prenom = officialName?.given?.[0] || '';

  // Extract profession from qualification
  let professionCode: string | undefined;
  let professionLabel: string | undefined;
  if (practitioner.qualification) {
    for (const q of practitioner.qualification) {
      const coding = q.code?.coding?.[0];
      if (coding) {
        professionCode = coding.code;
        professionLabel = coding.display;
        break;
      }
    }
  }

  return {
    trouve: true,
    nom,
    prenom,
    professionCode,
    professionLabel,
    actif: practitioner.active !== false,
  };
}

import { createClient } from "npm:@supabase/supabase-js@2";

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  // Rate limiting par IP
  const clientIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  if (isRateLimited(clientIp)) {
    return new Response(JSON.stringify({ error: 'Trop de requêtes' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  try {
    // Auth: verify JWT user or service_role
    const authHeader = req.headers.get('Authorization');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    if (!authHeader?.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'Non autorisé' }), {
        status: 401,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }
    const token = authHeader.replace('Bearer ', '');
    const isServiceRole = token === serviceRoleKey;
    if (!isServiceRole) {
      const supabaseAuth = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_ANON_KEY')!,
      );
      const { data: { user }, error: authErr } = await supabaseAuth.auth.getUser(token);
      if (authErr || !user) {
        return new Response(JSON.stringify({ error: 'Token invalide' }), {
          status: 401,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    const { numero_rpps, rpps, prenom, nom, soignant_id } = await req.json();
    const numeroRpps = String(numero_rpps || rpps || '').trim();

    if (!numeroRpps || !/^\d{11}$/.test(numeroRpps)) {
      return new Response(JSON.stringify({ error: 'Numéro RPPS invalide (11 chiffres requis)' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Mode test explicite
    if (numeroRpps === '00000000001') {
      return new Response(JSON.stringify({
        trouve: true,
        correspond: true,
        rpps: numeroRpps,
        nom_api: 'PICARD',
        prenom_api: 'Gabrielle',
        profession_api: 'IDE',
        actif: true,
        source: 'Mode test',
      }), {
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Appel API FHIR officielle de l'Annuaire Santé
    try {
      const result = await queryFhirAnnuaire(numeroRpps);

      if (!result.trouve) {
        return new Response(JSON.stringify({
          trouve: false,
          correspond: false,
          nom_api: null,
          prenom_api: null,
          profession_api: null,
          source: 'FHIR Annuaire Santé',
        }), {
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }

      // Vérification de correspondance d'identité
      const nomNorm = normalize(result.nom || '');
      const prenomNorm = normalize(result.prenom || '');
      const nomFourni = normalize(nom || '');
      const prenomFourni = normalize(prenom || '');

      // Nom : doit correspondre (contient ou est contenu)
      const nomCorrespond = !nomFourni || nomNorm.includes(nomFourni) || nomFourni.includes(nomNorm);

      // Prénom : comparaison sur les 3 premières lettres (prénoms composés)
      const prenomCorrespond = !prenomFourni ||
        prenomNorm.slice(0, 3) === prenomFourni.slice(0, 3);

      const correspond = nomCorrespond && prenomCorrespond;

      // Sauvegarder les données RPPS API sur le profil soignant si soignant_id fourni
      if (soignant_id && correspond) {
        try {
          const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
          const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
          const supabaseAdmin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
          await supabaseAdmin.from('soignants').update({
            rpps_verifie: true,
            rpps_verifie_le: new Date().toISOString(),
            rpps_nom_api: result.nom,
            rpps_prenom_api: result.prenom,
            rpps_profession_api: result.professionLabel || mapProfessionCode(result.professionCode),
          } as any).eq('id', soignant_id);
        } catch (dbErr) {
          console.error('Erreur sauvegarde RPPS sur soignant:', dbErr);
        }
      }

      return new Response(JSON.stringify({
        trouve: true,
        correspond,
        nom_api: result.nom,
        prenom_api: result.prenom,
        profession_api: result.professionLabel || mapProfessionCode(result.professionCode),
        actif: result.actif,
        source: 'FHIR Annuaire Santé',
      }), {
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });

    } catch (fhirError) {
      console.error('Erreur API FHIR Annuaire Santé:', fhirError);
      // En cas d'indisponibilité de l'API, on bloque par sécurité
      return new Response(JSON.stringify({
        error: 'Impossible de vérifier le numéro RPPS auprès de l\'Annuaire Santé. Réessayez ultérieurement.',
      }), {
        status: 503,
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
