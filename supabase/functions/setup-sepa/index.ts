import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";

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
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
    "Content-Type": "application/json",
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? ""
  );

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: corsHeaders(req),
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: authError } = await supabaseClient.auth.getUser(token);
    if (authError || !userData?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: corsHeaders(req),
      });
    }

    const userId = userData.user.id;

    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
      apiVersion: "2025-08-27.basil",
    });

    const { action, payment_method_id } = await req.json();

    // Get establishment
    const { data: etab, error: etabErr } = await supabaseAdmin
      .from("etablissements")
      .select("id, nom, email_contact, stripe_customer_id")
      .eq("id", userId)
      .single();

    if (etabErr || !etab) {
      return new Response(JSON.stringify({ error: "Établissement introuvable" }), {
        status: 404,
        headers: corsHeaders(req),
      });
    }

    // Ensure Stripe customer exists
    let customerId = etab.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: etab.email_contact,
        name: etab.nom,
        metadata: { etablissement_id: etab.id },
      });
      customerId = customer.id;
      await supabaseAdmin
        .from("etablissements")
        .update({ stripe_customer_id: customerId })
        .eq("id", etab.id);
    }

    if (action === "create_setup_intent") {
      const setupIntent = await stripe.setupIntents.create({
        customer: customerId,
        payment_method_types: ["sepa_debit"],
        metadata: { etablissement_id: etab.id },
      });

      return new Response(
        JSON.stringify({ client_secret: setupIntent.client_secret }),
        { headers: corsHeaders(req) }
      );
    }

    if (action === "confirm_sepa") {
      if (!payment_method_id) {
        return new Response(JSON.stringify({ error: "payment_method_id requis" }), {
          status: 400,
          headers: corsHeaders(req),
        });
      }

      // Set as default payment method
      await stripe.customers.update(customerId, {
        invoice_settings: { default_payment_method: payment_method_id },
      });

      // Get last4 of IBAN
      const pm = await stripe.paymentMethods.retrieve(payment_method_id);
      const last4 = pm.sepa_debit?.last4 || "****";

      // Update mode_paiement_commission to SEPA_DEBIT
      await supabaseAdmin
        .from("etablissements")
        .update({
          mode_paiement_commission: "SEPA_DEBIT",
          modifie_le: new Date().toISOString(),
        })
        .eq("id", etab.id);

      return new Response(
        JSON.stringify({ success: true, last4 }),
        { headers: corsHeaders(req) }
      );
    }

    if (action === "get_sepa_status") {
      if (!customerId) {
        return new Response(JSON.stringify({ has_sepa: false }), {
          headers: corsHeaders(req),
        });
      }

      const paymentMethods = await stripe.paymentMethods.list({
        customer: customerId,
        type: "sepa_debit",
        limit: 1,
      });

      if (paymentMethods.data.length > 0) {
        const pm = paymentMethods.data[0];
        return new Response(
          JSON.stringify({
            has_sepa: true,
            last4: pm.sepa_debit?.last4 || "****",
            payment_method_id: pm.id,
          }),
          { headers: corsHeaders(req) }
        );
      }

      return new Response(JSON.stringify({ has_sepa: false }), {
        headers: corsHeaders(req),
      });
    }

    return new Response(JSON.stringify({ error: "Action inconnue" }), {
      status: 400,
      headers: corsHeaders(req),
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erreur inconnue";
    console.error("Erreur setup-sepa:", message);
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500,
      headers: corsHeaders(req),
    });
  }
});
