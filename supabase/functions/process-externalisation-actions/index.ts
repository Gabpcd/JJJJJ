// process-externalisation-actions — Worker async pour Sprint 4 PR 2
//
// Cron pg_cron toutes les 5 min appelle cet endpoint en service_role.
// Lit fn_externalisations_a_traiter (pagination 50/run) pour récupérer
// les actions à dispatcher selon leur type_action.
//
// Types financiers :
//   STRIPE_REFUND_TOTAL / _PARTIEL → Stripe API refunds.create avec reprise
//   RECOMPENSE_PARRAINAGE_SOIGNANT → transferts Connect exacts et persistés
//   STRIPE_PAYMENT / STRIPE_PAYOUT → désactivés tant qu'aucune source métier
//                                     réconciliable ne les rend sûrs
//   CHORUS_RECYCLER_FACTURE         → piste-client.ts (PENDING_AIFE si scope KO)
//   DPAE_ANNULATION                 → email + push étab Net-Entreprises
//   EMAIL_NOTIF                     → send-email
//   SMS_NOTIF                       → send-sms (OTP téléphone)
//   PUSH_NOTIF                      → send-push
//   AVOIR_PDF_GENERATION            → bloqué : nécessite un AVOIR DB/Factur-X
//   REMBOURSEMENT_AVOIR_SWAN        → bloqué : confirmation bancaire manuelle
//
// Sur succès → fn_externalisation_succes
// Sur échec → fn_externalisation_echec avec backoff
// Sur PENDING_AIFE → fn_externalisation_echec(..., 'PENDING_AIFE')

import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { assertStripeSecretMode } from "../_shared/stripe-production.ts";
import {
  cronAuthErrorResponse,
  cronAuthProbeResponse,
  isCronAuthProbe,
  verifyCronServiceAuth,
} from "../_shared/cron-service-auth.ts";
import { ADMIN_LAUNCH_ACCESS_GROUPS } from "../_shared/admin-auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function corsHeaders(req: Request) {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": req.headers.get("origin") || "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

interface ActionRow {
  id: string;
  type_action: string;
  payload: Record<string, any>;
  source: string;
  source_id: string | null;
  tentatives: number;
}

interface DispatchResult {
  ok: boolean;
  resultat?: any;
  erreur?: string;
  pending_aife?: boolean;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const auth = await verifyCronServiceAuth(req, admin);
  if (!auth.ok) return cronAuthErrorResponse(auth, corsHeaders(req));
  if (isCronAuthProbe(req)) return cronAuthProbeResponse(auth);

  const workerId = `worker_${crypto.randomUUID().slice(0, 8)}`;

  // Récupérer batch
  const { data: rpcData, error: rpcErr } = await admin
    .rpc("fn_externalisations_a_traiter", { p_limit: 50, p_worker_id: workerId });
  if (rpcErr) {
    console.error("[worker] fn_externalisations_a_traiter error:", rpcErr);
    return new Response(JSON.stringify({ error: "RPC failed" }),
      { status: 500, headers: corsHeaders(req) });
  }
  const actions: ActionRow[] = (rpcData as any)?.actions || [];
  const excludedNonReal = Number((rpcData as any)?.excluded_non_real || 0);
  console.info("[worker] actions non réelles exclues", {
    count: excludedNonReal,
  });

  let success = 0, failed = 0, pendingAife = 0, ackFailed = 0;
  const startTs = Date.now();

  for (const action of actions) {
    let externalEffectSucceeded = false;
    try {
      const result = await dispatch(admin, action);
      if (result.ok) {
        externalEffectSucceeded = true;
        const { data: ack, error: ackError } = await admin.rpc(
          "fn_externalisation_succes",
          { p_id: action.id, p_resultat: result.resultat || {} },
        );
        if (ackError || ack?.success !== true) {
          throw new Error(
            `EXTERNALISATION_SUCCESS_ACK_FAILED:${ackError?.message || JSON.stringify(ack)}`,
          );
        }
        success++;
      } else if (result.pending_aife) {
        const { data: ack, error: ackError } = await admin.rpc(
          "fn_externalisation_echec",
          {
            p_id: action.id,
            p_erreur: result.erreur || "PENDING_AIFE",
            p_special_statut: "PENDING_AIFE",
          },
        );
        if (ackError || ack?.success !== true) {
          throw new Error(
            `EXTERNALISATION_PENDING_ACK_FAILED:${ackError?.message || JSON.stringify(ack)}`,
          );
        }
        pendingAife++;
      } else {
        const { data: ack, error: ackError } = await admin.rpc(
          "fn_externalisation_echec",
          { p_id: action.id, p_erreur: result.erreur || "Unknown error" },
        );
        if (ackError || ack?.success !== true) {
          throw new Error(
            `EXTERNALISATION_FAILURE_ACK_FAILED:${ackError?.message || JSON.stringify(ack)}`,
          );
        }
        failed++;
      }
    } catch (err) {
      console.error(`[worker] action ${action.id} threw:`, err);
      if (externalEffectSucceeded) {
        // L'effet fournisseur a réussi : ne jamais le rétrograder en échec.
        // Le lease relira l'action et sa clé d'idempotence retrouvera le même
        // objet externe avant un nouvel acquittement.
        ackFailed++;
        continue;
      }
      const { data: failureAck, error: failureAckError } = await admin.rpc(
        "fn_externalisation_echec",
        {
          p_id: action.id,
          p_erreur: (err as Error).message?.slice(0, 500) || "Exception",
        },
      );
      if (failureAckError || failureAck?.success !== true) ackFailed++;
      else failed++;
    }
  }

