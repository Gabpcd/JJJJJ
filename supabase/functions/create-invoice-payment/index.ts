import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2.57.2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? ""
  );

  try {
    // Authenticate user
    const authHeader = req.headers.get("Authorization")!;
    const token = authHeader.replace("Bearer ", "");
    const { data: { user } } = await supabaseClient.auth.getUser(token);
    if (!user?.email) throw new Error("Non authentifié");

    const { facture_id } = await req.json();
    if (!facture_id) throw new Error("facture_id requis");

    // Use service role to read facture
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get facture
    const { data: facture, error: errF } = await supabaseAdmin
      .from("factures")
      .select("*, etablissements(nom, email_contact, stripe_customer_id)")
      .eq("id", facture_id)
      .single();

    if (errF || !facture) throw new Error("Facture introuvable");

    // Vérification de propriété via le JWT de l'utilisateur
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: userRole } = await supabaseUser.rpc("fn_get_my_role");
    const userEtabId = userRole?.etablissement_id;
    if (!userEtabId || userEtabId !== facture.etablissement_id) {
      return new Response(JSON.stringify({ error: "Accès interdit : cette facture ne vous appartient pas" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (facture.statut === "PAYEE") throw new Error("Facture déjà payée");

    // Initialize Stripe
    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
      apiVersion: "2025-08-27.basil",
    });

    // Get or create Stripe customer
    let customerId = facture.etablissements?.stripe_customer_id;
    if (!customerId) {
      const customers = await stripe.customers.list({ email: user.email, limit: 1 });
      if (customers.data.length > 0) {
        customerId = customers.data[0].id;
      } else {
        const customer = await stripe.customers.create({
          email: user.email,
          name: facture.etablissements?.nom,
          metadata: { etablissement_id: facture.etablissement_id },
        });
        customerId = customer.id;
      }

      // Save stripe_customer_id
      await supabaseAdmin
        .from("etablissements")
        .update({ stripe_customer_id: customerId })
        .eq("id", facture.etablissement_id);
    }

    // Create Checkout session for one-time payment
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      line_items: [
        {
          price_data: {
            currency: "eur",
            product_data: {
              name: `Facture ${facture.numero_facture}`,
              description: `Commission Soin Direct — ${facture.nombre_missions ?? 0} missions`,
            },
            unit_amount: Math.round((facture.montant_ttc ?? 0) * 100),
          },
          quantity: 1,
        },
      ],
      mode: "payment",
      success_url: `${req.headers.get("origin")}/etablissement/facturation/${facture_id}?paiement=succes`,
      cancel_url: `${req.headers.get("origin")}/etablissement/facturation/${facture_id}?paiement=annule`,
      metadata: {
        facture_id: facture.id,
        numero_facture: facture.numero_facture,
        etablissement_id: facture.etablissement_id,
      },
    });

    // Update facture with Stripe info
    await supabaseAdmin
      .from("factures")
      .update({
        stripe_payment_intent_id: session.payment_intent as string,
        stripe_hosted_url: session.url,
        modifie_le: new Date().toISOString(),
      })
      .eq("id", facture_id);

    return new Response(JSON.stringify({ url: session.url }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erreur inconnue";
    console.error("Erreur create-invoice-payment:", message);
    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
