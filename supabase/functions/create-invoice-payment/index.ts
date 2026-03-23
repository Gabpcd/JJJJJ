import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2.57.2";

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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.error("create-invoice-payment: No Authorization header");
      return new Response(JSON.stringify({ error: "Non authentifié — header manquant" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    );

    const token = authHeader.replace("Bearer ", "");
    const { data: { user } } = await supabaseClient.auth.getUser(token);
    if (!user?.email) {
      console.error("create-invoice-payment: User not authenticated");
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

    console.log(`create-invoice-payment: user=${user.id}, facture=${facture_id}`);

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    const { data: facture, error: errF } = await supabaseAdmin
      .from("factures")
      .select("id, numero_facture, montant_ttc, nombre_missions, statut, etablissement_id, etablissements(nom, email_contact, stripe_customer_id)")
      .eq("id", facture_id)
      .single();

    if (errF || !facture) {
      console.error("create-invoice-payment: Facture introuvable", errF);
      return new Response(JSON.stringify({ error: "Facture introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Verify ownership via app_metadata
    const { data: userData } = await supabaseAdmin.auth.admin.getUserById(user.id);
    const userEtabId = userData?.user?.app_metadata?.etablissement_id || user.id;
    
    if (userEtabId !== facture.etablissement_id) {
      console.error(`create-invoice-payment: ownership mismatch user_etab=${userEtabId} facture_etab=${facture.etablissement_id}`);
      return new Response(JSON.stringify({ error: "Accès interdit : cette facture ne vous appartient pas" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (facture.statut === "PAYEE") {
      return new Response(JSON.stringify({ error: "Facture déjà payée" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) {
      console.error("create-invoice-payment: STRIPE_SECRET_KEY not set");
      return new Response(JSON.stringify({ error: "Configuration Stripe manquante" }), {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const stripe = new Stripe(stripeKey, { apiVersion: "2025-08-27.basil" });

    let customerId = (facture.etablissements as any)?.stripe_customer_id;
    if (!customerId) {
      const customers = await stripe.customers.list({ email: user.email, limit: 1 });
      if (customers.data.length > 0) {
        customerId = customers.data[0].id;
      } else {
        const customer = await stripe.customers.create({
          email: user.email,
          name: (facture.etablissements as any)?.nom,
          metadata: { etablissement_id: facture.etablissement_id },
        });
        customerId = customer.id;
      }

      await supabaseAdmin
        .from("etablissements")
        .update({ stripe_customer_id: customerId })
        .eq("id", facture.etablissement_id);
    }

    const appUrl = getCorsOrigin(req);
    const { embedded } = await req.clone().json().catch(() => ({ embedded: false }));
    
    console.log(`create-invoice-payment: creating checkout, amount=${facture.montant_ttc}, customer=${customerId}, embedded=${!!embedded}`);

    const sessionParams: any = {
      customer: customerId,
      line_items: [
        {
          price_data: {
            currency: "eur",
            product_data: {
              name: `Facture ${facture.numero_facture}`,
              description: `Commission Jolene — ${facture.nombre_missions ?? 0} missions`,
            },
            unit_amount: Math.round((facture.montant_ttc ?? 0) * 100),
          },
          quantity: 1,
        },
      ],
      mode: "payment",
    };

    if (embedded) {
      sessionParams.ui_mode = "embedded";
      sessionParams.return_url = `${appUrl}/etablissement/facturation?paiement=succes&session_id={CHECKOUT_SESSION_ID}`;
    } else {
      sessionParams.success_url = `${appUrl}/etablissement/facturation?paiement=succes`;
      sessionParams.cancel_url = `${appUrl}/etablissement/facturation`;
    }

    const session = await stripe.checkout.sessions.create(sessionParams);

    await supabaseAdmin
      .from("factures")
      .update({
        stripe_payment_intent_id: session.payment_intent as string,
        stripe_hosted_url: session.url,
        modifie_le: new Date().toISOString(),
      })
      .eq("id", facture_id);

    console.log(`create-invoice-payment: session created, client_secret=${!!session.client_secret}, url=${session.url}`);

    return new Response(JSON.stringify({ 
      url: session.url, 
      client_secret: session.client_secret || null,
    }), {
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error("Erreur create-invoice-payment:", msg);
    return new Response(JSON.stringify({ error: msg }), {
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      status: 500,
    });
  }
});
