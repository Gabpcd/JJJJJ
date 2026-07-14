// Réception fail-closed des événements de transaction Swan.
//
// Swan transmet son secret partagé en clair dans `x-swan-secret` et une
// enveloppe minimale (eventType/eventId/projectId/resourceId). Les détails
// financiers sont toujours relus depuis l'API authentifiée. Au lancement,
// aucun virement automatique Swan n'est autorisé : un événement canonique est
// journalisé et signalé, mais ne peut jamais marquer une prime ou un avoir
// comme payé sans liaison durable préalable.

import { createClient } from "npm:@supabase/supabase-js@2";
import { swanEnv, swanGraphQL } from "../_shared/swan-client.ts";
import {
  constantTimeSecretEquals,
  parseSwanWebhookEnvelope,
  sanitizeSwanTransaction,
  SWAN_TRANSACTION_EVENT_TYPES,
} from "../_shared/swan-webhook.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

function response(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function safeErrorCode(error: unknown): string {
  const message = error instanceof Error
    ? error.message
    : String(error ?? "ERREUR_INCONNUE");
  return message.replace(/[^A-Z0-9_:.-]/gi, "_").slice(0, 180) ||
    "ERREUR_INCONNUE";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return response({ error: "METHOD_NOT_ALLOWED" }, 405);
  }
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    console.error("[swan-webhook] Supabase service configuration missing");
    return response({ error: "SERVICE_UNAVAILABLE" }, 503);
  }

  const webhookSecret = Deno.env.get("SWAN_WEBHOOK_SECRET") ?? "";
  if (!webhookSecret) {
    console.error("[swan-webhook] SWAN_WEBHOOK_SECRET missing");
    return response({ error: "WEBHOOK_NOT_CONFIGURED" }, 503);
  }
  const suppliedSecret = req.headers.get("x-swan-secret") ?? "";
  if (!constantTimeSecretEquals(webhookSecret, suppliedSecret)) {
    return response({ error: "UNAUTHORIZED" }, 401);
  }

  const rawBody = await req.text();
  if (new TextEncoder().encode(rawBody).byteLength > 16_384) {
    return response({ error: "PAYLOAD_TOO_LARGE" }, 413);
  }

  let envelope;
  try {
    envelope = parseSwanWebhookEnvelope(JSON.parse(rawBody));
  } catch (error) {
    console.warn("[swan-webhook] Invalid envelope", safeErrorCode(error));
    return response({ error: "INVALID_PAYLOAD" }, 400);
  }

  const configuredProjectId = (Deno.env.get("SWAN_PROJECT_ID") ?? "").trim();
  if (configuredProjectId && envelope.projectId !== configuredProjectId) {
    return response({ error: "PROJECT_MISMATCH" }, 401);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: claim, error: claimError } = await admin.rpc(
    "fn_swan_webhook_reclamer" as any,
    {
      p_event_id: envelope.eventId,
      p_event_type: envelope.eventType,
      p_resource_id: envelope.resourceId,
      p_project_id: envelope.projectId,
    },
  );
  if (claimError || claim?.success !== true) {
    console.error(
      "[swan-webhook] Claim failed",
      claimError?.code || claim?.error_code || "unknown",
    );
    return response({ error: "PERSISTENCE_UNAVAILABLE" }, 503);
  }
  if (claim.claim === "DEJA_TRAITE") {
    return response({ received: true, duplicate: true });
  }
  if (claim.claim === "EN_COURS") {
    // EN_COURS n'est pas terminal : un 2xx ferait cesser les retries Swan et
    // pourrait laisser définitivement l'événement sous lease après un crash.
    return response({ received: false, retry: true }, 503);
  }

  const finalize = async (
    status: "TRAITE" | "IGNORE" | "ERREUR",
    snapshot: Record<string, unknown> | null,
    errorCode: string | null = null,
  ) => {
    const { data, error } = await admin.rpc(
      "fn_swan_webhook_finaliser" as any,
      {
        p_event_id: envelope.eventId,
        p_statut: status,
        p_transaction_snapshot: snapshot,
        p_error_code: errorCode,
      },
    );
    if (error || data?.success !== true) {
      throw new Error(
        `SWAN_FINALISATION_FAILED:${
          error?.code || data?.error_code || "unknown"
        }`,
      );
    }
  };

  try {
    if (!SWAN_TRANSACTION_EVENT_TYPES.has(envelope.eventType)) {
      await finalize("IGNORE", null);
      return response({ received: true, ignored: true });
    }

    const query = `
      query JoleneSwanTransaction($id: ID!) {
        transaction(id: $id) {
          id
          account { id }
          amount { currency value }
          statusInfo { status }
          type
        }
      }
    `;
    const canonical = await swanGraphQL<{ transaction?: unknown }>(
      query,
      { id: envelope.resourceId },
      { signal: AbortSignal.timeout(6_000) },
    );
    if (!canonical.ok || !canonical.data?.transaction) {
      throw new Error(
        `SWAN_CANONICAL_QUERY_FAILED:${canonical.httpStatus || "graphql"}`,
      );
    }

    const transaction = sanitizeSwanTransaction(
      canonical.data.transaction,
      envelope.resourceId,
    );
    const environment = swanEnv();
    if (!environment.accountId) throw new Error("SWAN_ACCOUNT_ID_MANQUANT");

    const expectedStatusByEvent: Record<string, string> = {
      "Transaction.Pending": "Pending",
      "Transaction.Booked": "Booked",
      "Transaction.Rejected": "Rejected",
      "Transaction.Canceled": "Canceled",
    };
    const accountMatches =
      transaction.accountId === environment.accountId.trim();
    const eventStatusMatches =
      transaction.status === expectedStatusByEvent[envelope.eventType];
    const snapshot = {
      id: transaction.id,
      amount_cents: transaction.amountCents,
      currency: transaction.currency,
      status: transaction.status,
      type: transaction.type,
      account_id_matches: accountMatches,
      event_status_matches: eventStatusMatches,
    };

    // Aucun binding action/beneficiaire/payment n'est créé tant que le flux
    // consentement S2S complet n'est pas activé. Même un Booked authentique ne
    // modifie donc jamais un avoir ou un parrainage par simple référence texte.
    const { error: alertError } = await admin.rpc(
      "fn_emettre_alerte_monitoring" as any,
      {
        p_type: accountMatches
          ? "SWAN_TRANSACTION_SANS_LIAISON"
          : "SWAN_ACCOUNT_MISMATCH",
        p_severite: accountMatches && transaction.currency === "EUR"
          ? "WARNING"
          : "CRITICAL",
        p_source: "swan-webhook",
        p_message:
          "Événement Swan authentique reçu sans liaison de paiement automatisée active.",
        p_details: {
          event_id: envelope.eventId,
          resource_id: envelope.resourceId,
          event_type: envelope.eventType,
          account_id_matches: accountMatches,
          event_status_matches: eventStatusMatches,
          currency: transaction.currency,
          amount_cents: transaction.amountCents,
          transaction_type: transaction.type,
        },
      },
    );
    if (alertError) {
      throw new Error(
        `SWAN_ALERT_PERSISTENCE_FAILED:${alertError.code || "unknown"}`,
      );
    }

    await finalize("IGNORE", snapshot);
    return response({ received: true, ignored: true });
  } catch (error) {
    const errorCode = safeErrorCode(error);
    console.error(
      "[swan-webhook] Processing failed",
      envelope.eventId,
      errorCode,
    );
    try {
      await finalize("ERREUR", null, errorCode);
    } catch (finalizeError) {
      console.error(
        "[swan-webhook] Error persistence failed",
        safeErrorCode(finalizeError),
      );
    }
    // Swan retente les réponses non-2xx. Le délai API ci-dessus est borné pour
    // répondre avant sa limite de dix secondes.
    return response({ error: "PROCESSING_FAILED" }, 500);
  }
});
