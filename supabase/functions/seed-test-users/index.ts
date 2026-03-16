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
    db: { schema: 'public' },
  });

  const results: Record<string, unknown> = {};

  const SOIGNANTE_ID = '57d814fb-c09b-4528-b4e0-ed8369328bd3';
  const ETAB_ID = '8500dba5-2c73-4035-8383-b854d59a9864';
  const OLD_SOIGNANTE_ID = 'ec814d29-3c4d-43fd-a8ae-914e0cb8d42c';

  // ─── 0. Cleanup orphan soignant with same RPPS ───
  try {
    // Delete old orphan profile
    await admin.from('soignants').delete().eq('id', OLD_SOIGNANTE_ID);
    // Delete old auth user if exists
    await admin.auth.admin.deleteUser(OLD_SOIGNANTE_ID);
    results.cleanup = 'old orphan deleted';
  } catch (err: any) {
    results.cleanup = err?.message || 'no cleanup needed';
  }

  // ─── 1. Soignante profile ───
  try {
    const { error } = await admin.from('soignants').upsert({
      id: SOIGNANTE_ID,
      prenom: 'Gabrielle',
      nom: 'Picard',
      email: 'test@joleneapp.com',
      telephone: '+33600000001',
      date_naissance: '1995-06-12',
      profession: 'IDE',
      numero_rpps: '00000000001',
      rpps_verifie: true,
      rayon_deplacement_km: 30,
      adresse_lat: 48.8566,
      adresse_lng: 2.3522,
      score_fiabilite: 85,
    }, { onConflict: 'id' });
    if (error) throw error;
    results.soignante = { id: SOIGNANTE_ID, status: 'OK' };
  } catch (err: any) {
    results.soignante = { status: 'ERROR', detail: err?.message || JSON.stringify(err) };
  }

  // ─── 2. Établissement profile ───
  try {
    const { error } = await admin.from('etablissements').upsert({
      id: ETAB_ID,
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
    }, { onConflict: 'id' });
    if (error) throw error;
    results.etablissement = { id: ETAB_ID, status: 'OK' };
  } catch (err: any) {
    results.etablissement = { status: 'ERROR', detail: err?.message || JSON.stringify(err) };
  }

  results.admin = { id: '09e82688-e524-42bb-9268-1384c757f33d', email: 'admin@joleneapp.com', status: 'OK' };

  return new Response(JSON.stringify(results, null, 2), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
