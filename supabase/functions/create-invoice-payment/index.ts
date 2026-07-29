import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyUserOrServiceRole } from "../_shared/admin-auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import {
  findInvoiceCheckoutSessionInconsistencies,
  findInvoicePaymentIntentInconsistencies,
} from "../_shared/invoice-payment-intent.ts";
import {
  ensureCanonicalEtablissementCustomer,
  mapStripeCustomerConfigurationError,
} from "../_shared/stripe-customer.ts";
import { mapStripeError } from "../_shared/stripe-errors.ts";
import { writeRequiredFinancialAudit } from "../_shared/financial-audit.ts";
import {
  acquireStripePaymentFlowClaim,
  adoptLegacyStripePaymentFlowClaim,
  bindStripePaymentFlowClaimSession,
  releaseStripePaymentFlowClaimForExpiredSession,
} from "../_shared/stripe-payment-flow-claim.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import {
  requireAcquiredStripeSourceCharge,
  StripeSourceChargeValidationError,
} from "../_shared/stripe-source-charge.ts";
import { resolveOperationalTestAccount } from "../_shared/test-account.ts";

async function findMatchingPaymentIntent(
  stripe: Stripe,
  factureId: string,
  customerId?: string | null,
) {
  const matches: Stripe.PaymentIntent[] = [];
  try {
    let page: string | undefined;
    do {
      const result = await stripe.paymentIntents.search({
        query: `metadata['facture_id']:'${factureId}'`,
        limit: 100,
        ...(page ? { page } : {}),
      });
      matches.push(...result.data.filter(
        (intent) => intent.metadata?.facture_id === factureId,
      ));
      page = result.has_more ? result.next_page || undefined : undefined;
    } while (page);
  } catch (error) {
    console.warn("create-invoice-payment: payment intent search unavailable", error);
  }

  // Toujours fusionner Search et l'historique Customer : un index partiel ne
  // doit pas laisser une tentative terminale masquer un débit réussi antérieur.
  if (customerId) {
    let startingAfter: string | undefined;
    do {
      const intents = await stripe.paymentIntents.list({
        customer: customerId,
        limit: 100,
        ...(startingAfter ? { starting_after: startingAfter } : {}),
      });
      matches.push(...intents.data.filter(
        (intent) => intent.metadata?.facture_id === factureId,
      ));
      startingAfter = intents.has_more ? intents.data.at(-1)?.id : undefined;
    } while (startingAfter);
  }

  const uniqueMatches = [...new Map(matches.map((intent) => [intent.id, intent])).values()];
  const actionableIntents = uniqueMatches.filter((intent) => (
    intent.status === "succeeded"
    || [
      "processing",
      "requires_capture",
      "requires_action",
      "requires_confirmation",
    ].includes(intent.status)
  ));
  if (actionableIntents.length > 1) {
    throw new Error(`Multiple actionable PaymentIntents for invoice ${factureId}`);
  }

  const priority = (intent: Stripe.PaymentIntent) => {
    if (intent.status === "succeeded") return 0;
    if ([
      "processing",
      "requires_capture",
      "requires_action",
      "requires_confirmation",
    ].includes(intent.status)) return 1;
    return 2;
  };
  return uniqueMatches.sort((a, b) => priority(a) - priority(b) || b.created - a.created)[0]
    ?? null;
}

async function findMatchingCheckoutSession(
  stripe: Stripe,
  factureId: string,
  customerId: string,
) {
  const matches: Stripe.Checkout.Session[] = [];
  let startingAfter: string | undefined;
  do {
    const sessions = await stripe.checkout.sessions.list({
      customer: customerId,
      limit: 100,
      ...(startingAfter ? { starting_after: startingAfter } : {}),
    });
    matches.push(...sessions.data.filter((session) => (
      session.client_reference_id === factureId
      || session.metadata?.facture_id === factureId
    )));
    startingAfter = sessions.has_more ? sessions.data.at(-1)?.id : undefined;
  } while (startingAfter);

  const actionableSessions = matches.filter((session) => (
    session.status === "complete"
    || (session.status === "open" && session.expires_at * 1000 > Date.now())
  ));
  if (actionableSessions.length > 1) {
    throw new Error(`Multiple actionable Checkout Sessions for invoice ${factureId}`);
  }

  const priority = (session: Stripe.Checkout.Session) => {
    if (session.status === "complete") return 0;
    if (session.status === "open" && session.expires_at * 1000 > Date.now()) return 1;
    return 2;
  };
  return matches.sort((a, b) => priority(a) - priority(b) || b.created - a.created)[0]
    ?? null;
}

