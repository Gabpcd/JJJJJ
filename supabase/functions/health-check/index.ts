import { createClient } from 'npm:@supabase/supabase-js@2';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  // F-3 fix : support ?secret= query param pour monitoring externe.
  // Le secret doit matcher HEALTH_CHECK_SECRET (Supabase Vault).
  const url = new URL(req.url);
  const querySecret = url.searchParams.get('secret');
  const healthCheckSecret = Deno.env.get('HEALTH_CHECK_SECRET');
  const isExternalMonitor = Boolean(
    querySecret && healthCheckSecret && querySecret === healthCheckSecret
  );

  const authHeader = req.headers.get('Authorization');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;

  if (!isExternalMonitor && !authHeader) {
    return new Response(JSON.stringify({ error: 'Non autorisé' }), {
      status: 401,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  if (!isExternalMonitor) {
    const bearerToken = authHeader!.replace('Bearer ', '');
    const isServiceRole = bearerToken === serviceRoleKey;

    if (!isServiceRole) {
      // Verify JWT and check admin role
      const supabaseAuth = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, { auth: { persistSession: false } });
      const { data: { user }, error } = await supabaseAuth.auth.getUser(bearerToken);
      if (error || !user) {
        return new Response(JSON.stringify({ error: 'Non autorisé' }), {
          status: 401,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
      const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
      await adminClient.rpc('fn_get_my_role_for_user', { p_user_id: user.id }).maybeSingle();
      const { data: { user: fullUser } } = await adminClient.auth.admin.getUserById(user.id);
      if (fullUser?.app_metadata?.role !== 'ADMIN') {
        return new Response(JSON.stringify({ error: 'Accès réservé aux administrateurs' }), {
          status: 403,
          headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
        });
      }
    }
  }

  try {
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
