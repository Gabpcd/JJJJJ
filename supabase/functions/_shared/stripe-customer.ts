import type Stripe from "npm:stripe@20.4.1";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export type EtablissementStripeCustomer = {
  id: string;
  nom: string | null;
  email_contact: string | null;
  stripe_customer_id: string | null;
};

export type StripeCustomerConfigurationErrorCode =
  | "CUSTOMER_PROFILE_INCOMPLETE"
  | "CUSTOMER_TENANT_MISMATCH"
  | "CUSTOMER_PERSISTENCE_FAILED";

export class StripeCustomerConfigurationError extends Error {
  constructor(
    public readonly code: StripeCustomerConfigurationErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "StripeCustomerConfigurationError";
  }
}

export type StripeCustomerConfigurationPublicError = {
  status: 409 | 422 | 503;
  code: StripeCustomerConfigurationErrorCode;
  userMessage: string;
  retryable: boolean;
  logLevel: "warn" | "error";
};

/**
 * Convertit uniquement les erreurs Customer connues en messages publics.
 * Le message interne peut contenir un diagnostic Supabase utile aux logs et
 * ne doit jamais être sérialisé tel quel dans une réponse client.
 */
export function mapStripeCustomerConfigurationError(
  error: unknown,
): StripeCustomerConfigurationPublicError | null {
  if (!(error instanceof StripeCustomerConfigurationError)) return null;

  if (error.code === "CUSTOMER_PROFILE_INCOMPLETE") {
    return {
      status: 422,
      code: error.code,
      userMessage:
        "Renseignez le nom légal et l'e-mail de contact de l'établissement avant de payer.",
      retryable: false,
      logLevel: "warn",
    };
  }
  if (error.code === "CUSTOMER_TENANT_MISMATCH") {
    return {
      status: 409,
      code: error.code,
      userMessage:
        "Le compte de paiement doit être vérifié par le support Jolene.",
      retryable: false,
      logLevel: "error",
    };
  }
  return {
    status: 503,
    code: error.code,
    userMessage: "Le compte de paiement n'a pas pu être enregistré. Réessayez.",
    retryable: true,
    logLevel: "error",
  };
}

function canonicalCustomerKey(
  etablissementId: string,
  previousCustomerId?: string | null,
): string {
  const base = `customer_etablissement_${etablissementId}`;
  return previousCustomerId ? `${base}_after_${previousCustomerId}` : base;
}

function stripeErrorCode(error: unknown): string | null {
  if (!error || typeof error !== "object" || !("code" in error)) return null;
  return typeof error.code === "string" ? error.code : null;
}

async function validateAndSyncCustomer(
  stripe: Stripe,
  customerId: string,
  etablissement: EtablissementStripeCustomer,
  name: string,
  email: string,
): Promise<string | null> {
  let customer: Stripe.Customer | Stripe.DeletedCustomer;
  try {
    customer = await stripe.customers.retrieve(customerId);
  } catch (error) {
    if (stripeErrorCode(error) === "resource_missing") return null;
    throw error;
  }
  if (customer.deleted) return null;
  const rawLinkedEtablissementId = customer.metadata?.etablissement_id || null;
  const linkedEtablissementId = rawLinkedEtablissementId?.trim() || null;
  if (linkedEtablissementId && linkedEtablissementId !== etablissement.id) {
    throw new StripeCustomerConfigurationError(
      "CUSTOMER_TENANT_MISMATCH",
      "Le compte de paiement Stripe doit être vérifié par le support Jolene.",
    );
  }

  // Une identité nom/e-mail n'est pas une preuve de propriété Stripe. Les
  // Customers historiques sans metadata tenant sont donc bloqués jusqu'à leur
  // audit et leur backfill manuel, même s'ils ne sont référencés qu'une fois en
  // base. Cela évite toute adoption silencieuse inter-tenant.
  if (!linkedEtablissementId) {
    throw new StripeCustomerConfigurationError(
      "CUSTOMER_TENANT_MISMATCH",
      "Customer Stripe historique sans metadata tenant : audit manuel requis.",
    );
  }

  if (
    rawLinkedEtablissementId !== etablissement.id ||
    customer.name !== name ||
    customer.email !== email
  ) {
    const updated = await stripe.customers.update(customer.id, {
      name,
      email,
      metadata: { ...customer.metadata, etablissement_id: etablissement.id },
    });
    if (updated.metadata?.etablissement_id !== etablissement.id) {
      throw new StripeCustomerConfigurationError(
        "CUSTOMER_TENANT_MISMATCH",
        "Le compte de paiement Stripe doit être vérifié par le support Jolene.",
      );
    }
  }
  return customer.id;
}

