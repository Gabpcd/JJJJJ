import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  const allowed = [
    "https://app.soindirect.com",
    "https://soinc-direct.lovable.app",
    "http://localhost:5173",
  ];
  return allowed.includes(origin) ? origin : allowed[0];
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

serve(async (req) => {
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
    const { nom, siret, finess, type, adresse_rue, adresse_ville, adresse_code_postal,
      adresse_departement, telephone_contact, email_contact, adresse_lat, adresse_lng,
      numero_licence } = body;

    // Validate required fields
    if (!nom || !siret || !type || !adresse_ville) {
      return new Response(JSON.stringify({ error: 'Champs obligatoires manquants' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Luhn validation
    if (!/^\d{14}$/.test(siret) || /^0+$/.test(siret)) {
      return new Response(JSON.stringify({ error: 'Le SIRET doit contenir 14 chiffres' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }
    {
      let sum = 0;
      for (let i = 0; i < 14; i++) {
        let d = parseInt(siret[i], 10);
        if (i % 2 === 0) { d *= 2; if (d > 9) d -= 9; }
        sum += d;
      }
      if (sum % 10 !== 0) {
        return new Response(JSON.stringify({ error: 'SIRET invalide (checksum incorrecte)' }), {
          status: 400,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // 2. Insert into etablissements table
    const insertPayload = {
      id: user.id,
      nom,
      siret,
      finess: finess || null,
      type,
      adresse_rue: adresse_rue || 'Non renseigné',
      adresse_ville,
      adresse_code_postal: adresse_code_postal || '00000',
      adresse_departement: adresse_departement || null,
      email_contact: email_contact || user.email,
      telephone_contact: telephone_contact || null,
      adresse_lat: adresse_lat || null,
      adresse_lng: adresse_lng || null,
    };

    const { error: insertError } = await supabaseAdmin
      .from('etablissements')
      .insert(insertPayload);

    if (insertError) {
      console.error('INSERT etablissements échoué', insertError.code);
      const msg = insertError.message || '';
      if (msg.includes('duplicate key') && msg.includes('siret')) {
        return new Response(JSON.stringify({ error: 'Ce numéro SIRET est déjà enregistré.' }), {
          status: 409,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify({ error: 'Erreur lors de la création du profil établissement.' }), {
        status: 500,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // 3. Set app_metadata role — server-side, no client involvement
    const { error: claimsError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
      app_metadata: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: user.id },
    });

    if (claimsError) {
      console.error('set-user-claims échoué', claimsError.code);
      await supabaseAdmin.from('etablissements').delete().eq('id', user.id);
      return new Response(JSON.stringify({ error: 'Erreur lors de la configuration du compte.' }), {
        status: 500,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // 4. Audit inscription + CGU + L1: CGV consent
    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id,
      type_acteur: 'ADMIN_ETABLISSEMENT',
      action: 'INSCRIPTION',
      type_ressource: 'etablissement',
      id_ressource: user.id,
      details: { evenement: 'inscription', type },
      navigateur_acteur: body.navigateur || null,
    });

    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id,
      type_acteur: 'ADMIN_ETABLISSEMENT',
      action: 'RGPD_CONSENTEMENT_DONNE',
      type_ressource: 'etablissement',
      id_ressource: user.id,
      details: { type: 'inscription', cgu: true, confidentialite: true, cgv: true },
      navigateur_acteur: body.navigateur || null,
    });

    return new Response(JSON.stringify({ success: true, etablissement_id: user.id }), {
      status: 200,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('register-etablissement error:', err);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), {
      status: 500,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