  const durationMs = Date.now() - startTs;
  const runSucceeded = failed === 0 && ackFailed === 0;
  console.log(`[worker] ${workerId}: ${actions.length} actions, ${success} success, ${failed} failed, ${pendingAife} pending_aife, ${ackFailed} ack_failed, ${durationMs}ms`);

  return new Response(JSON.stringify({
    run_success: runSucceeded,
    worker_id: workerId,
    processed: actions.length,
    excluded_non_real: excludedNonReal,
    success, failed, pending_aife: pendingAife, ack_failed: ackFailed,
    duration_ms: durationMs,
  }), {
    status: runSucceeded ? 200 : 500,
    headers: corsHeaders(req),
  });
});

// ─── Dispatch principal ──────────────────────────────────────────────

async function dispatch(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { type_action, payload } = action;
  switch (type_action) {
    case "STRIPE_REFUND_TOTAL":
    case "STRIPE_REFUND_PARTIEL":
      return dispatchStripeRefund(admin, action);
    case "STRIPE_PAYMENT":
      return dispatchStripePayment(admin, action);
    case "STRIPE_PAYOUT":
      return dispatchStripePayout(admin, action);
    case "CHORUS_RECYCLER_FACTURE":
    case "CHORUS_RECYCLE_FACTURE":
      return dispatchChorusRecycle(admin, action);
    case "DPAE_ANNULATION":
    case "DPAE_ANNULATION_NOTIF":
      return dispatchDpaeAnnulation(admin, action);
    case "EMAIL_NOTIF":
      return dispatchEmail(admin, action);
    case "SMS_NOTIF":
      return dispatchSmsOtp(admin, action);
    case "PUSH_NOTIF":
      return dispatchPush(admin, action);
    case "AVOIR_PDF_GENERATION":
      return dispatchAvoirPdf(admin, action);
    case "RECOMPENSE_PARRAINAGE_SOIGNANT":
      return dispatchRecompenseParrainage(admin, action);
    case "REMBOURSEMENT_AVOIR_SWAN":
      return dispatchRemboursementAvoirSwan(admin, action);
    default:
      return { ok: false, erreur: `Type d'action non supporté : ${type_action}` };
  }
}

// ─── Stripe ──────────────────────────────────────────────────────────

