import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { mapStripeError } from "../_shared/stripe-errors.ts";

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
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  try {
    // Auth check
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    );
    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser(authHeader.replace("Bearer ", ""));
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const soignantId = user.id;

    // Get soignant info
    const { data: soignant } = await supabaseAdmin
      .from("soignants")
      .select("prenom, nom, email, type_exercice, statut_liberal")
      .eq("id", soignantId)
      .single();

    if (!soignant) {
      return new Response(JSON.stringify({ error: "Soignant introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Block non-LIBERAL — allow LIBERAL, MIXTE, or anyone with statut_liberal ACTIF
    const isEligible = soignant.type_exercice === "LIBERAL"
      || soignant.type_exercice === "MIXTE"
      || soignant.statut_liberal === "ACTIF";

    if (!isEligible) {
      return new Response(
        JSON.stringify({
          error:
            "Stripe Connect est réservé aux soignants en exercice libéral ou mixte",
        }),
        {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
      apiVersion: "2025-08-27.basil",
    });

    // Check existing onboarding record
    const { data: existing } = await supabaseAdmin
      .from("stripe_connect_onboarding")
      .select("stripe_account_id, statut")
      .eq("soignant_id", soignantId)
      .maybeSingle();

    let accountId = existing?.stripe_account_id;

    if (!accountId) {
      // Create Stripe Connect Express account
      const account = await stripe.accounts.create({
        type: "express",
        country: "FR",
        email: soignant.email,
        business_type: "individual",
        individual: {
          first_name: soignant.prenom,
          last_name: soignant.nom,
          email: soignant.email,
        },
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        // Escrow 7b-D (PR 1) : payouts pilotés par Jolene. Les fonds attendent
        // sur le solde connecté du soignant ; le virement bancaire (« release »)
        // est déclenché par payouts.create après validation des présences —
        // jamais automatiquement. Les comptes créés AVANT ce changement sont
        // basculés par scripts/backfill-payouts-manual.ts (drain d'abord, A7).
        settings: {
          payouts: { schedule: { interval: "manual" } },
        },
        metadata: { soignant_id: soignantId },
      });
      accountId = account.id;

      // Upsert onboarding record
      await supabaseAdmin
        .from("stripe_connect_onboarding")
        .upsert(
          {
            soignant_id: soignantId,
            stripe_account_id: accountId,
            statut: "EN_COURS",
            modifie_le: new Date().toISOString(),
          },
          { onConflict: "soignant_id" }
        );

      // Save stripe_account_id on soignants table
      await supabaseAdmin
        .from("soignants")
        .update({ stripe_account_id: accountId })
        .eq("id", soignantId);
    }

    // Create account link for onboarding
    const origin = req.headers.get("origin") || "https://jolene.app";
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: `${origin}/soignant/stripe-connect?refresh=true`,
      return_url: `${origin}/soignant/stripe-connect?success=true`,
      type: "account_onboarding",
    });

    return new Response(
      JSON.stringify({
        success: true,
        url: accountLink.url,
        account_id: accountId,
      }),
      {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  } catch (error: unknown) {
    // [CP-STRIPE-6 H9] Mapping typed Stripe errors
    const mapped = mapStripeError(error);
    console[mapped.logLevel]("stripe-connect-onboard error:", {
      code: mapped.code,
      raw: error instanceof Error ? error.message : String(error),
    });
    return new Response(
      JSON.stringify({ error: mapped.code, message: mapped.userMessage }),
      {
        status: mapped.status,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  }
});
