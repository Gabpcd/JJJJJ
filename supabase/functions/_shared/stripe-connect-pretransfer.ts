// Remboursement d'un Checkout payé APRÈS ouverture d'un litige et AVANT
// transfert. Cette origine n'est ni un avoir, ni un remboursement d'escrow.
// Les RPC de ce contrat doivent être déployées avant ses trois consommateurs.
// Aucune opération historique n'est admise à partir de la seule absence Stripe.

type RecordValue = Record<string, unknown>;
type RpcClient = {
  rpc(name: string, args: RecordValue): PromiseLike<{ data: unknown; error: unknown }>;
};
type Reader = { retrieve(id: string): PromiseLike<unknown> };
type Pager = { list(params: RecordValue): PromiseLike<unknown> };
export type ConnectRefundStripe = {
  checkout: { sessions: Reader };
  paymentIntents: Reader;
  charges: Reader;
  customers: Reader;
  transfers: Pager;
  refunds: Reader & Pager & {
    create(params: RecordValue, options: { idempotencyKey: string }): PromiseLike<unknown>;
  };
};

export type ConnectRefundStatus =
  | "READY" | "PENDING" | "REQUIRES_ACTION" | "SUCCEEDED" | "FAILED" | "CANCELED" | "REVIEW";

export type ConnectOperation = {
  id: string;
  trace_id: string;
  session_id: string;
  payment_intent_id: string;
  charge_id: string;
  mission_id: string;
  etablissement_id: string;
  soignant_id: string;
  facture_honoraire_id: string;
  facture_commission_id: string;
  customer_id: string;
  destination_id: string;
  soignant_cents: number;
  commission_cents: number;
  total_cents: number;
  livemode: boolean;
  orientation: "TRANSFER" | "REFUND";
  litige_id: string | null;
  refund_id: string | null;
  refund_status: ConnectRefundStatus;
};

