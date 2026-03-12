import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Non autorisé" }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;

  try {
    const { user_id, role, etablissement_id } = await req.json();

    if (!user_id || !role) {
      return new Response(JSON.stringify({ error: "user_id et role requis" }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // Mode 1 : appel via service_role → tout autorisé
    if (authHeader.includes(serviceRoleKey)) {
      const appMetadata: Record<string, unknown> = { role };
      if (etablissement_id) appMetadata.etablissement_id = etablissement_id;

      const { error } = await supabaseAdmin.auth.admin.updateUserById(user_id, {
        app_metadata: appMetadata,
      });
      if (error) {
        return new Response(JSON.stringify({ error: "Erreur interne" }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Mode 2 : appel via JWT utilisateur
    const token = authHeader.replace("Bearer ", "");
    const supabaseAuth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!);
    const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Token invalide" }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // L'utilisateur ne peut définir le rôle QUE pour lui-même
    if (user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Interdit" }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // SEUL le rôle SOIGNANT est auto-assignable par un utilisateur
    // ADMIN_ETABLISSEMENT, ADMIN_GROUPE, ADMIN_PLATEFORME = INTERDIT
    if (role !== "SOIGNANT") {
      return new Response(JSON.stringify({ error: "Seul le rôle SOIGNANT peut être auto-assigné." }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { error } = await supabaseAdmin.auth.admin.updateUserById(user_id, {
      app_metadata: { role: "SOIGNANT" },
    });

    if (error) {
      return new Response(JSON.stringify({ error: "Erreur interne" }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
