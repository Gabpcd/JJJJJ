import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyUserOrServiceRole } from "../_shared/admin-auth.ts";
import { corsHeaders, jsonResponse, preflightResponse } from "../_shared/cors.ts";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import {
  ensureCanonicalEtablissementCustomer,
  StripeCustomerConfigurationError,
} from "../_shared/stripe-customer.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import { resolveOperationalTestAccount } from "../_shared/test-account.ts";

type SepaAction =
  | "create_setup_intent"
  | "finalize_setup_intent"
  | "confirm_sepa"
  | "get_sepa_status";

type EtablissementSepa = {
  id: string;
  nom: string | null;
  email_contact: string | null;
  stripe_customer_id: string | null;
  stripe_sepa_payment_method_id: string | null;
};

class PublicError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = "PublicError";
  }
}

function objectId(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && "id" in value && typeof value.id === "string") {
    return value.id;
  }
  return null;
}

function stripeErrorCode(error: unknown): string | null {
  if (!error || typeof error !== "object" || !("code" in error)) return null;
  return typeof error.code === "string" ? error.code : null;
}

function safeErrorDetails(error: unknown): Record<string, string | null> {
  if (!error || typeof error !== "object") return { name: "UnknownError", type: null, code: null, requestId: null };
  const record = error as Record<string, unknown>;
  return {
    name: typeof record.name === "string" ? record.name : "Error",
    type: typeof record.type === "string" ? record.type : null,
    code: typeof record.code === "string" ? record.code : null,
    requestId: typeof record.requestId === "string" ? record.requestId : null,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST") return jsonResponse(req, { error: "Méthode non autorisée" }, 405);

  try {
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);
    // Cette fonction traite un consentement bancaire interactif. Aucun bypass
    // service-role n'est nécessaire ni accepté sur ce point d'entrée public.
    if (auth.isServiceRole || !auth.userId) {
      return jsonResponse(req, { error: "Session utilisateur requise" }, 403);
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(req, { error: "Corps JSON invalide" }, 400);
    }

    const action = String(body.action || "") as SepaAction;
    const allowedActions = new Set<SepaAction>([
      "create_setup_intent",
      "finalize_setup_intent",
      // Alias conservé pour les clients déjà déployés. Il exige désormais un
      // setup_intent_id et n'accepte plus jamais un PaymentMethod arbitraire.
      "confirm_sepa",
      "get_sepa_status",
    ]);
    if (!allowedActions.has(action)) {
      return jsonResponse(req, { error: "Action inconnue" }, 400);
    }

    if (
      action !== "get_sepa_status" &&
      applyRateLimit(
        `setup-sepa:${action}`,
        `${auth.userId}:${getClientIp(req)}`,
        { max: 8, windowMs: 60_000 },
      )
    ) {
      return jsonResponse(req, { error: "Trop de tentatives. Réessayez dans une minute." }, 429);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
    if (!supabaseUrl || !anonKey || !serviceRoleKey || !stripeSecretKey) {
      throw new PublicError(503, "Le service de paiement est temporairement indisponible.");
    }
    try {
      assertStripeSecretMode(stripeSecretKey);
    } catch {
      throw new PublicError(503, "Le service de paiement est temporairement indisponible.");
    }

    const authorization = req.headers.get("Authorization") || "";
    const userClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authorization } },
    });
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Résolution serveur de l'établissement courant : aucun identifiant
    // d'établissement ni app_metadata fourni par le client n'est utilisé.
    const { data: etablissementId, error: scopeError } = await userClient.rpc("mon_etablissement_id");
    if (scopeError || typeof etablissementId !== "string") {
      return jsonResponse(req, { error: "Aucun établissement actif associé à ce compte" }, 403);
    }

    const requiredPermission = action === "get_sepa_status" ? "lecture_paiement" : "paiement";
    const { data: hasPermission, error: permissionError } = await userClient.rpc(
      "fn_a_permission_etablissement",
      { p_permission: requiredPermission, p_etablissement_id: etablissementId },
    );
    if (permissionError) {
      throw new PublicError(503, "La vérification des droits est temporairement indisponible.");
    }
    if (hasPermission !== true) {
      return jsonResponse(req, { error: "Vous n'avez pas les droits de paiement sur cet établissement" }, 403);
    }

    const { data: etab, error: etabError } = await supabaseAdmin
      .from("etablissements")
      .select("id, nom, email_contact, stripe_customer_id, stripe_sepa_payment_method_id")
      .eq("id", etablissementId)
      .is("supprime_le", null)
      .maybeSingle();
    if (etabError) throw new PublicError(503, "Le profil de paiement est temporairement indisponible.");
    if (!etab) return jsonResponse(req, { error: "Établissement introuvable" }, 404);

    const testAccount = await resolveOperationalTestAccount(
      supabaseAdmin,
      etablissementId,
    );
    if (!testAccount.ok) {
      throw new PublicError(
        503,
        "La classification du compte est temporairement indisponible.",
      );
    }
    if (testAccount.isTest) {
      return jsonResponse(req, { error: "TEST_ACCOUNT_PAYMENT_DISABLED" }, 403);
    }

    const stripe = new Stripe(stripeSecretKey, { apiVersion: "2026-02-25.clover" });
    const currentEtab = etab as EtablissementSepa;

    if (action === "get_sepa_status") {
      if (!currentEtab.stripe_customer_id || !currentEtab.stripe_sepa_payment_method_id) {
        return jsonResponse(req, { has_sepa: false });
      }
      try {
        const customer = await stripe.customers.retrieve(currentEtab.stripe_customer_id);
        if (
          customer.deleted
          || customer.metadata?.etablissement_id !== currentEtab.id
        ) {
          return jsonResponse(req, { has_sepa: false, needs_review: true });
        }
        const paymentMethod = await stripe.paymentMethods.retrieve(currentEtab.stripe_sepa_payment_method_id);
        const linkedCustomer = objectId(paymentMethod.customer);
        const last4 = paymentMethod.sepa_debit?.last4 || null;
        if (paymentMethod.type === "sepa_debit" && linkedCustomer === currentEtab.stripe_customer_id && last4) {
          return jsonResponse(req, { has_sepa: true, last4 });
        }
        return jsonResponse(req, { has_sepa: false });
      } catch (error) {
        if (stripeErrorCode(error) === "resource_missing") {
          return jsonResponse(req, { has_sepa: false });
        }
        throw error;
      }
    }

    const billingName = (currentEtab.nom || "").trim();
    const billingEmail = (currentEtab.email_contact || "").trim().toLowerCase();
    if (!billingName) {
      throw new PublicError(422, "Renseignez le nom légal de l'établissement avant de configurer le prélèvement.");
    }
    if (!billingEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(billingEmail)) {
      throw new PublicError(422, "Renseignez une adresse e-mail de contact valide avant de configurer le prélèvement.");
    }

    const resolveCanonicalCustomer = async (): Promise<string> => {
      try {
        return await ensureCanonicalEtablissementCustomer(
          stripe,
          supabaseAdmin,
          currentEtab,
        );
      } catch (error) {
        if (error instanceof StripeCustomerConfigurationError) {
          if (error.code === "CUSTOMER_PROFILE_INCOMPLETE") {
            throw new PublicError(422, "Renseignez le nom légal et l'e-mail de contact de l'établissement avant de configurer le prélèvement.");
          }
          if (error.code === "CUSTOMER_TENANT_MISMATCH") {
            throw new PublicError(409, "Le compte de paiement doit être vérifié par le support Jolene.");
          }
          throw new PublicError(503, "Le compte de paiement n'a pas pu être enregistré. Réessayez.");
        }
        throw error;
      }
    };

    if (action === "create_setup_intent") {
      const customerId = await resolveCanonicalCustomer();
      const setupIntent = await stripe.setupIntents.create({
        customer: customerId,
        payment_method_types: ["sepa_debit"],
        usage: "off_session",
        metadata: {
          etablissement_id: currentEtab.id,
          initiated_by: auth.userId,
          purpose: "jolene_commission_sepa",
        },
      });
      if (!setupIntent.client_secret) {
        throw new PublicError(503, "Le mandat SEPA n'a pas pu être initialisé. Réessayez.");
      }
      return jsonResponse(req, {
        client_secret: setupIntent.client_secret,
        billing_name: billingName,
        billing_email: billingEmail,
      });
    }

    const setupIntentId = typeof body.setup_intent_id === "string"
      ? body.setup_intent_id.trim()
      : "";
    if (!/^seti_[A-Za-z0-9]+$/.test(setupIntentId)) {
      return jsonResponse(req, {
        error: "setup_intent_id requis ; un PaymentMethod direct n'est pas accepté",
      }, 400);
    }
    const canonicalCustomerId = await resolveCanonicalCustomer();

    const setupIntent = await stripe.setupIntents.retrieve(setupIntentId);
    const setupCustomerId = objectId(setupIntent.customer);
    const setupPaymentMethodId = objectId(setupIntent.payment_method);
    const setupMandateId = objectId(setupIntent.mandate);
    if (
      setupIntent.status !== "succeeded" ||
      setupIntent.usage !== "off_session" ||
      !setupIntent.payment_method_types.includes("sepa_debit") ||
      setupCustomerId !== canonicalCustomerId ||
      setupIntent.metadata?.etablissement_id !== currentEtab.id ||
      setupIntent.metadata?.initiated_by !== auth.userId ||
      setupIntent.metadata?.purpose !== "jolene_commission_sepa" ||
      !setupPaymentMethodId ||
      !setupMandateId
    ) {
      throw new PublicError(409, "Le mandat SEPA n'est pas confirmé ou ne correspond pas à cet établissement.");
    }

    const paymentMethod = await stripe.paymentMethods.retrieve(setupPaymentMethodId);
    const paymentMethodCustomerId = objectId(paymentMethod.customer);
    const last4 = paymentMethod.sepa_debit?.last4 || null;
    if (
      paymentMethod.type !== "sepa_debit" ||
      paymentMethodCustomerId !== canonicalCustomerId ||
      !last4
    ) {
      throw new PublicError(409, "Le moyen de paiement SEPA n'est pas rattaché au bon établissement.");
    }

    await stripe.customers.update(
      canonicalCustomerId,
      { invoice_settings: { default_payment_method: paymentMethod.id } },
      { idempotencyKey: `jolene-sepa-default-${setupIntent.id}` },
    );

    const { data: saved, error: saveError } = await supabaseAdmin
      .from("etablissements")
      .update({
        mode_paiement_commission: "SEPA_DEBIT",
        stripe_sepa_payment_method_id: paymentMethod.id,
        iban_last4: last4,
        modifie_le: new Date().toISOString(),
      })
      .eq("id", currentEtab.id)
      .eq("stripe_customer_id", canonicalCustomerId)
      .select("id")
      .maybeSingle();
    if (saveError || !saved) {
      throw new PublicError(503, "Le mandat est confirmé mais son enregistrement a échoué. Réessayez.");
    }

    return jsonResponse(req, { success: true, last4 });
  } catch (error: unknown) {
    if (error instanceof PublicError) {
      return jsonResponse(req, { error: error.message }, error.status);
    }
    // Ne jamais journaliser de client_secret, d'IBAN, de token ou de corps de
    // requête. Les seuls champs conservés ici sont des métadonnées d'erreur.
    console.error("[setup-sepa] échec", safeErrorDetails(error));
    return new Response(
      JSON.stringify({ error: "Le service de paiement est temporairement indisponible." }),
      { status: 502, headers: corsHeaders(req) },
    );
  }
});