async function dispatchStripeRefund(admin: any, action: ActionRow): Promise<DispatchResult> {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
  assertStripeSecretMode(stripeKey);
  const stripe = new Stripe(stripeKey, { apiVersion: "2026-02-25.clover" });
  const { mission_id: missionId, montant, pourcentage } = action.payload;
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  // Certains anciens accords encodaient une indemnité SOIGNANT sous un type
  // STRIPE_REFUND_PARTIEL. Ce n'est jamais un refund client : l'exécuter ici
  // virerait de l'argent à la mauvaise partie.
  if (Object.prototype.hasOwnProperty.call(action.payload, "beneficiaire_id")) {
    return {
      ok: false,
      erreur: "ACTION_TYPE_MISMATCH: beneficiaire_id interdit sur un remboursement client",
    };
  }
  if (typeof missionId !== "string" || !uuidPattern.test(missionId)) {
    return { ok: false, erreur: "MISSION_ID_INVALIDE" };
  }

  const { data: mission, error: missionError } = await admin
    .from("missions")
    .select("id, etablissement_id, stripe_payment_intent_id")
    .eq("id", missionId)
    .maybeSingle();
  if (missionError || !mission) {
    return {
      ok: false,
      erreur: `MISSION_REFUND_INTROUVABLE: ${missionError?.message || missionId}`,
    };
  }
  if (!mission.stripe_payment_intent_id) {
    return { ok: false, erreur: `AUCUN_PAYMENT_INTENT: ${missionId}` };
  }

  const { data: etablissement, error: etablissementError } = await admin
    .from("etablissements")
    .select("id, stripe_customer_id")
    .eq("id", mission.etablissement_id)
    .maybeSingle();
  if (etablissementError || !etablissement?.stripe_customer_id) {
    return {
      ok: false,
      erreur: `STRIPE_CUSTOMER_ETABLISSEMENT_ABSENT: ${etablissementError?.message || mission.etablissement_id}`,
    };
  }

  const objectId = (value: unknown): string | null => {
    if (typeof value === "string") return value;
    if (value && typeof value === "object" && "id" in value) {
      const id = (value as { id?: unknown }).id;
      return typeof id === "string" ? id : null;
    }
    return null;
  };

  const paymentIntent = await stripe.paymentIntents.retrieve(
    mission.stripe_payment_intent_id,
    { expand: ["latest_charge"] },
  );
  const sourceType = paymentIntent.metadata?.type || "";
  if (sourceType === "CONNECT_MISSION_PAYMENT") {
    return {
      ok: false,
      erreur: "CONNECT_TRANSFER_REVERSAL_REQUIRED: utiliser le circuit Connect dédié",
    };
  }
  if (sourceType === "ESCROW_MISSION_PAYMENT") {
    return {
      ok: false,
      erreur: "ESCROW_REFUND_QUEUE_REQUIRED: utiliser fn_escrow_rembourser",
    };
  }
  if (sourceType !== "commission_reservation") {
    return {
      ok: false,
      erreur: `PAYMENT_PROVENANCE_INCONNUE: ${sourceType || "metadata.type absent"}`,
    };
  }

  const charge = typeof paymentIntent.latest_charge === "string"
    ? await stripe.charges.retrieve(paymentIntent.latest_charge)
    : paymentIntent.latest_charge;
  const customer = await stripe.customers.retrieve(etablissement.stripe_customer_id);
  const piCustomerId = objectId(paymentIntent.customer);
  const chargeCustomerId = objectId(charge?.customer);
  const chargePaymentIntentId = objectId(charge?.payment_intent);
  const customerIsDeleted = "deleted" in customer && customer.deleted;

  if (
    paymentIntent.id !== mission.stripe_payment_intent_id
    || paymentIntent.status !== "succeeded"
    || paymentIntent.currency !== "eur"
    || !Number.isSafeInteger(paymentIntent.amount)
    || paymentIntent.amount <= 0
    || paymentIntent.amount_received !== paymentIntent.amount
    || paymentIntent.amount_capturable !== 0
    || paymentIntent.metadata?.mission_id !== mission.id
    || paymentIntent.metadata?.etablissement_id !== mission.etablissement_id
    || piCustomerId !== etablissement.stripe_customer_id
    || customerIsDeleted
    || customer.metadata?.etablissement_id !== mission.etablissement_id
    || !charge
    || !charge.paid
    || !charge.captured
    || charge.status !== "succeeded"
    || charge.disputed
    || charge.currency !== "eur"
    || charge.amount !== paymentIntent.amount_received
    || charge.amount_refunded < 0
    || charge.amount_refunded > charge.amount
    || chargeCustomerId !== etablissement.stripe_customer_id
    || chargePaymentIntentId !== paymentIntent.id
  ) {
    return { ok: false, erreur: "STRIPE_REFUND_SOURCE_IDENTITY_MISMATCH" };
  }

  // Un crash peut survenir après refunds.create mais avant l'acquittement de
  // l'action. On retrouve alors l'objet exact par metadata, au lieu de déduire
  // un succès d'un montant remboursé global au PaymentIntent.
  const refundsPage = await stripe.refunds.list({
    payment_intent: paymentIntent.id,
    limit: 100,
  });
  if (refundsPage.has_more) {
    return { ok: false, erreur: "REFUND_HISTORY_REQUIRES_MANUAL_REVIEW" };
  }
  const ownRefunds = refundsPage.data.filter(
    (refund) => refund.metadata?.externalisation_action_id === action.id,
  );
  if (ownRefunds.length > 1) {
    return { ok: false, erreur: "DUPLICATE_EXTERNALISATION_REFUNDS" };
  }
  const existingRefund = ownRefunds[0] ?? null;

  let amountCents: number;
  if (action.type_action === "STRIPE_REFUND_PARTIEL") {
    const hasPercentage = pourcentage !== undefined && pourcentage !== null;
    const hasAmount = montant !== undefined && montant !== null;
    if (hasPercentage === hasAmount) {
      return {
        ok: false,
        erreur: "PARTIAL_REFUND_REQUIRES_EXACTLY_ONE_OF_MONTANT_OR_POURCENTAGE",
      };
    }
    if (hasPercentage) {
      const percentage = Number(pourcentage);
      if (!Number.isFinite(percentage) || percentage <= 0 || percentage > 100) {
        return { ok: false, erreur: "POURCENTAGE_REMBOURSEMENT_INVALIDE" };
      }
      // Base réelle encaissée Stripe, jamais un taux × une durée métier.
      amountCents = Math.round(paymentIntent.amount_received * percentage / 100);
    } else {
      const amountEuros = Number(montant);
      amountCents = Math.round(amountEuros * 100);
      if (
        !Number.isFinite(amountEuros)
        || amountEuros <= 0
        || Math.abs(amountEuros * 100 - amountCents) > 0.000001
      ) {
        return { ok: false, erreur: "MONTANT_REMBOURSEMENT_INVALIDE" };
      }
    }
  } else {
    if (montant !== undefined || pourcentage !== undefined) {
      return { ok: false, erreur: "TOTAL_REFUND_FORBIDS_PARTIAL_AMOUNT_FIELDS" };
    }
    amountCents = existingRefund
      ? existingRefund.amount
      : charge.amount - charge.amount_refunded;
  }

  if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
    return { ok: false, erreur: "AUCUN_MONTANT_REMBOURSABLE" };
  }
  const ownSucceededAmount = existingRefund?.status === "succeeded"
    ? existingRefund.amount
    : 0;
  const refundableForThisAction = charge.amount - charge.amount_refunded + ownSucceededAmount;
  if (amountCents > refundableForThisAction) {
    return { ok: false, erreur: "REFUND_AMOUNT_EXCEEDS_REMAINING_CHARGE" };
  }

  const refund = existingRefund ?? await stripe.refunds.create({
    payment_intent: paymentIntent.id,
    amount: amountCents,
    reason: "requested_by_customer",
    metadata: {
      externalisation_action_id: action.id,
      externalisation_action_type: action.type_action,
      mission_id: mission.id,
      etablissement_id: mission.etablissement_id,
      source: "process_externalisation_actions",
    },
  }, { idempotencyKey: `externalisation_refund_${action.id}` });

  if (
    objectId(refund.payment_intent) !== paymentIntent.id
    || objectId(refund.charge) !== charge.id
    || refund.amount !== amountCents
    || refund.currency !== "eur"
    || refund.metadata?.externalisation_action_id !== action.id
    || refund.metadata?.mission_id !== mission.id
    || refund.metadata?.etablissement_id !== mission.etablissement_id
  ) {
    return { ok: false, erreur: "STRIPE_REFUND_RESULT_IDENTITY_MISMATCH" };
  }
  if (refund.status !== "succeeded") {
    return {
      ok: false,
      erreur: `STRIPE_REFUND_NOT_SUCCEEDED:${refund.id}:${refund.status || "unknown"}`,
    };
  }

  return {
    ok: true,
    resultat: {
      refund_id: refund.id,
      amount: refund.amount,
      status: refund.status,
      payment_intent_id: paymentIntent.id,
      charge_id: charge.id,
    },
  };
}

