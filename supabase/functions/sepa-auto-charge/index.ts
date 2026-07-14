import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";
import { findInvoicePaymentIntentInconsistencies } from "../_shared/invoice-payment-intent.ts";
import { writeRequiredFinancialAudit } from "../_shared/financial-audit.ts";
import {
  acquireStripePaymentFlowClaim,
  bindStripePaymentFlowClaimIntent,
} from "../_shared/stripe-payment-flow-claim.ts";
import {
  assertStripePaymentInstrumentTenant,
  StripePaymentInstrumentConfigurationError,
} from "../_shared/stripe-payment-instrument.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import {
  requireAcquiredStripeSourceCharge,
  StripeSourceChargeValidationError,
} from "../_shared/stripe-source-charge.ts";

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
    const stripe = new Stripe(stripeKey, { apiVersion: "2026-02-25.clover" });

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
        "id, numero_facture, type_document, mission_id, montant_ttc, etablissement_id, stripe_payment_intent_id, etablissements(nom, stripe_customer_id, stripe_sepa_payment_method_id, mode_paiement_commission)",
      )
      .eq("statut", "EMISE")
      .eq("type_document", "FACTURE")
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
      if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
        failed++;
        results.push({ facture: f.numero_facture, error: "INVALID_AMOUNT" });
        continue;
      }
      let knownIntent: Stripe.PaymentIntent | null = null;
      const paymentFlowClaimExpected = {
        mission_id: null,
        facture_id: f.id,
        flow: "SEPA_INVOICE" as const,
        owner_token: `sepa:${f.id}`,
      };
      let paymentFlowClaim: Awaited<ReturnType<typeof acquireStripePaymentFlowClaim>> | null = null;

      try {
        paymentFlowClaim = await acquireStripePaymentFlowClaim(
          supabaseAdmin,
          paymentFlowClaimExpected,
        );
        if (!paymentFlowClaim.acquired) {
          failed++;
          results.push({
            facture: f.numero_facture,
            error: "PAYMENT_FLOW_ALREADY_CLAIMED",
            claimed_by: paymentFlowClaim.claim.flow,
          });
          continue;
        }
        const claimedPaymentIntentId = paymentFlowClaim.claim.stripe_payment_intent_id;
        if (claimedPaymentIntentId) {
          // Source prioritaire de reprise : le bind du claim peut avoir réussi
          // alors que le CAS sur factures a échoué. Ne jamais rappeler create
          // (même avec une ancienne clé d'idempotence) tant que ce PI existe.
          const claimedIntent = await stripe.paymentIntents.retrieve(claimedPaymentIntentId);
          knownIntent = claimedIntent;
          const claimChecks = findInvoicePaymentIntentInconsistencies(claimedIntent, {
            factureId: f.id,
            etablissementId: f.etablissement_id,
            customerId: etab.stripe_customer_id,
            amountCents,
            currency: "eur",
          });
          if (claimChecks.length > 0) {
            throw Object.assign(new Error("INVOICE_PAYMENT_MISMATCH"), {
              code: "INVOICE_PAYMENT_MISMATCH",
              paymentChecks: claimChecks,
            });
          }

          let claimSourceChargeAcquired = claimedIntent.status !== "succeeded";
          let claimSourceChargeChecks: string[] = [];
          if (claimedIntent.status === "succeeded") {
            try {
              await requireAcquiredStripeSourceCharge(stripe, claimedIntent, {
                customerId: etab.stripe_customer_id,
                amountCents,
                currency: "eur",
              });
              claimSourceChargeAcquired = true;
            } catch (error) {
              if (!(error instanceof StripeSourceChargeValidationError)) throw error;
              claimSourceChargeChecks = error.checks.map((check) => `source_charge.${check}`);
            }
          }

          const claimRecovery: Record<string, string> = {
            stripe_payment_intent_id: claimedIntent.id,
            modifie_le: new Date().toISOString(),
          };
          if (claimedIntent.status === "succeeded" && claimSourceChargeAcquired) {
            claimRecovery.statut = "PAYEE";
            claimRecovery.date_paiement = new Date().toISOString();
          } else if (
            claimedIntent.status !== "processing"
            && !(claimedIntent.status === "succeeded" && claimSourceChargeChecks.length === 0)
          ) {
            claimRecovery.statut = "EN_RETARD";
          }
          const { data: claimReconciled, error: claimReconcileError } = await supabaseAdmin
            .from("factures")
            .update(claimRecovery)
            .eq("id", f.id)
            .eq("statut", "EMISE")
            .eq("montant_ttc", f.montant_ttc)
            .or(
              `stripe_payment_intent_id.is.null,stripe_payment_intent_id.eq.${claimedIntent.id}`,
            )
            .select("id")
            .maybeSingle();
          if (claimReconcileError || !claimReconciled) {
            throw new Error("PERSISTENCE_CLAIMED_PAYMENT_INTENT_FAILED");
          }
          if (
            claimedIntent.status === "processing"
            || (claimedIntent.status === "succeeded" && claimSourceChargeAcquired)
          ) {
            charged++;
          } else {
            failed++;
          }
          results.push({
            facture: f.numero_facture,
            status: claimedIntent.status,
            pi: claimedIntent.id,
            recovered_from_claim: true,
            ...(claimSourceChargeChecks.length > 0
              ? { error: "SOURCE_CHARGE_NOT_ACQUIRED", checks: claimSourceChargeChecks }
              : {}),
          });
          continue;
        }
        await assertStripePaymentInstrumentTenant(stripe, {
          etablissementId: f.etablissement_id,
          customerId: etab.stripe_customer_id,
          paymentMethodId: etab.stripe_sepa_payment_method_id,
          paymentMethodType: "sepa_debit",
        });
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
        if (!["processing", "succeeded"].includes(paymentIntent.status)) {
          throw Object.assign(new Error("SEPA_UNEXPECTED_PAYMENT_STATUS"), {
            code: "SEPA_UNEXPECTED_PAYMENT_STATUS",
          });
        }
        const paymentChecks = findInvoicePaymentIntentInconsistencies(paymentIntent, {
          factureId: f.id,
          etablissementId: f.etablissement_id,
          customerId: etab.stripe_customer_id,
          amountCents,
          currency: "eur",
        });
        if (paymentChecks.length > 0) {
          throw Object.assign(new Error("INVOICE_PAYMENT_MISMATCH"), {
            code: "INVOICE_PAYMENT_MISMATCH",
            paymentChecks,
          });
        }
        await bindStripePaymentFlowClaimIntent(
          supabaseAdmin,
          paymentFlowClaimExpected,
          paymentIntent.id,
          paymentFlowClaim.claim.stripe_payment_intent_id,
        );

        // Update facture with payment intent
        const { data: persisted, error: persistError } = await supabaseAdmin
          .from("factures").update({
            stripe_payment_intent_id: paymentIntent.id,
            modifie_le: new Date().toISOString(),
          })
          .eq("id", f.id)
          .eq("statut", "EMISE")
          .eq("montant_ttc", f.montant_ttc)
          .is("stripe_payment_intent_id", null)
          .select("id")
          .maybeSingle();
        if (persistError || !persisted) {
          throw new Error("PERSISTENCE_PAYMENT_INTENT_FAILED");
        }

        // If payment succeeded immediately (rare for SEPA, usually processing)
        if (paymentIntent.status === "succeeded") {
          try {
            await requireAcquiredStripeSourceCharge(stripe, paymentIntent, {
              customerId: etab.stripe_customer_id,
              amountCents,
              currency: "eur",
            });
          } catch (error) {
            if (!(error instanceof StripeSourceChargeValidationError)) throw error;
            const { data: overdue, error: overdueError } = await supabaseAdmin
              .from("factures")
              .update({
                statut: "EN_RETARD",
                modifie_le: new Date().toISOString(),
              })
              .eq("id", f.id)
              .eq("statut", "EMISE")
              .eq("montant_ttc", f.montant_ttc)
              .eq("stripe_payment_intent_id", paymentIntent.id)
              .select("id")
              .maybeSingle();
            if (overdueError || !overdue) {
              throw new Error("PERSISTENCE_PAYMENT_STATUS_FAILED");
            }
            failed++;
            results.push({
              facture: f.numero_facture,
              status: paymentIntent.status,
              pi: paymentIntent.id,
              error: "SOURCE_CHARGE_NOT_ACQUIRED",
              checks: error.checks.map((check) => `source_charge.${check}`),
            });
            continue;
          }
          const { data: paid, error: paidError } = await supabaseAdmin.from("factures")
            .update({
              statut: "PAYEE",
              date_paiement: new Date().toISOString(),
              modifie_le: new Date().toISOString(),
            })
            .eq("id", f.id)
            .eq("statut", "EMISE")
            .eq("montant_ttc", f.montant_ttc)
            .eq("stripe_payment_intent_id", paymentIntent.id)
            .select("id")
            .maybeSingle();
          if (paidError || !paid) throw new Error("PERSISTENCE_PAYMENT_STATUS_FAILED");
        }

        charged++;
        results.push({
          facture: f.numero_facture,
          status: paymentIntent.status,
          pi: paymentIntent.id,
        });
      } catch (stripeErr: any) {
        if (stripeErr?.code === "INVOICE_PAYMENT_MISMATCH") {
          // Même incohérent, un PI déjà créé doit rester revendiqué durablement :
          // sans ce bind, la rétention limitée de la clé d'idempotence pourrait
          // autoriser un second débit lors d'une reprise très tardive.
          if (knownIntent?.id && paymentFlowClaim?.acquired) {
            await bindStripePaymentFlowClaimIntent(
              supabaseAdmin,
              paymentFlowClaimExpected,
              knownIntent.id,
              paymentFlowClaim.claim.stripe_payment_intent_id,
            );
          }
          await writeRequiredFinancialAudit(supabaseAdmin, {
            p_acteur_id: f.etablissement_id,
            p_type_acteur: "SYSTEME",
            p_action: "ADMIN_ACTION",
            p_type_ressource: "facture",
            p_id_ressource: f.id,
            p_cle_s3: null,
            p_details: {
              evenement: "SEPA_PAYMENT_INTENT_INCOHERENT",
              stripe_payment_intent_id: knownIntent?.id || null,
              incoherences: stripeErr.paymentChecks || [],
            },
            p_ip: null,
            p_navigateur: "sepa-auto-charge",
          }, "SEPA PaymentIntent mismatch audit failed");
          failed++;
          results.push({ facture: f.numero_facture, error: "PAYMENT_MISMATCH" });
          continue;
        }
        if (stripeErr instanceof StripePaymentInstrumentConfigurationError) {
          await writeRequiredFinancialAudit(supabaseAdmin, {
            p_acteur_id: f.etablissement_id,
            p_type_acteur: "SYSTEME",
            p_action: "ADMIN_ACTION",
            p_type_ressource: "facture",
            p_id_ressource: f.id,
            p_cle_s3: null,
            p_details: {
              evenement: "SEPA_INSTRUMENT_TENANT_INCOHERENT",
              raison: stripeErr.code,
            },
            p_ip: null,
            p_navigateur: "sepa-auto-charge",
          }, "SEPA payment instrument mismatch audit failed");
          failed++;
          results.push({
            facture: f.numero_facture,
            error: "PAYMENT_INSTRUMENT_REVIEW_REQUIRED",
          });
          continue;
        }
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
          let recoveredSourceChargeAcquired = intentStatus !== "succeeded";
          let recoveredSourceChargeChecks: string[] = [];
          if (intentStatus === "succeeded" && knownIntent) {
            try {
              await requireAcquiredStripeSourceCharge(stripe, knownIntent, {
                customerId: etab.stripe_customer_id,
                amountCents,
                currency: "eur",
              });
              recoveredSourceChargeAcquired = true;
            } catch (error) {
              if (error instanceof StripeSourceChargeValidationError) {
                recoveredSourceChargeChecks = error.checks.map(
                  (check) => `source_charge.${check}`,
                );
              } else {
                console.error(
                  `sepa-auto-charge: Charge source ${knownIntentId} non vérifiable`,
                  error,
                );
              }
            }
          }
          const recoveredUpdate: Record<string, string> = {
            stripe_payment_intent_id: knownIntentId,
            modifie_le: new Date().toISOString(),
          };
          if (intentStatus === "succeeded" && recoveredSourceChargeAcquired) {
            recoveredUpdate.statut = "PAYEE";
            recoveredUpdate.date_paiement = new Date().toISOString();
          } else if (
            intentStatus !== "processing"
            && !(intentStatus === "succeeded" && recoveredSourceChargeChecks.length === 0)
          ) {
            // Hors `processing`, toute erreur Stripe est traitée fail-closed :
            // la facture reste exigible mais sort de la file de prélèvement auto.
            // Le webhook `payment_intent.succeeded` peut toujours la passer à PAYEE.
            recoveredUpdate.statut = "EN_RETARD";
          }
          if (paymentFlowClaim?.acquired) {
            await bindStripePaymentFlowClaimIntent(
              supabaseAdmin,
              paymentFlowClaimExpected,
              knownIntentId,
              paymentFlowClaim.claim.stripe_payment_intent_id,
            );
          }

          const { data: recovered, error: recoveryError } = await supabaseAdmin
            .from("factures")
            .update(recoveredUpdate)
            .eq("id", f.id)
            .eq("statut", "EMISE")
            .eq("montant_ttc", f.montant_ttc)
            .is("stripe_payment_intent_id", null)
            .select("id")
            .maybeSingle();

          if (!recoveryError && recovered) {
            if (
              intentStatus === "processing"
              || (intentStatus === "succeeded" && recoveredSourceChargeAcquired)
            ) {
              charged++;
            } else failed++;
            results.push({
              facture: f.numero_facture,
              status: intentStatus ?? "unknown",
              pi: knownIntentId,
              recovered: true,
              ...(recoveredSourceChargeChecks.length > 0
                ? { error: "SOURCE_CHARGE_NOT_ACQUIRED", checks: recoveredSourceChargeChecks }
                : {}),
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
