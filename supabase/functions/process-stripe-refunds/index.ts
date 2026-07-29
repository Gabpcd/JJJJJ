// process-stripe-refunds — remboursements Stripe rapprochés exactement.
//
// Un appel refunds.create n'est pas un succès financier : un Refund peut
// rester pending/requires_action puis échouer. Cette fonction ne solde donc la
// queue, l'AVOIR, l'escrow et son exposition qu'après `status=succeeded`, via
// une seule transaction SQL (`fn_stripe_refund_rapprocher`).

import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  cronAuthErrorResponse,
  cronAuthProbeResponse,
  isCronAuthProbe,
  verifyCronServiceAuth,
} from "../_shared/cron-service-auth.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";

const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_KEY = Deno.env.get("STRIPE_SECRET_KEY") || "";
const LEASE_MS = 15 * 60 * 1000;
const MAX_BATCH = 10;

interface QueueRow {
  id: string;
  avoir_id: string | null;
  facture_origine_id: string | null;
  stripe_payment_intent_id: string;
  stripe_refund_id: string | null;
  montant_cts: number;
  tentatives: number;
  paiement_escrow_id: string | null;
  reverse_transfer: boolean;
  refund_application_fee_cts: number;
  absorbe_plateforme: boolean;
  escrow_statut_avant_remboursement: string | null;
}

type RefundContext = {
  paymentIntent: Stripe.PaymentIntent;
  charge: Stripe.Charge;
  params: Stripe.RefundCreateParams;
};

class ProvenPreflightError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = "ProvenPreflightError";
    this.code = code;
  }
}

class AmbiguousFinancialStateError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = "AmbiguousFinancialStateError";
    this.code = code;
  }
}

function objectId(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && "id" in value) {
    const id = (value as { id?: unknown }).id;
    return typeof id === "string" ? id : null;
  }
  return null;
}

function fail(code: string, message: string): never {
  throw new ProvenPreflightError(code, message);
}

function isDeletedCustomer(
  customer: Stripe.Customer | Stripe.DeletedCustomer,
): customer is Stripe.DeletedCustomer {
  return "deleted" in customer && customer.deleted === true;
}

async function retrieveCharge(
  stripe: Stripe,
  paymentIntent: Stripe.PaymentIntent,
): Promise<Stripe.Charge> {
  const latest = paymentIntent.latest_charge;
  if (!latest) fail("SOURCE_CHARGE_ABSENTE", "PaymentIntent sans Charge source");
  return typeof latest === "string"
    ? await stripe.charges.retrieve(latest)
    : latest;
}

async function validateCommonStripeSource(
  stripe: Stripe,
  item: QueueRow,
  paymentIntent: Stripe.PaymentIntent,
  expected: {
    etablissementId: string;
    customerId: string;
    amountCents: number;
    metadataMissionId?: string | null;
  },
  existingRefund: Stripe.Refund | null,
): Promise<Stripe.Charge> {
  const charge = await retrieveCharge(stripe, paymentIntent);
  const customer = await stripe.customers.retrieve(expected.customerId);
  const ownSucceededAmount = existingRefund?.status === "succeeded"
    ? existingRefund.amount
    : 0;
  const otherSucceededRefundedAmount = charge.amount_refunded - ownSucceededAmount;
  // Un refund/dispute étranger à cette queue est déjà un mouvement financier.
  // Il est donc interdit de classer le préflight en ECHEC et de restaurer
  // l'escrow : on le garde gelé jusqu'au rapprochement manuel exact.
  if (
    charge.disputed
    || otherSucceededRefundedAmount < 0
    || otherSucceededRefundedAmount > 0
  ) {
    throw new AmbiguousFinancialStateError(
      "STRIPE_SOURCE_ALREADY_MOVED",
      "La Charge porte déjà un remboursement ou une contestation hors de cette queue",
    );
  }
  const remainingForQueue = charge.amount - charge.amount_refunded + ownSucceededAmount;

  if (
    paymentIntent.id !== item.stripe_payment_intent_id
    || paymentIntent.status !== "succeeded"
    || paymentIntent.currency !== "eur"
    || paymentIntent.amount !== expected.amountCents
    || paymentIntent.amount_received !== expected.amountCents
    || paymentIntent.amount_capturable !== 0
    || objectId(paymentIntent.customer) !== expected.customerId
    || paymentIntent.metadata?.etablissement_id !== expected.etablissementId
    || (expected.metadataMissionId
      && paymentIntent.metadata?.mission_id !== expected.metadataMissionId)
    || isDeletedCustomer(customer)
    || customer.metadata?.etablissement_id !== expected.etablissementId
    || !charge.paid
    || !charge.captured
    || charge.status !== "succeeded"
    || charge.currency !== "eur"
    || charge.amount !== expected.amountCents
    || charge.amount_refunded < 0
    || charge.amount_refunded > charge.amount
    || objectId(charge.customer) !== expected.customerId
    || objectId(charge.payment_intent) !== paymentIntent.id
    || item.montant_cts > remainingForQueue
  ) {
    fail(
      "STRIPE_REFUND_SOURCE_IDENTITY_MISMATCH",
      "Le paiement Stripe ne correspond pas exactement à l'origine de la queue",
    );
  }
  return charge;
}

