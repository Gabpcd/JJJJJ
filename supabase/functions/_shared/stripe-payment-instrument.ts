import type Stripe from "npm:stripe@20.4.1";

export type StripePaymentInstrumentErrorCode =
  | "CUSTOMER_MISSING_OR_DELETED"
  | "CUSTOMER_TENANT_MISMATCH"
  | "PAYMENT_METHOD_TENANT_MISMATCH"
  | "PAYMENT_METHOD_TYPE_MISMATCH";

export class StripePaymentInstrumentConfigurationError extends Error {
  constructor(public readonly code: StripePaymentInstrumentErrorCode) {
    super(code);
    this.name = "StripePaymentInstrumentConfigurationError";
  }
}

function objectId(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (
    value && typeof value === "object" && "id" in value &&
    typeof value.id === "string"
  ) {
    return value.id;
  }
  return null;
}

/**
 * Preuve runtime fail-closed avant tout débit off-session : Customer non
 * supprimé, metadata tenant exacte, PaymentMethod du bon type et attaché à ce
 * même Customer. Le healthcheck de déploiement ne remplace pas cette garde.
 */
export async function assertStripePaymentInstrumentTenant(
  stripe: Stripe,
  params: {
    etablissementId: string;
    customerId: string;
    paymentMethodId: string;
    paymentMethodType: Stripe.PaymentMethod.Type;
  },
): Promise<{ customer: Stripe.Customer; paymentMethod: Stripe.PaymentMethod }> {
  let customer: Stripe.Customer | Stripe.DeletedCustomer;
  try {
    customer = await stripe.customers.retrieve(params.customerId);
  } catch (error) {
    if (
      error && typeof error === "object" && "code" in error &&
      error.code === "resource_missing"
    ) {
      throw new StripePaymentInstrumentConfigurationError(
        "CUSTOMER_MISSING_OR_DELETED",
      );
    }
    throw error;
  }
  if (customer.deleted) {
    throw new StripePaymentInstrumentConfigurationError(
      "CUSTOMER_MISSING_OR_DELETED",
    );
  }
  if (customer.metadata?.etablissement_id !== params.etablissementId) {
    throw new StripePaymentInstrumentConfigurationError(
      "CUSTOMER_TENANT_MISMATCH",
    );
  }

  const paymentMethod = await stripe.paymentMethods.retrieve(
    params.paymentMethodId,
  );
  if (paymentMethod.type !== params.paymentMethodType) {
    throw new StripePaymentInstrumentConfigurationError(
      "PAYMENT_METHOD_TYPE_MISMATCH",
    );
  }
  if (objectId(paymentMethod.customer) !== params.customerId) {
    throw new StripePaymentInstrumentConfigurationError(
      "PAYMENT_METHOD_TENANT_MISMATCH",
    );
  }

  return { customer, paymentMethod };
}