export class ConnectPretransferError extends Error {
  constructor(readonly code: string) { super(code); this.name = "ConnectPretransferError"; }
}
function fail(code: string): never { throw new ConnectPretransferError(code); }
function record(value: unknown): RecordValue {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail("CONNECT_OPERATION_SHAPE");
  return value as RecordValue;
}
function objectId(value: unknown): string | null {
  return typeof value === "string" ? value
    : value && typeof value === "object" && "id" in value && typeof value.id === "string" ? value.id : null;
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const idKeys = ["id", "trace_id", "mission_id", "etablissement_id", "soignant_id", "facture_honoraire_id", "facture_commission_id"] as const;
const stripeKeys = { session_id: "cs_", payment_intent_id: "pi_", charge_id: "ch_", customer_id: "cus_", destination_id: "acct_" } as const;
const statuses: ConnectRefundStatus[] = ["READY", "PENDING", "REQUIRES_ACTION", "SUCCEEDED", "FAILED", "CANCELED", "REVIEW"];

export function parseConnectOperation(value: unknown): ConnectOperation {
  const r = record(value);
  for (const key of idKeys) if (typeof r[key] !== "string" || !uuid.test(r[key] as string)) fail("CONNECT_OPERATION_IDENTITY");
  for (const [key, prefix] of Object.entries(stripeKeys)) {
    if (typeof r[key] !== "string" || !new RegExp(`^${prefix}[A-Za-z0-9_]{1,200}$`).test(r[key] as string)) fail("CONNECT_OPERATION_IDENTITY");
  }
  if (r.orientation !== "TRANSFER" && r.orientation !== "REFUND") fail("CONNECT_OPERATION_ORIENTATION");
  if (typeof r.livemode !== "boolean" || !statuses.includes(r.refund_status as ConnectRefundStatus)) fail("CONNECT_OPERATION_SHAPE");
  if (r.orientation === "REFUND" ? typeof r.litige_id !== "string" || !uuid.test(r.litige_id) : r.litige_id !== null) fail("CONNECT_OPERATION_DISPUTE");
  if (r.refund_id !== null && (typeof r.refund_id !== "string" || !/^re_[A-Za-z0-9_]{1,200}$/.test(r.refund_id))) fail("CONNECT_OPERATION_REFUND");
  for (const key of ["soignant_cents", "commission_cents", "total_cents"]) {
    if (!Number.isSafeInteger(r[key]) || (r[key] as number) <= 0) fail("CONNECT_OPERATION_AMOUNT");
  }
  if ((r.soignant_cents as number) + (r.commission_cents as number) !== r.total_cents) fail("CONNECT_OPERATION_AMOUNT");
  if (r.orientation === "TRANSFER" && (r.refund_id !== null || r.refund_status !== "READY")) fail("CONNECT_OPERATION_ORIENTATION");
  return Object.fromEntries([...idKeys, ...Object.keys(stripeKeys), "soignant_cents", "commission_cents", "total_cents", "livemode", "orientation", "litige_id", "refund_id", "refund_status"].map(k => [k, r[k]])) as ConnectOperation;
}

async function rpc(sb: RpcClient, name: string, args: RecordValue): Promise<unknown> {
  const { data, error } = await sb.rpc(name, args);
  if (error) fail("CONNECT_OPERATION_SQL_FAILED");
  return data;
}

export async function readConnectOperation(sb: RpcClient, sessionId: string): Promise<ConnectOperation | null> {
  const value = await rpc(sb, "fn_connect_avant_transfert_lire", { p_session_id: sessionId });
  if (value === null) return null;
  const op = parseConnectOperation(value);
  if (op.session_id !== sessionId) fail("CONNECT_OPERATION_SESSION");
  return op;
}

function sessionMetadata(op: ConnectOperation): Record<string, string> {
  return { type: "CONNECT_MISSION_PAYMENT", payment_scope: "INVOICE", connect_operation_id: op.id, mission_id: op.mission_id,
    etablissement_id: op.etablissement_id, soignant_id: op.soignant_id, connected_account_id: op.destination_id,
    facture_honoraires_id: op.facture_honoraire_id, facture_commission_id: op.facture_commission_id,
    soignant_cents: String(op.soignant_cents), commission_cents: String(op.commission_cents) };
}

// Réservation avant checkout.sessions.create, puis liaison avant de rendre le
// client_secret. Un ancien Checkout sans réservation ne peut pas être adopté.
export async function reserveConnectCheckout(sb: RpcClient, args: {
  factureHonoraireId: string; factureCommissionId: string; attemptKey: string;
}): Promise<string> {
  const value = record(await rpc(sb, "fn_connect_checkout_preparer", {
    p_facture_honoraire_id: args.factureHonoraireId,
    p_facture_commission_id: args.factureCommissionId, p_cle_tentative: args.attemptKey,
  }));
  if (typeof value.operation_id !== "string" || !uuid.test(value.operation_id)
    || value.facture_honoraire_id !== args.factureHonoraireId
    || value.facture_commission_id !== args.factureCommissionId) fail("CONNECT_ADMISSION_INVALID");
  return value.operation_id;
}
export async function bindConnectCheckout(sb: RpcClient, operationId: string, sessionId: string): Promise<void> {
  const value = record(await rpc(sb, "fn_connect_checkout_lier", { p_operation_id: operationId, p_session_id: sessionId }));
  if (value.bound !== true || value.operation_id !== operationId || value.session_id !== sessionId) fail("CONNECT_ADMISSION_INVALID");
}
export async function requireConnectCheckoutAdmission(sb: RpcClient, session: { id: string; metadata: Record<string, string> | null }): Promise<void> {
  const operationId = session.metadata?.connect_operation_id;
  if (!operationId || !uuid.test(operationId)) fail("CONNECT_HISTORICAL_CHECKOUT_REVIEW_REQUIRED");
  const value = record(await rpc(sb, "fn_connect_checkout_verifier", { p_operation_id: operationId, p_session_id: session.id }));
  if (value.admitted !== true || value.operation_id !== operationId || value.session_id !== session.id) fail("CONNECT_ADMISSION_INVALID");
}

export async function arbitrateConnectOperation(sb: RpcClient, stripe: ConnectRefundStripe,
  traceId: string, sessionId: string): Promise<ConnectOperation> {
  const session = record(await stripe.checkout.sessions.retrieve(sessionId));
  const meta = record(session.metadata);
  if (session.id !== sessionId || session.status !== "complete" || session.payment_status !== "paid"
    || typeof meta.connect_operation_id !== "string" || !uuid.test(meta.connect_operation_id)
    || meta.payment_scope !== "INVOICE") fail("CONNECT_HISTORICAL_CHECKOUT_REVIEW_REQUIRED");
  const piId = objectId(session.payment_intent);
  if (!piId) fail("CONNECT_REFUND_SOURCE_MISMATCH");
  const pi = record(await stripe.paymentIntents.retrieve(piId));
  const chargeId = objectId(pi.latest_charge);
  if (!chargeId) fail("CONNECT_REFUND_SOURCE_MISMATCH");
  const source = { session_id: sessionId, payment_intent_id: piId, charge_id: chargeId,
    mission_id: meta.mission_id, etablissement_id: meta.etablissement_id, soignant_id: meta.soignant_id,
    facture_honoraire_id: meta.facture_honoraires_id, facture_commission_id: meta.facture_commission_id,
    customer_id: objectId(session.customer), destination_id: meta.connected_account_id,
    soignant_cents: Number(meta.soignant_cents), commission_cents: Number(meta.commission_cents),
    total_cents: session.amount_total, livemode: session.livemode };
  // Vérifier la source Stripe avant de proposer ces champs au contrôle SQL.
  const candidate = parseConnectOperation({ ...source, id: meta.connect_operation_id, trace_id: traceId,
    orientation: "TRANSFER", litige_id: null, refund_id: null, refund_status: "READY" });
  await currentSource(stripe, candidate);
  const op = parseConnectOperation(await rpc(sb, "fn_connect_avant_transfert_arbitrer", {
    p_operation_id: candidate.id, p_trace_id: traceId, p_source: source,
  }));
  for (const key of [...idKeys, ...Object.keys(stripeKeys), "soignant_cents", "commission_cents", "total_cents", "livemode"] as const) {
    if ((op as unknown as RecordValue)[key] !== (candidate as unknown as RecordValue)[key]) fail("CONNECT_OPERATION_CHANGED");
  }
  return op;
}
export function connectRefundMetadata(op: ConnectOperation): Record<string, string> {
  if (op.orientation !== "REFUND" || !op.litige_id) fail("CONNECT_OPERATION_ORIENTATION");
  return { source: "jolene_connect_pretransfer", operation_id: op.id, trace_id: op.trace_id,
    session_id: op.session_id, payment_intent_id: op.payment_intent_id, charge_id: op.charge_id,
    mission_id: op.mission_id, etablissement_id: op.etablissement_id, soignant_id: op.soignant_id,
    facture_honoraires_id: op.facture_honoraire_id, facture_commission_id: op.facture_commission_id,
    litige_id: op.litige_id, motif: "LITIGE_OUVERT_AVANT_TRANSFERT" };
}
function exactMetadata(value: unknown, expected: Record<string, string>): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  return Object.entries(expected).every(([k, v]) => (value as RecordValue)[k] === v);
}