async function validateEscrowSource(
  sb: any,
  stripe: Stripe,
  item: QueueRow,
  paymentIntent: Stripe.PaymentIntent,
  existingRefund: Stripe.Refund | null,
): Promise<RefundContext> {
  const { data: escrow, error: escrowError } = await sb
    .from("paiements_escrow")
    .select(
      "id, mission_id, etablissement_id, soignant_id, montant_total_cents, honoraires_cents, commission_cents, stripe_payment_intent_id, statut",
    )
    .eq("id", item.paiement_escrow_id)
    .maybeSingle();
  if (escrowError || !escrow) {
    fail(
      "ESCROW_SOURCE_ABSENTE",
      `Escrow introuvable: ${escrowError?.message || item.paiement_escrow_id}`,
    );
  }

  const { data: etablissement, error: etablissementError } = await sb
    .from("etablissements")
    .select("id, stripe_customer_id")
    .eq("id", escrow.etablissement_id)
    .maybeSingle();
  const { data: onboarding, error: onboardingError } = await sb
    .from("stripe_connect_onboarding")
    .select("soignant_id, stripe_account_id, statut, onboarding_complete, charges_enabled, payouts_enabled")
    .eq("soignant_id", escrow.soignant_id)
    .maybeSingle();
  if (
    etablissementError
    || !etablissement?.stripe_customer_id
    || onboardingError
    || !onboarding?.stripe_account_id
  ) {
    fail(
      "ESCROW_TENANT_BINDING_ABSENT",
      etablissementError?.message || onboardingError?.message || "liaison Stripe absente",
    );
  }

  const prior = item.escrow_statut_avant_remboursement;
  const beforeRelease = prior === "DEBITE" || prior === "DISPONIBLE";
  const afterRelease = prior === "PAYE";
  const honorairesRefund = item.montant_cts - item.refund_application_fee_cts;
  const expectedFee = honorairesRefund === escrow.honoraires_cents
    ? escrow.commission_cents
    : Math.round(
      escrow.commission_cents * honorairesRefund / escrow.honoraires_cents,
    );
  if (
    escrow.statut !== "REMBOURSE_EN_COURS"
    || escrow.stripe_payment_intent_id !== item.stripe_payment_intent_id
    || (!beforeRelease && !afterRelease)
    || item.reverse_transfer !== beforeRelease
    || item.absorbe_plateforme !== afterRelease
    || honorairesRefund <= 0
    || honorairesRefund > escrow.honoraires_cents
    || item.refund_application_fee_cts < 0
    || item.refund_application_fee_cts !== expectedFee
    || item.montant_cts > escrow.montant_total_cents
    || (beforeRelease && honorairesRefund !== escrow.honoraires_cents)
  ) {
    fail(
      "ESCROW_REFUND_FLAGS_MISMATCH",
      "Montants, état antérieur ou options de reversal escrow incohérents",
    );
  }

  const destinationId = objectId(paymentIntent.transfer_data?.destination);
  if (
    paymentIntent.metadata?.type !== "ESCROW_MISSION_PAYMENT"
    || paymentIntent.metadata?.paiement_escrow_id !== escrow.id
    || paymentIntent.metadata?.mission_id !== escrow.mission_id
    || paymentIntent.metadata?.soignant_id !== escrow.soignant_id
    || paymentIntent.metadata?.etablissement_id !== escrow.etablissement_id
    || Number(paymentIntent.metadata?.honoraires_cents) !== escrow.honoraires_cents
    || Number(paymentIntent.metadata?.commission_cents) !== escrow.commission_cents
    || paymentIntent.application_fee_amount !== escrow.commission_cents
    || destinationId !== onboarding.stripe_account_id
  ) {
    fail(
      "ESCROW_PAYMENT_PROVENANCE_MISMATCH",
      "Le PaymentIntent n'est pas la destination charge de cet escrow",
    );
  }

  const charge = await validateCommonStripeSource(
    stripe,
    item,
    paymentIntent,
    {
      etablissementId: escrow.etablissement_id,
      customerId: etablissement.stripe_customer_id,
      amountCents: escrow.montant_total_cents,
      metadataMissionId: escrow.mission_id,
    },
    existingRefund,
  );

  const params: Stripe.RefundCreateParams = {
    payment_intent: paymentIntent.id,
    amount: item.montant_cts,
    reason: "requested_by_customer",
    metadata: {
      queue_id: item.id,
      source: "jolene_refunds_cron",
      origin_type: "ESCROW",
      paiement_escrow_id: escrow.id,
      mission_id: escrow.mission_id,
      etablissement_id: escrow.etablissement_id,
      reverse_transfer: String(item.reverse_transfer),
      absorbe_plateforme: String(item.absorbe_plateforme),
      refund_application_fee_cts: String(item.refund_application_fee_cts),
    },
  };
  if (item.reverse_transfer) params.reverse_transfer = true;
  if (item.reverse_transfer && item.refund_application_fee_cts > 0) {
    params.refund_application_fee = true;
  }
  return { paymentIntent, charge, params };
}

