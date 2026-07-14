import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  constantTimeSecretEquals,
  parseSwanWebhookEnvelope,
  sanitizeSwanTransaction,
} from "./swan-webhook.ts";

const ids = {
  eventId: "webhook_event_01J123ABC456DEF789",
  projectId: "project_01J123ABC456DEF789",
  resourceId: "bosco_05582b065b10c5ca8aa03342bb1cf389",
  accountId: "account_01J123ABC456DEF789",
};

Deno.test("Swan webhook compare le secret partagé sans accepter un préfixe", () => {
  assert(constantTimeSecretEquals("secret-live", "secret-live"));
  assertEquals(constantTimeSecretEquals("secret-live", "secret"), false);
  assertEquals(constantTimeSecretEquals("secret-live", "secret-live-x"), false);
  assertEquals(constantTimeSecretEquals("", ""), true);
});

Deno.test("Swan webhook accepte les identifiants GraphQL opaques officiels", () => {
  assertEquals(
    parseSwanWebhookEnvelope({ eventType: "Transaction.Booked", ...ids }),
    {
      eventType: "Transaction.Booked",
      eventId: ids.eventId,
      projectId: ids.projectId,
      resourceId: ids.resourceId,
    },
  );
  assertThrows(
    () =>
      parseSwanWebhookEnvelope({
        eventType: "Transaction.Booked",
        ...ids,
        resourceId: "../payment_123",
      }),
    Error,
    "RESOURCE_ID_INVALIDE",
  );
  assertThrows(
    () =>
      parseSwanWebhookEnvelope({
        eventType: "Transaction.Booked",
        ...ids,
        eventId: `event_${"a".repeat(200)}`,
      }),
    Error,
    "EVENT_ID_INVALIDE",
  );
});

Deno.test("Swan webhook ne conserve qu'un instantané bancaire non sensible", () => {
  const snapshot = sanitizeSwanTransaction({
    id: ids.resourceId,
    account: { id: ids.accountId, IBAN: "FR7630006000011234567890189" },
    amount: { value: "25.50", currency: "eur" },
    counterparty: "Nom sensible",
    reference: "Référence sensible",
    statusInfo: { status: "Booked" },
    type: "SepaCreditTransferOut",
  }, ids.resourceId);
  assertEquals(snapshot, {
    id: ids.resourceId,
    accountId: ids.accountId,
    amountCents: 2550,
    currency: "EUR",
    status: "Booked",
    type: "SepaCreditTransferOut",
  });
  assertEquals("IBAN" in snapshot, false);
  assertEquals("counterparty" in snapshot, false);
  assertEquals("reference" in snapshot, false);
});

Deno.test("Swan webhook refuse les montants ambigus ou non positifs", () => {
  const base = {
    id: ids.resourceId,
    account: { id: ids.accountId },
    amount: { value: "0.001", currency: "EUR" },
    statusInfo: { status: "Booked" },
    type: "SepaCreditTransferOut",
  };
  assertThrows(
    () => sanitizeSwanTransaction(base, ids.resourceId),
    Error,
    "MONTANT_INVALIDE",
  );
});
