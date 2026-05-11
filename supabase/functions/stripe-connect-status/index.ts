import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { mapStripeError } from "../_shared/stripe-errors.ts";

// [CP-STRIPE-6 H10] TTL du cache : si onboarding.modifie_le est plus
// récent que CACHE_TTL_MS, on retourne les données DB sans appeler
// stripe.accounts.retrieve (économise quota Stripe + latence UI).
// Le webhook account.updated (CP4) bumpe modifie_le = invalidation
// automatique à chaque changement réel côté Stripe.
const CACHE_TTL_MS = 5 * 60 * 1000;

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

    const { data: onboarding } = await supabaseAdmin
      .from("stripe_connect_onboarding")
      .select("*")
      .eq("soignant_id", user.id)
      .maybeSingle();

    if (!onboarding?.stripe_account_id) {
      return new Response(JSON.stringify({ statut: "NON_DEMANDE" }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // [CP-STRIPE-6 H11] Si déjà marqué SUPPRIME, pas besoin de re-tenter
    // un retrieve Stripe qui échouera de la même manière.
    if (onboarding.statut === "SUPPRIME") {
      return new Response(
        JSON.stringify({
          statut: "SUPPRIME",
          onboarding_complete: false,
          charges_enabled: false,
          payouts_enabled: false,
          iban_last4: onboarding.iban_last4 || null,
          requirements: [],
          disabled_reason: "account_deleted",
          message: "Votre compte Stripe Connect a été supprimé. Contactez le support ou recommencez l'onboarding.",
          cached: true,
        }),
        {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // [CP-STRIPE-6 H10] Check cache via modifie_le
    const url = new URL(req.url);
    const forceRefresh = url.searchParams.get("force") === "true";
    const modifieLe = onboarding.modifie_le
      ? new Date(onboarding.modifie_le).getTime()
      : 0;
    const cacheAge = Date.now() - modifieLe;
    const cacheValid = !forceRefresh && cacheAge < CACHE_TTL_MS;

    if (cacheValid) {
      // Cache hit : pas d'appel Stripe
      const onboardingComplete = !!(
        onboarding.charges_enabled &&
        onboarding.payouts_enabled &&
        onboarding.details_submitted
      );
      return new Response(
        JSON.stringify({
          statut: onboarding.statut,
          onboarding_complete: onboardingComplete,
          charges_enabled: !!onboarding.charges_enabled,
          payouts_enabled: !!onboarding.payouts_enabled,
          iban_last4: onboarding.iban_last4 || null,
          requirements: [],
          disabled_reason: null,
          cached: true,
          cache_age_seconds: Math.round(cacheAge / 1000),
        }),
        {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        }
      );
    }

    // Cache miss : call Stripe API
    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
      apiVersion: "2025-08-27.basil",
    });

    let account: Stripe.Account;
    try {
      account = await stripe.accounts.retrieve(onboarding.stripe_account_id);
    } catch (retrieveErr: unknown) {
      // [CP-STRIPE-6 H11] Compte supprimé côté Stripe (resource_missing/account_invalid)
      const e = retrieveErr as { code?: string; type?: string };
      if (e.code === "resource_missing" || e.code === "account_invalid") {
        console.warn(
          `Connect account ${onboarding.stripe_account_id} deleted on Stripe side — marking SUPPRIME`
        );

        await supabaseAdmin
          .from("stripe_connect_onboarding")
          .update({
            statut: "SUPPRIME",
            charges_enabled: false,
            payouts_enabled: false,
            modifie_le: new Date().toISOString(),
          })
          .eq("soignant_id", user.id);

        // Audit RGPD
        await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: user.id,
          p_type_acteur: "SYSTEME",
          p_action: "STRIPE_CONNECT_ACCOUNT_DELETED",
          p_type_ressource: "stripe_connect_onboarding",
          p_id_ressource: onboarding.id,
          p_cle_s3: null,
          p_details: {
            stripe_account_id: onboarding.stripe_account_id,
            stripe_error_code: e.code,
            detected_at: new Date().toISOString(),
          },
          p_ip: null,
          p_navigateur: "stripe-connect-status",
        });

        return new Response(
          JSON.stringify({
            statut: "SUPPRIME",
            onboarding_complete: false,
            charges_enabled: false,
            payouts_enabled: false,
            iban_last4: null,
            requirements: [],
            disabled_reason: "account_deleted",
            message: "Votre compte Stripe Connect a été supprimé. Contactez le support ou recommencez l'onboarding.",
          }),
          {
            status: 200,
            headers: { ...corsHeaders(req), "Content-Type": "application/json" },
          }
        );
      }
      // Autre erreur → remonter au catch global (mapStripeError)
      throw retrieveErr;
    }

    const onboardingComplete =
      !!account.details_submitted &&
      !!account.charges_enabled &&
      !!account.payouts_enabled;

    // Determine status
    let statut: string;
    if (onboardingComplete) {
      statut = "COMPLET";
    } else if (account.requirements?.disabled_reason) {
      statut = "SUSPENDU";
    } else {
      statut = "EN_COURS";
    }

    // Extract IBAN last4 from external accounts
    let ibanLast4: string | null = null;
    if (account.external_accounts?.data?.length) {
      const bankAccount = account.external_accounts.data[0];
      if ("last4" in bankAccount) {
        ibanLast4 = bankAccount.last4 as string;
      }
    }

    // Update onboarding record (bumpe modifie_le pour le cache)
    await supabaseAdmin
      .from("stripe_connect_onboarding")
      .update({
        statut,
        charges_enabled: account.charges_enabled ?? false,
        payouts_enabled: account.payouts_enabled ?? false,
        details_submitted: account.details_submitted ?? false,
        iban_last4: ibanLast4,
        modifie_le: new Date().toISOString(),
      })
      .eq("soignant_id", user.id);

    return new Response(
      JSON.stringify({
        statut,
        onboarding_complete: onboardingComplete,
        charges_enabled: account.charges_enabled ?? false,
        payouts_enabled: account.payouts_enabled ?? false,
        iban_last4: ibanLast4,
        requirements: account.requirements?.currently_due ?? [],
        disabled_reason: account.requirements?.disabled_reason ?? null,
        cached: false,
      }),
      {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  } catch (error: unknown) {
    // [CP-STRIPE-6 H9] Mapping typed Stripe errors
    const mapped = mapStripeError(error);
    console[mapped.logLevel]("stripe-connect-status error:", {
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