async function currentSource(stripe: ConnectRefundStripe, op: ConnectOperation, archivedRead = false) {
  // Lire la Session chez Stripe : le PI propagé dans une facture n'est jamais
  // une preuve de son identité documentaire.
  const session = record(await stripe.checkout.sessions.retrieve(op.session_id));
  const pi = record(await stripe.paymentIntents.retrieve(op.payment_intent_id));
  const charge = record(await stripe.charges.retrieve(op.charge_id));
  const customer = record(await stripe.customers.retrieve(op.customer_id));
  const metadata = sessionMetadata(op);
  if (session.id !== op.session_id || session.status !== "complete" || session.payment_status !== "paid"
    || !Array.isArray(session.payment_method_types) || session.payment_method_types.length !== 1 || session.payment_method_types[0] !== "card"
    || session.livemode !== op.livemode || session.amount_total !== op.total_cents || session.currency !== "eur"
    || session.client_reference_id !== op.mission_id || objectId(session.customer) !== op.customer_id
    || objectId(session.payment_intent) !== op.payment_intent_id || !exactMetadata(session.metadata, metadata)
    || pi.id !== op.payment_intent_id || pi.status !== "succeeded" || pi.livemode !== op.livemode
    || pi.amount !== op.total_cents || pi.amount_received !== op.total_cents || pi.amount_capturable !== 0
    || pi.transfer_data != null || pi.application_fee_amount != null || pi.on_behalf_of != null
    || !Array.isArray(pi.payment_method_types) || pi.payment_method_types.length !== 1 || pi.payment_method_types[0] !== "card"
    || pi.currency !== "eur" || objectId(pi.customer) !== op.customer_id || objectId(pi.latest_charge) !== op.charge_id
    || !exactMetadata(pi.metadata, metadata) || customer.id !== op.customer_id
    || (customer.deleted === true ? !archivedRead : !exactMetadata(customer.metadata, { etablissement_id: op.etablissement_id }))
    || charge.id !== op.charge_id || charge.livemode !== op.livemode || charge.paid !== true || charge.captured !== true
    || charge.status !== "succeeded" || charge.currency !== "eur" || charge.amount !== op.total_cents
    || charge.transfer_data != null || charge.transfer != null || charge.application_fee != null
    || charge.application_fee_amount != null || charge.on_behalf_of != null || charge.destination != null
    || !charge.payment_method_details || record(charge.payment_method_details).type !== "card"
    || objectId(charge.customer) !== op.customer_id || objectId(charge.payment_intent) !== op.payment_intent_id
    || !Number.isSafeInteger(charge.created) || (charge.created as number) <= 0
    || !Number.isSafeInteger(charge.amount_refunded) || (charge.amount_refunded as number) < 0
    || (charge.amount_refunded as number) > op.total_cents || typeof charge.refunded !== "boolean"
    || charge.disputed !== false) fail("CONNECT_REFUND_SOURCE_MISMATCH");
  return { session, pi, charge };
}