async function dispatchStripePayment(admin: any, action: ActionRow): Promise<DispatchResult> {
  void admin;
  // Aucun call site actif ne doit produire ce type générique : il ne porte ni
  // objet métier source, ni montant recalculable côté DB, ni recovery durable.
  // Les primes utilisent leur dispatcher exact; les missions Connect utilisent
  // stripe-connect-pay-mission. On conserve le type legacy uniquement pour que
  // les anciennes lignes deviennent ERROR visibles dans l'admin.
  return {
    ok: false,
    erreur: `STRIPE_PAYMENT_GENERIQUE_DESACTIVE:${action.id}`,
  };
}

async function dispatchStripePayout(admin: any, action: ActionRow): Promise<DispatchResult> {
  return { ok: false, erreur: "STRIPE_PAYOUT pas encore implémenté (Sprint 5+)" };
}

// ─── Parrainage soignant ────────────────────────────────────────────

// Prévient le soignant que sa prime a bien été versée : notif in-app (+ push via
// le flag push_envoyee traité en aval) ET email (via email_queue → email-cron).
async function notifierPrimeVersee(
  admin: any,
  userId: string,
  soignant: { prenom?: string | null; email?: string | null } | null,
  montant: number,
  canal: string,
): Promise<void> {
  try {
    await admin.from("notifications").insert({
      destinataire_id: userId,
      type_destinataire: "SOIGNANT",
      type: "PARRAINAGE_PRIME_VERSEE",
      titre: `🎉 Prime de parrainage versée (${montant}€)`,
      corps: canal === "STRIPE_CONNECT"
        ? `Votre prime de ${montant}€ a été versée sur votre compte Stripe.`
        : `Votre prime de ${montant}€ part en virement SEPA sur votre compte (réception sous 1 à 2 jours ouvrés).`,
      lien: "/soignant/parrainage",
    });
  } catch (_e) { /* notif best-effort */ }
  try {
    await admin.from("email_queue").insert({
      type: "PARRAINAGE_PRIME_VERSEE",
      destinataire_id: userId,
      destinataire_email: soignant?.email ?? null,
      data: { prenom: soignant?.prenom ?? null, montant, canal },
    });
  } catch (_e) { /* email best-effort */ }
}

