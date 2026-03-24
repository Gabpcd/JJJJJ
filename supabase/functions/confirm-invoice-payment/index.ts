import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "npm:stripe@18.5.0";
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
  };
}

async function findMatchingPaymentIntent(
  stripe: Stripe,
  factureId: string,
  customerId?: string | null,
  paymentIntentId?: string | null,
) {
  if (paymentIntentId) {
    try {
      return await stripe.paymentIntents.retrieve(paymentIntentId);
    } catch (error) {
      console.warn("confirm-invoice-payment: retrieve payment intent failed", error);
    }
  }

  try {
    const result = await stripe.paymentIntents.search({
      query: `metadata['facture_id']:'${factureId}'`,
      limit: 10,
    });

    const exactMatch = result.data.find((intent) => intent.metadata?.facture_id === factureId);
    if (exactMatch) return exactMatch;
  } catch (error) {
    console.warn("confirm-invoice-payment: payment intent search unavailable", error);
  }

  if (!customerId) return null;

  const intents = await stripe.paymentIntents.list({ customer: customerId, limit: 20 });
  return intents.data.find((intent) => intent.metadata?.facture_id === factureId) ?? null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Non authentifié" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    );

    const token = authHeader.replace("Bearer ", "");
    const { data: { user } } = await supabaseClient.auth.getUser(token);
    if (!user?.id) {
      return new Response(JSON.stringify({ error: "Non authentifié" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { facture_id } = await req.json();
    if (!facture_id) {
      return new Response(JSON.stringify({ error: "facture_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } },
    );

    const { data: facture, error: factureError } = await supabaseAdmin
      .from("factures")
      .select("id, numero_facture, statut, date_paiement, etablissement_id, montant_ttc, stripe_payment_intent_id, etablissements(stripe_customer_id)")
      .eq("id", facture_id)
      .single();

    if (factureError || !facture) {
      return new Response(JSON.stringify({ error: "Facture introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: userData } = await supabaseAdmin.auth.admin.getUserById(user.id);
    const userEtabId = userData?.user?.app_metadata?.etablissement_id || user.id;
    if (userEtabId !== facture.etablissement_id) {
      return new Response(JSON.stringify({ error: "Accès interdit" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (facture.statut === "PAYEE") {
      return new Response(JSON.stringify({ confirmed: true, status: "PAYEE", date_paiement: facture.date_paiement }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) {
      return new Response(JSON.stringify({ error: "Configuration Stripe manquante" }), {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const stripe = new Stripe(stripeKey, { apiVersion: "2025-08-27.basil" });
    const paymentIntent = await findMatchingPaymentIntent(
      stripe,
      facture.id,
      (facture.etablissements as any)?.stripe_customer_id,
      facture.stripe_payment_intent_id,
    );

    if (!paymentIntent) {
      return new Response(JSON.stringify({ confirmed: false, status: facture.statut ?? "EMISE" }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (paymentIntent.status !== "succeeded") {
      return new Response(JSON.stringify({
        confirmed: false,
        status: facture.statut ?? "EMISE",
        payment_intent_status: paymentIntent.status,
      }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { error: updateError } = await supabaseAdmin
      .from("factures")
      .update({
        statut: "PAYEE",
        date_paiement: new Date(paymentIntent.created * 1000).toISOString(),
        stripe_payment_intent_id: paymentIntent.id,
        modifie_le: new Date().toISOString(),
      })
      .eq("id", facture.id)
      .neq("statut", "PAYEE");

    if (updateError) {
      console.error("confirm-invoice-payment: facture update failed", updateError);
      return new Response(JSON.stringify({ error: "Impossible de synchroniser la facture" }), {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      confirmed: true,
      status: "PAYEE",
      payment_intent_id: paymentIntent.id,
      date_paiement: new Date(paymentIntent.created * 1000).toISOString(),
    }), {
      status: 200,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erreur inconnue";
    console.error("confirm-invoice-payment:", message);
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }
});