async function listAll(pager: Pager, params: RecordValue, maxPages: number): Promise<RecordValue[]> {
  const rows: RecordValue[] = [], seen = new Set<string>();
  let cursor: string | undefined;
  for (let pageNumber = 0; pageNumber < maxPages; pageNumber++) {
    const page = record(await pager.list({ ...params, limit: 100, ...(cursor ? { starting_after: cursor } : {}) }));
    if (!Array.isArray(page.data) || page.data.length > 100 || typeof page.has_more !== "boolean") fail("CONNECT_REFUND_PAGINATION");
    for (const value of page.data) {
      const row = record(value), id = objectId(row);
      if (!id || seen.has(id)) fail("CONNECT_REFUND_PAGINATION");
      seen.add(id); rows.push(row);
    }
    if (!page.has_more) return rows;
    cursor = objectId(page.data.at(-1)) || undefined;
    if (!cursor) fail("CONNECT_REFUND_PAGINATION");
  }
  fail("CONNECT_REFUND_PAGINATION_LIMIT");
}

export function assertConnectRefund(op: ConnectOperation, value: unknown): RecordValue {
  const r = record(value);
  if (typeof r.id !== "string" || !/^re_[A-Za-z0-9_]{1,200}$/.test(r.id)
    || (op.refund_id !== null && r.id !== op.refund_id) || r.amount !== op.total_cents || r.currency !== "eur"
    || objectId(r.payment_intent) !== op.payment_intent_id || objectId(r.charge) !== op.charge_id
    || !exactMetadata(r.metadata, connectRefundMetadata(op)) || r.reason !== "requested_by_customer"
    || r.transfer_reversal != null || r.source_transfer_reversal != null
    || !["pending", "requires_action", "succeeded", "failed", "canceled"].includes(r.status as string)) fail("CONNECT_REFUND_IDENTITY_MISMATCH");
  return r;
}

export type ConnectRefundResult = { operationId: string; status: ConnectRefundStatus; refunded: boolean };

