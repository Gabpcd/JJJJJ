import type Stripe from "npm:stripe@20.4.1";

type Database = { rpc(name: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }> };
export type StandardPayoutWork = {
  id: string; missionId: string; soignantId: string; etablissementId: string; factureHonoraireId: string;
  accountId: string; customerId: string; transferId: string; paymentIntentId: string; chargeId: string;
  amountCents: number; totalCents: number; livemode: boolean; state: string; attempt: number;
  payoutId: string | null; previousPayoutId: string | null; firstPostAt: string | null;
};
type SafetyCode = "WAITING_FUNDS" | "WAITING_ACCOUNT" | "SOURCE_NOT_ACQUIRED" | "IDENTITY_MISMATCH"
  | "PAGINATION_INCOMPLETE" | "AMBIGUOUS_CREATE_EXPIRED" | "PROVIDER_OR_PERSISTENCE_ERROR" | "CHECKED";
class PayoutSafetyError extends Error {
  constructor(readonly code: SafetyCode, readonly review = false) { super(code); }
}
function fail(code: SafetyCode, review = false): never { throw new PayoutSafetyError(code, review); }
function id(value: unknown): string | null {
  return typeof value === "string" ? value : value && typeof value === "object" && "id" in value && typeof value.id === "string" ? value.id : null;
}
async function rpc(db: Database, name: string, args: Record<string, unknown>): Promise<unknown> {
  const result = await db.rpc(name, args);
  if (result.error) fail("PROVIDER_OR_PERSISTENCE_ERROR");
  return result.data;
}
export function parseStandardPayoutWork(value: unknown): StandardPayoutWork {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail("IDENTITY_MISMATCH", true);
  const r = value as Record<string, unknown>;
  for (const key of ["id", "missionId", "soignantId", "etablissementId", "factureHonoraireId"]) {
    if (typeof r[key] !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(r[key] as string)) fail("IDENTITY_MISMATCH", true);
  }
  for (const [key, prefix] of Object.entries({ accountId: "acct_", customerId: "cus_", transferId: "tr_", paymentIntentId: "pi_", chargeId: "ch_" })) {
    if (typeof r[key] !== "string" || !new RegExp(`^${prefix}[A-Za-z0-9_]+$`).test(r[key] as string)) fail("IDENTITY_MISMATCH", true);
  }
  if (!Number.isSafeInteger(r.amountCents) || Number(r.amountCents) <= 0 || !Number.isSafeInteger(r.totalCents)
    || Number(r.totalCents) <= Number(r.amountCents) || typeof r.livemode !== "boolean"
    || !Number.isInteger(r.attempt) || Number(r.attempt) < 0 || Number(r.attempt) > 3
    || !["WAITING", "SUBMITTED", "FAILED"].includes(String(r.state))) fail("IDENTITY_MISMATCH", true);
  for (const key of ["payoutId", "previousPayoutId"]) if (r[key] !== null && (typeof r[key] !== "string" || !/^po_[A-Za-z0-9_]+$/.test(r[key] as string))) fail("IDENTITY_MISMATCH", true);
  if (r.firstPostAt !== null && (typeof r.firstPostAt !== "string" || !Number.isFinite(Date.parse(r.firstPostAt)))) fail("IDENTITY_MISMATCH", true);
  return r as unknown as StandardPayoutWork;
}
export function standardPayoutMetadata(w: StandardPayoutWork): Record<string, string> {
  return { type: "CONNECT_STANDARD_PAYOUT", trace_id: w.id, transfer_id: w.transferId,
    mission_id: w.missionId, soignant_id: w.soignantId, attempt: String(w.attempt) };
}
export function requireExactStandardPayout(p: Stripe.Payout, w: StandardPayoutWork): Stripe.Payout {
  if (!/^po_[A-Za-z0-9_]+$/.test(p.id) || p.amount !== w.amountCents || p.currency !== "eur"
    || p.livemode !== w.livemode || p.automatic !== false
    || !["pending", "in_transit", "paid", "failed", "canceled"].includes(p.status)
    || Object.entries(standardPayoutMetadata(w)).some(([k, v]) => p.metadata?.[k] !== v)) fail("IDENTITY_MISMATCH", true);
  return p;
}
async function recordPayout(db: Database, w: StandardPayoutWork, p: Stripe.Payout): Promise<void> {
  requireExactStandardPayout(p, w);
  const result = await rpc(db, "fn_connect_payout_constater", { p_trace_id: w.id, p_account_id: w.accountId, p_payout: p });
  if (!result || typeof result !== "object" || !("recorded" in result) || result.recorded !== true) fail("IDENTITY_MISMATCH", true);
}

