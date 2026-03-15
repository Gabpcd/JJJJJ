import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2.57.2";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  const allowed = [
    "https://app.soindirect.com",
    "https://soinc-direct.lovable.app",
    "http://localhost:5173",
  ];
  return allowed.includes(origin) ? origin : allowed[0];
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

  const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
    apiVersion: "2025-08-27.basil",
  });

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  try {
    // Verify Stripe signature
    const body = await req.text();
    const signature = req.headers.get("stripe-signature");
    if (!signature) {
      return new Response(JSON.stringify({ error: "Missing stripe-signature header" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
    if (!webhookSecret) {
      console.error("STRIPE_WEBHOOK_SECRET not configured");
      return new Response(JSON.stringify({ error: "Webhook secret not configured" }), {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret);
    } catch (err) {
      console.error("Signature verification failed:", err);
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    console.log(`Stripe webhook received: ${event.type}`);

    // Handle checkout.session.completed
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const factureId = session.metadata?.facture_id;

      if (!factureId) {
        console.warn("checkout.session.completed sans facture_id dans metadata");
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // C2: Idempotency guard — skip if already PAYEE
      const { data: existingFacture } = await supabaseAdmin
        .from("factures")
        .select("statut")
        .eq("id", factureId)
        .single();

      if (existingFacture?.statut === "PAYEE") {
        console.log(`Facture ${factureId} already PAYEE, skipping duplicate webhook`);
        return new Response(JSON.stringify({ received: true, skipped: "already_paid" }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // Update facture to PAYEE
      const { error: updateErr } = await supabaseAdmin
        .from("factures")
        .update({
          statut: "PAYEE",
          date_paiement: new Date().toISOString(),
          stripe_payment_intent_id: session.payment_intent as string,
          stripe_hosted_url: session.url,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", factureId)
        .neq("statut", "PAYEE");

      if (updateErr) {
        console.error("Erreur mise à jour facture:", updateErr);
        throw updateErr;
      }

      // Get facture details for audit
      const { data: facture } = await supabaseAdmin
        .from("factures")
        .select("numero_facture, etablissement_id, montant_ttc")
        .eq("id", factureId)
        .single();

      // Write audit log
      if (facture) {
        await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: facture.etablissement_id,
          p_type_acteur: "SYSTEME",
          p_action: "FINANCE_FACTURE_PAYEE",
          p_type_ressource: "facture",
          p_id_ressource: factureId,
          p_cle_s3: null,
          p_details: {
            numero_facture: facture.numero_facture,
            montant_ttc: facture.montant_ttc,
            stripe_session_id: session.id,
            stripe_payment_intent: session.payment_intent,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        });

        // M6: Send FACTURE_PAYEE email — use destinataire_id only, no raw email address
        {
          const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
          const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
          await fetch(`${supabaseUrl}/functions/v1/send-email`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${serviceRoleKey}`,
            },
            body: JSON.stringify({
              type: "FACTURE_PAYEE",
              destinataire_id: facture.etablissement_id,
              data: {
                numero: facture.numero_facture,
                montant_ttc: (facture.montant_ttc ?? 0).toFixed(2),
                date_paiement: new Date().toLocaleDateString("fr-FR"),
                facture_id: factureId,
              },
            }),
          }).catch((err: unknown) => console.error("Email FACTURE_PAYEE error:", err));
        }
      }
    }

    // Handle payment_intent.succeeded (backup reconciliation)
    if (event.type === "payment_intent.succeeded") {
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      const factureId = paymentIntent.metadata?.facture_id;

      if (factureId) {
        await supabaseAdmin
          .from("factures")
          .update({
            statut: "PAYEE",
            date_paiement: new Date().toISOString(),
            stripe_payment_intent_id: paymentIntent.id,
            modifie_le: new Date().toISOString(),
          })
          .eq("id", factureId)
          .neq("statut", "PAYEE");
      }
    }

    // Handle invoice.payment_failed
    if (event.type === "invoice.payment_failed") {
      const invoice = event.data.object as Stripe.Invoice;
      const stripeInvoiceId = invoice.id;

      const { error: failErr } = await supabaseAdmin
        .from("factures")
        .update({
          statut: "EN_RETARD",
          modifie_le: new Date().toISOString(),
        })
        .eq("stripe_invoice_id", stripeInvoiceId);

      if (failErr) {
        console.error("Erreur mise à jour facture en retard:", failErr);
      }
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erreur inconnue";
    console.error("Erreur stripe-webhook:", message);
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }
});
