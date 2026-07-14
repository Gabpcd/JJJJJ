import Stripe from "npm:stripe@20.4.1";

export type EscrowPayoutExpectation = {
  paiementEscrowId: string;
  missionId: string;
  soignantId: string;
  amountCents: number;
};

export function escrowPayoutInconsistencies(
  payout: Stripe.Payout,
  expected: EscrowPayoutExpectation,
): string[] {
  const checks: string[] = [];
  if (payout.amount !== expected.amountCents) checks.push("amount");
  if (payout.currency !== "eur") checks.push("currency");
  if (payout.metadata?.type !== "ESCROW_RELEASE") checks.push("type");
  if (payout.metadata?.paiement_escrow_id !== expected.paiementEscrowId) {
    checks.push("paiement_escrow_id");
  }
  if (payout.metadata?.mission_id !== expected.missionId) checks.push("mission_id");
  if (payout.metadata?.soignant_id !== expected.soignantId) checks.push("soignant_id");
  if (!["pending", "in_transit", "paid", "failed", "canceled"].includes(payout.status)) {
    checks.push("status");
  }
  return checks;
}

export function requireExactEscrowPayout(
  payout: Stripe.Payout,
  expected: EscrowPayoutExpectation,
): Stripe.Payout {
  const checks = escrowPayoutInconsistencies(payout, expected);
  if (checks.length > 0) {
    throw new Error(`ESCROW_PAYOUT_IDENTITY_MISMATCH:${checks.join(",")}`);
  }
  return payout;
}
