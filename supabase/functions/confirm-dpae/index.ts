import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.jolene.app" ||
    origin === "https://jolene.app" ||
    origin === "http://localhost:5173" ||
    origin.endsWith(".lovable.app") ||
    origin.endsWith(".lovableproject.com")
  ) {
    return origin;
  }
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
    "Content-Type": "application/json",
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ success: false, error: "Non authentifié" }), {
        status: 401,
        headers: corsHeaders(req),
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { auth: { persistSession: false } },
    );
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } },
    );

    const { data: authData, error: authError } = await supabaseClient.auth.getUser(token);
    const user = authData.user;
    if (authError || !user?.id) {
      return new Response(JSON.stringify({ success: false, error: "Non authentifié" }), {
        status: 401,
        headers: corsHeaders(req),
      });
    }

    const { contrat_id } = await req.json();
    if (!contrat_id) {
      return new Response(JSON.stringify({ success: false, error: "contrat_id requis" }), {
        status: 400,
        headers: corsHeaders(req),
      });
    }

    const { data: contrat, error: contratError } = await supabaseAdmin
      .from("contrats_mission")
      .select("id, etablissement_id, type_contrat, dpae_effectuee, dpae_effectuee_le")
      .eq("id", contrat_id)
      .single();

    if (contratError || !contrat) {
      return new Response(JSON.stringify({ success: false, error: "Contrat introuvable" }), {
        status: 404,
        headers: corsHeaders(req),
      });
    }

    if (contrat.type_contrat === "REMPLACEMENT_LIBERAL") {
      return new Response(JSON.stringify({ success: true, dpae_effectuee_le: contrat.dpae_effectuee_le }), {
        status: 200,
        headers: corsHeaders(req),
      });
    }

    const { data: userData } = await supabaseAdmin.auth.admin.getUserById(user.id);
    const userEtabId = userData?.user?.app_metadata?.etablissement_id || user.id;

    let authorized = userEtabId === contrat.etablissement_id;
    if (!authorized) {
      const { data: etablissement } = await supabaseAdmin
        .from("etablissements")
        .select("groupe_sante_id")
        .eq("id", contrat.etablissement_id)
        .maybeSingle();

      if (etablissement?.groupe_sante_id) {
        const { data: membership } = await supabaseAdmin
          .from("admins_groupe_sante")
          .select("id")
          .eq("groupe_id", etablissement.groupe_sante_id)
          .eq("utilisateur_id", user.id)
          .maybeSingle();

        authorized = Boolean(membership);
      }
    }

    if (!authorized) {
      return new Response(JSON.stringify({ success: false, error: "Accès refusé" }), {
        status: 403,
        headers: corsHeaders(req),
      });
    }

    if (contrat.dpae_effectuee) {
      return new Response(JSON.stringify({ success: true, dpae_effectuee_le: contrat.dpae_effectuee_le }), {
        status: 200,
        headers: corsHeaders(req),
      });
    }

    const confirmedAt = new Date().toISOString();
    const { error: updateError } = await supabaseAdmin
      .from("contrats_mission")
      .update({
        dpae_effectuee: true,
        dpae_effectuee_le: confirmedAt,
        modifie_le: confirmedAt,
      })
      .eq("id", contrat_id);

    if (updateError) {
      console.error("confirm-dpae update failed", updateError);
      return new Response(JSON.stringify({ success: false, error: "Impossible d'enregistrer la DPAE" }), {
        status: 500,
        headers: corsHeaders(req),
      });
    }

    return new Response(JSON.stringify({ success: true, dpae_effectuee_le: confirmedAt }), {
      status: 200,
      headers: corsHeaders(req),
    });
  } catch (error) {
    console.error("confirm-dpae", error);
    return new Response(JSON.stringify({ success: false, error: "Erreur interne" }), {
      status: 500,
      headers: corsHeaders(req),
    });
  }
});