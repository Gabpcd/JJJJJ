import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const results: Record<string, unknown> = {};

  // ─── 1. Soignante ───
  try {
    const { data: soignantAuth, error: e1 } = await admin.auth.admin.createUser({
      email: 'test@joleneapp.com',
      password: 'TestJolene2026!',
      email_confirm: true,
      app_metadata: { role: 'SOIGNANT' },
      user_metadata: { prenom: 'Gabrielle', nom: 'Picard' },
    });
    if (e1) throw e1;

    const uid = soignantAuth.user.id;
    const { error: e1b } = await admin.from('soignants').insert({
      id: uid,
      prenom: 'Gabrielle',
      nom: 'Picard',
      email: 'test@joleneapp.com',
      telephone: '+33 6 00 00 00 01',
      date_naissance: '1995-06-12',
      profession: 'IDE',
      type_contrat: 'CDDU',
      types_contrat_acceptes: JSON.stringify(['CDDU', 'VACATION']),
      numero_rpps: '00000000001',
      rpps_verifie: true,
      rayon_deplacement_km: 30,
      adresse_lat: 48.8566,
      adresse_lng: 2.3522,
      score_fiabilite: 85,
    });
    if (e1b) throw e1b;
    results.soignante = { id: uid, email: 'test@joleneapp.com', status: 'OK' };
  } catch (err) {
    results.soignante = { status: 'ERROR', message: String(err) };
  }

  // ─── 2. Établissement ───
  try {
    const { data: etabAuth, error: e2 } = await admin.auth.admin.createUser({
      email: 'etab@joleneapp.com',
      password: 'TestJolene2026!',
      email_confirm: true,
      app_metadata: { role: 'ETABLISSEMENT' },
      user_metadata: { nom_etablissement: 'Clinique Test Jolene' },
    });
    if (e2) throw e2;

    const uid = etabAuth.user.id;
    const { error: e2b } = await admin.from('etablissements').insert({
      id: uid,
      nom: 'Clinique Test Jolene',
      siret: '36252187900034',
      type: 'CLINIQUE_PRIVEE',
      adresse_rue: '12 rue de la Paix',
      adresse_ville: 'Paris',
      adresse_code_postal: '75002',
      adresse_departement: '75',
      adresse_lat: 48.8698,
      adresse_lng: 2.3311,
      email_contact: 'etab@joleneapp.com',
      telephone_contact: '0142000000',
      taux_majoration_nuit_pourcent: 25,
      taux_majoration_dimanche_pourcent: 50,
      taux_majoration_ferie_pourcent: 100,
    });
    if (e2b) throw e2b;
    results.etablissement = { id: uid, email: 'etab@joleneapp.com', status: 'OK' };
  } catch (err) {
    results.etablissement = { status: 'ERROR', message: String(err) };
  }

  // ─── 3. Admin ───
  try {
    const { data: adminAuth, error: e3 } = await admin.auth.admin.createUser({
      email: 'admin@joleneapp.com',
      password: 'TestJolene2026!',
      email_confirm: true,
      app_metadata: { role: 'ADMIN_PLATEFORME' },
      user_metadata: { prenom: 'Admin', nom: 'Jolene' },
    });
    if (e3) throw e3;
    results.admin = { id: adminAuth.user.id, email: 'admin@joleneapp.com', status: 'OK' };
  } catch (err) {
    results.admin = { status: 'ERROR', message: String(err) };
  }

  return new Response(JSON.stringify(results, null, 2), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