async function dispatchRecompenseParrainage(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { parrainage_id, parrain_id, filleul_id, montant_parrain, montant_filleul } = action.payload;
  if (!parrainage_id || !parrain_id || !filleul_id) {
    return { ok: false, erreur: "parrainage_id + parrain_id + filleul_id requis" };
  }
  if (action.source !== "parrainage_soignant" || action.source_id !== parrainage_id) {
    return { ok: false, erreur: "PARRAINAGE_ACTION_PROVENANCE_MISMATCH" };
  }

  const { data: parrainage, error: parrainageError } = await admin
    .from("parrainages")
    .select("id, parrain_id, filleul_id, statut, prime_versee_le")
    .eq("id", parrainage_id)
    .maybeSingle();
  if (parrainageError || !parrainage) {
    return { ok: false, erreur: `PARRAINAGE_INTROUVABLE:${parrainageError?.message || parrainage_id}` };
  }
  if (
    parrainage.parrain_id !== parrain_id
    || parrainage.filleul_id !== filleul_id
  ) {
    return { ok: false, erreur: "PARRAINAGE_BENEFICIAIRES_MISMATCH" };
  }
  if (parrainage.statut === "PRIME_VERSEE" && parrainage.prime_versee_le) {
    return { ok: true, resultat: { skip: "deja_versee" } };
  }
  if (parrainage.statut !== "VALIDE_EN_ATTENTE_SEUIL") {
    return { ok: false, erreur: `PARRAINAGE_STATUT_INVALIDE:${parrainage.statut}` };
  }

  const { data: primeParam, error: primeError } = await admin.rpc("fn_param_num", {
    p_cle: "prime_parrainage_eur",
    p_defaut: 25,
  });
  const prime = Number(primeParam);
  if (
    primeError
    || !Number.isFinite(prime)
    || prime <= 0
    || Number(montant_parrain) !== prime
    || Number(montant_filleul) !== prime
  ) {
    return { ok: false, erreur: `PARRAINAGE_MONTANT_MISMATCH:${primeError?.message || prime}` };
  }

  const { data: persistedAction, error: actionError } = await admin
    .from("externalisation_actions")
    .select("id, statut, resultat")
    .eq("id", action.id)
    .maybeSingle();
  if (actionError || !persistedAction || persistedAction.statut !== "PROCESSING") {
    return { ok: false, erreur: `PARRAINAGE_ACTION_STATE_MISMATCH:${actionError?.message || persistedAction?.statut}` };
  }

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
  assertStripeSecretMode(stripeKey);
  const stripe = new Stripe(stripeKey, { apiVersion: "2026-02-25.clover" });
  const results: Record<string, string> = {
    ...((persistedAction.resultat && typeof persistedAction.resultat === "object")
      ? persistedAction.resultat
      : {}),
  };

  const persistProgress = async () => {
    const { data, error } = await admin
      .from("externalisation_actions")
      .update({ resultat: results, derniere_tentative_le: new Date().toISOString() })
      .eq("id", action.id)
      .eq("statut", "PROCESSING")
      .select("id")
      .maybeSingle();
    if (error || !data) {
      throw new Error(`PARRAINAGE_PROGRESS_PERSISTENCE_FAILED:${error?.message || "state conflict"}`);
    }
  };

  for (const [role, userId] of [
    ["parrain", parrain_id],
    ["filleul", filleul_id],
  ] as const) {
    const amountCents = Math.round(prime * 100);
    const { data: soignant, error: soignantError } = await admin
      .from("soignants")
      .select("id, stripe_account_id, prenom, nom, email")
      .eq("id", userId)
      .maybeSingle();
    const { data: onboarding, error: onboardingError } = await admin
      .from("stripe_connect_onboarding")
      .select("soignant_id, stripe_account_id, statut, onboarding_complete, charges_enabled, payouts_enabled")
      .eq("soignant_id", userId)
      .maybeSingle();
    const connectedAccountId = soignant?.stripe_account_id || null;

    // Jolene n'est pas payeur de paie : sans compte Connect libéral complet,
    // la prime reste due et part en traitement manuel explicite. Aucun virement
    // SWAN n'est déclaré « versé » sur la seule création d'un Payment pending.
    if (
      soignantError
      || !soignant
      || onboardingError
      || !onboarding
      || !connectedAccountId
      || onboarding.stripe_account_id !== connectedAccountId
      || onboarding.statut !== "COMPLET"
      || onboarding.onboarding_complete !== true
      || onboarding.charges_enabled !== true
      || onboarding.payouts_enabled !== true
    ) {
      if (results[`${role}_canal`] !== "TRAITEMENT_MANUEL_REQUIS") {
        results[`${role}_canal`] = "TRAITEMENT_MANUEL_REQUIS";
        await persistProgress();
        if (soignant) {
          const { error: notificationError } = await admin.from("notifications").insert({
            destinataire_id: userId,
            type_destinataire: "SOIGNANT",
            type: "PARRAINAGE",
            titre: `${prime}€ de prime validée`,
            corps: `Votre prime de ${prime}€ est due. Son mode de versement doit être validé par l'équipe Jolene.`,
            lien: "/soignant/parrainage",
          });
          if (notificationError) throw new Error(`PARRAINAGE_DUE_NOTIFICATION_FAILED:${notificationError.message}`);
        }
      }
      return {
        ok: false,
        erreur: `PARRAINAGE_TRAITEMENT_MANUEL_REQUIS:${role}:${soignantError?.message || onboardingError?.message || "Connect incomplet"}`,
      };
    }

    let transfer: Stripe.Transfer;
    const persistedTransferId = results[`${role}_ref`];
    if (persistedTransferId) {
      transfer = await stripe.transfers.retrieve(persistedTransferId);
    } else {
      transfer = await stripe.transfers.create({
        amount: amountCents,
        currency: "eur",
        destination: connectedAccountId,
        description: `Prime parrainage Jolene (${role})`,
        metadata: {
          externalisation_action_id: action.id,
          parrainage_id,
          role,
          beneficiaire_id: userId,
        },
      }, { idempotencyKey: `parrainage_transfer_${parrainage_id}_${role}` });
    }
    if (
      transfer.amount !== amountCents
      || transfer.currency !== "eur"
      || (typeof transfer.destination === "string"
        ? transfer.destination
        : transfer.destination?.id) !== connectedAccountId
      || transfer.metadata?.externalisation_action_id !== action.id
      || transfer.metadata?.parrainage_id !== parrainage_id
      || transfer.metadata?.role !== role
      || transfer.metadata?.beneficiaire_id !== userId
      || transfer.reversed
      || transfer.amount_reversed !== 0
    ) {
      return { ok: false, erreur: `PARRAINAGE_TRANSFER_IDENTITY_MISMATCH:${role}:${transfer.id}` };
    }

    if (!persistedTransferId) {
      results[`${role}_canal`] = "STRIPE_CONNECT";
      results[`${role}_ref`] = transfer.id;
      await persistProgress();
      await notifierPrimeVersee(admin, userId, soignant, prime, "STRIPE_CONNECT");
    }
  }

  const { data: paid, error: paidError } = await admin.from("parrainages")
    .update({ statut: "PRIME_VERSEE", prime_versee_le: new Date().toISOString() })
    .eq("id", parrainage_id)
    .eq("statut", "VALIDE_EN_ATTENTE_SEUIL")
    .eq("parrain_id", parrain_id)
    .eq("filleul_id", filleul_id)
    .select("id")
    .maybeSingle();
  if (paidError || !paid) {
    return { ok: false, erreur: `PARRAINAGE_FINALISATION_FAILED:${paidError?.message || "state conflict"}` };
  }

  const { data: audit, error: auditError } = await admin.rpc("fn_ecrire_audit_safe", {
    p_acteur_id: parrain_id,
    p_type_acteur: "SYSTEME",
    p_action: "PARRAINAGE_SOIGNANT_PRIME_VERSEE",
    p_type_ressource: "parrainage",
    p_id_ressource: parrainage_id,
    p_details: results,
  });
  if (auditError || audit?.success !== true) {
    return { ok: false, erreur: `PARRAINAGE_AUDIT_FAILED:${auditError?.message || JSON.stringify(audit)}` };
  }

  return { ok: true, resultat: results };
}

