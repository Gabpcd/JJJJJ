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

  // Use fetch directly to bypass any client-side RLS issues
  const ETAB_ID = '8500dba5-2c73-4035-8383-b854d59a9864';

  // Check if already exists
  const checkRes = await fetch(`${supabaseUrl}/rest/v1/etablissements?id=eq.${ETAB_ID}&select=id`, {
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': `Bearer ${serviceRoleKey}`,
    },
  });
  const existing = await checkRes.json();

  if (existing.length > 0) {
    return new Response(JSON.stringify({ status: 'already_exists', id: ETAB_ID }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const res = await fetch(`${supabaseUrl}/rest/v1/etablissements`, {
    method: 'POST',
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal',
    },
    body: JSON.stringify({
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
    }),
  });

  const status = res.status;
  const body = status === 201 ? 'OK' : await res.text();

  return new Response(JSON.stringify({ status, body }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