async function validateAvoirSource(
  sb: any,
  stripe: Stripe,
  item: QueueRow,
  paymentIntent: Stripe.PaymentIntent,
  existingRefund: Stripe.Refund | null,
): Promise<RefundContext> {
  const { data: avoir, error: avoirError } = await sb
    .from("factures_honoraires")
    .select(
      "id, type_document, statut, mode_remboursement, facture_precedente_id, montant_ttc, etablissement_id, mission_id, soignant_id",
    )
    .eq("id", item.avoir_id)
    .maybeSingle();
  const { data: origine, error: origineError } = await sb
    .from("factures_honoraires")
    .select(
      "id, type_document, statut, montant_ttc, etablissement_id, mission_id, soignant_id, stripe_payment_intent_id",
    )
    .eq("id", item.facture_origine_id)
    .maybeSingle();
  if (avoirError || !avoir || origineError || !origine) {
    fail(
      "AVOIR_SOURCE_ABSENTE",
      avoirError?.message || origineError?.message || "avoir/facture introuvable",
    );
  }

  const avoirCents = Math.round(Number(avoir.montant_ttc) * 100);
  if (
    avoir.type_document !== "AVOIR"
    || !["EMISE", "EN_RETARD"].includes(avoir.statut)
    || avoir.mode_remboursement !== "AUTO_STRIPE"
    || avoir.facture_precedente_id !== origine.id
    || origine.type_document !== "FACTURE"
    || origine.statut !== "PAYEE"
    || origine.stripe_payment_intent_id !== item.stripe_payment_intent_id
    || Math.round(Number(origine.montant_ttc) * 100) !== paymentIntent.amount
    || avoir.etablissement_id !== origine.etablissement_id
    || avoir.mission_id !== origine.mission_id
    || avoir.soignant_id !== origine.soignant_id
    || item.montant_cts !== avoirCents
  ) {
    fail(
      "AVOIR_REFUND_PROVENANCE_MISMATCH",
      "L'avoir et sa facture d'origine ne correspondent pas exactement à la queue",
    );
  }

  const { data: etablissement, error: etablissementError } = await sb
    .from("etablissements")
    .select("id, stripe_customer_id")
    .eq("id", origine.etablissement_id)
    .maybeSingle();
  if (etablissementError || !etablissement?.stripe_customer_id) {
    fail(
      "AVOIR_CUSTOMER_ABSENT",
      etablissementError?.message || "Customer établissement absent",
    );
  }

  const { data: transfers, error: transfersError } = origine.mission_id
    ? await sb
      .from("stripe_transfers")
      .select("id, statut, stripe_payment_intent_id")
      .eq("mission_id", origine.mission_id)
      .limit(20)
    : { data: [], error: null };
  if (transfersError) {
    fail("CONNECT_LOOKUP_FAILED", transfersError.message);
  }
  const activeConnect = (transfers || []).some(
    (transfer: { statut: string }) =>
      !["ECHOUE", "ANNULEE", "REMBOURSE"].includes(transfer.statut),
  );
  const metadataType = paymentIntent.metadata?.type || "";
  const metadataBound = paymentIntent.metadata?.mission_id === origine.mission_id
    || paymentIntent.metadata?.facture_id === origine.id;
  if (
    activeConnect
    || metadataType === "CONNECT_MISSION_PAYMENT"
    || metadataType === "ESCROW_MISSION_PAYMENT"
    || !metadataBound
  ) {
    fail(
      activeConnect || metadataType === "CONNECT_MISSION_PAYMENT"
        ? "CONNECT_TRANSFER_REVERSAL_REQUIRED"
        : "STANDARD_PAYMENT_PROVENANCE_MISMATCH",
      "Refund automatique interdit sans provenance standard exacte",
    );
  }

  const charge = await validateCommonStripeSource(
    stripe,
    item,
    paymentIntent,
    {
      etablissementId: origine.etablissement_id,
      customerId: etablissement.stripe_customer_id,
      amountCents: paymentIntent.amount,
      metadataMissionId: paymentIntent.metadata?.mission_id ? origine.mission_id : null,
    },
    existingRefund,
  );
  if (item.montant_cts > paymentIntent.amount) {
    fail("AVOIR_AMOUNT_EXCEEDS_SOURCE", "L'avoir dépasse le paiement Stripe source");
  }

  return {
    paymentIntent,
    charge,
    params: {
      payment_intent: paymentIntent.id,
      amount: item.montant_cts,
      reason: "requested_by_customer",
      metadata: {
        queue_id: item.id,
        source: "jolene_refunds_cron",
        origin_type: "AVOIR",
        avoir_id: avoir.id,
        facture_origine_id: origine.id,
        mission_id: origine.mission_id || "",
        etablissement_id: origine.etablissement_id,
        reverse_transfer: "false",
        absorbe_plateforme: "false",
        refund_application_fee_cts: "0",
      },
    },
  };
}