// Remboursement d'un avoir par virement SEPA SWAN (auto, fallback manuel admin).
async function dispatchRemboursementAvoirSwan(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { avoir_id } = action.payload;
  if (!avoir_id) return { ok: false, erreur: "avoir_id requis" };

  const { data: avoir, error: avoirError } = await admin.from("factures_honoraires")
    .select("id, numero_facture, soignant_id, mode_remboursement, date_remboursement, montant_ttc, type_document, statut")
    .eq("id", avoir_id).maybeSingle();
  if (avoirError || !avoir) {
    return { ok: false, erreur: `Avoir introuvable:${avoirError?.message || avoir_id}` };
  }
  if (avoir.type_document !== "AVOIR") return { ok: false, erreur: "Document non-avoir" };
  if (avoir.date_remboursement) return { ok: true, resultat: { skip: "déjà remboursé" } }; // idempotent

  // Initier un Payment SWAN peut ne produire que ConsentPending. Sans binding
  // S2S durable + webhook Booked exact, ce n'est jamais une preuve de virement.
  // L'avoir reste donc EMISE et doit être confirmé via le RPC admin manuel
  // après preuve bancaire ; aucun IBAN brut ni montant de payload n'est utilisé.
  return {
    ok: false,
    erreur:
      `REMBOURSEMENT_AVOIR_MANUEL_REQUIS:${avoir.id}:${avoir.numero_facture || "sans_numero"}`,
  };
}

// ─── Chorus Pro ──────────────────────────────────────────────────────

async function dispatchChorusRecycle(admin: any, action: ActionRow): Promise<DispatchResult> {
  // Si PISTE_OAUTH_SCOPE pas configuré (cas actuel jusqu'à déblocage AIFE),
  // marquer PENDING_AIFE pour re-check 24h
  const oauthScope = Deno.env.get("PISTE_OAUTH_SCOPE");
  if (!oauthScope || !oauthScope.includes("recyclerFacture")) {
    return { ok: false, erreur: "PISTE scopes pas activés AIFE (recyclerFacture absent)", pending_aife: true };
  }

  // À implémenter quand AIFE active les scopes (Sprint final).
  // Pour le moment : marquer PENDING_AIFE même si scope présent
  // (car la chaîne piste-client complète n'est pas dans cette PR)
  return { ok: false, erreur: "Chorus recycleFacture pas encore intégré (à finaliser post-AIFE)", pending_aife: true };
}

// ─── DPAE ────────────────────────────────────────────────────────────

async function validatePushResponse(
  response: Response,
): Promise<{ ok: true; data: Record<string, any> } | { ok: false; error: string }> {
  const data = await response.json().catch(() => null) as
    | Record<string, any>
    | null;
  const delivered = Number(data?.sent) > 0;
  const intentionallySkipped = data?.skipped === true;
  const fallbackDelivered = data?.email_fallback === true;
  if (
    response.ok
    && data?.success === true
    && (delivered || intentionallySkipped || fallbackDelivered)
  ) {
    return { ok: true, data: data || {} };
  }
  return {
    ok: false,
    error: data?.pending === true
      ? `PUSH_RESULT_INDETERMINATE:${response.status}`
      : `PUSH_NOT_DELIVERED:${response.status}:${data?.error || "invalid_response"}`,
  };
}

