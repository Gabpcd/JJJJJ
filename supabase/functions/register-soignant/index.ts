import { createClient } from 'npm:@supabase/supabase-js@2';
import { verifyTurnstileToken } from '../_shared/verify-turnstile.ts';

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

// M7: Rate limiting - 5 requests per IP per 10 minutes
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

// Professions exemptées de RPPS (aides-soignantes, accompagnants éducatifs)
const PROFESSIONS_SANS_RPPS = ['AS', 'AES'];

function normalizeStr(s: string): string {
  return (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
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

/** Server-side RPPS verification against Annuaire Santé */
async function verifierRppsServeur(rpps: string, nom: string, prenom: string): Promise<{ valide: boolean; verifie?: boolean; erreur?: string }> {
  // Mode test
  if (rpps === '00000000001') {
    return { valide: true, verifie: true };
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  try {
    // Call our own verify-rpps Edge Function internally
    const res = await fetchWithTimeout(
      `${supabaseUrl}/functions/v1/verify-rpps`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${serviceRoleKey}`,
        },
        body: JSON.stringify({ rpps, nom, prenom }),
      },
      10000
    );

    if (!res.ok) {
      console.error('verify-rpps HTTP error:', res.status);
      // On network/service failure, we still block — security first
      return { valide: false, erreur: 'Impossible de vérifier le numéro RPPS. Réessayez.' };
    }

    const data = await res.json();

    if (!data.trouve) {
      return { valide: false, erreur: 'Numéro RPPS introuvable dans l\'annuaire santé.' };
    }

    if (data.correspond === false) {
      return { valide: false, erreur: 'Le numéro RPPS ne correspond pas à votre identité (nom/prénom).' };
    }

    if (data.fhir_indisponible) {
      return { valide: true, verifie: false };
    }

    return { valide: true, verifie: true };
  } catch (err) {
    console.error('RPPS verification error:', err);
    return { valide: false, erreur: 'Impossible de vérifier le numéro RPPS. Réessayez.' };
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  // M7: Rate limiting
  const clientIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  if (!checkRateLimit(clientIp)) {
    return new Response(JSON.stringify({ error: 'Trop de tentatives. Réessayez dans quelques minutes.' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // 1. Authenticate caller via JWT
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Non authentifié' }), {
      status: 401,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  const token = authHeader.replace('Bearer ', '');
  const supabaseAuth = createClient(supabaseUrl, anonKey);
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'Non authentifié' }), {
      status: 401,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  try {
    const body = await req.json();
    const { prenom, nom, telephone, dateNaissance, profession, typesContrat,
      rpps, rayon, lat, lng, turnstileToken } = body;

    // Captcha anti-bot Cloudflare Turnstile (no-op tant que TURNSTILE_SECRET_KEY non configurée)
    const captcha = await verifyTurnstileToken(turnstileToken, clientIp);
    if (!captcha.success) {
      return new Response(JSON.stringify({ error: captcha.error }), {
        status: 403,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Validate required fields
    if (!prenom || !nom || !profession) {
      return new Response(JSON.stringify({ error: 'Champs obligatoires manquants (prenom, nom, profession)' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // E7: dateNaissance is mandatory
    if (!dateNaissance) {
      return new Response(JSON.stringify({ error: 'Date de naissance requise.' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // L2: Server-side age verification (must be 18+)
    {
      const birth = new Date(dateNaissance);
      const today = new Date();
      const age = today.getFullYear() - birth.getFullYear();
      const monthDiff = today.getMonth() - birth.getMonth();
      const dayDiff = today.getDate() - birth.getDate();
      const actualAge = monthDiff < 0 || (monthDiff === 0 && dayDiff < 0) ? age - 1 : age;
      if (actualAge < 18) {
        return new Response(JSON.stringify({ error: 'Vous devez avoir au moins 18 ans pour vous inscrire.' }), {
          status: 400,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    // ══════════════════════════════════════════════════
    // RPPS VERIFICATION — Server-side (double vérification)
    // ══════════════════════════════════════════════════
    const rppsObligatoire = !PROFESSIONS_SANS_RPPS.includes(profession);
    let rppsServerVerifie = false;

    if (rppsObligatoire) {
      // RPPS is mandatory for this profession
      if (!rpps || !/^\d{11}$/.test(rpps)) {
        return new Response(JSON.stringify({ error: 'Le numéro RPPS est obligatoire pour votre profession (11 chiffres).' }), {
          status: 400,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }

      // Verify against Annuaire Santé
      const verification = await verifierRppsServeur(rpps, nom, prenom);
      if (!verification.valide) {
        return new Response(JSON.stringify({ error: verification.erreur }), {
          status: 400,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
      rppsServerVerifie = verification.verifie !== false;
    } else {
      // For AS/AES: RPPS optional, but validate format if provided
      if (rpps && !/^\d{11}$/.test(rpps)) {
        return new Response(JSON.stringify({ error: 'Numéro RPPS invalide (11 chiffres requis)' }), {
          status: 400,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    // Validate rayon
    const rayonKm = typeof rayon === 'number' ? Math.min(Math.max(rayon, 5), 100) : 30;

    // Sanitize typesContrat
    const validContrats = ['CDDU', 'VACATION', 'LIBERAL', 'SALARIE'];
    const contrats: string[] = Array.isArray(typesContrat)
      ? typesContrat.filter((c: string) => validContrats.includes(c))
      : ['CDDU'];
    if (contrats.length === 0) contrats.push('CDDU');

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      db: { schema: 'public' },
    });

    // 2. Insert into soignants table (server-side, no client manipulation possible)
    const insertPayload = {
      id: user.id,
      prenom: String(prenom).slice(0, 100),
      nom: String(nom).slice(0, 100),
      email: user.email,
      telephone: telephone ? String(telephone).slice(0, 20) : null,
      date_naissance: dateNaissance || null,
      profession,
      type_contrat: contrats[0],
      types_contrat_acceptes: JSON.stringify(contrats),
      numero_rpps: rpps || null,
      rpps_verifie: rppsObligatoire && !!rpps && rppsServerVerifie,
      rayon_deplacement_km: rayonKm,
      adresse_lat: typeof lat === 'number' ? lat : null,
      adresse_lng: typeof lng === 'number' ? lng : null,
    };

    const { error: insertError } = await supabaseAdmin
      .from('soignants')
      .insert(insertPayload);

    if (insertError) {
      console.error('INSERT soignants échoué', insertError.code);
      const msg = insertError.message || '';
      if (msg.includes('duplicate key')) {
        return new Response(JSON.stringify({ error: 'Un compte avec cet identifiant existe déjà.' }), {
          status: 409,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify({ error: 'Erreur lors de la création du profil soignant.' }), {
        status: 500,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // 3. Set app_metadata role — server-side
    const { error: claimsError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
      app_metadata: { role: 'SOIGNANT' },
    });

    if (claimsError) {
      console.error('set-user-claims échoué', claimsError.code);
      // Rollback
      await supabaseAdmin.from('soignants').delete().eq('id', user.id);
      return new Response(JSON.stringify({ error: 'Erreur lors de la configuration du compte.' }), {
        status: 500,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // 4. Audit inscription + CGU consent
    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id,
      type_acteur: 'SOIGNANT',
      action: 'INSCRIPTION',
      type_ressource: 'soignant',
      id_ressource: user.id,
      details: { evenement: 'inscription', profession, rpps_verifie: rppsObligatoire && !!rpps && rppsServerVerifie },
      navigateur_acteur: body.navigateur || null,
    });

    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id,
      type_acteur: 'SOIGNANT',
      action: 'RGPD_CONSENTEMENT_DONNE',
      type_ressource: 'soignant',
      id_ressource: user.id,
      details: { type: 'inscription', cgu: true, confidentialite: true },
      navigateur_acteur: body.navigateur || null,
    });

    // 5. Email bienvenue (best-effort — ne bloque pas l'inscription)
    try {
      await supabaseAdmin.functions.invoke('send-email', {
        body: {
          type: 'BIENVENUE_SOIGNANT',
          destinataire_id: user.id,
          data: {
            prenom: String(prenom).slice(0, 100),
            nom: String(nom).slice(0, 100),
            profession,
            lien_dashboard: 'https://jolene.app/soignant',
          },
        },
      });
    } catch (emailErr) {
      console.warn('[register-soignant] Email bienvenue non envoyé (best-effort):', emailErr);
    }

    // 6. Planifier la série onboarding J0/J1/J3/J7 (best-effort)
    try {
      await supabaseAdmin.rpc('fn_planifier_serie_onboarding', {
        p_utilisateur_id: user.id,
        p_serie: 'SOIGNANT_ONBOARDING',
      });
    } catch (serieErr) {
      console.warn('[register-soignant] Planification série onboarding échouée (best-effort):', serieErr);
    }

    return new Response(JSON.stringify({ success: true, soignant_id: user.id }), {
      status: 200,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('register-soignant error:', err);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), {
      status: 500,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