async function validateSource(
  sb: any,
  stripe: Stripe,
  item: QueueRow,
  paymentIntent: Stripe.PaymentIntent,
  existingRefund: Stripe.Refund | null,
): Promise<RefundContext> {
  const isEscrow = Boolean(item.paiement_escrow_id);
  const isAvoir = Boolean(item.avoir_id && item.facture_origine_id);
  if (isEscrow === isAvoir) {
    fail(
      "QUEUE_ORIGIN_AMBIGUOUS",
      "Une queue doit provenir exactement d'un escrow ou d'un avoir",
    );
  }
  return isEscrow
    ? validateEscrowSource(sb, stripe, item, paymentIntent, existingRefund)
    : validateAvoirSource(sb, stripe, item, paymentIntent, existingRefund);
}

function assertRefundIdentity(
  item: QueueRow,
  context: RefundContext,
  refund: Stripe.Refund,
): void {
  const metadata = refund.metadata || {};
  const expectedOrigin = item.paiement_escrow_id ? "ESCROW" : "AVOIR";
  if (
    objectId(refund.payment_intent) !== context.paymentIntent.id
    || objectId(refund.charge) !== context.charge.id
    || refund.amount !== item.montant_cts
    || refund.currency !== "eur"
    || metadata.queue_id !== item.id
    || metadata.source !== "jolene_refunds_cron"
    || metadata.origin_type !== expectedOrigin
    || metadata.reverse_transfer !== String(item.reverse_transfer)
    || metadata.absorbe_plateforme !== String(item.absorbe_plateforme)
    || metadata.refund_application_fee_cts
      !== String(item.refund_application_fee_cts)
  ) {
    throw new Error(`REFUND_RESULT_IDENTITY_MISMATCH:${refund.id}`);
  }
  if (
    refund.status === "succeeded"
    && item.reverse_transfer
    && !refund.transfer_reversal
  ) {
    throw new Error(`REFUND_TRANSFER_REVERSAL_MISSING:${refund.id}`);
  }
}