export async function processConnectRefundBatch(sb: RpcClient, stripe: ConnectRefundStripe,
  ownerToken: () => string): Promise<{ processed: number; succeeded: number; pending: number; failed: number; errors: string[] }> {
  // Budget additionnel explicite : deux intentions. La sélection historique
  // avoir/escrow (dix lignes) conserve son ordre et son budget.
  const values = await rpc(sb, "fn_connect_remboursements_a_traiter", { p_limit: 2 });
  if (!Array.isArray(values) || values.length > 2) fail("CONNECT_REFUND_BATCH_INVALID");
  const operations = values.map(parseConnectOperation);
  if (new Set(operations.map(op => op.id)).size !== operations.length
    || operations.some(op => op.orientation !== "REFUND")) fail("CONNECT_REFUND_BATCH_INVALID");
  const report = { processed: 0, succeeded: 0, pending: 0, failed: 0, errors: [] as string[] };
  for (const op of operations) {
    report.processed++;
    try {
      const result = await processConnectPretransferRefund(sb, stripe, op, ownerToken());
      if (result.refunded) report.succeeded++;
      else if (["FAILED", "CANCELED", "REVIEW"].includes(result.status)) report.failed++;
      else report.pending++;
    } catch (error) {
      // Aucun message fournisseur/SQL, payload, secret, email ou nouvel effet.
      // Bail expirant + intention immuable permettent une nouvelle lecture.
      report.pending++;
      report.errors.push(error instanceof ConnectPretransferError ? error.code : "CONNECT_REFUND_TRANSPORT_UNCERTAIN");
    }
  }
  return report;
}

