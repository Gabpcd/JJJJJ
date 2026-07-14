export const SWAN_TRANSACTION_EVENT_TYPES = new Set([
  "Transaction.Pending",
  "Transaction.Booked",
  "Transaction.Rejected",
  "Transaction.Canceled",
]);

// Les scalaires GraphQL ID de Swan sont opaques et préfixés (par exemple
// `bosco_...` pour une transaction), pas nécessairement des UUID.
const OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/;

export interface SwanWebhookEnvelope {
  eventType: string;
  eventId: string;
  projectId: string;
  resourceId: string;
}

export interface SwanTransactionSnapshot {
  id: string;
  accountId: string;
  amountCents: number;
  currency: string;
  status: string;
  type: string;
}

/** Comparaison à temps constant pour le secret partagé envoyé par Swan. */
export function constantTimeSecretEquals(
  expected: string,
  actual: string,
): boolean {
  const encoder = new TextEncoder();
  const left = encoder.encode(expected);
  const right = encoder.encode(actual);
  const length = Math.max(left.length, right.length, 1);
  let difference = left.length ^ right.length;
  for (let index = 0; index < length; index += 1) {
    difference |= (left[index % Math.max(left.length, 1)] ?? 0) ^
      (right[index % Math.max(right.length, 1)] ?? 0);
  }
  return difference === 0;
}

function requiredOpaqueId(value: unknown, field: string): string {
  if (typeof value !== "string" || !OPAQUE_ID_PATTERN.test(value)) {
    throw new Error(`SWAN_${field.toUpperCase()}_INVALIDE`);
  }
  return value;
}

/** Le webhook officiel est volontairement parcimonieux : aucun détail métier n'est accepté. */
export function parseSwanWebhookEnvelope(value: unknown): SwanWebhookEnvelope {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("SWAN_PAYLOAD_INVALIDE");
  }
  const payload = value as Record<string, unknown>;
  if (
    typeof payload.eventType !== "string" ||
    !/^[A-Za-z][A-Za-z0-9.]{0,99}$/.test(payload.eventType)
  ) {
    throw new Error("SWAN_EVENT_TYPE_INVALIDE");
  }
  return {
    eventType: payload.eventType,
    eventId: requiredOpaqueId(payload.eventId, "event_id"),
    projectId: requiredOpaqueId(payload.projectId, "project_id"),
    resourceId: requiredOpaqueId(payload.resourceId, "resource_id"),
  };
}

function exactCents(value: unknown): number {
  if (typeof value !== "string" && typeof value !== "number") {
    throw new Error("SWAN_MONTANT_INVALIDE");
  }
  const normalized = String(value);
  if (!/^(?:0|[1-9][0-9]{0,10})(?:\.[0-9]{1,2})?$/.test(normalized)) {
    throw new Error("SWAN_MONTANT_INVALIDE");
  }
  const [euros, decimals = ""] = normalized.split(".");
  const cents = Number(euros) * 100 + Number(decimals.padEnd(2, "0"));
  if (!Number.isSafeInteger(cents) || cents <= 0) {
    throw new Error("SWAN_MONTANT_INVALIDE");
  }
  return cents;
}

/**
 * Réduit la réponse GraphQL canonique à un instantané sans IBAN, contrepartie,
 * libellé ni référence bancaire. Ces données minimales suffisent au diagnostic.
 */
export function sanitizeSwanTransaction(
  value: unknown,
  expectedResourceId: string,
): SwanTransactionSnapshot {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("SWAN_TRANSACTION_ABSENTE");
  }
  const transaction = value as Record<string, any>;
  const id = requiredOpaqueId(transaction.id, "transaction_id");
  if (id !== expectedResourceId) {
    throw new Error("SWAN_TRANSACTION_RESOURCE_MISMATCH");
  }
  const accountId = requiredOpaqueId(transaction.account?.id, "account_id");
  const currency = typeof transaction.amount?.currency === "string"
    ? transaction.amount.currency.toUpperCase()
    : "";
  const status = typeof transaction.statusInfo?.status === "string"
    ? transaction.statusInfo.status
    : "";
  const type = typeof transaction.type === "string" ? transaction.type : "";
  if (!/^[A-Za-z][A-Za-z0-9]{0,79}$/.test(status)) {
    throw new Error("SWAN_TRANSACTION_STATUT_INVALIDE");
  }
  if (!/^[A-Za-z][A-Za-z0-9]{0,119}$/.test(type)) {
    throw new Error("SWAN_TRANSACTION_TYPE_INVALIDE");
  }
  return {
    id,
    accountId,
    amountCents: exactCents(transaction.amount?.value),
    currency,
    status,
    type,
  };
}
