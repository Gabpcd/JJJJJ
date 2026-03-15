import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.soindirect.com" ||
    origin === "http://localhost:5173" ||
    origin.endsWith(".lovable.app")
  ) {
    return origin;
  }
  return "https://app.soindirect.com";
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  // M8: Require authentication (service_role or admin JWT)
  const authHeader = req.headers.get('Authorization');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;

  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Non autorisé' }), {
      status: 401,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  const bearerToken = authHeader.replace('Bearer ', '');
  const isServiceRole = bearerToken === serviceRoleKey;

  if (!isServiceRole) {
    // Verify JWT and check admin role
    const supabaseAuth = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!);
    const { data: { user }, error } = await supabaseAuth.auth.getUser(bearerToken);
    if (error || !user) {
      return new Response(JSON.stringify({ error: 'Non autorisé' }), {
        status: 401,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }
    // Only ADMIN can call health-check via JWT
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: roleData } = await adminClient.rpc('fn_get_my_role_for_user', { p_user_id: user.id }).maybeSingle();
    // Fallback: check app_metadata
    const { data: { user: fullUser } } = await adminClient.auth.admin.getUserById(user.id);
    if (fullUser?.app_metadata?.role !== 'ADMIN') {
      return new Response(JSON.stringify({ error: 'Accès réservé aux administrateurs' }), {
        status: 403,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }
  }

  try {
    const supabase = createClient(supabaseUrl, serviceRoleKey);
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