async function dispatchDpaeAnnulation(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { contrat_id, mission_id, motif } = action.payload;
  if (!contrat_id) return { ok: false, erreur: "contrat_id missing" };
  if (action.source !== "ANNULATION_MISSION" || !mission_id || !action.source_id) {
    return { ok: false, erreur: "DPAE_ACTION_PROVENANCE_MISMATCH" };
  }

  let sourceMatchesMission = action.source_id === mission_id;
  if (!sourceMatchesMission) {
    const { data: candidature, error: candidatureError } = await admin
      .from("candidatures")
      .select("id, mission_id")
      .eq("id", action.source_id)
      .maybeSingle();
    if (candidatureError) {
      return {
        ok: false,
        erreur: `DPAE_CANDIDATURE_LOOKUP_FAILED:${candidatureError.message}`,
      };
    }
    sourceMatchesMission = candidature?.mission_id === mission_id;
  }
  if (!sourceMatchesMission) {
    return { ok: false, erreur: "DPAE_ACTION_PROVENANCE_MISMATCH" };
  }

  const { data: contrat, error: contratError } = await admin.from("contrats_mission")
    .select("id, mission_id, etablissement_id, numero_contrat, type_contrat, statut, dpae_numero")
    .eq("id", contrat_id).maybeSingle();
  if (contratError || !contrat) {
    return { ok: false, erreur: `contrat introuvable:${contratError?.message || contrat_id}` };
  }
  if (
    contrat.mission_id !== mission_id
    || !["CDD", "CDDU", "VACATION"].includes(contrat.type_contrat)
    || contrat.statut !== "RUPTURE_ETAB"
  ) {
    return { ok: false, erreur: "DPAE_CONTRAT_SALARIE_IDENTITY_MISMATCH" };
  }

  const { data: actionState, error: actionStateError } = await admin
    .from("externalisation_actions")
    .select("id, statut, resultat")
    .eq("id", action.id)
    .maybeSingle();
  if (actionStateError || !actionState || actionState.statut !== "PROCESSING") {
    return { ok: false, erreur: `DPAE_ACTION_STATE_MISMATCH:${actionStateError?.message || actionState?.statut}` };
  }
  const progress: Record<string, unknown> = {
    ...((actionState.resultat && typeof actionState.resultat === "object")
      ? actionState.resultat
      : {}),
  };
  const persistProgress = async () => {
    const { data, error } = await admin
      .from("externalisation_actions")
      .update({ resultat: progress, derniere_tentative_le: new Date().toISOString() })
      .eq("id", action.id)
      .eq("statut", "PROCESSING")
      .select("id")
      .maybeSingle();
    if (error || !data) {
      throw new Error(`DPAE_PROGRESS_PERSISTENCE_FAILED:${error?.message || "state conflict"}`);
    }
  };

  // Option A : email + push étab pour annulation manuelle Net-Entreprises
  // (Option B API tiers déclarant URSSAF = Sprint 5+)
  if (progress.email_sent !== true) {
    const emailResponse = await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SERVICE_ROLE_KEY}` },
      body: JSON.stringify({
        type: "DPAE_ANNULATION_RAPPEL",
        destinataire_id: contrat.etablissement_id,
        idempotency_key: `externalisation.${action.id}.dpae-email`,
        data: {
          contrat_id: contrat.id,
          mission_id,
          numero_contrat: contrat.numero_contrat,
          type_contrat: contrat.type_contrat,
          motif,
          dpae_numero: contrat.dpae_numero,
          url: "https://www.net-entreprises.fr/declaration-prealable-embauche/",
          echeance_legale_h: 48,
        },
      }),
    });
    if (!emailResponse.ok) {
      return { ok: false, erreur: `DPAE_EMAIL_FAILED:${emailResponse.status}` };
    }
    progress.email_sent = true;
    await persistProgress();
  }
  if (progress.push_sent !== true) {
    const pushResponse = await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SERVICE_ROLE_KEY}` },
      body: JSON.stringify({
        destinataire_id: contrat.etablissement_id,
        type_evenement: "DPAE_ANNULATION_RAPPEL",
        titre: "⚠️ Annulation DPAE à effectuer",
        corps: `Contrat ${contrat.numero_contrat || ""} annulé. Annulez la DPAE sur Net-Entreprises sous 48h.`,
        lien: `/contrat/${contrat_id}`,
        idempotency_key: `externalisation.${action.id}.dpae-push`,
      }),
    });
    const pushOutcome = await validatePushResponse(pushResponse);
    if (!pushOutcome.ok) {
      return { ok: false, erreur: `DPAE_PUSH_FAILED:${pushOutcome.error}` };
    }
    progress.push_sent = true;
    await persistProgress();
  }

  return {
    ok: true,
    resultat: {
      ...progress,
      mode: "OPTION_A_MANUEL",
      contrat_id: contrat.id,
      mission_id,
      etablissement_id: contrat.etablissement_id,
      type_contrat: contrat.type_contrat,
    },
  };
}

// ─── Emails + Push (relais simples) ──────────────────────────────────

async function dispatchEmail(admin: any, action: ActionRow): Promise<DispatchResult> {
  if (action.payload?.destinataire_role !== undefined) {
    if (
      action.payload.destinataire_role !== "ADMIN"
      || action.source !== "AUTRE"
      || !action.source_id
      || action.payload.type !== "RECLAMATION_SCORE_NOUVELLE"
      || action.payload?.data?.reclamation_id !== action.source_id
    ) {
      return { ok: false, erreur: "EMAIL_ROLE_SYSTEME_NON_AUTORISE" };
    }

    // Seule classe système sans UUID admise : la réclamation score historique.
    // Relecture de la source puis résolution explicite des admins actifs ayant
    // l'intégralité des groupes de lancement; aucun email/UUID du payload.
    const { data: reclamation, error: reclamationError } = await admin
      .from("reclamations_score")
      .select("id, contesteur_id, evenement_type, motif_categorie")
      .eq("id", action.source_id)
      .maybeSingle();
    if (
      reclamationError
      || !reclamation
      || reclamation.contesteur_id !== action.payload?.data?.contesteur_id
      || reclamation.evenement_type !== action.payload?.data?.evenement_type
      || reclamation.motif_categorie !== action.payload?.data?.motif_categorie
    ) {
      return {
        ok: false,
        erreur:
          `EMAIL_RECLAMATION_SOURCE_INCOHERENTE:${reclamationError?.message || "binding"}`,
      };
    }

    const { data: adminRows, error: adminsError } = await admin
      .from("equipe_admin")
      .select("user_id, actif, acces_groupes")
      .eq("actif", true)
      .not("user_id", "is", null);
    if (adminsError) {
      return { ok: false, erreur: `EMAIL_ADMINS_INDISPONIBLES:${adminsError.message}` };
    }
    const admins = (adminRows || []).filter((candidate: any) => {
      if (
        typeof candidate.user_id !== "string"
        || !Array.isArray(candidate.acces_groupes)
      ) return false;
      const groupes = new Set(
        candidate.acces_groupes.filter(
          (groupe: unknown): groupe is string => typeof groupe === "string",
        ),
      );
      return ADMIN_LAUNCH_ACCESS_GROUPS.every((groupe) => groupes.has(groupe));
    });
    if (admins.length === 0) {
      return { ok: false, erreur: "EMAIL_AUCUN_ADMIN_ACTIF_COMPLET" };
    }

    for (const adminRow of admins) {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
        },
        body: JSON.stringify({
          destinataire_id: adminRow.user_id,
          type: "ADMIN_BROADCAST",
          data: {
            subject: "Nouvelle réclamation de score — action requise",
            body:
              `Une réclamation ${reclamation.evenement_type} (${reclamation.motif_categorie}) `
              + `doit être examinée dans l’administration Jolene. Référence : ${reclamation.id}.`,
            groupe: "Conformité & Technique",
          },
          idempotency_key: `externalisation.${action.id}.${adminRow.user_id}`,
        }),
      });
      if (!res.ok) {
        return {
          ok: false,
          erreur: `send-email admin ${res.status}`,
        };
      }
    }
    return {
      ok: true,
      resultat: {
        classe: "SYSTEM_ADMIN_RECLAMATION",
        admins_notifies: admins.length,
      },
    };
  }

  const res = await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify({
      ...action.payload,
      idempotency_key: `externalisation.${action.id}.email`,
    }),
  });
  if (res.ok) return { ok: true, resultat: { status: res.status } };
  return { ok: false, erreur: `send-email ${res.status}` };
}

