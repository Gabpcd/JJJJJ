export type InvoicePaymentIntentLike = {
  id: string;
  status: string;
  amount: number;
  amount_received: number;
  currency: string;
  customer: unknown;
  metadata?: Record<string, string> | null;
};

export type InvoicePaymentIntentExpectation = {
  factureId: string;
  etablissementId: string;
  customerId: string;
  amountCents: number;
  currency?: string;
};

export type InvoicePaymentIntentInconsistency =
  | "facture_id"
  | "etablissement_id"
  | "customer"
  | "currency"
  | "amount"
  | "amount_received";

export type InvoiceCheckoutSessionLike = {
  id: string;
  customer: unknown;
  client_reference_id?: string | null;
  currency?: string | null;
  amount_total?: number | null;
  metadata?: Record<string, string> | null;
};

export type InvoiceCheckoutSessionInconsistency =
  | "facture_id"
  | "etablissement_id"
  | "client_reference_id"
  | "customer"
  | "currency"
  | "amount_total";

function objectId(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (
    value &&
    typeof value === "object" &&
    "id" in value &&
    typeof value.id === "string"
  ) {
    return value.id;
  }
  return null;
}

/**
 * Vérifie l'identité comptable complète d'un PaymentIntent de facture.
 *
 * Tous les intents, y compris ceux encore en cours, doivent appartenir à la
 * bonne facture, au bon établissement et au Customer canonique. Pour un
 * paiement réussi, Stripe doit en plus avoir effectivement reçu l'intégralité
 * du montant attendu avant que la facture puisse passer à PAYEE.
 */
export function findInvoicePaymentIntentInconsistencies(
  paymentIntent: InvoicePaymentIntentLike,
  expected: InvoicePaymentIntentExpectation,
): InvoicePaymentIntentInconsistency[] {
  const inconsistencies: InvoicePaymentIntentInconsistency[] = [];
  const expectedCurrency = (expected.currency || "eur").toLowerCase();

  if (paymentIntent.metadata?.facture_id !== expected.factureId) {
    inconsistencies.push("facture_id");
  }
  if (paymentIntent.metadata?.etablissement_id !== expected.etablissementId) {
    inconsistencies.push("etablissement_id");
  }
  if (objectId(paymentIntent.customer) !== expected.customerId) {
    inconsistencies.push("customer");
  }
  if (paymentIntent.currency.toLowerCase() !== expectedCurrency) {
    inconsistencies.push("currency");
  }
  if (paymentIntent.amount !== expected.amountCents) {
    inconsistencies.push("amount");
  }

  const amountReceivedIsPlausible =
    Number.isInteger(paymentIntent.amount_received) &&
    paymentIntent.amount_received >= 0 &&
    paymentIntent.amount_received <= expected.amountCents;
  if (
    !amountReceivedIsPlausible ||
    (
      paymentIntent.status === "succeeded" &&
      paymentIntent.amount_received !== expected.amountCents
    )
  ) {
    inconsistencies.push("amount_received");
  }

  return inconsistencies;
}

/** Vérifie l'enveloppe Checkout avant d'en réexposer l'URL ou de la solder. */
export function findInvoiceCheckoutSessionInconsistencies(
  session: InvoiceCheckoutSessionLike,
  expected: InvoicePaymentIntentExpectation,
): InvoiceCheckoutSessionInconsistency[] {
  const inconsistencies: InvoiceCheckoutSessionInconsistency[] = [];
  const expectedCurrency = (expected.currency || "eur").toLowerCase();

  if (session.metadata?.facture_id !== expected.factureId) {
    inconsistencies.push("facture_id");
  }
  if (session.metadata?.etablissement_id !== expected.etablissementId) {
    inconsistencies.push("etablissement_id");
  }
  if (session.client_reference_id !== expected.factureId) {
    inconsistencies.push("client_reference_id");
  }
  if (objectId(session.customer) !== expected.customerId) {
    inconsistencies.push("customer");
  }
  if ((session.currency || "").toLowerCase() !== expectedCurrency) {
    inconsistencies.push("currency");
  }
  if (session.amount_total !== expected.amountCents) {
    inconsistencies.push("amount_total");
  }

  return inconsistencies;
}
