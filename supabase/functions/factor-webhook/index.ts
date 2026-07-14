// Edge function : factor-webhook
// Reçoit les notifications du factor (Defacto) sur les changements de statut.
// Vérifie la signature HMAC et met à jour factor_advances.
//
// Configuration requise (secrets Supabase) :
//   DEFACTO_WEBHOOK_SECRET=<secret partagé pour vérifier la signature>

import { createClient } from "npm:@supabase/supabase-js@2";

async function verifyHmacSignature(secret: string, body: string, signature: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sigBuf = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  const sigHex = Array.from(new Uint8Array(sigBuf)).map(b => b.toString(16).padStart(2, "0")).join("");
  // Comparaison constante pour éviter timing attacks
  if (sigHex.length !== signature.length) return false;
  let result = 0;
  for (let i = 0; i < sigHex.length; i++) result |= sigHex.charCodeAt(i) ^ signature.charCodeAt(i);
  return result === 0;
}

function mapDefactoStatus(status: string): string {
  const s = (status || "").toLowerCase();
  if (s.includes("financed") || s.includes("paid_out")) return "FINANCEE";
  if (s.includes("approved")) return "APPROUVEE";
  if (s.includes("collected") || s.includes("recovered")) return "RECOUVREE";
  if (s.includes("unpaid") || s.includes("default")) return "IMPAYEE";
  if (s.includes("reject") || s.includes("declined")) return "REJETEE";
  if (s.includes("review") || s.includes("analys")) return "EN_ANALYSE";
  if (s.includes("cancel")) return "ANNULEE";
  return "DEMANDEE";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }

  try {
    const rawBody = await req.text();
    const signature = req.headers.get("x-defacto-signature") || req.headers.get("x-webhook-signature") || "";
    const secret = Deno.env.get("DEFACTO_WEBHOOK_SECRET");

    if (!secret) {
      console.error("DEFACTO_WEBHOOK_SECRET non configuré");
      return new Response(JSON.stringify({ error: "Service non configuré" }), { status: 503 });
    }

    if (!signature) {
      return new Response(JSON.stringify({ error: "Signature manquante" }), { status: 401 });
    }

    const isValid = await verifyHmacSignature(secret, rawBody, signature);
    if (!isValid) {
      console.warn("Webhook signature invalide");
      return new Response(JSON.stringify({ error: "Signature invalide" }), { status: 401 });
    }

    const event = JSON.parse(rawBody);
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    // Format Defacto attendu (à confirmer avec leur doc) :
    // {
    //   "event": "invoice.financed" | "invoice.rejected" | "invoice.collected" | "invoice.unpaid",
    //   "data": {
    //     "id": "...",                  // provider_advance_id
    //     "external_id": "FH-2026-04-0001", // numéro facture
    //     "status": "financed",
    //     "fee_amount": 1500,           // en centimes
    //     "net_amount": 48500,          // en centimes
    //     "financed_at": "2026-04-08T..."
    //   }
    // }
    const data = event.data || event;
    const providerAdvanceId = data.id || data.advance_id;
    const externalId = data.external_id || data.invoice_number;

    if (!providerAdvanceId && !externalId) {
      console.warn("Webhook sans identifiant exploitable");
      return new Response(JSON.stringify({ ok: true, ignored: true }), { status: 200 });
    }

    // Trouver l'avance correspondante
    const query = supabaseAdmin.from("factor_advances").select("id, statut, facture_honoraire_id, soignant_id, approuvee_le");
    const { data: advance } = providerAdvanceId
      ? await query.eq("provider_advance_id", providerAdvanceId).maybeSingle()
      : await (async () => {
          const { data: f } = await supabaseAdmin.from("factures_honoraires").select("id").eq("numero_facture", externalId).maybeSingle();
          if (!f) return { data: null };
          return await query.eq("facture_honoraire_id", f.id).maybeSingle();
        })();

    if (!advance) {
      console.warn(`Webhook : avance introuvable pour ${providerAdvanceId || externalId}`);
      return new Response(JSON.stringify({ ok: true, ignored: true }), { status: 200 });
    }

    const newStatus = mapDefactoStatus(data.status || event.event || "");
    const updates: Record<string, unknown> = {
      statut: newStatus,
      raw_response: data,
    };

    if (newStatus === "FINANCEE") {
      updates.financee_le = new Date().toISOString();
      if (data.net_amount) updates.montant_net_soignant = data.net_amount / 100;
      if (data.fee_amount) updates.frais_factor = data.fee_amount / 100;

      // Marquer la facture honoraires comme FACTORISEE
      await supabaseAdmin
        .from("factures_honoraires")
        .update({ statut: "FACTORISEE" } as any)
        .eq("id", advance.facture_honoraire_id);

      // Notification au soignant
      await supabaseAdmin.from("notifications").insert({
        destinataire_id: advance.soignant_id,
        type_destinataire: "SOIGNANT",
        type: "PAIEMENT_RAPIDE_RECU",
        titre: "Paiement rapide reçu",
        corps: `Votre paiement a été versé via affacturage (${data.net_amount ? (data.net_amount / 100).toFixed(2) + ' €' : ''}).`,
        lien: "/soignant/mes-avances",
      } as any);
    }

    if (newStatus === "RECOUVREE") {
      updates.recouvree_le = new Date().toISOString();
      // La facture honoraires devient PAYEE (l'établissement a payé le factor)
      await supabaseAdmin
        .from("factures_honoraires")
        .update({ statut: "PAYEE", date_paiement: new Date().toISOString() } as any)
        .eq("id", advance.facture_honoraire_id);
    }

    if (newStatus === "REJETEE" || newStatus === "IMPAYEE") {
      updates.motif_rejet = data.reason || data.motif || null;
      // Notifier soignant + admin
      await supabaseAdmin.from("notifications").insert({
        destinataire_id: advance.soignant_id,
        type_destinataire: "SOIGNANT",
        type: "PAIEMENT_RAPIDE_REFUSE",
        titre: newStatus === "REJETEE" ? "Demande d'avance refusée" : "Avance non récupérée",
        corps: data.reason || "Voir détails dans votre espace.",
        lien: "/soignant/mes-avances",
      } as any);
    }

    if (newStatus === "APPROUVEE" && !advance.approuvee_le) {
      updates.approuvee_le = new Date().toISOString();
    }

    await supabaseAdmin.from("factor_advances").update(updates).eq("id", advance.id);

    return new Response(JSON.stringify({ ok: true, updated: true, status: newStatus }), { status: 200 });
  } catch (err: unknown) {
    console.error("factor-webhook error:", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Erreur interne" }), { status: 500 });
  }
});
