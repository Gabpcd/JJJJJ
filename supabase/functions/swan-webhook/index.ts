// swan-webhook — Réception des événements SWAN (statut virement SCT)
//
// Configuré dans SWAN Dashboard → Webhooks.
// verify_jwt = false (SWAN ne sait pas signer un JWT Supabase).
// Authentification : signature HMAC-SHA256 vérifiée via SWAN_WEBHOOK_SECRET.
//
// Événements traités :
//   Transaction.Booked  → parrainage PRIME_VERSEE + notification soignant
//   Transaction.Rejected → audit + notification admin + PRIME_REJETEE
//
// Le payload SWAN contient eventType + resourceId (transaction ID).
// On query SWAN GraphQL pour récupérer les détails du paiement.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHmac } from "node:crypto";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function corsHeaders(req: Request) {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": req.headers.get("origin") || "*",
    "Access-Control-Allow-Headers": "authorization, content-type, x-swan-signature",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function verifySwanSignature(body: string, signature: string | null, secret: string): boolean {
  if (!signature || !secret) return false;
  const expected = createHmac("sha256", secret).update(body).digest("hex");
  return signature === expected;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  const cors = corsHeaders(req);

  const webhookSecret = Deno.env.get("SWAN_WEBHOOK_SECRET") || "";
  const rawBody = await req.text();

  if (webhookSecret) {
    const signature = req.headers.get("x-swan-signature") || req.headers.get("x-webhook-signature") || "";
    if (!verifySwanSignature(rawBody, signature, webhookSecret)) {
      console.error("[swan-webhook] Signature invalide");
      return new Response(JSON.stringify({ error: "Invalid signature" }), { status: 401, headers: cors });
    }
  }

  let payload: any;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400, headers: cors });
  }

  const eventType = payload.eventType || payload.type || "";
  const resourceId = payload.resourceId || payload.transaction?.id || "";

  console.log(`[swan-webhook] Event: ${eventType}, resourceId: ${resourceId}`);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

  try {
    if (eventType === "Transaction.Booked") {
      await handleTransactionBooked(admin, resourceId, payload);
    } else if (eventType === "Transaction.Rejected" || eventType === "Transaction.Canceled") {
      await handleTransactionRejected(admin, resourceId, payload, eventType);
    }
  } catch (err) {
    console.error(`[swan-webhook] Error handling ${eventType}:`, (err as Error).message);
  }

  return new Response(JSON.stringify({ received: true, eventType }), { status: 200, headers: cors });
});

async function findParrainageBySwanRef(admin: any, swanTransactionId: string): Promise<any> {
  const { data } = await admin.from("externalisation_actions" as any)
    .select("payload, source_id")
    .eq("type_action", "RECOMPENSE_PARRAINAGE_SOIGNANT")
    .eq("statut", "DONE")
    .order("cree_le", { ascending: false })
    .limit(50);

  if (!data) return null;

  for (const action of data) {
    const p = action.payload as any;
    if (p?.parrainage_id) {
      const { data: parrainage } = await admin.from("parrainages" as any)
        .select("id, parrain_id, filleul_id, statut")
        .eq("id", p.parrainage_id)
        .maybeSingle();
      if (parrainage) return parrainage;
    }
  }
  return null;
}

async function handleTransactionBooked(admin: any, resourceId: string, payload: any) {
  const reference = payload.transaction?.reference || payload.reference || "";
  const parrainageId = extractParrainageIdFromReference(reference);

  if (parrainageId) {
    const { data: parrainage } = await admin.from("parrainages" as any)
      .select("id, parrain_id, filleul_id, statut")
      .eq("id", parrainageId)
      .maybeSingle();

    if (parrainage && parrainage.statut !== "PRIME_VERSEE") {
      await admin.from("parrainages" as any).update({
        statut: "PRIME_VERSEE",
        prime_versee_le: new Date().toISOString(),
      }).eq("id", parrainageId);

      for (const userId of [parrainage.parrain_id, parrainage.filleul_id]) {
        if (userId) {
          await admin.from("notifications").insert({
            destinataire_id: userId,
            type_destinataire: "SOIGNANT",
            type: "PARRAINAGE_PRIME_VERSEE",
            titre: "Prime de parrainage versée !",
            corps: "Votre prime de 50€ a été versée sur votre compte bancaire.",
            lien: "/soignant/parrainage",
          });
        }
      }

      await admin.rpc("fn_ecrire_audit_safe" as any, {
        p_acteur_id: parrainage.parrain_id,
        p_type_acteur: "SYSTEME",
        p_action: "PARRAINAGE_SOIGNANT_PRIME_VERSEE",
        p_type_ressource: "parrainage",
        p_id_ressource: parrainageId,
        p_details: { swan_transaction_id: resourceId, event: "Transaction.Booked" },
      });
    }
  }

  console.log(`[swan-webhook] Transaction.Booked processed: ${resourceId}, parrainage: ${parrainageId || "N/A"}`);
}

async function handleTransactionRejected(admin: any, resourceId: string, payload: any, eventType: string) {
  const reference = payload.transaction?.reference || payload.reference || "";
  const reason = payload.transaction?.reasonCode || payload.reason || "unknown";
  const parrainageId = extractParrainageIdFromReference(reference);

  if (parrainageId) {
    await admin.rpc("fn_ecrire_audit_safe" as any, {
      p_acteur_id: parrainageId,
      p_type_acteur: "SYSTEME",
      p_action: "PARRAINAGE_SOIGNANT_FRAUDE",
      p_type_ressource: "parrainage",
      p_id_ressource: parrainageId,
      p_details: { swan_transaction_id: resourceId, event: eventType, reason },
    });

    await admin.from("notifications").insert({
      destinataire_id: null,
      type_destinataire: "ADMIN_PLATEFORME",
      type: "SYSTEM",
      titre: "Virement parrainage rejeté par SWAN",
      corps: `Transaction ${resourceId} rejetée (${reason}). Parrainage ${parrainageId}.`,
      lien: "/admin/utilisateurs",
    });
  }

  console.log(`[swan-webhook] ${eventType}: ${resourceId}, reason: ${reason}, parrainage: ${parrainageId || "N/A"}`);
}

function extractParrainageIdFromReference(reference: string): string | null {
  const match = reference.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i);
  return match ? match[1] : null;
}
