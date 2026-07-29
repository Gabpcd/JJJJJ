import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, getCorsOrigin } from "../_shared/cors.ts";
import { mapStripeError } from "../_shared/stripe-errors.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import { resolveOperationalTestAccount } from "../_shared/test-account.ts";

const STRIPE_WEB_RETURN_ORIGINS = new Set([
  "https://jolene.app",
  "https://www.jolene.app",
  "https://app.jolene.app",
  "http://localhost:5173",
  "http://localhost:8080",
]);

const NATIVE_APP_ORIGINS = new Set([
  "https://localhost",
  "capacitor://localhost",
]);

function getTrustedStripeReturnOrigin(req: Request): string | null {
  const requestOrigin = req.headers.get("origin");
  if (!requestOrigin || getCorsOrigin(req) !== requestOrigin) return null;

  if (NATIVE_APP_ORIGINS.has(requestOrigin)) {
    // Un Account Link s'ouvre dans le navigateur système : le retour natif doit
    // donc passer par l'Universal Link public, jamais par l'origine WebView.
    return "https://jolene.app";
  }

  return STRIPE_WEB_RETURN_ORIGINS.has(requestOrigin) ? requestOrigin : null;
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

    const returnOrigin = getTrustedStripeReturnOrigin(req);
    if (!returnOrigin) {
      return new Response(JSON.stringify({ error: "ORIGINE_NON_AUTORISEE" }), {
        status: 403,
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

    const testAccount = await resolveOperationalTestAccount(
      supabaseAdmin,
      soignantId,
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

    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
    assertStripeSecretMode(stripeKey);
    const stripe = new Stripe(stripeKey, {
      apiVersion: "2026-02-25.clover",
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
      const account = await stripe.accounts.create(
        {
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
        },
        { idempotencyKey: `connect_account_${soignantId}` },
      );
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
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: `${returnOrigin}/soignant/stripe-connect?refresh=true`,
      return_url: `${returnOrigin}/soignant/stripe-connect?success=true`,
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
