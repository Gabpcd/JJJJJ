import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2.57.2";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin.endsWith(".lovable.app")
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

  const supabaseAnon = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? ""
  );
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  const authHeader = req.headers.get("Authorization")!;

  try {
    // Authenticate
    const token = authHeader.replace("Bearer ", "");
    const { data: { user } } = await supabaseAnon.auth.getUser(token);
    if (!user?.email) throw new Error("Non authentifié");

    const { mission_id } = await req.json();
    if (!mission_id) throw new Error("mission_id requis");

    // Verify ownership via JWT user role
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: userRole } = await supabaseUser.rpc("fn_get_my_role");
    const userEtabId = userRole?.etablissement_id;

    // Get mission + establishment
    const { data: mission, error: errM } = await supabaseAdmin
      .from("missions")
      .select(
        "id, intitule, montant_commission_ttc, etablissement_id, etablissements(nom, email_contact, stripe_customer_id, mode_paiement_commission)"
      )
      .eq("id", mission_id)
      .single();

    if (errM || !mission) throw new Error("Mission introuvable");

    // Ownership check
    if (!userEtabId || userEtabId !== mission.etablissement_id) {
      return new Response(
        JSON.stringify({ error: "Accès interdit" }),
        { status: 403, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    const etab = (mission as any).etablissements;
    if (etab?.mode_paiement_commission !== "STRIPE_RESERVATION") {
      return new Response(
        JSON.stringify({ skipped: true, reason: "Mode de paiement non Stripe" }),
        { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    const commissionTTC = (mission as any).montant_commission_ttc;
    if (!commissionTTC || commissionTTC <= 0) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "Pas de commission" }),
        { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // Initialize Stripe
    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
      apiVersion: "2025-08-27.basil",
    });

    // Get or create Stripe customer
    let customerId = etab?.stripe_customer_id;
    if (!customerId) {
      const customers = await stripe.customers.list({ email: user.email, limit: 1 });
      if (customers.data.length > 0) {
        customerId = customers.data[0].id;
      } else {
        const customer = await stripe.customers.create({
          email: user.email,
          name: etab?.nom,
          metadata: { etablissement_id: mission.etablissement_id },
        });
        customerId = customer.id;
      }
      await supabaseAdmin
        .from("etablissements")
        .update({ stripe_customer_id: customerId })
        .eq("id", mission.etablissement_id);
    }

    // Check for saved default payment method
    const customer = await stripe.customers.retrieve(customerId);
    const defaultPM =
      typeof customer !== "string" && !customer.deleted
        ? (customer.invoice_settings?.default_payment_method as string) || null
        : null;

    const amountCents = Math.round(commissionTTC * 100);

    if (defaultPM) {
      // Auto-authorize with saved card
      const paymentIntent = await stripe.paymentIntents.create({
        amount: amountCents,
        currency: "eur",
        customer: customerId,
        payment_method: defaultPM,
        capture_method: "manual", // authorize only, capture on TERMINEE
        confirm: true,
        off_session: true,
        description: `Commission mission: ${(mission as any).intitule}`,
        metadata: {
          mission_id: mission.id,
          etablissement_id: mission.etablissement_id,
          type: "commission_reservation",
        },
      });

      // Record payment
      await supabaseAdmin.from("paiements_mission").insert({
        mission_id: mission.id,
        etablissement_id: mission.etablissement_id,
        montant_ht: (mission as any).montant_commission_ttc / 1.2,
        montant_tva: (mission as any).montant_commission_ttc - (mission as any).montant_commission_ttc / 1.2,
        montant_ttc: commissionTTC,
        stripe_payment_intent_id: paymentIntent.id,
        statut: "AUTORISE",
      });

      return new Response(
        JSON.stringify({ success: true, auto_charged: true, payment_intent_id: paymentIntent.id }),
        { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    } else {
      // No saved card → return client_secret for manual card entry
      const paymentIntent = await stripe.paymentIntents.create({
        amount: amountCents,
        currency: "eur",
        customer: customerId,
        capture_method: "manual",
        description: `Commission mission: ${(mission as any).intitule}`,
        metadata: {
          mission_id: mission.id,
          etablissement_id: mission.etablissement_id,
          type: "commission_reservation",
        },
        setup_future_usage: "off_session", // Save card for future
      });

      // Record pending payment
      await supabaseAdmin.from("paiements_mission").insert({
        mission_id: mission.id,
        etablissement_id: mission.etablissement_id,
        montant_ht: commissionTTC / 1.2,
        montant_tva: commissionTTC - commissionTTC / 1.2,
        montant_ttc: commissionTTC,
        stripe_payment_intent_id: paymentIntent.id,
        statut: "EN_ATTENTE",
      });

      return new Response(
        JSON.stringify({
          success: true,
          auto_charged: false,
          client_secret: paymentIntent.client_secret,
          payment_intent_id: paymentIntent.id,
          amount: commissionTTC,
        }),
        { headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }
  } catch (error: unknown) {
    console.error("Erreur create-mission-payment:", error instanceof Error ? error.message : error);
    return new Response(
      JSON.stringify({ error: "Une erreur interne est survenue." }),
      { headers: { ...corsHeaders(req), "Content-Type": "application/json" }, status: 500 }
    );
  }
});