async function dispatchSmsOtp(admin: any, action: ActionRow): Promise<DispatchResult> {
  const p = action.payload;
  const code = typeof p?.data?.code === "string" ? p.data.code : "";
  const telephone = typeof p?.telephone === "string" ? p.telephone : "";
  if (
    action.source !== "AUTRE"
    || !action.source_id
    || p?.type !== "OTP_VERIFICATION_TELEPHONE"
    || !/^\d{6}$/.test(code)
    || !telephone
  ) {
    return { ok: false, erreur: "SMS_OTP_PAYLOAD_INVALIDE" };
  }

  // La ligne OTP est la source métier. Une action forgée, périmée, déjà
  // utilisée ou visant un autre numéro ne déclenche jamais un SMS.
  const { data: otp, error: otpError } = await admin
    .from("otps_telephone")
    .select("id, user_id, telephone, utilise, expire_le")
    .eq("id", action.source_id)
    .maybeSingle();
  if (otpError || !otp) {
    return { ok: false, erreur: `SMS_OTP_SOURCE_INTROUVABLE:${otpError?.message || action.source_id}` };
  }
  if (otp.telephone !== telephone) {
    return { ok: false, erreur: "SMS_OTP_TELEPHONE_MISMATCH" };
  }
  if (otp.utilise || Date.parse(otp.expire_le) <= Date.now()) {
    return { ok: true, resultat: { skipped: true, reason: otp.utilise ? "otp_used" : "otp_expired" } };
  }

  const res = await fetch(`${SUPABASE_URL}/functions/v1/send-sms`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({
      telephone,
      type: "OTP_VERIFICATION_TELEPHONE",
      contenu: `Votre code de vérification est ${code}. Il expire dans 10 minutes. Ne le partagez jamais.`,
      destinataire_id: otp.user_id,
      prefix_type: "OTP_VERIFICATION_TELEPHONE",
      idempotency_key: `externalisation.${action.id}.sms`,
    }),
  });
  const responseBody = await res.json().catch(() => null) as Record<string, any> | null;
  if (res.ok && responseBody?.success === true) {
    return {
      ok: true,
      resultat: { status: res.status, provider_id: responseBody.sid || null },
    };
  }
  return {
    ok: false,
    erreur: `send-sms OTP ${res.status}:${responseBody?.error || "provider_error"}`,
  };
}

async function dispatchPush(admin: any, action: ActionRow): Promise<DispatchResult> {
  const p = action.payload;
  // Adapter le format pour send-push (peut être appelé avec destinataire_id, type_evenement, titre, corps, data.lien)
  const body: any = {
    destinataire_id: p.destinataire_id,
    titre: p.titre || p.title,
    corps: p.corps || p.body,
    lien: p.lien || p.data?.lien,
    data: p.data,
    type_evenement: p.type_evenement,
    idempotency_key: `externalisation.${action.id}.push`,
  };
  const res = await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify(body),
  });
  const outcome = await validatePushResponse(res);
  if (outcome.ok) {
    return {
      ok: true,
      resultat: { status: res.status, push: outcome.data },
    };
  }
  return { ok: false, erreur: `send-push ${outcome.error}` };
}

// ─── AVOIR PDF ───────────────────────────────────────────────────────

async function dispatchAvoirPdf(admin: any, action: ActionRow): Promise<DispatchResult> {
  const { mission_id } = action.payload;
  if (!mission_id) return { ok: false, erreur: "mission_id missing" };
  const { data: mission, error: missionError } = await admin
    .from("missions")
    .select("id")
    .eq("id", mission_id)
    .maybeSingle();
  if (missionError || !mission) {
    return { ok: false, erreur: `mission introuvable:${missionError?.message || mission_id}` };
  }

  // L'ancien code stockait du HTML avec une extension .html tout en le
  // présentant comme PDF comptable, avec numéro aléatoire et montant recalculé
  // depuis la mission. Seul generate-invoice/Factur-X peut émettre le document
  // légal à partir d'un AVOIR DB exact. Sans avoir_id dans cette action legacy,
  // l'automatisme est explicitement bloqué pour revue admin.
  return {
    ok: false,
    erreur: `AVOIR_PDF_CONFORME_REQUIERT_AVOIR_DB:${mission_id}`,
  };
}
