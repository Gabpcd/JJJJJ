import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyUserOrServiceRole } from "../_shared/admin-auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { findInvoicePaymentIntentInconsistencies } from "../_shared/invoice-payment-intent.ts";
import { writeRequiredFinancialAudit } from "../_shared/financial-audit.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import {
  requireAcquiredStripeSourceCharge,
  StripeSourceChargeValidationError,
} from "../_shared/stripe-source-charge.ts";

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
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Méthode non autorisée" }), {
      status: 405,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) {
      return new Response(JSON.stringify({ error: auth.error }), {
        status: auth.status,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (auth.isServiceRole || !auth.userId || !authHeader) {
      return new Response(JSON.stringify({ error: "Session utilisateur requise" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseUser = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        auth: { persistSession: false },
        global: { headers: { Authorization: authHeader } },
      },
    );

    const body = await req.json().catch(() => null) as { facture_id?: unknown } | null;
    const facture_id = typeof body?.facture_id === "string" ? body.facture_id : "";
    if (!facture_id) {
      return new Response(JSON.stringify({ error: "facture_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseAdmin = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } },
    );

    const { data: facture, error: factureError } = await supabaseAdmin
      .from("factures")
      .select("id, numero_facture, statut, type_document, date_paiement, etablissement_id, montant_ttc, stripe_payment_intent_id, etablissements(stripe_customer_id)")
      .eq("id", facture_id)
      .single();

    if (factureError || !facture) {
      return new Response(JSON.stringify({ error: "Facture introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { data: hasPaymentPermission, error: permissionError } = await supabaseUser.rpc(
      "fn_a_permission_etablissement",
      { p_permission: "paiement", p_etablissement_id: facture.etablissement_id },
    );
    if (permissionError) {
      throw new Error(`Vérification des droits de paiement impossible: ${permissionError.message}`);
    }
    if (hasPaymentPermission !== true) {
      return new Response(JSON.stringify({ error: "Vous n'avez pas les droits de paiement sur cet établissement" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (facture.type_document !== "FACTURE") {
      return new Response(JSON.stringify({
        confirmed: false,
        error: "Seule une facture peut être rapprochée avec un débit Stripe",
      }), {
        status: 409,
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

    const stripe = new Stripe(stripeKey, { apiVersion: "2026-02-25.clover" });
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
    if (!Number.isSafeInteger(montantAttenduCents) || montantAttenduCents <= 0) {
      return new Response(JSON.stringify({
        confirmed: false,
        error: "Le montant de la facture est invalide",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    const customerFacture = (facture.etablissements as any)?.stripe_customer_id ?? null;
    const incoherences = findInvoicePaymentIntentInconsistencies(paymentIntent, {
      factureId: facture.id,
      etablissementId: facture.etablissement_id,
      customerId: customerFacture || "",
      amountCents: montantAttenduCents,
      currency: "eur",
    });

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

    try {
      await requireAcquiredStripeSourceCharge(stripe, paymentIntent, {
        customerId: customerFacture || "",
        amountCents: montantAttenduCents,
        currency: "eur",
      });
    } catch (error) {
      if (!(error instanceof StripeSourceChargeValidationError)) throw error;
      return new Response(JSON.stringify({
        confirmed: false,
        error: "Le débit Stripe n'est plus acquis pour cette facture",
        checks_failed: error.checks.map((check) => `source_charge.${check}`),
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (factureDejaPayee) {
      if (facture.stripe_payment_intent_id !== paymentIntent.id) {
        return new Response(JSON.stringify({
          confirmed: false,
          error: "La facture payée n'est pas liée à ce paiement Stripe",
          invoice_status: facture.statut,
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
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
    let confirmationQuery = supabaseAdmin
      .from("factures")
      .update({
        statut: "PAYEE",
        date_paiement: datePaiement,
        stripe_payment_intent_id: paymentIntent.id,
        modifie_le: new Date().toISOString(),
      })
      .eq("id", facture.id)
      .eq("montant_ttc", facture.montant_ttc)
      .in("statut", ["EMISE", "EN_RETARD"]);
    confirmationQuery = facture.stripe_payment_intent_id
      ? confirmationQuery.eq("stripe_payment_intent_id", facture.stripe_payment_intent_id)
      : confirmationQuery.is("stripe_payment_intent_id", null);
    const { data: factureConfirmee, error: updateError } = await confirmationQuery
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

      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: facture.etablissement_id,
        p_type_acteur: "SYSTEME",
        p_action: "ADMIN_ACTION",
        p_type_ressource: "facture",
        p_id_ressource: facture.id,
        p_cle_s3: null,
        p_details: {
          raison: "statut_modifie_concurremment",
          statut_initial: facture.statut,
          statut_actuel: factureActuelle?.statut ?? "inconnu",
          stripe_payment_intent: paymentIntent.id,
          evenement: "FACTURE_PAIEMENT_CONFIRMATION_CAS_PERDU",
        },
        p_ip: null,
        p_navigateur: "edge-function/confirm-invoice-payment",
      }, "confirm-invoice-payment: lost CAS audit failed");

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
