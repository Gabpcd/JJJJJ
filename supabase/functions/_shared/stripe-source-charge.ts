import Stripe from "npm:stripe@20.4.1";

function objectId(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && "id" in value && typeof value.id === "string") {
    return value.id;
  }
  return null;
}

export class StripeSourceChargeValidationError extends Error {
  readonly checks: string[];

  constructor(checks: string[]) {
    super(`STRIPE_SOURCE_CHARGE_NOT_ACQUIRED: ${checks.join(",")}`);
    this.name = "StripeSourceChargeValidationError";
    this.checks = checks;
  }
}

export async function requireAcquiredStripeSourceCharge(
  stripe: Stripe,
  paymentIntent: Stripe.PaymentIntent,
  expected: {
    customerId: string;
    amountCents: number;
    currency?: string;
  },
): Promise<Stripe.Charge> {
  const chargeId = objectId(paymentIntent.latest_charge);
  if (!chargeId) throw new StripeSourceChargeValidationError(["latest_charge"]);

  const charge = await stripe.charges.retrieve(chargeId);
  const expectedCurrency = (expected.currency || "eur").toLowerCase();
  const checks: string[] = [];
  if (charge.refunded) checks.push("refunded");
  if (charge.amount_refunded > 0) checks.push("amount_refunded");
  if (charge.disputed) checks.push("disputed");
  if (!charge.paid) checks.push("paid");
  if (charge.status !== "succeeded") checks.push("status");
  if (charge.amount !== expected.amountCents) checks.push("amount");
  if (charge.currency.toLowerCase() !== expectedCurrency) checks.push("currency");
  if (objectId(charge.customer) !== expected.customerId) checks.push("customer");
  if (objectId(charge.payment_intent) !== paymentIntent.id) checks.push("payment_intent");
  if (checks.length > 0) throw new StripeSourceChargeValidationError(checks);
  return charge;
}