async function findExistingRefund(
  stripe: Stripe,
  item: QueueRow,
  paymentIntent: Stripe.PaymentIntent,
): Promise<{ refund: Stripe.Refund | null; absenceProven: boolean }> {
  if (item.stripe_refund_id) {
    const refund = await stripe.refunds.retrieve(item.stripe_refund_id);
    return { refund, absenceProven: false };
  }

  const refunds: Stripe.Refund[] = [];
  let startingAfter: string | undefined;
  do {
    const page = await stripe.refunds.list({
      payment_intent: paymentIntent.id,
      limit: 100,
      ...(startingAfter ? { starting_after: startingAfter } : {}),
    });
    refunds.push(...page.data);
    startingAfter = page.has_more ? page.data.at(-1)?.id : undefined;
    if (page.has_more && !startingAfter) {
      throw new Error("REFUND_HISTORY_PAGINATION_FAILED");
    }
  } while (startingAfter);
  const matches = refunds.filter(
    (refund) => refund.metadata?.queue_id === item.id,
  );
  if (matches.length > 1) {
    throw new Error("DUPLICATE_QUEUE_REFUNDS_MANUAL_REVIEW");
  }
  return { refund: matches[0] ?? null, absenceProven: matches.length === 0 };
}

async function bindRefundId(sb: any, item: QueueRow, refundId: string): Promise<void> {
  let query = sb
    .from("stripe_refunds_queue")
    .update({
      stripe_refund_id: refundId,
      erreur: null,
      dernier_essai_le: new Date().toISOString(),
    })
    .eq("id", item.id)
    .eq("statut", "EN_COURS");
  query = item.stripe_refund_id
    ? query.eq("stripe_refund_id", item.stripe_refund_id)
    : query.is("stripe_refund_id", null);
  const { data, error } = await query.select("id").maybeSingle();
  if (!error && data) return;

  // Le webhook peut avoir gagné la course et déjà finalisé exactement ce
  // refund. C'est la seule absence de ligne modifiable acceptée.
  const { data: current, error: currentError } = await sb
    .from("stripe_refunds_queue")
    .select("statut, stripe_refund_id")
    .eq("id", item.id)
    .maybeSingle();
  if (
    currentError
    || !current
    || current.stripe_refund_id !== refundId
    || !["EN_COURS", "TRAITE", "ECHEC"].includes(current.statut)
  ) {
    throw new Error(
      `REFUND_ID_PERSISTENCE_FAILED:${error?.message || currentError?.message || "state conflict"}`,
    );
  }
}