// Liste complète bornée : une limite atteinte n'est jamais une preuve d'absence.
// Même après expiration de l'idempotence Stripe, un objet exact se rapproche.
async function recoverPayout(stripe: Stripe, w: StandardPayoutWork): Promise<Stripe.Payout | null> {
  let cursor: string | undefined;
  const matches: Stripe.Payout[] = [];
  const seen = new Set<string>();
  for (let pageNumber = 0; pageNumber < 20; pageNumber++) {
    const page = await stripe.payouts.list({ limit: 100, ...(cursor ? { starting_after: cursor } : {}) }, { stripeAccount: w.accountId });
    for (const p of page.data) {
      if (seen.has(p.id)) fail("PAGINATION_INCOMPLETE", true);
      seen.add(p.id);
      if (p.metadata?.trace_id !== w.id) continue;
      const attempt = Number(p.metadata.attempt);
      if (Number.isInteger(attempt) && attempt >= 0 && attempt < w.attempt && ["failed", "canceled"].includes(p.status)) continue;
      matches.push(requireExactStandardPayout(p, w));
    }
    if (!page.has_more) {
      if (matches.length > 1) fail("IDENTITY_MISMATCH", true);
      return matches[0] || null;
    }
    cursor = page.data.at(-1)?.id;
    if (!cursor) fail("PAGINATION_INCOMPLETE", true);
  }
  fail("PAGINATION_INCOMPLETE", true);
}

