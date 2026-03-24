import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "npm:stripe@14";
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
  return "https://app.jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  };
}

serve(async (req) => {
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

    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
      apiVersion: "2023-10-16",
    });

    const account = await stripe.accounts.retrieve(
      onboarding.stripe_account_id
    );

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

    // Update onboarding record if status changed or new data
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
      }),
      {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  } catch (error: unknown) {
    console.error("stripe-connect-status error:", error);
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue." }),
      {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      }
    );
  }
});