async function reconcile(
  sb: any,
  item: QueueRow,
  refundId: string | null,
  result: "SUCCEEDED" | "FAILED" | "CANCELED",
  detail: string | null,
): Promise<void> {
  const { data, error } = await sb.rpc("fn_stripe_refund_rapprocher", {
    p_queue_id: item.id,
    p_stripe_refund_id: refundId,
    p_resultat: result,
    p_detail: detail,
    p_finalise_le: new Date().toISOString(),
  });
  if (error || !data?.success) {
    throw new Error(
      `REFUND_RECONCILIATION_FAILED:${error?.message || JSON.stringify(data)}`,
    );
  }
}

async function keepAmbiguousForPolling(
  sb: any,
  item: QueueRow,
  detail: string,
  refundId?: string | null,
): Promise<void> {
  const update: Record<string, unknown> = {
    statut: "EN_COURS",
    erreur: detail.slice(0, 500),
    dernier_essai_le: new Date().toISOString(),
  };
  if (refundId) update.stripe_refund_id = refundId;
  const { data, error } = await sb
    .from("stripe_refunds_queue")
    .update(update)
    .eq("id", item.id)
    .eq("statut", "EN_COURS")
    .select("id")
    .maybeSingle();
  if (error || !data) {
    throw new Error(`REFUND_POLL_STATE_FAILED:${error?.message || "state conflict"}`);
  }
}

async function alertAdmins(
  sb: any,
  item: QueueRow,
  code: string,
  message: string,
): Promise<void> {
  try {
    const { data: admins, error: adminsError } = await sb.rpc("fn_list_admin_user_ids");
    if (adminsError) throw adminsError;
    for (const adminId of (admins || []) as string[]) {
      await sb.functions.invoke("send-email", {
        body: {
          type: "REFUND_ECHEC_ADMIN",
          destinataire_id: adminId,
          data: {
            queue_id: item.id,
            avoir_id: item.avoir_id,
            paiement_escrow_id: item.paiement_escrow_id,
            montant_formatte: (item.montant_cts / 100).toFixed(2),
            payment_intent_id: item.stripe_payment_intent_id,
            refund_id: item.stripe_refund_id,
            erreur_code: code,
            erreur_stripe: message.slice(0, 300),
          },
        },
      });
    }
  } catch (error) {
    console.error("REFUND_ECHEC_ADMIN notification failed:", error);
  }
}