async function requireReadyAccount(stripe: Stripe, w: StandardPayoutWork): Promise<void> {
  const a = await stripe.accounts.retrieve(w.accountId);
  if (a.id !== w.accountId || a.metadata?.soignant_id !== w.soignantId
    || a.settings?.payouts?.schedule?.interval !== "manual") fail("IDENTITY_MISMATCH", true);
  if (!a.payouts_enabled || !a.charges_enabled || !a.details_submitted || a.requirements?.disabled_reason
    || a.capabilities?.transfers !== "active") fail("WAITING_ACCOUNT");
}
// Le solde global peut contenir de l'escrow : il ne suffit jamais. Vérifier
// d'abord la contribution available du paiement destination de CE transfert.
async function requireAcquiredFunds(stripe: Stripe, w: StandardPayoutWork, now: number): Promise<void> {
  const tr = await stripe.transfers.retrieve(w.transferId);
  const pi = await stripe.paymentIntents.retrieve(w.paymentIntentId);
  const ch = await stripe.charges.retrieve(w.chargeId);
  const customer = await stripe.customers.retrieve(w.customerId);
  if (tr.id !== w.transferId || tr.amount !== w.amountCents || tr.currency !== "eur" || tr.livemode !== w.livemode
    || id(tr.destination) !== w.accountId || id(tr.source_transaction) !== w.chargeId
    || tr.transfer_group !== `facture_${w.factureHonoraireId}` || tr.metadata?.mission_id !== w.missionId
    || tr.metadata?.soignant_id !== w.soignantId || tr.metadata?.facture_honoraires_id !== w.factureHonoraireId
    || tr.metadata?.payment_scope !== "INVOICE" || customer.deleted || customer.metadata?.etablissement_id !== w.etablissementId
    || customer.id !== w.customerId || customer.livemode !== w.livemode
    || pi.id !== w.paymentIntentId || pi.status !== "succeeded" || pi.amount !== w.totalCents || pi.amount_received !== w.totalCents
    || pi.currency !== "eur" || pi.livemode !== w.livemode || id(pi.customer) !== w.customerId || id(pi.latest_charge) !== w.chargeId
    || pi.transfer_data != null || pi.application_fee_amount != null
    || ch.id !== w.chargeId || ch.amount !== w.totalCents || ch.currency !== "eur" || ch.livemode !== w.livemode
    || id(ch.payment_intent) !== w.paymentIntentId || id(ch.customer) !== w.customerId) fail("IDENTITY_MISMATCH", true);
  if (tr.reversed || tr.amount_reversed !== 0 || ch.refunded || ch.amount_refunded !== 0 || ch.disputed
    || !ch.paid || !ch.captured || ch.status !== "succeeded") fail("SOURCE_NOT_ACQUIRED", true);
  const destinationPaymentId = id(tr.destination_payment);
  if (!destinationPaymentId) fail("IDENTITY_MISMATCH", true);
  const dest = await stripe.charges.retrieve(destinationPaymentId, { stripeAccount: w.accountId });
  const balanceId = id(dest.balance_transaction);
  if (dest.id !== destinationPaymentId || id(dest.source_transfer) !== tr.id || dest.amount !== w.amountCents
    || dest.currency !== "eur" || dest.livemode !== w.livemode || !dest.paid || !dest.captured
    || dest.refunded || dest.amount_refunded !== 0 || !balanceId) fail("IDENTITY_MISMATCH", true);
  const tx = await stripe.balanceTransactions.retrieve(balanceId, { stripeAccount: w.accountId });
  if (tx.id !== balanceId || id(tx.source) !== dest.id || tx.amount !== w.amountCents || tx.net !== w.amountCents
    || tx.currency !== "eur") fail("IDENTITY_MISMATCH", true);
  if (tx.status !== "available" || !Number.isSafeInteger(tx.available_on) || tx.available_on * 1000 > now) fail("WAITING_FUNDS");
  const balance = await stripe.balance.retrieve({ stripeAccount: w.accountId });
  const eur = balance.available.find(b => b.currency === "eur");
  if (!eur || eur.amount < w.amountCents || (eur.source_types?.card ?? 0) < w.amountCents) fail("WAITING_FUNDS");
}

