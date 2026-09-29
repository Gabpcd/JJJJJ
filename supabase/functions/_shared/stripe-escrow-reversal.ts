import type Stripe from "npm:stripe@20.4.1";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

const id = (value: unknown): string | null => typeof value === "string" ? value
  : value && typeof value === "object" && "id" in value && typeof value.id === "string" ? value.id : null;

/** Destination charges create their Transfer in Stripe, not in stripe_transfers.
 * Verify the full source chain before acknowledging that reversal. This does
 * NOT confirm a customer refund: charge.refunded / the refund worker do that.
 */
export async function requireEscrowReversalBinding(
  stripe: Stripe,
  db: SupabaseClient,
  transfer: Stripe.Transfer,
) {
  const fail = (reason: string): never => { throw new Error(`ESCROW_REVERSAL_IDENTITY_MISMATCH:${reason}`); };
  const sourceId = id(transfer.source_transaction);
  if (!sourceId) return fail("source_charge_missing");
  const charge = await stripe.charges.retrieve(sourceId);
  const piId = id(charge.payment_intent);
  if (!piId) return fail("payment_intent_missing");
  const pi = await stripe.paymentIntents.retrieve(piId);
  const { data: escrow, error } = await db.from("paiements_escrow")
    .select("id,mission_id,soignant_id,etablissement_id,stripe_payment_intent_id,montant_total_cents,honoraires_cents,commission_cents")
    .eq("stripe_payment_intent_id", pi.id).maybeSingle();
  if (error || !escrow) return fail("escrow_missing");
  const { data: onboarding, error: onboardingError } = await db.from("stripe_connect_onboarding")
    .select("stripe_account_id").eq("soignant_id", escrow.soignant_id).maybeSingle();
  const total = Number(escrow.montant_total_cents);
  if (onboardingError || !onboarding?.stripe_account_id
    || !Number.isSafeInteger(total) || total <= 0
    || total !== Number(escrow.honoraires_cents) + Number(escrow.commission_cents)
    || pi.metadata?.type !== "ESCROW_MISSION_PAYMENT"
    || pi.metadata?.paiement_escrow_id !== escrow.id
    || pi.metadata?.mission_id !== escrow.mission_id
    || pi.metadata?.soignant_id !== escrow.soignant_id
    || pi.metadata?.etablissement_id !== escrow.etablissement_id
    || pi.application_fee_amount !== Number(escrow.commission_cents)
    || pi.status !== "succeeded" || pi.amount !== total || pi.amount_received !== total
    || pi.currency !== "eur" || charge.currency !== "eur" || transfer.currency !== "eur"
    || pi.livemode !== charge.livemode || pi.livemode !== transfer.livemode
    || id(pi.latest_charge) !== charge.id || id(charge.transfer) !== transfer.id
    || charge.id !== sourceId || charge.amount !== total || !charge.paid
    || charge.status !== "succeeded"
    || transfer.amount !== total || transfer.transfer_group !== `mission_${escrow.mission_id}`
    || id(transfer.destination) !== onboarding.stripe_account_id
    || id(pi.transfer_data?.destination) !== onboarding.stripe_account_id
    || !Number.isSafeInteger(transfer.amount_reversed) || transfer.amount_reversed <= 0
    || transfer.amount_reversed > total || transfer.reversed !== (transfer.amount_reversed === total)) {
    return fail("payment_source");
  }
  let after: string | undefined;
  let sum = 0;
  const seen = new Set<string>();
  do {
    const page = await stripe.transfers.listReversals(transfer.id, {
      limit: 100, ...(after ? { starting_after: after } : {}),
    });
    for (const reversal of page.data) {
      if (seen.has(reversal.id)) return fail("duplicate_reversal");
      seen.add(reversal.id);
      const refundId = id(reversal.source_refund);
      if (!refundId || reversal.currency !== "eur" || id(reversal.transfer) !== transfer.id
        || !Number.isSafeInteger(reversal.amount) || reversal.amount <= 0) return fail("reversal_source");
      const refund = await stripe.refunds.retrieve(refundId);
      const queueId = refund.metadata?.queue_id;
      if (!queueId) return fail("refund_queue_missing");
      const { data: queue, error: queueError } = await db.from("stripe_refunds_queue")
        .select("id,paiement_escrow_id,stripe_payment_intent_id,stripe_refund_id,montant_cts,reverse_transfer,absorbe_plateforme,refund_application_fee_cts")
        .eq("id", queueId).maybeSingle();
      if (queueError || !queue || queue.paiement_escrow_id !== escrow.id
        || queue.stripe_payment_intent_id !== pi.id || queue.reverse_transfer !== true
        || queue.absorbe_plateforme !== false
        || (queue.stripe_refund_id && queue.stripe_refund_id !== refund.id)
        || queue.montant_cts !== refund.amount || refund.amount !== reversal.amount
        || refund.currency !== "eur" || id(refund.charge) !== charge.id
        || id(refund.payment_intent) !== pi.id || id(refund.transfer_reversal) !== reversal.id
        || !["pending", "succeeded"].includes(refund.status || "")
        || refund.metadata?.source !== "jolene_refunds_cron"
        || refund.metadata?.origin_type !== "ESCROW"
        || refund.metadata?.paiement_escrow_id !== escrow.id
        || refund.metadata?.mission_id !== escrow.mission_id
        || refund.metadata?.etablissement_id !== escrow.etablissement_id
        || refund.metadata?.reverse_transfer !== "true"
        || refund.metadata?.absorbe_plateforme !== "false"
        || refund.metadata?.refund_application_fee_cts !== String(queue.refund_application_fee_cts)) {
        return fail("refund_source");
      }
      sum += reversal.amount;
    }
    const next = page.has_more ? page.data.at(-1)?.id : undefined;
    if (page.has_more && (!next || next === after)) return fail("pagination_incomplete");
    after = next;
  } while (after);
  if (sum !== transfer.amount_reversed) return fail("reversal_sum");
  return escrow;
}
