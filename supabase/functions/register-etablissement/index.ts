import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // 1. Authenticate caller via JWT
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Non authentifié' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const token = authHeader.replace('Bearer ', '');
  const supabaseAuth = createClient(supabaseUrl, anonKey);
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'Non authentifié' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
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
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (siret.length !== 14) {
      return new Response(JSON.stringify({ error: 'Le SIRET doit contenir 14 chiffres' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
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
      console.error('INSERT etablissements échoué', insertError);
      // Translate known constraint violations
      const msg = insertError.message || '';
      if (msg.includes('duplicate key') && msg.includes('siret')) {
        return new Response(JSON.stringify({ error: 'Ce numéro SIRET est déjà enregistré.' }), {
          status: 409,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify({ error: 'Erreur lors de la création du profil établissement.' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 3. Set app_metadata role — server-side, no client involvement
    const { error: claimsError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
      app_metadata: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: user.id },
    });

    if (claimsError) {
      console.error('set-user-claims échoué', claimsError);
      // Rollback: delete the etablissement row
      await supabaseAdmin.from('etablissements').delete().eq('id', user.id);
      return new Response(JSON.stringify({ error: 'Erreur lors de la configuration du compte.' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 4. Audit inscription + CGU consent
    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id,
      type_acteur: 'ADMIN_ETABLISSEMENT',
      action: 'CONNEXION',
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
      details: { type: 'inscription', cgu: true, confidentialite: true },
      navigateur_acteur: body.navigateur || null,
    });

    return new Response(JSON.stringify({ success: true, etablissement_id: user.id }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('register-etablissement error:', err);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
