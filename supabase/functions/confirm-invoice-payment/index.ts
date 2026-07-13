import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";

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

Deno.serve(async (req) => {
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

    const statutsTransitionPaiement = ["EMISE", "EN_RETARD"];
    const factureDejaPayee = facture.statut === "PAYEE";
    if (!factureDejaPayee && !statutsTransitionPaiement.includes(facture.statut)) {
      return new Response(JSON.stringify({
        confirmed: false,
        error: "Cette facture ne peut pas être rapprochée dans son état actuel",
        invoice_status: facture.statut,
      }), {
        status: 409,
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
    assertStripeSecretMode(stripeKey);

    const stripe = new Stripe(stripeKey, { apiVersion: "2025-08-27.basil" });
    const paymentIntent = await findMatchingPaymentIntent(
      stripe,
      facture.id,
      (facture.etablissements as any)?.stripe_customer_id,
      facture.stripe_payment_intent_id,
    );

    if (!paymentIntent) {
      if (factureDejaPayee) {
        return new Response(JSON.stringify({
          confirmed: false,
          error: "Impossible de vérifier le paiement Stripe associé à cette facture",
          invoice_status: facture.statut,
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({ confirmed: false, status: facture.statut ?? "EMISE" }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const montantAttenduCents = Math.round(Number(facture.montant_ttc ?? 0) * 100);
    const customerFacture = (facture.etablissements as any)?.stripe_customer_id ?? null;
    const customerPaymentIntent = typeof paymentIntent.customer === "string"
      ? paymentIntent.customer
      : paymentIntent.customer?.id ?? null;
    const incoherences: string[] = [];

    if (paymentIntent.metadata?.facture_id !== facture.id) {
      incoherences.push("facture_id");
    }
    if (paymentIntent.currency.toLowerCase() !== "eur") {
      incoherences.push("currency");
    }
    if (paymentIntent.amount !== montantAttenduCents) {
      incoherences.push("amount");
    }
    if (
      paymentIntent.status === "succeeded"
      && paymentIntent.amount_received !== montantAttenduCents
    ) {
      incoherences.push("amount_received");
    }
    if (!customerFacture || !customerPaymentIntent || customerPaymentIntent !== customerFacture) {
      incoherences.push("customer");
    }

    if (incoherences.length > 0) {
      console.error(
        `confirm-invoice-payment: PaymentIntent ${paymentIntent.id} incohérent avec la facture ${facture.id}`,
        incoherences,
      );
      return new Response(JSON.stringify({
        confirmed: false,
        error: "Le paiement Stripe ne correspond pas à cette facture",
        checks_failed: incoherences,
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (paymentIntent.status !== "succeeded") {
      if (factureDejaPayee) {
        return new Response(JSON.stringify({
          confirmed: false,
          error: "Le paiement Stripe associé n'est pas confirmé",
          invoice_status: facture.statut,
          payment_intent_status: paymentIntent.status,
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({
        confirmed: false,
        status: facture.statut ?? "EMISE",
        payment_intent_status: paymentIntent.status,
      }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (factureDejaPayee) {
      return new Response(JSON.stringify({
        confirmed: true,
        status: "PAYEE",
        date_paiement: facture.date_paiement,
        payment_intent_id: paymentIntent.id,
      }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const datePaiement = new Date(paymentIntent.created * 1000).toISOString();
    const { data: factureConfirmee, error: updateError } = await supabaseAdmin
      .from("factures")
      .update({
        statut: "PAYEE",
        date_paiement: datePaiement,
        stripe_payment_intent_id: paymentIntent.id,
        modifie_le: new Date().toISOString(),
      })
      .eq("id", facture.id)
      .in("statut", ["EMISE", "EN_RETARD"])
      .select("id")
      .maybeSingle();

    if (updateError) {
      console.error("confirm-invoice-payment: facture update failed", updateError);
      return new Response(JSON.stringify({ error: "Impossible de synchroniser la facture" }), {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (!factureConfirmee) {
      const { data: factureActuelle, error: factureActuelleError } = await supabaseAdmin
        .from("factures")
        .select("statut")
        .eq("id", facture.id)
        .maybeSingle();

      if (factureActuelleError) {
        console.error("confirm-invoice-payment: lost CAS state lookup failed", factureActuelleError);
      }

      const { error: auditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: facture.etablissement_id,
        p_type_acteur: "SYSTEME",
        p_action: "FACTURE_PAIEMENT_CONFIRMATION_CAS_PERDU",
        p_type_ressource: "facture",
        p_id_ressource: facture.id,
        p_cle_s3: null,
        p_details: {
          raison: "statut_modifie_concurremment",
          statut_initial: facture.statut,
          statut_actuel: factureActuelle?.statut ?? "inconnu",
          stripe_payment_intent: paymentIntent.id,
        },
        p_ip: null,
        p_navigateur: "edge-function/confirm-invoice-payment",
      });

      if (auditError) {
        console.error("confirm-invoice-payment: lost CAS audit failed", auditError);
      }

      return new Response(JSON.stringify({
        confirmed: false,
        error: "La facture a changé d'état pendant la confirmation du paiement",
        invoice_status: factureActuelle?.statut ?? "inconnu",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      confirmed: true,
      status: "PAYEE",
      payment_intent_id: paymentIntent.id,
      date_paiement: datePaiement,
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