/**
 * Retourne l'unique Customer Stripe rattaché à un établissement.
 *
 * La clé Stripe commune rend les créations concurrentes idempotentes entre les
 * différents flux. Le CAS SQL empêche ensuite un appel tardif d'écraser un ID
 * déjà gagné ; sa relecture et la metadata Stripe ferment le risque cross-tenant.
 */
export async function ensureCanonicalEtablissementCustomer(
  stripe: Stripe,
  supabaseAdmin: SupabaseClient,
  etablissement: EtablissementStripeCustomer,
): Promise<string> {
  const name = (etablissement.nom || "").trim();
  const email = (etablissement.email_contact || "").trim().toLowerCase();
  if (!name || !email) {
    throw new StripeCustomerConfigurationError(
      "CUSTOMER_PROFILE_INCOMPLETE",
      "Le nom légal et l'e-mail de contact de l'établissement sont requis pour le paiement.",
    );
  }

  // Un ID Stripe valide reste la source canonique et reçoit les éventuelles
  // corrections du nom/e-mail légal. Un ID supprimé côté Stripe est remplacé
  // plus bas, mais uniquement par CAS sur cette valeur devenue obsolète.
  if (etablissement.stripe_customer_id) {
    const existingId = await validateAndSyncCustomer(
      stripe,
      etablissement.stripe_customer_id,
      etablissement,
      name,
      email,
    );
    if (existingId) return existingId;
  }

  // Les paramètres de création restent immuables : nom/e-mail sont synchronisés
  // juste après. Un changement de profil ne peut donc provoquer d'erreur
  // idempotency_error lors d'un retry Stripe dans les 24 heures.
  let candidate = await stripe.customers.create(
    { metadata: { etablissement_id: etablissement.id } },
    {
      idempotencyKey: canonicalCustomerKey(
        etablissement.id,
        etablissement.stripe_customer_id,
      ),
    },
  );
  let validatedCandidate = await validateAndSyncCustomer(
    stripe,
    candidate.id,
    etablissement,
    name,
    email,
  );
  if (!validatedCandidate) {
    // Une clé idempotente peut encore rejouer pendant 24 h un Customer supprimé
    // avant que sa persistance DB n'ait abouti. Versionner par cet ID permet une
    // recréation déterministe sans rendre la clé dépendante du profil mutable.
    candidate = await stripe.customers.create(
      { metadata: { etablissement_id: etablissement.id } },
      {
        idempotencyKey: `${
          canonicalCustomerKey(
            etablissement.id,
            etablissement.stripe_customer_id,
          )
        }_after_${candidate.id}`,
      },
    );
    validatedCandidate = await validateAndSyncCustomer(
      stripe,
      candidate.id,
      etablissement,
      name,
      email,
    );
    if (!validatedCandidate) {
      throw new StripeCustomerConfigurationError(
        "CUSTOMER_PERSISTENCE_FAILED",
        "Le Customer Stripe canonique est introuvable après sa création.",
      );
    }
  }

  let claimQuery = supabaseAdmin
    .from("etablissements")
    .update({ stripe_customer_id: candidate.id })
    .eq("id", etablissement.id);
  claimQuery = etablissement.stripe_customer_id
    ? claimQuery.eq("stripe_customer_id", etablissement.stripe_customer_id)
    : claimQuery.is("stripe_customer_id", null);
  const { data: claimed, error: claimError } = await claimQuery
    .select("stripe_customer_id")
    .maybeSingle();
  if (claimError) {
    throw new StripeCustomerConfigurationError(
      "CUSTOMER_PERSISTENCE_FAILED",
      `Persistance client Stripe impossible: ${claimError.message}`,
    );
  }

  let canonicalId = claimed?.stripe_customer_id as string | null | undefined;
  if (!canonicalId) {
    const { data: current, error: readError } = await supabaseAdmin
      .from("etablissements")
      .select("stripe_customer_id")
      .eq("id", etablissement.id)
      .maybeSingle();
    if (readError || !current?.stripe_customer_id) {
      throw new StripeCustomerConfigurationError(
        "CUSTOMER_PERSISTENCE_FAILED",
        `Relecture client Stripe impossible: ${
          readError?.message || "établissement absent"
        }`,
      );
    }
    canonicalId = current.stripe_customer_id as string;
  }

  const canonicalCustomerId = await validateAndSyncCustomer(
    stripe,
    canonicalId,
    etablissement,
    name,
    email,
  );
  if (!canonicalCustomerId) {
    throw new StripeCustomerConfigurationError(
      "CUSTOMER_PERSISTENCE_FAILED",
      "Le compte de paiement enregistré est introuvable chez Stripe.",
    );
  }
  return canonicalCustomerId;
}
