import { createClient } from 'npm:@supabase/supabase-js@2';
import { verifyAdminOrServiceRole } from '../_shared/admin-auth.ts';
import { corsHeaders } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  // Une sonde HEAD publique confirme seulement que le runtime Edge repond.
  // Elle ne touche pas la base et ne divulgue aucun diagnostic. Le detail du
  // healthcheck reste reserve aux administrateurs AAL2 et aux appels internes.
  // Les secrets en query string sont volontairement ignores : les URL sont
  // journalisees par les proxies et ne doivent jamais transporter un secret.
  if (req.method === 'HEAD') {
    return new Response(null, {
      status: 200,
      headers: { ...corsHeaders(req), 'Cache-Control': 'no-store' },
    });
  }

  if (req.method !== 'GET' && req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Methode non autorisee' }), {
      status: 405,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  const auth = await verifyAdminOrServiceRole(req);
  if (!auth.ok) {
    return new Response(JSON.stringify({ error: auth.error }), {
      status: auth.status,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  try {
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const { data, error } = await supabase.rpc('fn_health_check');
    if (error) throw error;

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      status: data?.status === 'OK' ? 200 : 500,
    });
  } catch (err) {
    console.error('health-check error:', err);
    return new Response(JSON.stringify({ status: 'ERROR', error: 'Erreur interne' }), {
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});