export async function processConnectPretransferRefund(
  sb: RpcClient, stripe: ConnectRefundStripe, expected: ConnectOperation, ownerToken: string,
  options: { allowCreate: boolean } = { allowCreate: true },
): Promise<ConnectRefundResult> {
  if (expected.orientation !== "REFUND" || !uuid.test(ownerToken)) fail("CONNECT_OPERATION_ORIENTATION");
  // Cette RPC relit l'exclusion canonique TEST et les liens métier, puis COMMIT
  // le bail. Aucun verrou de ligne n'est conservé pendant un appel Stripe.
  const lease = record(await rpc(sb, "fn_connect_remboursement_prendre", { p_operation_id: expected.id, p_owner_token: ownerToken }));
  if (lease.acquired !== true || lease.owner_token !== ownerToken) fail("CONNECT_REFUND_BUSY");
  if (typeof lease.can_create !== "boolean") fail("CONNECT_REFUND_LEASE_INVALID");
  const op = parseConnectOperation(lease.operation);
  for (const key of [...idKeys, ...Object.keys(stripeKeys), "soignant_cents", "commission_cents", "total_cents", "livemode", "orientation", "litige_id"] as const) {
    if ((op as unknown as RecordValue)[key] !== (expected as unknown as RecordValue)[key]) fail("CONNECT_OPERATION_CHANGED");
  }
  const { charge } = await currentSource(stripe, op, !lease.can_create);
  const refunds = await listAll(stripe.refunds, { charge: op.charge_id }, 10);
  if (refunds.length > 1) fail("CONNECT_REFUND_FOREIGN_MOVEMENT");
  let refund: RecordValue | null = refunds.length ? assertConnectRefund(op, refunds[0]) : null;
  if (op.refund_id) {
    const exact = assertConnectRefund(op, await stripe.refunds.retrieve(op.refund_id));
    if (!refund || refund.id !== exact.id) fail("CONNECT_REFUND_LIST_INCONSISTENT");
    refund = exact; // objet relu, jamais l'instantané d'un webhook.
  }
  // La Charge n'est pas l'autorité du statut d'un Refund différé. Pour l'objet
  // propre pending/requires_action, les agrégats peuvent déjà refléter son
  // montant : ils ne produisent jamais SUCCEEDED. Un agrégat partiel inexpliqué
  // reste refusé. Un vrai essai TEST devra documenter cette sémantique Stripe.
  const nonSucceeded = refund && refund.status !== "succeeded";
  const ownSucceeded = refund?.status === "succeeded" ? op.total_cents : 0;
  if (nonSucceeded ? ![0, op.total_cents].includes(charge.amount_refunded as number)
    : charge.amount_refunded !== ownSucceeded || charge.refunded !== (ownSucceeded === op.total_cents)) fail("CONNECT_REFUND_FOREIGN_MOVEMENT");
  if (!refund) {
    if (!options.allowCreate) fail("CONNECT_REFUND_WEBHOOK_OBJECT_MISSING");
    if (!lease.can_create) fail("CONNECT_REFUND_ACCOUNT_CLOSED");
    if (op.refund_id || op.refund_status !== "READY") fail("CONNECT_REFUND_MISSING_OBJECT");
    // La recherche globale d'absence de transfert protège exclusivement la
    // création d'un mouvement. Un Refund propre déjà identifié est constaté
    // depuis sa source immuable, même après des milliers de transferts tiers.
    const transfers = await listAll(stripe.transfers, { created: { gte: charge.created } }, 20);
    if (transfers.some(t => objectId(t.source_transaction) === op.charge_id)) fail("CONNECT_REFUND_TRANSFER_PRESENT");
    // Le serveur fixe first_attempt_at UNE fois, autorise seulement 20 h depuis
    // cet instant et vérifie encore le bail. Au-delà : aucun nouveau POST.
    const start = record(await rpc(sb, "fn_connect_remboursement_demarrer", { p_operation_id: op.id, p_owner_token: ownerToken }));
    if (start.operation_id !== op.id || start.owner_token !== ownerToken || start.create_allowed !== true) fail("CONNECT_REFUND_CREATE_WINDOW_CLOSED");
    refund = assertConnectRefund(op, await stripe.refunds.create({
      payment_intent: op.payment_intent_id, amount: op.total_cents, reason: "requested_by_customer",
      metadata: connectRefundMetadata(op),
    }, { idempotencyKey: `connect_pretransfer_refund_${op.id}` }));
  }
  const returnedAfterSuccess = op.refund_status === "SUCCEEDED" && ["failed", "canceled"].includes(refund.status as string);
  const failureBalanceId = objectId(refund.failure_balance_transaction);
  if (returnedAfterSuccess && (!failureBalanceId || !/^txn_[A-Za-z0-9_]{1,200}$/.test(failureBalanceId))) fail("CONNECT_REFUND_RETURN_NOT_PROVEN");
  // Transaction unique : objet exact + statut réel + trace + audit. Une erreur
  // ne doit être ni avalée, ni acquittée comme remboursement confirmé.
  const receipt = record(await rpc(sb, "fn_connect_remboursement_constater", {
    p_operation_id: op.id, p_owner_token: ownerToken,
    p_refund: { id: refund.id, payment_intent_id: op.payment_intent_id, charge_id: op.charge_id,
      amount: refund.amount, currency: refund.currency, status: refund.status,
      failure_balance_transaction_id: failureBalanceId },
  }));
  const actualStatus = String(refund.status).toUpperCase();
  // Une observation pending périmée ne régresse pas un succès déjà atomique.
  if (receipt.operation_id !== op.id || receipt.refund_id !== refund.id
    || !statuses.includes(receipt.status as ConnectRefundStatus)
    || (receipt.status !== actualStatus && receipt.status !== "REVIEW"
      && !(receipt.status === "SUCCEEDED" && actualStatus === "PENDING"))) fail("CONNECT_REFUND_RECEIPT_INVALID");
  if (receipt.status === "SUCCEEDED" && receipt.review_code != null) fail("CONNECT_REFUND_RECEIPT_INVALID");
  if (receipt.status === "REVIEW" && !["REFUND_RETURNED_AFTER_SUCCESS", "REFUND_REQUIRES_ACTION_AFTER_SUCCESS", "REFUND_STATUS_CONTRADICTORY", "CREATE_WINDOW_CLOSED"].includes(receipt.review_code as string)) fail("CONNECT_REFUND_RECEIPT_INVALID");
  return { operationId: op.id, status: receipt.status as ConnectRefundStatus, refunded: receipt.status === "SUCCEEDED" };
}
