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
  return "https://app.jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
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
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { mission_id } = await req.json();
    if (!mission_id) {
      return new Response(JSON.stringify({ error: "mission_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Verify mission ownership
    const { data: mission } = await supabaseAdmin
      .from("missions")
      .select("id, etablissement_id, soignant_assigne_id, statut, montant_commission_ttc, duree_heures, taux_horaire_base")
      .eq("id", mission_id)
      .single();

    if (!mission) {
      return new Response(JSON.stringify({ error: "Mission introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (mission.statut !== "TERMINEE") {
      return new Response(JSON.stringify({ error: "La mission doit être terminée" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Check caller is the établissement owner
    const { data: etab } = await supabaseAdmin
      .from("etablissements")
      .select("id, stripe_customer_id, nom, email_contact")
      .eq("id", mission.etablissement_id)
      .single();

    if (!etab) {
      return new Response(JSON.stringify({ error: "Établissement introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Check soignant has Connect account
    const soignantId = mission.soignant_assigne_id;
    const { data: connectOnboarding } = await supabaseAdmin
      .from("stripe_connect_onboarding")
      .select("stripe_account_id, statut")
      .eq("soignant_id", soignantId)
      .maybeSingle();

    if (!connectOnboarding || connectOnboarding.statut !== "COMPLET" || !connectOnboarding.stripe_account_id) {
      return new Response(JSON.stringify({ error: "Le soignant n'a pas de compte Stripe Connect actif" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Check idempotency - already has a transfer record
    const { data: existingTransfer } = await supabaseAdmin
      .from("stripe_transfers")
      .select("id, statut")
      .eq("mission_id", mission_id)
      .maybeSingle();

    if (existingTransfer?.statut === "TRANSFERE") {
      return new Response(JSON.stringify({ error: "Ce paiement a déjà été effectué" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
      apiVersion: "2025-08-27.basil",
    });

    // Calculate amounts
    const commissionTTC = Math.round((mission.montant_commission_ttc || 0) * 100); // in cents
    const salaireBrut = Math.round((mission.duree_heures || 0) * (mission.taux_horaire_base || 0) * 100); // in cents
    const totalCents = commissionTTC + salaireBrut;

    // Reuse or create Stripe customer
    let customerId = etab.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        name: etab.nom,
        email: etab.email_contact,
        metadata: { etablissement_id: etab.id },
      });
      customerId = customer.id;
      await supabaseAdmin
        .from("etablissements")
        .update({ stripe_customer_id: customerId })
        .eq("id", etab.id);
    }

    // Create Checkout Session
    const origin = req.headers.get("origin") || "https://app.jolene.app";
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      ui_mode: "embedded",
      mode: "payment",
      line_items: [
        {
          price_data: {
            currency: "eur",
            unit_amount: commissionTTC,
            product_data: { name: "Commission Jolene" },
          },
          quantity: 1,
        },
        {
          price_data: {
            currency: "eur",
            unit_amount: salaireBrut,
            product_data: { name: "Salaire soignant" },
          },
          quantity: 1,
        },
      ],
      payment_intent_data: {
        transfer_group: `mission_${mission_id}`,
        metadata: {
          type: "CONNECT_MISSION_PAYMENT",
          mission_id,
          soignant_id: soignantId,
          connected_account_id: connectOnboarding.stripe_account_id,
          soignant_cents: salaireBrut.toString(),
          commission_cents: commissionTTC.toString(),
        },
      },
      metadata: {
        type: "CONNECT_MISSION_PAYMENT",
        mission_id,
        facture_id: "", // not a facture flow
      },
      return_url: `${origin}/etablissement/missions/${mission_id}?payment=success`,
    });

    // Upsert stripe_transfers record
    if (!existingTransfer) {
      await supabaseAdmin.from("stripe_transfers").insert({
        mission_id,
        soignant_id: soignantId,
        etablissement_id: mission.etablissement_id,
        stripe_account_id: connectOnboarding.stripe_account_id,
        montant_soignant_cents: salaireBrut,
        montant_commission_cents: commissionTTC,
        statut: "EN_ATTENTE",
        stripe_checkout_session_id: session.id,
      });
    }

    return new Response(JSON.stringify({
      client_secret: session.client_secret,
      commission_ttc: commissionTTC / 100,
      salaire_brut: salaireBrut / 100,
      total: totalCents / 100,
    }), {
      status: 200,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (error: unknown) {
    console.error("stripe-connect-pay-mission error:", error);
    return new Response(JSON.stringify({ error: "Une erreur interne est survenue." }), {
      status: 500,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }
});
