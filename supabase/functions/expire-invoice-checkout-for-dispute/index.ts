import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2.99.2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { writeRequiredFinancialAudit } from "../_shared/financial-audit.ts";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";

function json(req: Request, body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Méthode non autorisée" }, 405);

  try {
  const auth = await verifyAdminOrServiceRole(req);
  if (!auth.ok) return json(req, { error: auth.error }, auth.status);
  if (auth.isServiceRole || !auth.userId) {
    return json(req, { error: "Session administrateur requise" }, 403);
  }

  const body = await req.json().catch(() => null) as { litige_id?: unknown } | null;
  const litigeId = typeof body?.litige_id === "string" ? body.litige_id : "";
  if (!litigeId) return json(req, { error: "litige_id requis" }, 400);

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );

  const { data: litige, error: litigeError } = await supabaseAdmin
    .from("litiges")
    .select("id, mission_id, facture_id, statut")
    .eq("id", litigeId)
    .maybeSingle();
  if (litigeError) return json(req, { error: litigeError.message }, 500);
  if (
    !litige
    || !litige.facture_id
    || !["OUVERT", "EN_DISCUSSION", "EN_MEDIATION", "MEDIATION_EN_COURS", "REVUE_ADMIN"].includes(litige.statut)
  ) {
    return json(req, { error: "Litige facture introuvable ou déjà résolu" }, 409);
  }

  const { data: transfer, error: transferError } = await supabaseAdmin
    .from("stripe_transfers")
    .select("id, statut, stripe_checkout_session_id, stripe_payment_intent_id")
    .eq("mission_id", litige.mission_id)
    .eq("facture_honoraire_id", litige.facture_id)
    .not("statut", "in", '("ECHOUE","ANNULEE","REMBOURSE")')
    .order("cree_le", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (transferError) return json(req, { error: transferError.message }, 500);
  if (!transfer?.stripe_checkout_session_id) {
    return json(req, { success: true, action: "AUCUNE_TENTATIVE_ACTIVE" });
  }

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  assertStripeSecretMode(stripeKey);
  const stripe = new Stripe(stripeKey, { apiVersion: "2026-02-25.clover" });
  const session = await stripe.checkout.sessions.retrieve(transfer.stripe_checkout_session_id);

  if (session.status === "complete" || transfer.stripe_payment_intent_id) {
    return json(req, {
      error: "PAIEMENT_DEJA_TERMINE",
      message: "Le paiement vient d’être finalisé. Rapprochez-le avant d’appliquer l’avoir ou le complément.",
    }, 409);
  }
  if (session.status === "open") {
    await stripe.checkout.sessions.expire(session.id);
  }

  // L'effet Stripe est externe à la transaction PostgreSQL. On exige donc
  // l'audit avant de rendre la tentative inactive en base : si l'audit échoue,
  // un retry retrouve la ligne EN_ATTENTE et peut terminer proprement, sans
  // laisser une expiration non tracée puis invisible au prochain appel.
  await writeRequiredFinancialAudit(supabaseAdmin, {
    p_acteur_id: auth.userId,
    p_type_acteur: "ADMIN_PLATEFORME",
    p_action: "FINANCE_CHARGE_EXPIRED",
    p_type_ressource: "litige",
    p_id_ressource: litige.id,
    p_cle_s3: null,
    p_details: {
      evenement: "CHECKOUT_EXPIRE_AVANT_CORRECTION_LITIGE",
      facture_honoraire_id: litige.facture_id,
      stripe_transfer_id: transfer.id,
      stripe_checkout_session_id: session.id,
      ancien_statut_session: session.status,
    },
  }, "audit expiration Checkout avant correction");

  const { data: annule, error: updateError } = await supabaseAdmin
    .from("stripe_transfers")
    .update({ statut: "ANNULEE" })
    .eq("id", transfer.id)
    .eq("stripe_checkout_session_id", session.id)
    .in("statut", ["EN_ATTENTE"])
    .select("id")
    .maybeSingle();
  if (updateError || !annule) {
    return json(req, {
      error: "TENTATIVE_MODIFIEE_CONCURREMMENT",
      message: "L’état du paiement a changé. Rechargez le litige avant de le résoudre.",
    }, 409);
  }

  return json(req, {
    success: true,
    action: "CHECKOUT_EXPIRE",
    stripe_checkout_session_id: session.id,
  });
  } catch (error) {
    console.error("[expire-invoice-checkout-for-dispute] unexpected error", error);
    return json(req, {
      error: "EXPIRATION_CHECKOUT_INDISPONIBLE",
      message: "Impossible de sécuriser la tentative de paiement pour le moment.",
    }, 500);
  }
});
