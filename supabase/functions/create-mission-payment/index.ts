import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyUserOrServiceRole } from "../_shared/admin-auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { resolveOperationalTestAccount } from "../_shared/test-account.ts";

// Pré-lancement public : STRIPE_RESERVATION est volontairement désactivé.
// L'ancien flux créait une autorisation capture_method=manual sans mécanisme
// durable de capture/réautorisation/SCA. Il ne doit plus créer aucun objet Stripe.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Méthode non autorisée" }), {
      status: 405,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) {
      return new Response(JSON.stringify({ error: auth.error }), {
        status: auth.status,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (auth.isServiceRole || !auth.userId || !authHeader) {
      return new Response(JSON.stringify({ error: "Session utilisateur requise" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const body = await req.json().catch(() => null) as { mission_id?: unknown } | null;
    const missionId = typeof body?.mission_id === "string" ? body.mission_id : "";
    if (!missionId) {
      return new Response(JSON.stringify({ error: "mission_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAdmin = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } },
    );
    const supabaseUser = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        auth: { persistSession: false },
        global: { headers: { Authorization: authHeader } },
      },
    );

    const { data: mission, error: missionError } = await supabaseAdmin
      .from("missions")
      .select("id, etablissement_id")
      .eq("id", missionId)
      .maybeSingle();
    if (missionError || !mission) {
      return new Response(JSON.stringify({ error: "Mission introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: hasPaymentPermission, error: permissionError } = await supabaseUser.rpc(
      "fn_a_permission_etablissement",
      { p_permission: "paiement", p_etablissement_id: mission.etablissement_id },
    );
    if (permissionError) {
      throw new Error(
        `Vérification des droits de paiement impossible: ${permissionError.message}`,
      );
    }
    if (hasPaymentPermission !== true) {
      return new Response(
        JSON.stringify({
          error: "Vous n'avez pas les droits de paiement sur cet établissement",
        }),
        {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        },
      );
    }

    const testAccount = await resolveOperationalTestAccount(
      supabaseAdmin,
      mission.etablissement_id,
    );
    if (!testAccount.ok) {
      return new Response(JSON.stringify({
        error: "TEST_ACCOUNT_CLASSIFICATION_UNAVAILABLE",
      }), {
        status: 503,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (testAccount.isTest) {
      return new Response(JSON.stringify({
        error: "TEST_ACCOUNT_PAYMENT_DISABLED",
      }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      error: "STRIPE_RESERVATION_DISABLED",
      message:
        "La réservation par carte n'est pas disponible. Utilisez le prélèvement SEPA ou la facture mensuelle.",
    }), {
      status: 410,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(
      "create-mission-payment disabled endpoint:",
      error instanceof Error ? error.message : String(error),
    );
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }
});