// Les retours Stripe restent sur une URL web HTTPS. L'origine CORS native est
// gérée séparément par le helper partagé et ne doit jamais devenir un
// `return_url` capacitor:// ou https://localhost.
function getApplicationReturnOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
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

  let step = 'init';

  try {
    step = '1_auth_header';
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

    step = '3_parse_body';
    const body = await req.json().catch(() => null) as {
      facture_id?: unknown;
      embedded?: unknown;
    } | null;
    const facture_id = typeof body?.facture_id === "string" ? body.facture_id : "";
    const embedded = body?.embedded === true;
    if (!facture_id) {
      return new Response(JSON.stringify({ error: "facture_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    console.log(`[create-invoice-payment] step=3 user=${auth.userId}, facture=${facture_id}, embedded=${embedded}`);

    step = '4_fetch_facture';
    const supabaseAdmin = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    const { data: facture, error: errF } = await supabaseAdmin
      .from("factures")
      .select(
        "id, numero_facture, montant_ttc, nombre_missions, statut, etablissement_id, mission_id, type_document, stripe_payment_intent_id, stripe_hosted_url, etablissements(id, nom, email_contact, stripe_customer_id, mode_paiement_commission)",
      )
      .eq("id", facture_id)
      .single();

    if (errF || !facture) {
      console.error("[create-invoice-payment] step=4 Facture introuvable", errF);
      return new Response(JSON.stringify({ error: "Facture introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    console.log(`[create-invoice-payment] step=4 facture statut=${facture.statut} montant=${facture.montant_ttc} etab=${facture.etablissement_id}`);

    step = '5_payment_permission';
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

    const testAccount = await resolveOperationalTestAccount(
      supabaseAdmin,
      facture.etablissement_id,
    );
    if (!testAccount.ok) {
      return new Response(JSON.stringify({
        error: "TEST_ACCOUNT_CLASSIFICATION_UNAVAILABLE",
      }), {
        status: 503,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (testAccount.isTest) {
      return new Response(JSON.stringify({
        error: "TEST_ACCOUNT_PAYMENT_DISABLED",
      }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const statutsPayables = ["EMISE", "EN_RETARD"];
    if (facture.type_document !== "FACTURE") {
      return new Response(JSON.stringify({
        error: "DOCUMENT_NON_PAYABLE",
        message: "Seule une facture peut faire l'objet d'un débit Stripe.",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (!statutsPayables.includes(facture.statut)) {
      const dejaPayee = facture.statut === "PAYEE";
      return new Response(JSON.stringify({
        error: dejaPayee
          ? "Facture déjà payée"
          : "Cette facture ne peut pas être payée dans son état actuel",
        status: facture.statut,
      }), {
        status: dejaPayee ? 400 : 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Une facture commission liée à une mission ne peut pas être encaissée via
    // ce Checkout standard si le flux Connect a déjà revendiqué la mission.
    // Cela évite de débiter séparément la commission pendant qu'un paiement
    // groupé commission + honoraires est en cours (ou en reprise).
    if (facture.type_document === "FACTURE" && facture.mission_id) {
      const { data: connectClaim, error: connectClaimError } = await supabaseAdmin
        .from("stripe_transfers")
        .select("id, statut, stripe_checkout_session_id, stripe_payment_intent_id")
        .eq("mission_id", facture.mission_id)
        .not("statut", "in", "(REMBOURSE,ANNULEE)")
        .order("cree_le", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (connectClaimError) {
        throw new Error(`Vérification du paiement Connect impossible: ${connectClaimError.message}`);
      }
      if (connectClaim) {
        return new Response(JSON.stringify({
          error: "PAIEMENT_CONNECT_DEJA_REVENDIQUE",
          message:
            "Cette mission est déjà prise en charge par le paiement groupé Stripe Connect.",
          status: connectClaim.statut,
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    step = '6_stripe_init';
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) {
      console.error("[create-invoice-payment] step=6 STRIPE_SECRET_KEY not set");
      return new Response(JSON.stringify({ error: "Configuration Stripe manquante" }), {
        status: 500,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    assertStripeSecretMode(stripeKey);

    // Figer la version compilée par stripe-node pour garder requêtes et webhooks cohérents.
    const stripe = new Stripe(stripeKey, { apiVersion: "2026-02-25.clover" });

    step = '7_customer';
    const montantCents = Math.round(Number(facture.montant_ttc ?? 0) * 100);
    if (!Number.isSafeInteger(montantCents) || montantCents <= 0) {
      return new Response(JSON.stringify({ error: "Montant de la facture invalide" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    const etablissementFacture = Array.isArray(facture.etablissements)
      ? facture.etablissements[0]
      : facture.etablissements;
    if (etablissementFacture?.mode_paiement_commission === "SEPA_DEBIT") {
      return new Response(JSON.stringify({
        error: "FACTURE_RESERVEE_SEPA",
        message:
          "Cette facture est configurée pour le prélèvement SEPA et ne peut pas ouvrir un Checkout.",
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    const customerId = await ensureCanonicalEtablissementCustomer(
      stripe,
      supabaseAdmin,
      etablissementFacture,
    );

    const paymentFlowClaimExpected = {
      mission_id: null,
      facture_id: facture.id,
      flow: "CHECKOUT_INVOICE" as const,
      owner_token: `invoice:${facture.id}`,
    };
    let paymentFlowClaim = await acquireStripePaymentFlowClaim(
      supabaseAdmin,
      paymentFlowClaimExpected,
    );
    let existingIntent: Stripe.PaymentIntent | null = null;
    let existingSession: Stripe.Checkout.Session | null = null;

    if (!paymentFlowClaim.acquired) {
      if (paymentFlowClaim.claim.flow === "LEGACY_UNKNOWN") {
        step = '7b_recover_legacy_claim';

        // Le backfill historique ne peut pas connaître avec certitude le flux
        // utilisé. On relit donc tout l'historique Stripe du Customer avant le
        // moindre changement de claim ou toute nouvelle création.
        existingIntent = await findMatchingPaymentIntent(
          stripe,
          facture.id,
          customerId,
        );
        existingSession = await findMatchingCheckoutSession(
          stripe,
          facture.id,
          customerId,
        );

        const legacyClaimIntentId = paymentFlowClaim.claim.stripe_payment_intent_id;
        let exactLegacyIntent: Stripe.PaymentIntent | null = existingIntent;
        if (legacyClaimIntentId) {
          const claimedIntent = existingIntent?.id === legacyClaimIntentId
            ? existingIntent
            : await stripe.paymentIntents.retrieve(legacyClaimIntentId);
          if (existingIntent && existingIntent.id !== claimedIntent.id) {
            await writeRequiredFinancialAudit(supabaseAdmin, {
              p_acteur_id: facture.etablissement_id,
              p_type_acteur: "SYSTEME",
              p_action: "ADMIN_ACTION",
              p_type_ressource: "facture",
              p_id_ressource: facture.id,
              p_cle_s3: null,
              p_details: {
                evenement: "FACTURE_LEGACY_STRIPE_AMBIGU",
                raison: "payment_intent_claim_different_de_la_recherche",
                stripe_payment_intent_claim: legacyClaimIntentId,
                stripe_payment_intent_trouve: existingIntent.id,
              },
              p_ip: null,
              p_navigateur: "edge-function/create-invoice-payment",
            }, "Legacy invoice PaymentIntent ambiguity audit failed");
            return new Response(JSON.stringify({
              error: "LEGACY_PAYMENT_REVIEW_REQUIRED",
              message:
                "Plusieurs paiements historiques correspondent à cette facture. Le support Jolene doit les rapprocher avant toute nouvelle tentative.",
              retryable: false,
            }), {
              status: 409,
              headers: { ...corsHeaders(req), "Content-Type": "application/json" },
            });
          }
          exactLegacyIntent = claimedIntent;
        }

        const sessionPaymentIntentId = existingSession
          ? (
            typeof existingSession.payment_intent === "string"
              ? existingSession.payment_intent
              : existingSession.payment_intent?.id || null
          )
          : null;
        if (sessionPaymentIntentId) {
          const sessionIntent = exactLegacyIntent?.id === sessionPaymentIntentId
            ? exactLegacyIntent
            : await stripe.paymentIntents.retrieve(sessionPaymentIntentId);
          if (exactLegacyIntent && exactLegacyIntent.id !== sessionIntent.id) {
            await writeRequiredFinancialAudit(supabaseAdmin, {
              p_acteur_id: facture.etablissement_id,
              p_type_acteur: "SYSTEME",
              p_action: "ADMIN_ACTION",
              p_type_ressource: "facture",
              p_id_ressource: facture.id,
              p_cle_s3: null,
              p_details: {
                evenement: "FACTURE_LEGACY_STRIPE_AMBIGU",
                raison: "checkout_et_payment_intent_differents",
                stripe_session_id: existingSession?.id || null,
                stripe_payment_intent_claim: exactLegacyIntent.id,
                stripe_payment_intent_checkout: sessionIntent.id,
              },
              p_ip: null,
              p_navigateur: "edge-function/create-invoice-payment",
            }, "Legacy Checkout/PaymentIntent ambiguity audit failed");
            return new Response(JSON.stringify({
              error: "LEGACY_PAYMENT_REVIEW_REQUIRED",
              message:
                "Le paiement historique ne peut pas être rapproché automatiquement. Le support Jolene doit le vérifier.",
              retryable: false,
            }), {
              status: 409,
              headers: { ...corsHeaders(req), "Content-Type": "application/json" },
            });
          }
          exactLegacyIntent = sessionIntent;
        }

        const legacyChecks: string[] = [];
        if (existingSession) {
          legacyChecks.push(...findInvoiceCheckoutSessionInconsistencies(
            existingSession,
            {
              factureId: facture.id,
              etablissementId: facture.etablissement_id,
              customerId,
              amountCents: montantCents,
              currency: "eur",
            },
          ).map((check) => `checkout.${check}`));
        }
        if (exactLegacyIntent) {
          legacyChecks.push(...findInvoicePaymentIntentInconsistencies(
            exactLegacyIntent,
            {
              factureId: facture.id,
              etablissementId: facture.etablissement_id,
              customerId,
              amountCents: montantCents,
              currency: "eur",
            },
          ).map((check) => `payment_intent.${check}`));
          if (exactLegacyIntent.status === "succeeded") {
            try {
              await requireAcquiredStripeSourceCharge(stripe, exactLegacyIntent, {
                customerId,
                amountCents: montantCents,
                currency: "eur",
              });
            } catch (error) {
              if (!(error instanceof StripeSourceChargeValidationError)) throw error;
              legacyChecks.push(
                ...error.checks.map((check) => `source_charge.${check}`),
              );
            }
          }
        }
        if (existingSession?.status === "complete") {
          if (!exactLegacyIntent) legacyChecks.push("payment_intent.missing");
          else if (exactLegacyIntent.status !== "succeeded") {
            legacyChecks.push("payment_intent.status");
          }
        } else if (exactLegacyIntent?.status === "succeeded" && existingSession) {
          legacyChecks.push("checkout.status");
        }
        if (!existingSession && !exactLegacyIntent) {
          legacyChecks.push("stripe_evidence.missing");
        }

        if (legacyChecks.length > 0) {
          await writeRequiredFinancialAudit(supabaseAdmin, {
            p_acteur_id: facture.etablissement_id,
            p_type_acteur: "SYSTEME",
            p_action: "ADMIN_ACTION",
            p_type_ressource: "facture",
            p_id_ressource: facture.id,
            p_cle_s3: null,
            p_details: {
              evenement: "FACTURE_LEGACY_STRIPE_INCOHERENTE",
              stripe_session_id: existingSession?.id || null,
              stripe_payment_intent_id: exactLegacyIntent?.id || null,
              incoherences: legacyChecks,
            },
            p_ip: null,
            p_navigateur: "edge-function/create-invoice-payment",
          }, "Legacy invoice Stripe mismatch audit failed");
          return new Response(JSON.stringify({
            error: "LEGACY_PAYMENT_REVIEW_REQUIRED",
            message:
              "Le paiement historique ne correspond pas exactement à cette facture. Le support Jolene doit le vérifier.",
            retryable: false,
          }), {
            status: 409,
            headers: { ...corsHeaders(req), "Content-Type": "application/json" },
          });
        }

        await adoptLegacyStripePaymentFlowClaim(
          supabaseAdmin,
          paymentFlowClaimExpected,
          {
            stripeCheckoutSessionId: existingSession?.id || null,
            stripePaymentIntentId: exactLegacyIntent?.id || null,
          },
        );

        paymentFlowClaim = await acquireStripePaymentFlowClaim(
          supabaseAdmin,
          paymentFlowClaimExpected,
        );
        if (!paymentFlowClaim.acquired) {
          throw new Error("Stripe legacy claim adoption lost its atomic ownership");
        }
        existingIntent = exactLegacyIntent;
      } else {
        return new Response(JSON.stringify({
          error: "PAIEMENT_MISSION_DEJA_REVENDIQUE",
          message:
            "Cette facture ou l'une de ses missions possède déjà un autre flux de paiement Stripe.",
          claimed_by: paymentFlowClaim.claim.flow,
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    if (!paymentFlowClaim.acquired) {
      return new Response(JSON.stringify({
        error: "PAIEMENT_MISSION_DEJA_REVENDIQUE",
        message:
          "Cette facture ou l'une de ses missions possède déjà un autre flux de paiement Stripe.",
        claimed_by: paymentFlowClaim.claim.flow,
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    step = '8_search_intent';
    existingIntent = existingIntent ?? await findMatchingPaymentIntent(
      stripe,
      facture.id,
      customerId,
    );

    if (existingIntent) {
      const incoherences = findInvoicePaymentIntentInconsistencies(existingIntent, {
        factureId: facture.id,
        etablissementId: facture.etablissement_id,
        customerId,
        amountCents: montantCents,
        currency: "eur",
      });
      if (incoherences.length > 0) {
        console.error("create-invoice-payment: PaymentIntent incohérent", {
          factureId: facture.id,
          paymentIntentId: existingIntent.id,
          incoherences,
        });
        return new Response(JSON.stringify({
          error: "PAYMENT_INTENT_MISMATCH",
          message: "Le paiement Stripe ne correspond pas à cette facture.",
          checks_failed: incoherences,
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    if (existingIntent?.status === "succeeded") {
      try {
        await requireAcquiredStripeSourceCharge(stripe, existingIntent, {
          customerId,
          amountCents: montantCents,
          currency: "eur",
        });
      } catch (error) {
        if (!(error instanceof StripeSourceChargeValidationError)) throw error;
        console.error("create-invoice-payment: Charge source non acquise", {
          factureId: facture.id,
          paymentIntentId: existingIntent.id,
          checks: error.checks,
        });
        return new Response(JSON.stringify({
          error: "PAYMENT_SOURCE_CHARGE_MISMATCH",
          message: "Le débit Stripe n'est plus acquis pour cette facture.",
          checks_failed: error.checks.map((check) => `source_charge.${check}`),
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      let syncQuery = supabaseAdmin
        .from("factures")
        .update({
          statut: "PAYEE",
          date_paiement: new Date(existingIntent.created * 1000).toISOString(),
          stripe_payment_intent_id: existingIntent.id,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", facture.id)
        .eq("montant_ttc", facture.montant_ttc)
        .in("statut", ["EMISE", "EN_RETARD"]);
      syncQuery = facture.stripe_payment_intent_id
        ? syncQuery.eq("stripe_payment_intent_id", facture.stripe_payment_intent_id)
        : syncQuery.is("stripe_payment_intent_id", null);
      const { data: factureSynchronisee, error: syncError } = await syncQuery
        .select("id")
        .maybeSingle();

      if (syncError) {
        throw new Error(`Impossible de synchroniser la facture payée: ${syncError.message}`);
      }

      if (!factureSynchronisee) {
        const { data: factureActuelle, error: factureActuelleError } = await supabaseAdmin
          .from("factures")
          .select("statut")
          .eq("id", facture.id)
          .maybeSingle();

        if (factureActuelleError) {
          console.error("create-invoice-payment: lost CAS state lookup failed", factureActuelleError);
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
            stripe_payment_intent: existingIntent.id,
            evenement: "FACTURE_PAIEMENT_CHECKOUT_CAS_PERDU",
          },
          p_ip: null,
          p_navigateur: "edge-function/create-invoice-payment",
        }, "Invoice succeeded-intent CAS audit failed");

        throw new Error(
          `PaymentIntent réussi impossible à rapprocher avec la facture ${facture.id}`,
        );
      }

      return new Response(JSON.stringify({ error: "Facture déjà payée", status: "PAYEE" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (existingIntent && ["processing", "requires_capture", "requires_action", "requires_confirmation"].includes(existingIntent.status)) {
      return new Response(JSON.stringify({ error: "Un paiement est déjà en cours pour cette facture", status: existingIntent.status }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    step = '8b_search_checkout';
    existingSession = existingSession ?? await findMatchingCheckoutSession(
      stripe,
      facture.id,
      customerId,
    );
    let checkoutIdempotencyKey = `invoice_checkout_${facture.id}`;
    const intentTerminalConnu = !!existingIntent
      && ["canceled", "requires_payment_method"].includes(existingIntent.status);

    const verifierSessionReutilisable = async (
      session: Stripe.Checkout.Session,
      requireSucceededIntent: boolean,
    ): Promise<string[]> => {
      const incoherences: string[] = findInvoiceCheckoutSessionInconsistencies(session, {
        factureId: facture.id,
        etablissementId: facture.etablissement_id,
        customerId,
        amountCents: montantCents,
        currency: "eur",
      });
      const sessionPaymentIntentId = typeof session.payment_intent === "string"
        ? session.payment_intent
        : session.payment_intent?.id || null;

      if (sessionPaymentIntentId) {
        const sessionPaymentIntent = existingIntent?.id === sessionPaymentIntentId
          ? existingIntent
          : await stripe.paymentIntents.retrieve(sessionPaymentIntentId);
        incoherences.push(...findInvoicePaymentIntentInconsistencies(sessionPaymentIntent, {
          factureId: facture.id,
          etablissementId: facture.etablissement_id,
          customerId,
          amountCents: montantCents,
          currency: "eur",
        }).map((check) => `payment_intent.${check}`));
        if (requireSucceededIntent && sessionPaymentIntent.status !== "succeeded") {
          incoherences.push("payment_intent.status");
        } else if (requireSucceededIntent) {
          try {
            await requireAcquiredStripeSourceCharge(stripe, sessionPaymentIntent, {
              customerId,
              amountCents: montantCents,
              currency: "eur",
            });
          } catch (error) {
            if (!(error instanceof StripeSourceChargeValidationError)) throw error;
            incoherences.push(
              ...error.checks.map((check) => `source_charge.${check}`),
            );
          }
        }
      } else if (requireSucceededIntent) {
        incoherences.push("payment_intent.missing");
      }

      return incoherences;
    };

    const auditerSessionIncoherente = async (
      session: Stripe.Checkout.Session,
      incoherences: string[],
    ) => {
      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: facture.etablissement_id,
        p_type_acteur: "SYSTEME",
        p_action: "ADMIN_ACTION",
        p_type_ressource: "facture",
        p_id_ressource: facture.id,
        p_cle_s3: null,
        p_details: {
          evenement: "FACTURE_CHECKOUT_IDENTITE_INCOHERENTE",
          stripe_session_id: session.id,
          incoherences,
        },
        p_ip: null,
        p_navigateur: "edge-function/create-invoice-payment",
      }, "Invoice checkout mismatch audit failed");
    };

    if (existingSession?.status === "open" && existingSession.expires_at * 1000 > Date.now()) {
      const incoherences = await verifierSessionReutilisable(existingSession, false);
      if (incoherences.length > 0) {
        await stripe.checkout.sessions.expire(existingSession.id);
        if (paymentFlowClaimExpected) {
          await releaseStripePaymentFlowClaimForExpiredSession(
            supabaseAdmin,
            "CHECKOUT_INVOICE",
            existingSession.id,
          );
        }
        await auditerSessionIncoherente(existingSession, incoherences);
        return new Response(JSON.stringify({
          error: "CHECKOUT_SESSION_MISMATCH",
          message: "La tentative de paiement précédente n'est plus valide. Réessayez.",
          retryable: true,
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      if (paymentFlowClaimExpected) {
        await bindStripePaymentFlowClaimSession(
          supabaseAdmin,
          paymentFlowClaimExpected,
          existingSession.id,
          paymentFlowClaim?.claim.stripe_checkout_session_id || null,
        );
      }
      // Reprise de la même tentative : aucune nouvelle Session ni nouveau PI.
      return new Response(JSON.stringify({
        url: existingSession.url,
        client_secret: existingSession.client_secret || null,
        resumed: true,
      }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        status: 200,
      });
    }

    // Une Session complète est toujours autoritaire, même si un autre PI
    // terminal plus récent existe. La sauter permettrait à ce PI d'ouvrir un
    // nouveau Checkout et de masquer une charge réussie ou incohérente.
    if (existingSession?.status === "complete") {
      const incoherences = await verifierSessionReutilisable(existingSession, true);
      if (incoherences.length > 0) {
        await auditerSessionIncoherente(existingSession, incoherences);
        return new Response(JSON.stringify({
          error: "CHECKOUT_SESSION_MISMATCH",
          message: "Le paiement terminé nécessite une vérification par le support Jolene.",
          retryable: false,
        }), {
          status: 409,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
      if (paymentFlowClaimExpected) {
        await bindStripePaymentFlowClaimSession(
          supabaseAdmin,
          paymentFlowClaimExpected,
          existingSession.id,
          paymentFlowClaim?.claim.stripe_checkout_session_id || null,
        );
      }
      return new Response(JSON.stringify({
        error: "Un paiement Checkout a déjà été validé et reste en cours de rapprochement",
        status: "complete",
      }), {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        status: 409,
      });
    }

    if (existingSession) {
      // Session expirée (ou encore marquée open après expires_at) : on la rend
      // explicitement inutilisable, puis on avance la version de façon stable.
      if (existingSession.status === "open") {
        await stripe.checkout.sessions.expire(existingSession.id);
      }
      checkoutIdempotencyKey = `invoice_checkout_${facture.id}_after_${existingSession.id}`;
    } else if (existingIntent && ["canceled", "requires_payment_method"].includes(existingIntent.status)) {
      checkoutIdempotencyKey = `invoice_checkout_${facture.id}_after_${existingIntent.id}`;
    } else if (facture.stripe_payment_intent_id) {
      // Une référence DB orpheline reste une version déterministe ; elle ne doit
      // jamais forcer la réutilisation éternelle de la première clé Stripe.
      checkoutIdempotencyKey = `invoice_checkout_${facture.id}_after_${facture.stripe_payment_intent_id}`;
    }

    step = '9_checkout';
    const appUrl = getApplicationReturnOrigin(req);

    console.log(`[create-invoice-payment] step=9 creating checkout, amount=${facture.montant_ttc}, customer=${customerId}, embedded=${!!embedded}`);

    const sessionParams: any = {
      customer: customerId,
      client_reference_id: facture.id,
      line_items: [
        {
          price_data: {
            currency: "eur",
            product_data: {
              name: `Facture ${facture.numero_facture}`,
              description: `Commission Jolene — ${facture.nombre_missions ?? 0} missions`,
            },
            unit_amount: montantCents,
          },
          quantity: 1,
        },
      ],
      mode: "payment",
      metadata: {
        facture_id: facture.id,
        etablissement_id: facture.etablissement_id,
      },
      payment_intent_data: {
        metadata: {
          facture_id: facture.id,
          etablissement_id: facture.etablissement_id,
        },
        description: `Facture ${facture.numero_facture}`,
        // Stripe : statement_descriptor doit contenir au moins 1 lettre Latin, 5-22 chars, pas de caractères spéciaux.
        // "JOLENE" suffit — pas de suffix (qui doit aussi respecter les règles Latin + ne pas dépasser combiné).
        statement_descriptor: "JOLENE",
      },
    };

    if (embedded) {
      sessionParams.ui_mode = "embedded";
      sessionParams.return_url = `${appUrl}/etablissement/facturation?paiement=succes&session_id={CHECKOUT_SESSION_ID}`;
    } else {
      sessionParams.success_url = `${appUrl}/etablissement/facturation?paiement=succes`;
      sessionParams.cancel_url = `${appUrl}/etablissement/facturation`;
    }

    const session = await stripe.checkout.sessions.create(sessionParams, {
      idempotencyKey: checkoutIdempotencyKey,
    });

    if (paymentFlowClaimExpected) {
      try {
        await bindStripePaymentFlowClaimSession(
          supabaseAdmin,
          paymentFlowClaimExpected,
          session.id,
          paymentFlowClaim?.claim.stripe_checkout_session_id || null,
        );
      } catch (claimError) {
        await stripe.checkout.sessions.expire(session.id).catch(() => undefined);
        throw claimError;
      }
    }

    const createdPaymentIntentId = typeof session.payment_intent === "string"
      ? session.payment_intent
      : session.payment_intent?.id || null;
    let factureLieeQuery = supabaseAdmin
      .from("factures")
      .update({
        stripe_payment_intent_id: createdPaymentIntentId,
        stripe_hosted_url: session.url ?? null,
        modifie_le: new Date().toISOString(),
      })
      .eq("id", facture_id)
      .eq("montant_ttc", facture.montant_ttc)
      .in("statut", ["EMISE", "EN_RETARD"]);
    factureLieeQuery = facture.stripe_payment_intent_id
      ? factureLieeQuery.eq("stripe_payment_intent_id", facture.stripe_payment_intent_id)
      : factureLieeQuery.is("stripe_payment_intent_id", null);
    factureLieeQuery = facture.stripe_hosted_url
      ? factureLieeQuery.eq("stripe_hosted_url", facture.stripe_hosted_url)
      : factureLieeQuery.is("stripe_hosted_url", null);
    const { data: factureLiee, error: updateError } = await factureLieeQuery
      .select("id")
      .maybeSingle();

    if (updateError || !factureLiee) {
      let expirationError: unknown = null;
      try {
        await stripe.checkout.sessions.expire(session.id);
        if (paymentFlowClaimExpected) {
          await releaseStripePaymentFlowClaimForExpiredSession(
            supabaseAdmin,
            "CHECKOUT_INVOICE",
            session.id,
          );
        }
      } catch (error) {
        expirationError = error;
      }

      const { data: factureActuelle } = await supabaseAdmin
        .from("factures")
        .select("statut")
        .eq("id", facture.id)
        .maybeSingle();
      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: facture.etablissement_id,
        p_type_acteur: "SYSTEME",
        p_action: "ADMIN_ACTION",
        p_type_ressource: "facture",
        p_id_ressource: facture.id,
        p_cle_s3: null,
        p_details: {
          evenement: "FACTURE_CHECKOUT_CAS_PERDU_COMPENSE",
          stripe_session_id: session.id,
          stripe_payment_intent_id: createdPaymentIntentId,
          statut_actuel: factureActuelle?.statut ?? "inconnu",
          session_expiree: expirationError === null,
          erreur_db: Boolean(updateError),
        },
        p_ip: null,
        p_navigateur: "edge-function/create-invoice-payment",
      }, "Invoice post-checkout CAS audit failed");
      if (expirationError) {
        throw new Error("La Session Checkout orpheline n'a pas pu être désactivée");
      }
      if (updateError) {
        throw new Error("La liaison de la Session Checkout à la facture a échoué");
      }
      return new Response(JSON.stringify({
        error: "INVOICE_STATE_CHANGED",
        message: "La facture a changé d'état. La tentative de paiement a été annulée.",
        retryable: false,
      }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    console.log("[create-invoice-payment] session created", {
      id: session.id,
      hasPaymentIntent: Boolean(session.payment_intent),
      hasClientSecret: Boolean(session.client_secret),
      hasHostedUrl: Boolean(session.url),
    });

    return new Response(JSON.stringify({
      url: session.url,
      client_secret: session.client_secret || null,
    }), {
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: unknown) {
    const err = error as { name?: string; type?: string; code?: string };
    const customerError = mapStripeCustomerConfigurationError(error);
    const mapped = customerError || mapStripeError(error);

    // Ne jamais journaliser/retourner session.url, client_secret, paramètre
    // Stripe, message Supabase brut ou stack au navigateur.
    console.error("[create-invoice-payment] failure", {
      step,
      name: err?.name || "Error",
      type: err?.type || null,
      code: err?.code || mapped.code,
    });

    return new Response(JSON.stringify({
      error: mapped.userMessage,
      code: mapped.code,
      retryable: mapped.retryable,
    }), {
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      status: mapped.status,
    });
  }
});
