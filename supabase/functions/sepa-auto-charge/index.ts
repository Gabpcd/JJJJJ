import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";

const PAYMENT_INTENT_ID = /^pi_[A-Za-z0-9]+$/;
const PAYMENT_INTENT_STATUSES = new Set([
  "requires_payment_method",
  "requires_confirmation",
  "requires_action",
  "processing",
  "requires_capture",
  "canceled",
  "succeeded",
]);

function isPaymentIntentId(value: unknown): value is string {
  return typeof value === "string" && PAYMENT_INTENT_ID.test(value);
}

function isPaymentIntentStatus(
  value: unknown,
): value is Stripe.PaymentIntent.Status {
  return typeof value === "string" && PAYMENT_INTENT_STATUSES.has(value);
}

/**
 * SEPA Auto-Charge: called by cron (service_role) or admin manually.
 * For each EMISE facture of a SEPA-enabled établissement,
 * creates a PaymentIntent and charges the default SEPA payment method.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST") {
    return jsonResponse(req, { error: "Méthode non autorisée" }, 405);
  }

  try {
    const auth = await verifyAdminOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);

    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    if (!serviceRoleKey || !supabaseUrl) {
      return jsonResponse(
        req,
        { error: "Configuration serveur incomplète" },
        503,
      );
    }
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) {
      return jsonResponse(
        req,
        { error: "Configuration Stripe manquante" },
        503,
      );
    }
    try {
      assertStripeSecretMode(stripeKey);
    } catch {
      return jsonResponse(req, {
        error: "Configuration Stripe production invalide",
      }, 503);
    }
    const stripe = new Stripe(stripeKey, { apiVersion: "2025-08-27.basil" });

    // Get all EMISE factures for SEPA-enabled establishments.
    // Idempotence : on EXCLUT les factures déjà tentées (stripe_payment_intent_id
    // renseigné) — un prélèvement SEPA reste « processing » plusieurs jours et la
    // facture demeure EMISE jusqu'au webhook payment_intent.succeeded → PAYEE. Sans
    // ce garde-fou, une exécution quotidienne re-prélèverait la même facture (double
    // débit). Un refus Stripe certain passe la facture en EN_RETARD ; une réponse
    // ambiguë reste récupérable avec la même clé d'idempotence.
    const { data: factures, error: fetchErr } = await supabaseAdmin
      .from("factures")
      .select(
        "id, numero_facture, montant_ttc, etablissement_id, etablissements(nom, stripe_customer_id, stripe_sepa_payment_method_id, mode_paiement_commission)",
      )
      .eq("statut", "EMISE")
      .is("stripe_payment_intent_id", null);

    if (fetchErr) {
      return jsonResponse(req, { error: "Erreur chargement factures" }, 500);
    }

    // Filter to SEPA-enabled only
    const sepaFactures = (factures || []).filter((f: any) => {
      const etab = f.etablissements;
      return etab?.mode_paiement_commission === "SEPA_DEBIT" &&
        etab?.stripe_customer_id &&
        etab?.stripe_sepa_payment_method_id;
    });

    let charged = 0;
    let failed = 0;
    const results: any[] = [];

    for (const f of sepaFactures) {
      const etab = (f as any).etablissements;
      const amountCents = Math.round((f.montant_ttc ?? 0) * 100);
      if (amountCents <= 0) continue;
      let knownIntent: Stripe.PaymentIntent | null = null;

      try {
        const paymentIntent = await stripe.paymentIntents.create({
          amount: amountCents,
          currency: "eur",
          customer: etab.stripe_customer_id,
          payment_method: etab.stripe_sepa_payment_method_id,
          confirm: true,
          off_session: true,
          mandate_data: {
            customer_acceptance: {
              type: "offline",
            },
          },
          description: `Facture ${f.numero_facture} — Commission Jolene`,
          statement_descriptor: "JOLENE",
          metadata: {
            facture_id: f.id,
            etablissement_id: f.etablissement_id,
            type: "SEPA_COMMISSION",
          },
        }, { idempotencyKey: `jolene-sepa-facture-${f.id}` });
        knownIntent = paymentIntent;

        // Update facture with payment intent
        const { data: persisted, error: persistError } = await supabaseAdmin
          .from("factures").update({
            stripe_payment_intent_id: paymentIntent.id,
            modifie_le: new Date().toISOString(),
          }).eq("id", f.id).select("id").maybeSingle();
        if (persistError || !persisted) {
          throw new Error("PERSISTENCE_PAYMENT_INTENT_FAILED");
        }

        // If payment succeeded immediately (rare for SEPA, usually processing)
        if (paymentIntent.status === "succeeded") {
          const { error: paidError } = await supabaseAdmin.from("factures")
            .update({
              statut: "PAYEE",
              date_paiement: new Date().toISOString(),
              modifie_le: new Date().toISOString(),
            }).eq("id", f.id);
          if (paidError) throw new Error("PERSISTENCE_PAYMENT_STATUS_FAILED");
        }

        charged++;
        results.push({
          facture: f.numero_facture,
          status: paymentIntent.status,
          pi: paymentIntent.id,
        });
      } catch (stripeErr: any) {
        const persistenceFailure = String(stripeErr?.message || "").startsWith(
          "PERSISTENCE_",
        );
        const embeddedIntent = stripeErr?.payment_intent ??
          stripeErr?.raw?.payment_intent;
        let knownIntentId = isPaymentIntentId(knownIntent?.id)
          ? knownIntent.id
          : null;

        if (
          embeddedIntent && typeof embeddedIntent === "object" &&
          isPaymentIntentId(embeddedIntent.id)
        ) {
          knownIntent = embeddedIntent as Stripe.PaymentIntent;
          knownIntentId = embeddedIntent.id;
        } else if (isPaymentIntentId(embeddedIntent)) {
          knownIntentId = embeddedIntent;
        }

        // Stripe peut renvoyer seulement l'identifiant du PaymentIntent dans
        // l'erreur. On tente alors une lecture pour connaître son état, mais son
        // identifiant reste une preuve suffisante pour bloquer toute nouvelle
        // tentative automatique sur cette facture.
        if (knownIntentId && !isPaymentIntentStatus(knownIntent?.status)) {
          try {
            knownIntent = await stripe.paymentIntents.retrieve(knownIntentId);
          } catch {
            // Une lecture Stripe ambiguë ne doit jamais provoquer un second débit.
          }
        }

        if (knownIntentId) {
          const intentStatus = isPaymentIntentStatus(knownIntent?.status)
            ? knownIntent.status
            : null;
          const recoveredUpdate: Record<string, string> = {
            stripe_payment_intent_id: knownIntentId,
            modifie_le: new Date().toISOString(),
          };
          if (intentStatus === "succeeded") {
            recoveredUpdate.statut = "PAYEE";
            recoveredUpdate.date_paiement = new Date().toISOString();
          } else if (intentStatus !== "processing") {
            // Hors `processing`, toute erreur Stripe est traitée fail-closed :
            // la facture reste exigible mais sort de la file de prélèvement auto.
            // Le webhook `payment_intent.succeeded` peut toujours la passer à PAYEE.
            recoveredUpdate.statut = "EN_RETARD";
          }

          const { data: recovered, error: recoveryError } = await supabaseAdmin
            .from("factures")
            .update(recoveredUpdate)
            .eq("id", f.id)
            .in("statut", ["EMISE", "EN_RETARD"])
            .select("id")
            .maybeSingle();

          if (!recoveryError && recovered) {
            if (intentStatus === "succeeded" || intentStatus === "processing") {
              charged++;
            } else failed++;
            results.push({
              facture: f.numero_facture,
              status: intentStatus ?? "unknown",
              pi: knownIntentId,
              recovered: true,
            });
            continue;
          }
        }

        failed++;
        results.push({
          facture: f.numero_facture,
          error: persistenceFailure ? "PERSISTENCE_FAILED" : "STRIPE_FAILED",
        });
        // Sans PaymentIntent certain, une erreur réseau/DB reste ambiguë. La clé
        // d'idempotence garantit que le prochain passage ne créera pas un débit neuf.
      }
    }

    return jsonResponse(req, {
      success: true,
      total_sepa_factures: sepaFactures.length,
      charged,
      failed,
      results,
    });
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : "Erreur inconnue";
    console.error("sepa-auto-charge error:", msg);
    return jsonResponse(req, { error: "Erreur interne" }, 500);
  }
});