Deno.serve(async (req) => {
  const startedAt = Date.now();
  const sb = createClient(URL, KEY);

  try {
    const auth = await verifyCronServiceAuth(req, sb);
    if (!auth.ok) return cronAuthErrorResponse(auth);
    if (isCronAuthProbe(req)) return cronAuthProbeResponse(auth);

    assertStripeSecretMode(STRIPE_KEY);
    const stripe = new Stripe(STRIPE_KEY, { apiVersion: "2026-02-25.clover" });
    const leaseBefore = new Date(Date.now() - LEASE_MS).toISOString();
    const { data: excluded, error: excludedError } = await sb.rpc(
      "fn_compter_files_finance_exclues_test",
    );
    if (excludedError) {
      throw new Error(`TEST_ACCOUNT_FILTER_UNAVAILABLE:${excludedError.message}`);
    }
    console.info("[process-stripe-refunds] files test exclues", {
      count: Number((excluded as Record<string, unknown>)?.stripe_refunds || 0),
    });

    const { data: rows, error: selectError } = await sb.rpc(
      "fn_stripe_refunds_reels_a_traiter",
      {
        p_lease_before: leaseBefore,
        p_limit: MAX_BATCH,
      },
    );
    if (selectError) throw new Error(`REFUND_QUEUE_READ_FAILED:${selectError.message}`);

    const queue = (rows || []) as QueueRow[];
    let succeeded = 0;
    let pending = 0;
    let failed = 0;
    let skipped = 0;

    for (const item of queue) {
      const { data: lock, error: lockError } = await sb
        .from("stripe_refunds_queue")
        .update({ statut: "EN_COURS", dernier_essai_le: new Date().toISOString() })
        .eq("id", item.id)
        .in("statut", ["EN_ATTENTE", "EN_COURS"])
        .eq("tentatives", item.tentatives)
        .or(`dernier_essai_le.is.null,dernier_essai_le.lt.${leaseBefore}`)
        .select("id")
        .maybeSingle();
      if (lockError || !lock) {
        skipped++;
        continue;
      }

      let exactRefund: Stripe.Refund | null = null;
      let refundAbsenceProven = false;
      let createAttempted = false;
      try {
        const paymentIntent = await stripe.paymentIntents.retrieve(
          item.stripe_payment_intent_id,
          { expand: ["latest_charge"] },
        );
        const existing = await findExistingRefund(stripe, item, paymentIntent);
        exactRefund = existing.refund;
        refundAbsenceProven = existing.absenceProven;
        if (exactRefund) await bindRefundId(sb, item, exactRefund.id);

        const context = await validateSource(
          sb,
          stripe,
          item,
          paymentIntent,
          exactRefund,
        );

        if (!exactRefund) {
          createAttempted = true;
          exactRefund = await stripe.refunds.create(context.params, {
            idempotencyKey: `refund_queue_${item.id}`,
          });
          await bindRefundId(sb, item, exactRefund.id);
        }
        assertRefundIdentity(item, context, exactRefund);

        if (exactRefund.status === "succeeded") {
          await reconcile(sb, item, exactRefund.id, "SUCCEEDED", null);
          succeeded++;
        } else if (exactRefund.status === "failed" || exactRefund.status === "canceled") {
          const result = exactRefund.status === "canceled" ? "CANCELED" : "FAILED";
          const detail = exactRefund.failure_reason || `Stripe refund ${exactRefund.status}`;
          await reconcile(sb, item, exactRefund.id, result, detail);
          await alertAdmins(sb, { ...item, stripe_refund_id: exactRefund.id }, result, detail);
          failed++;
        } else {
          // pending / requires_action / statut futur inconnu : le lease relira
          // cet objet exact. Aucun compteur de retry ne doit transformer une
          // issue Stripe ambiguë en échec métier.
          await keepAmbiguousForPolling(
            sb,
            item,
            `STRIPE_REFUND_PENDING:${exactRefund.id}:${exactRefund.status || "unknown"}`,
            exactRefund.id,
          );
          pending++;
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const code = error instanceof ProvenPreflightError
          ? error.code
          : error instanceof AmbiguousFinancialStateError
          ? error.code
          : (error as { code?: string })?.code || "REFUND_AMBIGUOUS_ERROR";

        // Seul un préflight prouvé, après une liste Stripe exhaustive montrant
        // qu'aucun refund queue_id n'existe et avant refunds.create, autorise la
        // restauration escrow + ECHEC. Après l'appel Stripe, timeout/réseau est
        // toujours ambigu : polling indéfini, jamais de faux FAILED.
        if (
          error instanceof ProvenPreflightError
          && refundAbsenceProven
          && !createAttempted
          && !exactRefund
        ) {
          await reconcile(sb, item, null, "FAILED", `${code}:${message}`);
          await alertAdmins(sb, item, code, message);
          failed++;
        } else {
          await keepAmbiguousForPolling(
            sb,
            item,
            `${code}:${message}`,
            exactRefund?.id || item.stripe_refund_id,
          );
          // Alerte immédiate : cet état est sûr (gelé) mais exige une attention
          // si Stripe ou la DB ne redeviennent pas joignables.
          await alertAdmins(
            sb,
            { ...item, stripe_refund_id: exactRefund?.id || item.stripe_refund_id },
            code,
            message,
          );
          pending++;
        }
      }
    }

    const success = failed === 0;
    return new Response(JSON.stringify({
      success,
      processed: queue.length,
      succeeded,
      pending,
      failed,
      skipped,
      duration_ms: Date.now() - startedAt,
    }), {
      status: success ? 200 : 500,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("process-stripe-refunds fatal:", message);
    return new Response(JSON.stringify({
      error: "Une erreur interne est survenue.",
      details: message,
    }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