async function processOne(db: Database, stripe: Stripe, initial: StandardPayoutWork, owner: string, now: number): Promise<void> {
  let w = initial;
  const existing = w.payoutId
    ? requireExactStandardPayout(await stripe.payouts.retrieve(w.payoutId, { stripeAccount: w.accountId }), w)
    : await recoverPayout(stripe, w);
  if (existing) {
    await recordPayout(db, w, existing);
    if (!["failed", "canceled"].includes(existing.status)) return;
    if (w.attempt >= 3) fail("PROVIDER_OR_PERSISTENCE_ERROR", true);
    // Un failed/canceled n'autorise pas un nouveau débit du solde tant que
    // Stripe n'a pas rendu les fonds de cet objet précis disponibles.
    const returnedId = id(existing.failure_balance_transaction);
    if (!returnedId) fail("WAITING_FUNDS");
    const returned = await stripe.balanceTransactions.retrieve(returnedId, { stripeAccount: w.accountId });
    if (returned.id !== returnedId || id(returned.source) !== existing.id || returned.currency !== "eur"
      || returned.amount !== w.amountCents || returned.net !== w.amountCents) fail("IDENTITY_MISMATCH", true);
    if (returned.status !== "available" || returned.available_on * 1000 > now) fail("WAITING_FUNDS");
    await requireReadyAccount(stripe, w);
    if (await rpc(db, "fn_connect_payout_reessayer", { p_trace_id: w.id, p_owner: owner, p_previous_id: existing.id }) !== true) fail("WAITING_ACCOUNT");
    w = { ...w, state: "WAITING", attempt: w.attempt + 1, payoutId: null, previousPayoutId: existing.id, firstPostAt: null };
  } else if (w.payoutId || w.state !== "WAITING") {
    fail("IDENTITY_MISMATCH", true);
  }
  if (w.firstPostAt && now - Date.parse(w.firstPostAt) >= 20 * 60 * 60 * 1000) fail("AMBIGUOUS_CREATE_EXPIRED", true);
  await requireReadyAccount(stripe, w);
  await requireAcquiredFunds(stripe, w, now);
  if (await rpc(db, "fn_connect_payout_demarrer", { p_trace_id: w.id, p_owner: owner }) !== true) fail("WAITING_ACCOUNT");
  // Aucun rollback après ce point : first_post_at + même clé bornent la reprise
  // même si Stripe répond après l'expiration du lease ou si la persistance échoue.
  const payout = await stripe.payouts.create({ amount: w.amountCents, currency: "eur", source_type: "card",
    metadata: standardPayoutMetadata(w) }, { stripeAccount: w.accountId, idempotencyKey: `connect_payout_${w.id}_${w.attempt}` });
  await recordPayout(db, w, payout);
}

export async function processStandardConnectPayouts(db: Database, stripe: Stripe, options: { now?: number; owner?: () => string } = {}) {
  const summary = { examined: 0, checked: 0, deferred: 0, review: 0, errors: 0 };
  const due = await rpc(db, "fn_connect_payouts_a_traiter", { p_limit: 5 });
  if (!Array.isArray(due) || due.length > 10) fail("IDENTITY_MISMATCH", true);
  for (const candidate of due) {
    if (!candidate || typeof candidate !== "object" || typeof candidate.id !== "string") fail("IDENTITY_MISMATCH", true);
    const owner = options.owner?.() || crypto.randomUUID();
    const value = await rpc(db, "fn_connect_payout_prendre", { p_trace_id: candidate.id, p_owner: owner });
    if (value === null) continue;
    summary.examined++;
    let code: SafetyCode = "CHECKED";
    let review = false;
    try {
      const work = parseStandardPayoutWork(value);
      await processOne(db, stripe, work, owner, options.now ?? Date.now());
      summary.checked++;
    } catch (error) {
      code = error instanceof PayoutSafetyError ? error.code : "PROVIDER_OR_PERSISTENCE_ERROR";
      review = error instanceof PayoutSafetyError && error.review;
      if (review) summary.review++;
      else if (["WAITING_FUNDS", "WAITING_ACCOUNT"].includes(code)) summary.deferred++;
      else summary.errors++;
    }
    await rpc(db, "fn_connect_payout_reporter", { p_trace_id: candidate.id, p_owner: owner, p_code: code, p_review: review });
  }
  return summary;
}

// Événement Connect signé, puis objet courant relu : aucune promotion depuis le
// payload d'un événement ancien. Le cron assure aussi cette réconciliation.
export async function reconcileStandardPayoutEvent(db: Database, stripe: Stripe, accountId: string, payoutId: string): Promise<void> {
  const p = await stripe.payouts.retrieve(payoutId, { stripeAccount: accountId });
  if (p.id !== payoutId || p.metadata?.type !== "CONNECT_STANDARD_PAYOUT" || !p.metadata.trace_id) fail("IDENTITY_MISMATCH", true);
  const result = await rpc(db, "fn_connect_payout_constater", { p_trace_id: p.metadata.trace_id, p_account_id: accountId, p_payout: p });
  if (!result || typeof result !== "object" || !(("recorded" in result && result.recorded === true)
    || ("ignored" in result && result.ignored === true))) fail("IDENTITY_MISMATCH", true);
}
