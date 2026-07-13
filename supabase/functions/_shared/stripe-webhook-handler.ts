import Stripe from "npm:stripe@18.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { assertStripeSecretMode, isProductionRuntime } from "./stripe-production.ts";

export type StripeWebhookSource = "PLATFORM" | "CONNECT";

type VerifiedStripeEvent = {
  event: Stripe.Event;
  source: StripeWebhookSource;
};

// Défense en profondeur : même correctement configurés dans Stripe, les deux
// endpoints n'ont pas le droit d'exécuter les branches de l'autre source.
// L'allow-list est vérifiée avant le claim et avant toute écriture métier.
const PLATFORM_EVENT_TYPES = new Set([
  "charge.dispute.closed",
  "charge.dispute.created",
  "charge.expired",
  "charge.failed",
  "charge.pending",
  "charge.refunded",
  "charge.succeeded",
  "checkout.session.expired",
  "checkout.session.completed",
  "invoice.payment_failed",
  "payment_intent.payment_failed",
  "payment_intent.succeeded",
  "transfer.created",
  "transfer.reversed",
  "transfer.updated",
]);

const CONNECT_EVENT_TYPES = new Set([
  "account.updated",
  "payout.canceled",
  "payout.created",
  "payout.failed",
  "payout.paid",
]);

function eventAllowedForSource(source: StripeWebhookSource, eventType: string): boolean {
  return source === "PLATFORM"
    ? PLATFORM_EVENT_TYPES.has(eventType)
    : CONNECT_EVENT_TYPES.has(eventType);
}

async function payoutTransferSourceIds(
  stripe: Stripe,
  payoutId: string,
  stripeAccount: string,
): Promise<string[]> {
  // Un payout automatique peut agréger plusieurs transfers. Stripe expose le
  // contenu exact via les balance transactions filtrées par payout, à lire
  // dans le contexte du compte connecté (`Stripe-Account`).
  const transferIds = new Set<string>();
  let startingAfter: string | undefined;

  while (true) {
    const page = await stripe.balanceTransactions.list(
      {
        payout: payoutId,
        limit: 100,
        ...(startingAfter ? { starting_after: startingAfter } : {}),
      },
      { stripeAccount },
    );

    for (const transaction of page.data) {
      const sourceId = typeof transaction.source === "string"
        ? transaction.source
        : transaction.source?.id;
      if (sourceId?.startsWith("tr_")) transferIds.add(sourceId);
    }

    if (!page.has_more) break;
    const last = page.data.at(-1);
    if (!last) throw new Error(`Stripe payout ${payoutId} pagination incomplete`);
    startingAfter = last.id;
  }

  return [...transferIds];
}

function stripeWebhookSecrets(): Array<{ source: StripeWebhookSource; secret: string }> {
  // STRIPE_WEBHOOK_SECRET reste un alias transitoire du secret plateforme pour
  // ne pas interrompre les paiements existants pendant la rotation. Le secret
  // Connect est toujours distinct et explicite.
  const platform = (
    Deno.env.get("STRIPE_PLATFORM_WEBHOOK_SECRET")
    || Deno.env.get("STRIPE_WEBHOOK_SECRET")
    || ""
  ).trim();
  const connect = (Deno.env.get("STRIPE_CONNECT_WEBHOOK_SECRET") || "").trim();

  if (isProductionRuntime() && (!platform || !connect)) {
    throw new Error("Both Stripe webhook secrets are required in production");
  }
  if (platform && connect && platform === connect) {
    throw new Error("Stripe webhook secrets must be distinct");
  }

  const candidates: Array<{ source: StripeWebhookSource; secret: string }> = [
    { source: "PLATFORM", secret: platform },
    { source: "CONNECT", secret: connect },
  ];
  return candidates.filter((candidate) => candidate.secret.length > 0);
}

async function verifyStripeEvent(
  stripe: Stripe,
  body: string,
  signature: string,
  expectedSource: StripeWebhookSource,
): Promise<VerifiedStripeEvent | null> {
  const candidates = stripeWebhookSecrets();
  if (!candidates.some((candidate) => candidate.source === expectedSource)) {
    throw new Error(`Stripe ${expectedSource} webhook secret missing`);
  }

  // On ne logue ni la signature, ni les erreurs intermédiaires : seule la
  // vérification cryptographique détermine quel secret a signé la livraison.
  for (const candidate of candidates) {
    try {
      const event = await stripe.webhooks.constructEventAsync(
        body,
        signature,
        candidate.secret,
      );
      return { event, source: candidate.source };
    } catch {
      // Essayer le second endpoint secret sans exposer de détail.
    }
  }
  return null;
}

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  };
}

// Audit escrow DIRECT en table (pas via le rpc fn_ecrire_audit_safe) : le
// binding PostgREST de ce RPC 9-params sérialise les uuid en « null » →
// « invalid input syntax for type uuid » → l'audit edge échouait silencieusement
// (trou d'observabilité prod découvert par la recette escrow, run #11 du
// 09/07/2026). Le service_role bypasse la RLS : l'insert direct est fiable.
async function auditEscrow(admin: any, action: string, missionId: string | null, details: unknown) {
  try {
    const { error } = await admin.from("journaux_audit").insert({
      acteur_id: "00000000-0000-0000-0000-000000000000",
      type_acteur: "SYSTEME",
      action,
      type_ressource: "mission",
      id_ressource: missionId,
      cle_s3_ressource: null,
      details: details ?? null,
      ip_acteur: null,
      navigateur_acteur: "stripe-webhook",
    });
    if (error) console.error("audit escrow webhook insert:", error.message);
  } catch (e) { console.error("audit escrow webhook throw:", e); }
}

export async function handleStripeWebhook(
  req: Request,
  expectedSource: StripeWebhookSource = "PLATFORM",
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") || "";
  try {
    assertStripeSecretMode(stripeKey);
  } catch {
    return new Response(JSON.stringify({ error: "Stripe configuration invalid" }), {
      status: 503,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }
  const stripe = new Stripe(stripeKey, {
    apiVersion: "2025-08-27.basil",
  });

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  let claimedEventId: string | null = null;

  try {
    // Verify Stripe signature
    const body = await req.text();
    const signature = req.headers.get("stripe-signature");
    if (!signature) {
      return new Response(JSON.stringify({ error: "Missing stripe-signature header" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    let verified: VerifiedStripeEvent | null;
    try {
      verified = await verifyStripeEvent(stripe, body, signature, expectedSource);
    } catch {
      console.error(`Stripe ${expectedSource} webhook secret not configured safely`);
      return new Response(JSON.stringify({ error: "Webhook configuration invalid" }), {
        status: 503,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (!verified || verified.source !== expectedSource) {
      console.error(`Stripe ${expectedSource} webhook signature rejected`);
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const { event } = verified;
    const eventAccount = event.account || null;
    if (
      (verified.source === "CONNECT" && !eventAccount)
      || (verified.source === "PLATFORM" && eventAccount)
    ) {
      console.error(`Stripe webhook source mismatch for ${verified.source}`);
      return new Response(JSON.stringify({ error: "Webhook source mismatch" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Stripe envoie également les événements TEST aux URLs Connect de
    // production. Ils doivent être acquittés sans jamais toucher la DB prod.
    if (isProductionRuntime() && event.livemode !== true) {
      console.warn(`Stripe ${verified.source} non-live event ignored: ${event.type}`);
      return new Response(JSON.stringify({ received: true, skipped: "non_live_event" }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    if (!eventAllowedForSource(verified.source, event.type)) {
      console.warn(`Stripe ${verified.source} event outside source allow-list ignored: ${event.type}`);
      return new Response(JSON.stringify({ received: true, skipped: "source_event_not_allowed" }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    console.log(`Stripe webhook received: source=${verified.source} type=${event.type} livemode=${event.livemode}`);

    // Idempotence stricte par event.id (iter4 audit fix)
    // Empêche le re-traitement si Stripe renvoie le même webhook 2x.
    const { data: claimStatus, error: idempErr } = await supabaseAdmin.rpc(
      "fn_stripe_webhook_event_claim" as never,
      {
        p_event_id: event.id,
        p_event_type: event.type,
        p_payload: event.data as unknown as Record<string, unknown>,
        p_source_webhook: verified.source,
        p_livemode: event.livemode,
      } as never,
    );
    if (idempErr) {
      throw new Error(`Idempotence claim failed: ${idempErr.message}`);
    }
    if (claimStatus === "PROCESSED") {
      console.log(`Event ${event.id} already processed, skipping`);
      return new Response(JSON.stringify({ received: true, skipped: "already_processed" }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (claimStatus === "PROCESSING") {
      return new Response(JSON.stringify({ received: false, retry: "already_processing" }), {
        status: 409,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (claimStatus !== "CLAIMED") {
      throw new Error("Idempotence claim returned an invalid state");
    }
    claimedEventId = event.id;

    // HOTFIX double transfert — fn_stripe_webhook_event_is_new répond TRUE tant
    // que traite_le est NULL, or plusieurs branches (dont CONNECT_MISSION_PAYMENT)
    // retournaient AVANT le marquage final de fin de handler. Sur un retry Stripe
    // (timeout inclus), la branche entière se ré-exécutait — y compris
    // transfers.create. Chaque return anticipé « traitement terminé » doit poser
    // traite_le via ce helper. Le catch global, lui, ne marque pas (retry voulu).
    const markEventProcessed = async () => {
      const { data, error } = await supabaseAdmin.from("stripe_webhook_events")
        .update({
          traite_le: new Date().toISOString(),
          traitement_commence_le: null,
          erreur: null,
        })
        .eq("event_id", event.id)
        .select("event_id")
        .maybeSingle();
      if (error || !data) {
        throw new Error(`Webhook completion persistence failed: ${error?.message || "event missing"}`);
      }
      claimedEventId = null;
    };

    const requireConnectedSoignantId = async (): Promise<string> => {
      if (verified.source !== "CONNECT" || !eventAccount) {
        throw new Error("Connected-account context required");
      }
      const { data, error } = await supabaseAdmin
        .from("stripe_connect_onboarding")
        .select("soignant_id")
        .eq("stripe_account_id", eventAccount)
        .maybeSingle();
      if (error || !data?.soignant_id) {
        throw new Error(
          `Connected account not linked: ${error?.message || "missing onboarding"}`,
        );
      }
      return data.soignant_id as string;
    };

    const linkExactPayoutTransfers = async (
      payoutId: string,
      connectedSoignantId: string,
    ): Promise<{ sourceIds: string[]; linked: number }> => {
      if (verified.source !== "CONNECT" || !eventAccount) {
        throw new Error("Connected-account context required for payout reconciliation");
      }
      const sourceIds = await payoutTransferSourceIds(stripe, payoutId, eventAccount);
      if (sourceIds.length === 0) return { sourceIds, linked: 0 };

      const { data, error } = await supabaseAdmin.rpc(
        "fn_stripe_lier_payout_transfers" as never,
        {
          p_stripe_payout_id: payoutId,
          p_soignant_id: connectedSoignantId,
          p_stripe_transfer_ids: sourceIds,
        } as never,
      );
      if (error) {
        throw new Error(`Exact payout transfer linkage failed: ${error.message}`);
      }
      return { sourceIds, linked: Number(data || 0) };
    };

    // Handle checkout.session.completed
    if (verified.source === "PLATFORM" && event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const metadataType = session.metadata?.type;

      // ── Connect mission payment flow ──
      if (metadataType === "CONNECT_MISSION_PAYMENT") {
        // Verify payment actually succeeded before creating transfer
        if (session.payment_status !== "paid") {
          console.warn(`CONNECT_MISSION_PAYMENT session ${session.id} not paid (status: ${session.payment_status}), skipping transfer`);
          await markEventProcessed();
          return new Response(JSON.stringify({ received: true, skipped: "not_paid" }), {
            status: 200,
            headers: { ...corsHeaders(req), "Content-Type": "application/json" },
          });
        }

        let missionId = session.metadata?.mission_id;
        let soignantId = session.metadata?.soignant_id;
        let connectedAccountId = session.metadata?.connected_account_id;
        let soignantCents = parseInt(session.metadata?.soignant_cents || "0", 10);

        // BUG-BOUCLE-PAIEMENT Fix D.2 — fallback defensive sur payment_intent.metadata.
        // Les sessions Checkout legacy (avant Fix D.1) ont les metadata critiques
        // uniquement sur payment_intent_data.metadata, pas sur session.metadata.
        // Si un champ critique manque, retrieve le payment_intent pour récupérer.
        if (!missionId || !soignantId || !connectedAccountId || !soignantCents) {
          const paymentIntentIdForLookup = typeof session.payment_intent === "string"
            ? session.payment_intent
            : session.payment_intent?.id;
          if (paymentIntentIdForLookup) {
            try {
              const pi = await stripe.paymentIntents.retrieve(paymentIntentIdForLookup);
              missionId = missionId ?? pi.metadata?.mission_id;
              soignantId = soignantId ?? pi.metadata?.soignant_id;
              connectedAccountId = connectedAccountId ?? pi.metadata?.connected_account_id;
              if (!soignantCents) {
                soignantCents = parseInt(pi.metadata?.soignant_cents || "0", 10);
              }
              console.log(`CONNECT_MISSION_PAYMENT metadata fallback depuis payment_intent ${paymentIntentIdForLookup}`);
            } catch (piErr) {
              console.error("payment_intent.retrieve fallback failed:", piErr);
            }
          }
        }

        // BUG-BOUCLE-PAIEMENT Fix D.3 — logging + audit anomalie si metadata toujours incomplet après fallback.
        // Avant ce fix, la branche était skippée silencieusement (return 200 sans UPDATE DB ni log).
        // Maintenant, on trace explicitement pour que l'admin puisse investiguer.
        if (!missionId || !soignantId || !connectedAccountId || !soignantCents) {
          const champsManquants: string[] = [];
          if (!missionId) champsManquants.push("mission_id");
          if (!soignantId) champsManquants.push("soignant_id");
          if (!connectedAccountId) champsManquants.push("connected_account_id");
          if (!soignantCents) champsManquants.push("soignant_cents");

          console.error(
            `CONNECT_METADATA_MANQUANTE session ${session.id}: champs manquants=${champsManquants.join(",")}, session.metadata=${JSON.stringify(session.metadata)}`
          );
          await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
            p_acteur_id: "00000000-0000-0000-0000-000000000000",
            p_type_acteur: "SYSTEME",
            p_action: "CONNECT_METADATA_MANQUANTE",
            p_type_ressource: "checkout_session",
            p_id_ressource: missionId ?? null,
            p_cle_s3: null,
            p_details: {
              stripe_session_id: session.id,
              stripe_payment_intent_id: typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id,
              champs_manquants: champsManquants,
              session_metadata: session.metadata,
            },
            p_ip: null,
            p_navigateur: "stripe-webhook",
          });
          throw new Error(`Paid Connect checkout metadata incomplete: ${champsManquants.join(",")}`);
        }

        if (missionId && soignantId && connectedAccountId && soignantCents > 0) {
          // HOTFIX double transfert — garde idempotente AVANT transfers.create :
          // si un transfer définitif existe déjà pour cette mission (retry Stripe
          // après timeout, ré-livraison), on ne recrée RIEN. Statuts définitifs =
          // même liste que stripe-connect-pay-mission (:271). REMBOURSE exclu :
          // un re-paiement légitime après remboursement doit pouvoir re-transférer.
          const { data: transferExistant, error: transferExistantError } = await supabaseAdmin
            .from("stripe_transfers")
            .select("statut, stripe_transfer_id")
            .eq("mission_id", missionId)
            .maybeSingle();
          if (transferExistantError) {
            throw new Error(`Transfer idempotency lookup failed: ${transferExistantError.message}`);
          }
          const transferDejaCree = Boolean(
            transferExistant?.stripe_transfer_id &&
            ["TRANSFERE", "CHARGE_REUSSI", "PAYE"].includes(transferExistant.statut)
          );

          let mouvementStripeConfirme = false;
          try {
            // Idempotency key portée par la session Checkout : un retry du même
            // event réutilise la même clé (Stripe renvoie le transfer existant au
            // lieu d'en créer un second) ; un nouveau paiement légitime (nouvelle
            // session après remboursement) a une clé différente.
            const transfer = transferDejaCree
              ? { id: transferExistant!.stripe_transfer_id as string }
              : await stripe.transfers.create({
                amount: soignantCents,
                currency: "eur",
                destination: connectedAccountId,
                transfer_group: `mission_${missionId}`,
                metadata: { mission_id: missionId, soignant_id: soignantId || "" },
              }, { idempotencyKey: `transfer_${session.id}` });
            mouvementStripeConfirme = true;
            if (transferDejaCree) {
              console.log(
                `Transfer ${transfer.id} déjà créé pour mission ${missionId}; reprise de la réconciliation locale`,
              );
            }

            // Get the actual charge ID from the payment intent
            const paymentIntentId = typeof session.payment_intent === "string" ? session.payment_intent : null;
            let chargeId: string | null = null;
            if (paymentIntentId) {
              try {
                const pi = await stripe.paymentIntents.retrieve(paymentIntentId);
                chargeId = pi.latest_charge ? (typeof pi.latest_charge === "string" ? pi.latest_charge : pi.latest_charge.id) : null;
              } catch { /* fallback to payment_intent id */ }
            }

            if (!transferDejaCree) {
              const { data: transferUpdated, error: transferUpdateError } = await supabaseAdmin
                .from("stripe_transfers")
                .update({
                  statut: "TRANSFERE",
                  stripe_transfer_id: transfer.id,
                  stripe_charge_id: chargeId || paymentIntentId,
                  stripe_payment_intent_id: paymentIntentId,
                  transfere_le: new Date().toISOString(),
                })
                .eq("mission_id", missionId)
                .select("id")
                .maybeSingle();
              if (transferUpdateError || !transferUpdated) {
                throw new Error(
                  `Transfer persistence failed after Stripe success: ${transferUpdateError?.message || "row missing"}`,
                );
              }
            }

            // BUG-BOUCLE-PAIEMENT Fix A — créer un paiements_soignant pour rendre
            // la mission comptabilisée comme "payée" côté fn_obligations_financieres.
            // Avant ce fix, le webhook ne touchait pas paiements_soignant, or la RPC
            // filtre les missions à payer via NOT EXISTS paiements_soignant → boucle.
            // Idempotent : on check d'abord si un paiement pour ce transfer existe déjà.
            const nowIso = new Date().toISOString();
            const { data: existingPayment, error: existingPaymentError } = await supabaseAdmin
              .from("paiements_soignant")
              .select("id")
              .eq("stripe_transfer_id", transfer.id)
              .maybeSingle();
            if (existingPaymentError) {
              throw new Error(`Caregiver payment reconciliation lookup failed: ${existingPaymentError.message}`);
            }

            // Fetch mission data une fois (utilisé pour paiements_soignant + facture commission)
            const { data: missionRow, error: missionRowError } = await supabaseAdmin
              .from("missions")
              .select("etablissement_id, intitule, montant_commission_ht, montant_commission_tva, montant_commission_ttc, type_contrat_applique")
              .eq("id", missionId)
              .single();
            if (missionRowError || !missionRow) {
              throw new Error(
                `Mission reconciliation lookup failed: ${missionRowError?.message || "row missing"}`,
              );
            }

            if (!existingPayment) {
              const { error: paiementInsertErr } = await supabaseAdmin
                .from("paiements_soignant")
                .insert({
                  mission_id: missionId,
                  soignant_id: soignantId,
                  etablissement_id: missionRow?.etablissement_id,
                  montant_net: soignantCents / 100,
                  methode: "NOTE_HONORAIRES",
                  reference_virement: `STRIPE-${transfer.id}`,
                  date_paiement: nowIso.split("T")[0],
                  statut: "CONFIRME",
                  confirme_par_etablissement: true,
                  confirme_par_etablissement_le: nowIso,
                  confirme_par_soignant: true,
                  confirme_par_soignant_le: nowIso,
                  stripe_transfer_id: transfer.id,
                });
              if (paiementInsertErr) {
                throw new Error(`Caregiver payment persistence failed: ${paiementInsertErr.message}`);
              }
            }

            // Mark mission: soignant paid via Connect + commission included in same payment
            const { data: missionUpdated, error: missionUpdateError } = await supabaseAdmin
              .from("missions")
              .update({
                mode_paiement_soignant: "STRIPE_CONNECT",
                commission_facturee: true,
                modifie_le: new Date().toISOString(),
              })
              .eq("id", missionId)
              .select("id")
              .maybeSingle();
            if (missionUpdateError || !missionUpdated) {
              throw new Error(
                `Mission payment reconciliation failed: ${missionUpdateError?.message || "row missing"}`,
              );
            }

            // Phase 2 Option Y — créer la facture commission PAYEE directement.
            // Commission capturée à la source par Stripe (via le split transfer :
            // charge total = honoraires soignant + commission, transfer = honoraires
            // seuls, la commission reste sur le compte plateforme). On émet donc une
            // facture commission avec statut PAYEE immédiatement pour cohérence
            // comptable étab (cf. docs/logique-paiements-v1.md §2.3).
            //
            // Idempotent : numero_facture déterministe FACT-STRIPE-YYYY-MM-DD-<mission8>
            // garantit unicité par mission ; ON CONFLICT numero_facture DO NOTHING
            // côté PostgreSQL via le check préalable.
            const commissionTtc = Number(missionRow?.montant_commission_ttc || 0);
            const commissionHt = Number(missionRow?.montant_commission_ht || 0);
            const commissionTva = Number(missionRow?.montant_commission_tva || 0);
            if (commissionTtc > 0 && missionRow?.etablissement_id) {
              const numeroFactureCommission = `FACT-STRIPE-${nowIso.split("T")[0]}-${missionId.split("-")[0]}`;
              const { data: existingFactCom, error: existingFactComError } = await supabaseAdmin
                .from("factures")
                .select("id")
                .eq("mission_id", missionId)
                .maybeSingle();
              if (existingFactComError) {
                throw new Error(`Commission invoice lookup failed: ${existingFactComError.message}`);
              }
              if (!existingFactCom) {
                const { data: factCreated, error: factErr } = await supabaseAdmin
                  .from("factures")
                  .insert({
                    etablissement_id: missionRow.etablissement_id,
                    mission_id: missionId,
                    numero_facture: numeroFactureCommission,
                    montant_ht: commissionHt,
                    montant_tva: commissionTva,
                    montant_ttc: commissionTtc,
                    taux_tva: 20,
                    nombre_missions: 1,
                    statut: "PAYEE",
                    date_emission: nowIso,
                    date_paiement: nowIso,
                    mode_paiement: "STRIPE",
                    stripe_payment_intent_id: paymentIntentId,
                    type_document: "FACTURE",
                  })
                  .select("id, numero_facture")
                  .maybeSingle();
                if (factErr || !factCreated) {
                  throw new Error(
                    `Commission invoice persistence failed: ${factErr?.message || "row missing"}`,
                  );
                } else {
                  console.log(`Facture commission ${factCreated.numero_facture} créée (PAYEE) pour mission ${missionId}`);
                  await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
                    p_acteur_id: "00000000-0000-0000-0000-000000000000",
                    p_type_acteur: "SYSTEME",
                    p_action: "FACTURE_COMMISSION_CREATED_VIA_STRIPE",
                    p_type_ressource: "facture",
                    p_id_ressource: factCreated.id,
                    p_cle_s3: null,
                    p_details: {
                      mission_id: missionId,
                      mission_intitule: missionRow.intitule,
                      etablissement_id: missionRow.etablissement_id,
                      numero_facture: factCreated.numero_facture,
                      montant_ttc: commissionTtc,
                      stripe_payment_intent_id: paymentIntentId,
                      stripe_transfer_id: transfer.id,
                    },
                    p_ip: null,
                    p_navigateur: "stripe-webhook",
                  });
                }
              }
            }

            // [CP-STRIPE-2 H1/H7/H14] Propagation du paiement vers factures_honoraires :
            // - stripe_payment_intent_id rempli pour les avoirs AUTO_STRIPE futurs
            // - transition statut EMISE/EN_RETARD → PAYEE
            // - invoke send-email PAIEMENT_RAPIDE_RECU (notif soignant)
            // Le guard `in statut EMISE/EN_RETARD` couvre H4 pour la facture honoraires
            // (une facture ANNULEE/REMPLACEE ne peut pas repasser PAYEE par ce chemin).
            const factureHonorairesId = session.metadata?.facture_honoraires_id;
            if (factureHonorairesId && paymentIntentId) {
              const { data: factureUpdated, error: factureError } = await supabaseAdmin
                .from("factures_honoraires")
                .update({
                  stripe_payment_intent_id: paymentIntentId,
                  statut: "PAYEE",
                  date_paiement: new Date().toISOString().split("T")[0],
                })
                .eq("id", factureHonorairesId)
                .in("statut", ["EMISE", "EN_RETARD"])
                .select("id, numero_facture, montant_ttc, soignant_id, mission_id")
                .maybeSingle();

              if (factureError) {
                throw new Error(`Caregiver invoice reconciliation failed: ${factureError.message}`);
              } else if (!factureUpdated) {
                const { data: factureDejaPayee, error: factureDejaPayeeError } = await supabaseAdmin
                  .from("factures_honoraires")
                  .select("statut, stripe_payment_intent_id")
                  .eq("id", factureHonorairesId)
                  .maybeSingle();
                if (factureDejaPayeeError) {
                  throw new Error(`Caregiver invoice state lookup failed: ${factureDejaPayeeError.message}`);
                }
                if (
                  factureDejaPayee?.statut !== "PAYEE"
                  || factureDejaPayee.stripe_payment_intent_id !== paymentIntentId
                ) {
                  const { error: anomalyAuditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
                    p_acteur_id: "00000000-0000-0000-0000-000000000000",
                    p_type_acteur: "SYSTEME",
                    p_action: "FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE",
                    p_type_ressource: "facture_honoraires",
                    p_id_ressource: factureHonorairesId,
                    p_cle_s3: null,
                    p_details: {
                      raison: "statut_non_modifiable",
                      mission_id: missionId,
                      stripe_payment_intent_id: paymentIntentId,
                      stripe_session_id: session.id,
                    },
                    p_ip: null,
                    p_navigateur: "stripe-webhook",
                  });
                  if (anomalyAuditError) {
                    console.error("Caregiver invoice anomaly audit failed:", anomalyAuditError.message);
                  }
                  throw new Error(
                    `Caregiver invoice ${factureHonorairesId} is not reconcilable after Stripe transfer`,
                  );
                }
                console.log(
                  `factures_honoraires ${factureHonorairesId} already reconciled for ${paymentIntentId}`,
                );
              } else {
                // Invoke send-email PAIEMENT_RAPIDE_RECU (non-bloquant)
                try {
                  const { data: soignantRow } = await supabaseAdmin
                    .from("soignants")
                    .select("prenom")
                    .eq("id", factureUpdated.soignant_id)
                    .maybeSingle();
                  const { data: soignantUser } = await supabaseAdmin.auth.admin.getUserById(
                    factureUpdated.soignant_id
                  );
                  const soignantEmail = soignantUser?.user?.email;
                  const { data: missionDetail } = await supabaseAdmin
                    .from("missions")
                    .select("intitule, etablissements(nom)")
                    .eq("id", factureUpdated.mission_id)
                    .maybeSingle();

                  if (soignantEmail) {
                    await supabaseAdmin.functions.invoke("send-email", {
                      body: {
                        type: "PAIEMENT_RAPIDE_RECU",
                        destinataire_id: factureUpdated.soignant_id,
                        destinataire_email: soignantEmail,
                        data: {
                          soignant_prenom: soignantRow?.prenom || "",
                          montant_ttc: Number(factureUpdated.montant_ttc).toFixed(2),
                          numero_facture: factureUpdated.numero_facture,
                          mission_intitule: missionDetail?.intitule || "",
                          etablissement_nom:
                            (missionDetail?.etablissements as { nom?: string } | null)?.nom || "",
                          contexte: "CONNECT_MISSION_PAYMENT",
                        },
                      },
                    });
                  }
                } catch (emailErr) {
                  // Non-bloquant — le paiement et la mise à jour facture restent valides
                  console.error("send-email PAIEMENT_RAPIDE_RECU failed:", emailErr);
                }
                console.log(
                  `factures_honoraires ${factureHonorairesId} marked PAYEE for mission ${missionId}`
                );
              }
            } else {
              console.warn(
                `CONNECT webhook: missing facture_honoraires_id or payment_intent_id (session ${session.id})`
              );
            }

            // RGPD Art. 32 : audit du transfert financier (Stripe Connect mission payment)
            await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
              p_acteur_id: soignantId || "00000000-0000-0000-0000-000000000000",
              p_type_acteur: "SYSTEME",
              p_action: "FINANCE_TRANSFER_CONNECT",
              p_type_ressource: "mission",
              p_id_ressource: missionId,
              p_cle_s3: null,
              p_details: {
                stripe_transfer_id: transfer.id,
                stripe_charge_id: chargeId,
                stripe_payment_intent_id: paymentIntentId,
                stripe_session_id: session.id,
                soignant_id: soignantId,
                connected_account_id: connectedAccountId,
                facture_honoraires_id: factureHonorairesId || null,
                montant_cents: soignantCents,
                devise: "eur",
              },
              p_ip: null,
              p_navigateur: "stripe-webhook",
            });

            console.log(`Connect transfer ${transfer.id} created for mission ${missionId}`);
          } catch (transferErr: any) {
            if (mouvementStripeConfirme) {
              const reconciliationMessage = transferErr?.message || String(transferErr);
              throw new Error(
                `Post-transfer reconciliation failed; Stripe event must retry: ${reconciliationMessage}`,
              );
            }
            // BUG-WEBHOOK-CATCH-SILENT — catch précédent mettait statut=ECHOUE
            // avec une colonne `modifie_le` INEXISTANTE dans stripe_transfers →
            // UPDATE échouait silencieusement côté PostgREST (pas de throw sans
            // .throwOnError()), et la row restait en EN_ATTENTE. Aucun audit
            // n'était écrit. Webhook retournait 200. Diagnostic impossible.
            // Observé in-situ sur M2 (pi_3TOwlQ, 22/04/2026 09:08) :
            // balance_insufficient en mode TEST → stripe.transfers.create throw
            // → catch entered → UPDATE modifie_le silently fails → M2 reste à
            // l'infini en "à payer" avec transfer EN_ATTENTE invisible côté ops.
            //
            // Fix : (1) retirer modifie_le, (2) remplir `erreur` avec code+msg
            // Stripe, (3) audit explicite STRIPE_TRANSFER_ECHOUE, (4) log loud.
            const stripeErrCode = transferErr?.code || transferErr?.raw?.code || null;
            const stripeErrMsg = transferErr?.message || String(transferErr);
            const errorLabel = stripeErrCode
              ? `${stripeErrCode} — ${stripeErrMsg}`
              : stripeErrMsg;

            console.error(
              `STRIPE_TRANSFER_ECHOUE mission=${missionId} amount_cents=${soignantCents} destination=${connectedAccountId} code=${stripeErrCode} message=${stripeErrMsg}`
            );

            const { error: updateErr } = await supabaseAdmin
              .from("stripe_transfers")
              .update({
                statut: "ECHOUE",
                erreur: errorLabel.substring(0, 2000),
              })
              .eq("mission_id", missionId);
            if (updateErr) {
              throw new Error(`Failed transfer persistence failed: ${updateErr.message}`);
            }

            const { error: transferFailureAuditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
              p_acteur_id: "00000000-0000-0000-0000-000000000000",
              p_type_acteur: "SYSTEME",
              p_action: "FINANCE_TRANSFER_FAILED",
              p_type_ressource: "stripe_transfer",
              p_id_ressource: missionId,
              p_cle_s3: null,
              p_details: {
                mission_id: missionId,
                soignant_id: soignantId,
                connected_account_id: connectedAccountId,
                stripe_session_id: session.id,
                stripe_payment_intent_id: typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id,
                montant_cents: soignantCents,
                stripe_error_code: stripeErrCode,
                stripe_error_message: stripeErrMsg,
                stripe_error_type: transferErr?.type || null,
              },
              p_ip: null,
              p_navigateur: "stripe-webhook",
            });
            if (transferFailureAuditError) {
              throw new Error(`Failed transfer audit failed: ${transferFailureAuditError.message}`);
            }
          }
        }

        await markEventProcessed();
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // ── Standard facture payment flow ──
      // Les moyens de paiement différés émettent checkout.session.completed
      // avant que les fonds soient confirmés. Seul `paid` peut solder la
      // facture ici ; payment_intent.succeeded assurera le rapprochement plus tard.
      if (session.payment_status !== "paid") {
        console.log(
          `Invoice checkout ${session.id} not paid yet (${session.payment_status}); waiting for payment_intent.succeeded`,
        );
        await markEventProcessed();
        return new Response(JSON.stringify({ received: true, skipped: "invoice_payment_not_paid" }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      const factureId = session.metadata?.facture_id;

      if (!factureId) {
        console.warn("checkout.session.completed sans facture_id dans metadata");
        await markEventProcessed();
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // C2: Idempotency guard — skip if already PAYEE
      const { data: existingFacture, error: existingFactureError } = await supabaseAdmin
        .from("factures")
        .select("statut")
        .eq("id", factureId)
        .single();
      if (existingFactureError || !existingFacture) {
        throw new Error(
          `Checkout invoice reconciliation lookup failed: ${existingFactureError?.message || "row missing"}`,
        );
      }

      if (existingFacture?.statut === "PAYEE") {
        console.log(`Facture ${factureId} already PAYEE, skipping duplicate webhook`);
        await markEventProcessed();
        return new Response(JSON.stringify({ received: true, skipped: "already_paid" }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // [CP-STRIPE-3 H4] Update facture to PAYEE avec guard statut explicite.
      // Autrefois : .neq("statut", "PAYEE") — laissait passer ANNULEE/REMPLACEE/BROUILLON
      // qui pouvaient être marqués PAYEE si un webhook arrivait après annulation admin.
      // Désormais : .in("statut", ["EMISE","EN_RETARD"]) bloque ces cas. Si
      // aucune ligne n'est mise à jour après capture Stripe, l'événement reste
      // retryable jusqu'à résolution de l'anomalie comptable.
      const { data: factureUpdated, error: updateErr } = await supabaseAdmin
        .from("factures")
        .update({
          statut: "PAYEE",
          date_paiement: new Date().toISOString(),
          stripe_payment_intent_id: session.payment_intent as string,
          stripe_hosted_url: session.url,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", factureId)
        .in("statut", ["EMISE", "EN_RETARD"])
        .select("id, numero_facture, etablissement_id, montant_ttc")
        .maybeSingle();

      if (updateErr) {
        console.error("Erreur mise à jour facture:", updateErr);
        throw updateErr;
      }

      if (!factureUpdated) {
        // Anomalie : paiement Stripe capturé mais facture dans statut invalide
        // (ANNULEE/REMPLACEE/BROUILLON). Le paiement est côté Stripe mais rien
        // ne peut être comptabilisé côté plateforme. À investiguer manuellement.
        console.warn(
          `FACTURE webhook: facture ${factureId} not in EMISE/EN_RETARD, skipped (status may be ANNULEE/REMPLACEE)`
        );
        const { data: factureInvalide, error: factureInvalideError } = await supabaseAdmin
          .from("factures")
          .select("statut, etablissement_id")
          .eq("id", factureId)
          .maybeSingle();
        if (factureInvalideError) {
          throw new Error(`Invalid invoice state lookup failed: ${factureInvalideError.message}`);
        }
        const { error: invalidFactureAuditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: factureInvalide?.etablissement_id || "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: "FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE",
          p_type_ressource: "facture",
          p_id_ressource: factureId,
          p_cle_s3: null,
          p_details: {
            raison: "statut_non_modifiable",
            statut_actuel: factureInvalide?.statut || "inconnu",
            stripe_session_id: session.id,
            stripe_payment_intent: session.payment_intent,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        });
        if (invalidFactureAuditError) {
          console.error("Invalid invoice state audit failed:", invalidFactureAuditError.message);
        }
        throw new Error(
          `Captured checkout cannot reconcile invoice ${factureId} in status ${factureInvalide?.statut || "missing"}`,
        );
      }

      // Alias pour la suite du bloc (audit + email) — factureUpdated tient déjà
      // numero_facture, etablissement_id, montant_ttc grâce au .select() ci-dessus.
      const facture = factureUpdated;

      // Write audit log
      if (facture) {
        await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: facture.etablissement_id,
          p_type_acteur: "SYSTEME",
          p_action: "FINANCE_FACTURE_PAYEE",
          p_type_ressource: "facture",
          p_id_ressource: factureId,
          p_cle_s3: null,
          p_details: {
            numero_facture: facture.numero_facture,
            montant_ttc: facture.montant_ttc,
            stripe_session_id: session.id,
            stripe_payment_intent: session.payment_intent,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        });

        // M6: Send FACTURE_PAYEE email
        {
          const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
          const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
          await fetch(`${supabaseUrl}/functions/v1/send-email`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${serviceRoleKey}`,
            },
            body: JSON.stringify({
              type: "FACTURE_PAYEE",
              destinataire_id: facture.etablissement_id,
              data: {
                numero: facture.numero_facture,
                montant_ttc: (facture.montant_ttc ?? 0).toFixed(2),
                date_paiement: new Date().toLocaleDateString("fr-FR"),
                facture_id: factureId,
              },
            }),
          }).catch((err: unknown) => console.error("Email FACTURE_PAYEE error:", err));
        }
      }
    }

    // ── Escrow 7b-D (PR 3) : débit escrow confirmé → DEBITE ──
    // Destination charge SEPA (escrow-debit-echeance) : `processing` → `succeeded`
    // quelques jours après. INITIE → DEBITE. La disponibilité réelle des fonds
    // (available sur le solde connecté) est vérifiée séparément au release (A3).
    if (verified.source === "PLATFORM" && event.type === "payment_intent.succeeded"
        && (event.data.object as Stripe.PaymentIntent).metadata?.type === "ESCROW_MISSION_PAYMENT") {
      const pi = event.data.object as Stripe.PaymentIntent;
      const escrowId = pi.metadata?.paiement_escrow_id;
      if (escrowId) {
        const chargeId = pi.latest_charge
          ? (typeof pi.latest_charge === "string" ? pi.latest_charge : pi.latest_charge.id)
          : null;
        // Garde de statut : ne repasse DEBITE que depuis INITIE (idempotent,
        // n'écrase pas un REMBOURSE/DISPUTE arrivé entre-temps).
        const { data: updated, error: escrowDebitError } = await supabaseAdmin
          .from("paiements_escrow")
          .update({
            statut: "DEBITE",
            stripe_charge_id: chargeId,
            debite_le: new Date().toISOString(),
            erreur: null,
            modifie_le: new Date().toISOString(),
          })
          .eq("id", escrowId)
          .eq("statut", "INITIE")
          .select("id, mission_id, etablissement_id")
          .maybeSingle();
        if (escrowDebitError) {
          throw new Error(`Escrow debit reconciliation failed: ${escrowDebitError.message}`);
        }

        await auditEscrow(supabaseAdmin, "ESCROW_DEBITE", pi.metadata?.mission_id ?? null, {
          paiement_escrow_id: escrowId,
          stripe_payment_intent_id: pi.id,
          stripe_charge_id: chargeId,
          deja_traite: !updated,
        });
      }
      await markEventProcessed();
      return new Response(JSON.stringify({ received: true, escrow: "debite" }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // ── Escrow 7b-D (PR 3) : échec de débit → incident (gel ⚡ + relance J+3) ──
    if (verified.source === "PLATFORM" && event.type === "payment_intent.payment_failed"
        && (event.data.object as Stripe.PaymentIntent).metadata?.type === "ESCROW_MISSION_PAYMENT") {
      const pi = event.data.object as Stripe.PaymentIntent;
      const escrowId = pi.metadata?.paiement_escrow_id;
      if (escrowId) {
        const failMsg = pi.last_payment_error?.message
          || pi.last_payment_error?.code
          || "payment_intent.payment_failed";
        const { error: escrowIncidentError } = await supabaseAdmin.rpc("fn_escrow_marquer_incident", {
          p_paiement_escrow_id: escrowId,
          p_type_incident: "ECHEC",
          p_detail: String(failMsg).substring(0, 500),
        });
        if (escrowIncidentError) {
          throw new Error(`Escrow payment failure reconciliation failed: ${escrowIncidentError.message}`);
        }
      }
      await markEventProcessed();
      return new Response(JSON.stringify({ received: true, escrow: "echec" }), {
        status: 200,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Handle payment_intent.succeeded (backup reconciliation)
    if (verified.source === "PLATFORM" && event.type === "payment_intent.succeeded") {
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      let factureId = paymentIntent.metadata?.facture_id;

      if (!factureId) {
        const { data: factureByPaymentIntent, error: factureLookupError } = await supabaseAdmin
          .from("factures")
          .select("id")
          .eq("stripe_payment_intent_id", paymentIntent.id)
          .maybeSingle();
        if (factureLookupError) {
          throw new Error(`PaymentIntent invoice lookup failed: ${factureLookupError.message}`);
        }

        factureId = factureByPaymentIntent?.id;
      }

      if (factureId) {
        const { data: paymentIntentFactureUpdated, error: paymentIntentFactureError } = await supabaseAdmin
          .from("factures")
          .update({
            statut: "PAYEE",
            date_paiement: new Date().toISOString(),
            stripe_payment_intent_id: paymentIntent.id,
            modifie_le: new Date().toISOString(),
          })
          .eq("id", factureId)
          .in("statut", ["EMISE", "EN_RETARD"])
          .select("id")
          .maybeSingle();
        if (paymentIntentFactureError) {
          throw new Error(`PaymentIntent invoice reconciliation failed: ${paymentIntentFactureError.message}`);
        }
        if (!paymentIntentFactureUpdated) {
          const { data: factureDejaReconcilee, error: factureStateError } = await supabaseAdmin
            .from("factures")
            .select("statut, stripe_payment_intent_id")
            .eq("id", factureId)
            .maybeSingle();
          if (factureStateError) {
            throw new Error(`PaymentIntent invoice state lookup failed: ${factureStateError.message}`);
          }
          if (
            factureDejaReconcilee?.statut !== "PAYEE"
            || factureDejaReconcilee.stripe_payment_intent_id !== paymentIntent.id
          ) {
            throw new Error(`PaymentIntent ${paymentIntent.id} cannot reconcile invoice ${factureId}`);
          }
        }
      } else {
        console.warn(`payment_intent.succeeded without facture mapping: ${paymentIntent.id}`);
      }
    }

    // Handle SEPA debit charge succeeded
    if (verified.source === "PLATFORM" && event.type === "charge.succeeded") {
      const charge = event.data.object as Stripe.Charge;
      if (charge.payment_method_details?.type === "sepa_debit") {
        const missionId = charge.metadata?.mission_id;
        if (missionId) {
          // Fetch the etablissement before updating to capture it in audit
          const { data: mission, error: missionLookupError } = await supabaseAdmin
            .from("missions")
            .select("etablissement_id")
            .eq("id", missionId)
            .single();
          if (missionLookupError || !mission) {
            throw new Error(
              `SEPA mission lookup failed: ${missionLookupError?.message || "row missing"}`,
            );
          }

          const { error: paymentCaptureError } = await supabaseAdmin
            .from("paiements_mission")
            .update({
              statut: "CAPTURE",
              capture_le: new Date().toISOString(),
              stripe_charge_id: charge.id,
            })
            .eq("mission_id", missionId)
            .eq("statut", "EN_ATTENTE");
          if (paymentCaptureError) {
            throw new Error(`SEPA payment reconciliation failed: ${paymentCaptureError.message}`);
          }

          // Mark commission as invoiced
          const { data: commissionMissionUpdated, error: commissionMissionError } = await supabaseAdmin
            .from("missions")
            .update({ commission_facturee: true, modifie_le: new Date().toISOString() })
            .eq("id", missionId)
            .select("id")
            .maybeSingle();
          if (commissionMissionError || !commissionMissionUpdated) {
            throw new Error(
              `SEPA mission reconciliation failed: ${commissionMissionError?.message || "row missing"}`,
            );
          }

          // RGPD Art. 32 : audit du prélèvement SEPA
          if (mission?.etablissement_id) {
            await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
              p_acteur_id: mission.etablissement_id,
              p_type_acteur: "SYSTEME",
              p_action: "FINANCE_SEPA_CAPTURE",
              p_type_ressource: "mission",
              p_id_ressource: missionId,
              p_cle_s3: null,
              p_details: {
                stripe_charge_id: charge.id,
                montant_cents: charge.amount,
                devise: charge.currency,
                payment_method: "sepa_debit",
              },
              p_ip: null,
              p_navigateur: "stripe-webhook",
            });
          }

          console.log(`SEPA charge captured for mission ${missionId}`);
        }
      }
    }

    // Handle invoice.payment_failed
    if (verified.source === "PLATFORM" && event.type === "invoice.payment_failed") {
      const invoice = event.data.object as Stripe.Invoice;
      const stripeInvoiceId = invoice.id;

      const { error: failErr } = await supabaseAdmin
        .from("factures")
        .update({
          statut: "EN_RETARD",
          modifie_le: new Date().toISOString(),
        })
        .eq("stripe_invoice_id", stripeInvoiceId);

      if (failErr) {
        throw new Error(`Invoice failure reconciliation failed: ${failErr.message}`);
      }
    }

    // Handle checkout.session.expired — clean up EN_ATTENTE transfers
    if (verified.source === "PLATFORM" && event.type === "checkout.session.expired") {
      const expiredSession = event.data.object as Stripe.Checkout.Session;
      const expiredMissionId = expiredSession.metadata?.mission_id;
      const expiredType = expiredSession.metadata?.type;

      if (expiredType === "CONNECT_MISSION_PAYMENT" && expiredMissionId) {
        // Reset the transfer so user can retry
        const { error: checkoutExpiryError } = await supabaseAdmin
          .from("stripe_transfers")
          .update({ statut: "ECHOUE", erreur: "Checkout expiré" })
          .eq("mission_id", expiredMissionId)
          .eq("statut", "EN_ATTENTE");
        if (checkoutExpiryError) {
          throw new Error(`Expired checkout reconciliation failed: ${checkoutExpiryError.message}`);
        }

        console.log(`Connect checkout expired for mission ${expiredMissionId}, transfer reset to ECHOUE`);
      }

      // For facture payments, just log — the facture stays EMISE
      const expiredFactureId = expiredSession.metadata?.facture_id;
      if (expiredFactureId) {
        console.log(`Facture checkout expired for ${expiredFactureId}`);
      }
    }

    // Handle account.updated (Connect onboarding status)
    if (verified.source === "CONNECT" && event.type === "account.updated") {
      const account = event.data.object as Stripe.Account;
      const accountId = account.id;
      if (!eventAccount || accountId !== eventAccount) {
        throw new Error("Connect account.updated object/account mismatch");
      }

      let statut = "EN_COURS";
      if (account.details_submitted && account.charges_enabled && account.payouts_enabled) {
        statut = "COMPLET";
      } else if (account.requirements?.disabled_reason) {
        statut = "SUSPENDU";
      }

      let ibanLast4: string | null = null;
      if (account.external_accounts?.data?.length) {
        const bankAccount = account.external_accounts.data[0];
        if ("last4" in bankAccount) {
          ibanLast4 = bankAccount.last4 as string;
        }
      }

      const { data: onboardingUpdated, error: onboardingUpdateError } = await supabaseAdmin
        .from("stripe_connect_onboarding")
        .update({
          statut,
          charges_enabled: account.charges_enabled ?? false,
          payouts_enabled: account.payouts_enabled ?? false,
          details_submitted: account.details_submitted ?? false,
          iban_last4: ibanLast4,
          modifie_le: new Date().toISOString(),
        })
        .eq("stripe_account_id", accountId)
        .select("id")
        .maybeSingle();
      if (onboardingUpdateError || !onboardingUpdated) {
        // account.updated peut arriver avant la fin de l'upsert local lors d'un
        // onboarding. Le 500 force Stripe à retenter au lieu de perdre l'état.
        throw new Error(
          `Connect onboarding persistence failed: ${onboardingUpdateError?.message || "account not linked"}`,
        );
      }

      console.log(`Connect account ${accountId} updated to ${statut}`);
    }

    // ============================================================
    // [CP-STRIPE-4] 13 events Stripe supplémentaires (H6)
    // Ordre : critiques (dispute, fail) → importants (paid, reversed, canceled)
    //         → informatifs (created, updated, pending, expired)
    // ============================================================

    // ── charge.failed : paiement étab échoué ──
    if (verified.source === "PLATFORM" && event.type === "charge.failed") {
      const charge = event.data.object as Stripe.Charge;
      const paymentIntentId = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent?.id;
      if (paymentIntentId) {
        const { data: facture, error: failedChargeLookupError } = await supabaseAdmin
          .from("factures")
          .select("id, numero_facture, etablissement_id, montant_ttc, statut")
          .eq("stripe_payment_intent_id", paymentIntentId)
          .maybeSingle();
        if (failedChargeLookupError) {
          throw new Error(`Failed charge invoice lookup failed: ${failedChargeLookupError.message}`);
        }

        if (facture && facture.statut !== "PAYEE") {
          const { data: failedChargeUpdated, error: failedChargeUpdateError } = await supabaseAdmin
            .from("factures")
            .update({ statut: "EN_RETARD", modifie_le: new Date().toISOString() })
            .eq("id", facture.id)
            .neq("statut", "PAYEE")
            .select("id")
            .maybeSingle();
          if (failedChargeUpdateError) {
            throw new Error(`Failed charge invoice reconciliation failed: ${failedChargeUpdateError.message}`);
          }
          if (!failedChargeUpdated) {
            const { data: concurrentFacture, error: concurrentFactureError } = await supabaseAdmin
              .from("factures")
              .select("statut")
              .eq("id", facture.id)
              .maybeSingle();
            if (concurrentFactureError) {
              throw new Error(`Failed charge invoice state lookup failed: ${concurrentFactureError.message}`);
            }
            if (concurrentFacture?.statut !== "PAYEE") {
              throw new Error(`Failed charge cannot reconcile invoice ${facture.id}`);
            }
          }

          // Notif étab
          try {
            await supabaseAdmin.functions.invoke("send-email", {
              body: {
                type: "CHARGE_FAILED_ETAB",
                destinataire_id: facture.etablissement_id,
                data: {
                  numero_facture: facture.numero_facture,
                  montant_ttc: Number(facture.montant_ttc || 0).toFixed(2),
                  failure_message: charge.failure_message || "Erreur carte",
                  failure_code: charge.failure_code || "",
                },
              },
            });
          } catch (emailErr) {
            console.error("send-email CHARGE_FAILED_ETAB failed:", emailErr);
          }
        }

        const { error: failedChargeAuditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: facture?.etablissement_id || "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: "FINANCE_CHARGE_FAILED",
          p_type_ressource: "facture",
          p_id_ressource: facture?.id || null,
          p_cle_s3: null,
          p_details: {
            stripe_charge_id: charge.id,
            stripe_payment_intent_id: paymentIntentId,
            failure_code: charge.failure_code,
            failure_message: charge.failure_message,
            amount: charge.amount,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        });
        if (failedChargeAuditError) {
          throw new Error(`Failed charge audit failed: ${failedChargeAuditError.message}`);
        }
      }
      console.log(`charge.failed handled: ${charge.id}`);
    }

    // ── charge.dispute.created : chargeback étab ──
    if (verified.source === "PLATFORM" && event.type === "charge.dispute.created") {
      const dispute = event.data.object as Stripe.Dispute;
      const chargeId = typeof dispute.charge === "string" ? dispute.charge : dispute.charge?.id;

      // Escrow 7b-D (PR 3) : une dispute sur une charge escrow → incident
      // (gel ⚡ de l'établissement). La dispute SEPA est absorbée par Jolene
      // sous le plafond A2 (§11.1) ; le circuit contentieux suit son cours.
      const { data: escrowDispute, error: escrowDisputeLookupError } = await supabaseAdmin
        .from("paiements_escrow")
        .select("id, mission_id")
        .eq("stripe_charge_id", chargeId)
        .maybeSingle();
      if (escrowDisputeLookupError) {
        throw new Error(`Dispute escrow lookup failed: ${escrowDisputeLookupError.message}`);
      }
      if (escrowDispute) {
        const { error: escrowDisputeIncidentError } = await supabaseAdmin.rpc("fn_escrow_marquer_incident", {
          p_paiement_escrow_id: escrowDispute.id,
          p_type_incident: "DISPUTE",
          p_detail: `dispute ${dispute.id} reason=${dispute.reason}`,
        });
        if (escrowDisputeIncidentError) {
          throw new Error(`Dispute escrow incident persistence failed: ${escrowDisputeIncidentError.message}`);
        }
      }

      const { data: transfer, error: disputeTransferLookupError } = await supabaseAdmin
        .from("stripe_transfers")
        .select("id, mission_id, soignant_id, etablissement_id, dispute_id")
        .eq("stripe_charge_id", chargeId)
        .maybeSingle();
      if (disputeTransferLookupError) {
        throw new Error(`Dispute transfer lookup failed: ${disputeTransferLookupError.message}`);
      }

      if (transfer && !transfer.dispute_id) {
        const evidenceDueBy = dispute.evidence_details?.due_by
          ? new Date(dispute.evidence_details.due_by * 1000).toISOString()
          : null;

        const { data: disputeTransferUpdated, error: disputeTransferUpdateError } = await supabaseAdmin
          .from("stripe_transfers")
          .update({
            dispute_id: dispute.id,
            dispute_statut: "OUVERT",
            dispute_reason: dispute.reason,
            dispute_cree_le: new Date().toISOString(),
          })
          .eq("id", transfer.id)
          .select("id")
          .maybeSingle();
        if (disputeTransferUpdateError || !disputeTransferUpdated) {
          throw new Error(
            `Dispute transfer persistence failed: ${disputeTransferUpdateError?.message || "row missing"}`,
          );
        }

        // Notif admin URGENT (tous les admins)
        const { data: admins, error: disputeAdminsError } = await supabaseAdmin.rpc("fn_list_admin_user_ids");
        if (disputeAdminsError) {
          console.error("Admin lookup for dispute notification failed:", disputeAdminsError.message);
        }
        for (const adminId of (admins || []) as string[]) {
          try {
            await supabaseAdmin.functions.invoke("send-email", {
              body: {
                type: "DISPUTE_OUVERTE_ADMIN",
                destinataire_id: adminId,
                data: {
                  dispute_id: dispute.id,
                  mission_id: transfer.mission_id,
                  montant: (dispute.amount / 100).toFixed(2),
                  reason: dispute.reason,
                  evidence_due_by: evidenceDueBy ? new Date(evidenceDueBy).toLocaleDateString("fr-FR") : "—",
                },
              },
            });
          } catch (emailErr) {
            console.error("send-email DISPUTE_OUVERTE_ADMIN failed:", emailErr);
          }
        }
      }

      const { error: disputeCreatedAuditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: transfer?.etablissement_id || "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_DISPUTE_OUVERTE",
        p_type_ressource: "mission",
        p_id_ressource: transfer?.mission_id || null,
        p_cle_s3: null,
        p_details: {
          dispute_id: dispute.id,
          stripe_charge_id: chargeId,
          reason: dispute.reason,
          amount: dispute.amount,
          status: dispute.status,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      if (disputeCreatedAuditError) {
        throw new Error(`Dispute creation audit failed: ${disputeCreatedAuditError.message}`);
      }
      console.log(`charge.dispute.created handled: ${dispute.id}`);
    }

    // ── charge.dispute.closed : dispute résolu ──
    if (verified.source === "PLATFORM" && event.type === "charge.dispute.closed") {
      const dispute = event.data.object as Stripe.Dispute;
      const { data: transfer, error: closedDisputeLookupError } = await supabaseAdmin
        .from("stripe_transfers")
        .select("id, mission_id, etablissement_id")
        .eq("dispute_id", dispute.id)
        .maybeSingle();
      if (closedDisputeLookupError) {
        throw new Error(`Closed dispute transfer lookup failed: ${closedDisputeLookupError.message}`);
      }

      if (transfer) {
        const { data: closedDisputeUpdated, error: closedDisputeUpdateError } = await supabaseAdmin
          .from("stripe_transfers")
          .update({ dispute_statut: `CLOS_${dispute.status}` })
          .eq("id", transfer.id)
          .select("id")
          .maybeSingle();
        if (closedDisputeUpdateError || !closedDisputeUpdated) {
          throw new Error(
            `Closed dispute persistence failed: ${closedDisputeUpdateError?.message || "row missing"}`,
          );
        }

        const { data: admins, error: closedDisputeAdminsError } = await supabaseAdmin.rpc("fn_list_admin_user_ids");
        if (closedDisputeAdminsError) {
          console.error("Admin lookup for closed-dispute notification failed:", closedDisputeAdminsError.message);
        }
        for (const adminId of (admins || []) as string[]) {
          try {
            await supabaseAdmin.functions.invoke("send-email", {
              body: {
                type: "DISPUTE_CLOSE_ADMIN",
                destinataire_id: adminId,
                data: {
                  dispute_id: dispute.id,
                  dispute_status: dispute.status,
                  mission_id: transfer.mission_id,
                  montant: (dispute.amount / 100).toFixed(2),
                },
              },
            });
          } catch (emailErr) {
            console.error("send-email DISPUTE_CLOSE_ADMIN failed:", emailErr);
          }
        }
      }

      const { error: disputeClosedAuditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: transfer?.etablissement_id || "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_DISPUTE_CLOSE",
        p_type_ressource: "mission",
        p_id_ressource: transfer?.mission_id || null,
        p_cle_s3: null,
        p_details: { dispute_id: dispute.id, status: dispute.status, amount: dispute.amount },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      if (disputeClosedAuditError) {
        throw new Error(`Dispute closure audit failed: ${disputeClosedAuditError.message}`);
      }
      console.log(`charge.dispute.closed handled: ${dispute.id} → ${dispute.status}`);
    }

    // ── charge.refunded : refund exécuté (fondations CP-STRIPE-5) ──
    if (verified.source === "PLATFORM" && event.type === "charge.refunded") {
      const charge = event.data.object as Stripe.Charge;
      const paymentIntentId = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent?.id;

      // Si ligne dans stripe_refunds_queue, la marquer TRAITE
      if (paymentIntentId) {
        const { error: refundQueueError } = await supabaseAdmin
          .from("stripe_refunds_queue")
          .update({ statut: "TRAITE", traite_le: new Date().toISOString() })
          .eq("stripe_payment_intent_id", paymentIntentId)
          .in("statut", ["EN_ATTENTE", "EN_COURS"]);
        if (refundQueueError) {
          throw new Error(`Refund queue reconciliation failed: ${refundQueueError.message}`);
        }

        // Si facture_honoraires AVOIR liée : marquer REMBOURSEE
        const { error: creditNoteRefundError } = await supabaseAdmin
          .from("factures_honoraires")
          .update({
            statut: "REMBOURSEE",
            date_remboursement: new Date().toISOString(),
            reference_remboursement: charge.id,
          })
          .eq("stripe_payment_intent_id", paymentIntentId)
          .eq("type_document", "AVOIR")
          .in("statut", ["EMISE", "EN_RETARD"]);
        if (creditNoteRefundError) {
          throw new Error(`Credit-note refund reconciliation failed: ${creditNoteRefundError.message}`);
        }
      }

      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_CHARGE_REFUNDED",
        p_type_ressource: "charge",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: {
          stripe_charge_id: charge.id,
          stripe_payment_intent_id: paymentIntentId,
          amount_refunded: charge.amount_refunded,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`charge.refunded handled: ${charge.id}`);
    }

    // ── transfer.reversed : transfer annulé ──
    if (verified.source === "PLATFORM" && event.type === "transfer.reversed") {
      const transfer = event.data.object as Stripe.Transfer;
      const { data: row, error: reversedTransferLookupError } = await supabaseAdmin
        .from("stripe_transfers")
        .select("id, mission_id, soignant_id, etablissement_id")
        .eq("stripe_transfer_id", transfer.id)
        .maybeSingle();
      if (reversedTransferLookupError) {
        throw new Error(`Reversed transfer lookup failed: ${reversedTransferLookupError.message}`);
      }

      if (row) {
        const { error: reversedTransferError } = await supabaseAdmin
          .from("stripe_transfers")
          .update({
            statut: "REMBOURSE",
            reversed_le: new Date().toISOString(),
          })
          .eq("id", row.id);
        if (reversedTransferError) {
          throw new Error(`Reversed transfer reconciliation failed: ${reversedTransferError.message}`);
        }
      }

      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: row?.soignant_id || "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_TRANSFER_REVERSED",
        p_type_ressource: "mission",
        p_id_ressource: row?.mission_id || null,
        p_cle_s3: null,
        p_details: { stripe_transfer_id: transfer.id, amount: transfer.amount },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`transfer.reversed handled: ${transfer.id}`);
    }

    // ── transfer.created : audit only ──
    if (verified.source === "PLATFORM" && event.type === "transfer.created") {
      const transfer = event.data.object as Stripe.Transfer;
      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_TRANSFER_CREATED",
        p_type_ressource: "transfer",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: {
          stripe_transfer_id: transfer.id,
          destination: transfer.destination,
          amount: transfer.amount,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`transfer.created audited: ${transfer.id}`);
    }

    // ── transfer.updated : audit only ──
    if (verified.source === "PLATFORM" && event.type === "transfer.updated") {
      const transfer = event.data.object as Stripe.Transfer;
      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_TRANSFER_UPDATED",
        p_type_ressource: "transfer",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: { stripe_transfer_id: transfer.id, metadata: transfer.metadata },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`transfer.updated audited: ${transfer.id}`);
    }

    // ── payout.created : lier exactement les transfers agrégés ──
    if (verified.source === "CONNECT" && event.type === "payout.created") {
      const payout = event.data.object as Stripe.Payout;
      const connectedSoignantId = await requireConnectedSoignantId();
      // Les payouts escrow ont leur lien exact dans leurs metadata +
      // paiements_escrow.stripe_payout_id. Les payouts automatiques legacy sont
      // rapprochés via les balance transactions du payout, jamais par un UPDATE
      // global des lignes dont stripe_payout_id serait NULL.
      const linkage = payout.metadata?.type === "ESCROW_RELEASE"
        ? { sourceIds: [] as string[], linked: 0 }
        : await linkExactPayoutTransfers(payout.id, connectedSoignantId);
      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_PAYOUT_CREATED",
        p_type_ressource: "payout",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: {
          stripe_payout_id: payout.id,
          stripe_account_id: eventAccount,
          soignant_id: connectedSoignantId,
          amount: payout.amount,
          arrival_date: payout.arrival_date,
          destination: payout.destination,
          transfer_source_ids: linkage.sourceIds,
          transfers_linked: linkage.linked,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`payout.created audited: ${payout.id}`);
    }

    // ── payout.paid : argent arrivé sur compte soignant ──
    if (verified.source === "CONNECT" && event.type === "payout.paid") {
      const payout = event.data.object as Stripe.Payout;
      const connectedSoignantId = await requireConnectedSoignantId();

      // Payout escrow : confirmation atomique et exacte par escrow + payout +
      // compte Connect. C'est ici seulement que l'escrow devient PAYE.
      if (payout.metadata?.type === "ESCROW_RELEASE") {
        const escrowId = payout.metadata?.paiement_escrow_id;
        if (!escrowId || !eventAccount) {
          throw new Error("ESCROW_RELEASE payout metadata incomplete");
        }
        const payeLe = payout.arrival_date
          ? new Date(payout.arrival_date * 1000).toISOString()
          : new Date().toISOString();
        const { data: transitioned, error: transitionError } = await supabaseAdmin.rpc(
          "fn_escrow_confirmer_payout" as never,
          {
            p_paiement_escrow_id: escrowId,
            p_stripe_payout_id: payout.id,
            p_stripe_account_id: eventAccount,
            p_paye_le: payeLe,
          } as never,
        );
        if (transitionError) {
          throw new Error(`Escrow payout confirmation failed: ${transitionError.message}`);
        }

        const { error: auditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: "ESCROW_RELEASE_PAYE",
          p_type_ressource: "mission",
          p_id_ressource: payout.metadata?.mission_id ?? null,
          p_cle_s3: null,
          p_details: {
            paiement_escrow_id: payout.metadata?.paiement_escrow_id ?? null,
            stripe_payout_id: payout.id,
            stripe_account_id: eventAccount,
            soignant_id: connectedSoignantId,
            arrival_date: payout.arrival_date,
            transitioned: transitioned === true,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        });
        if (auditError) {
          throw new Error(`Escrow payout audit failed: ${auditError.message}`);
        }
        await markEventProcessed();
        return new Response(JSON.stringify({ received: true, escrow: "payout_paid" }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // Legacy : Stripe donne la composition exacte du payout par balance
      // transaction. On persiste d'abord ces liens atomiquement, puis on ne
      // transitionne que les lignes de ce payout et de ce compte Connect.
      const linkage = await linkExactPayoutTransfers(payout.id, connectedSoignantId);
      const { data: transfersToMark, error: transfersToMarkError } = await supabaseAdmin
        .from("stripe_transfers")
        .update({
          statut: "PAYE",
          stripe_payout_id: payout.id,
          paye_le: payout.arrival_date ? new Date(payout.arrival_date * 1000).toISOString() : new Date().toISOString(),
        })
        .eq("stripe_payout_id", payout.id)
        .eq("soignant_id", connectedSoignantId)
        .eq("statut", "TRANSFERE")
        .select("id, soignant_id, montant_soignant, mission_id");
      if (transfersToMarkError) {
        throw new Error(`Legacy payout reconciliation failed: ${transfersToMarkError.message}`);
      }

      // Notif soignant pour chaque transfer matched
      for (const t of (transfersToMark || []) as Array<{
        id: string;
        soignant_id: string;
        montant_soignant: number;
        mission_id: string;
      }>) {
        try {
          const { data: soignantRow } = await supabaseAdmin
            .from("soignants")
            .select("prenom")
            .eq("id", t.soignant_id)
            .maybeSingle();
          const { data: soignantUser } = await supabaseAdmin.auth.admin.getUserById(t.soignant_id);
          const soignantEmail = soignantUser?.user?.email;
          if (soignantEmail) {
            await supabaseAdmin.functions.invoke("send-email", {
              body: {
                type: "PAIEMENT_RAPIDE_RECU",
                destinataire_id: t.soignant_id,
                destinataire_email: soignantEmail,
                data: {
                  contexte: "CONNECT_PAYOUT_PAID",
                  soignant_prenom: soignantRow?.prenom || "",
                  montant_ttc: Number(t.montant_soignant).toFixed(2),
                  iban_last4: "",
                  arrival_date: payout.arrival_date
                    ? new Date(payout.arrival_date * 1000).toLocaleDateString("fr-FR")
                    : "aujourd'hui",
                },
              },
            });
          }
        } catch (emailErr) {
          console.error("send-email PAIEMENT_RAPIDE_RECU (payout.paid) failed:", emailErr);
        }
      }

      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_PAYOUT_PAID",
        p_type_ressource: "payout",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: {
          stripe_payout_id: payout.id,
          amount: payout.amount,
          arrival_date: payout.arrival_date,
          transfer_source_ids: linkage.sourceIds,
          transfers_linked: linkage.linked,
          transfers_marked: (transfersToMark || []).length,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`payout.paid handled: ${payout.id} → ${(transfersToMark || []).length} transfers marked PAYE`);
    }

    // ── payout.failed : payout échoué (RIB invalide, compte fermé, etc.) ──
    if (verified.source === "CONNECT" && event.type === "payout.failed") {
      const payout = event.data.object as Stripe.Payout;
      const connectedSoignantId = await requireConnectedSoignantId();
      const errMsg = payout.failure_message || "payout.failed";

      if (payout.metadata?.type === "ESCROW_RELEASE") {
        const escrowId = payout.metadata?.paiement_escrow_id;
        if (!escrowId || !eventAccount) {
          throw new Error("ESCROW_RELEASE payout metadata incomplete");
        }
        const detail = `${payout.failure_code || "payout_failed"} — ${errMsg}`;
        const { data: transitioned, error: transitionError } = await supabaseAdmin.rpc(
          "fn_escrow_echouer_payout" as never,
          {
            p_paiement_escrow_id: escrowId,
            p_stripe_payout_id: payout.id,
            p_stripe_account_id: eventAccount,
            p_detail: detail,
          } as never,
        );
        if (transitionError) {
          throw new Error(`Escrow payout failure persistence failed: ${transitionError.message}`);
        }
        const { error: auditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: "ESCROW_RELEASE_ECHOUE",
          p_type_ressource: "mission",
          p_id_ressource: payout.metadata?.mission_id ?? null,
          p_cle_s3: null,
          p_details: {
            paiement_escrow_id: escrowId,
            stripe_payout_id: payout.id,
            stripe_account_id: eventAccount,
            soignant_id: connectedSoignantId,
            failure_code: payout.failure_code,
            transitioned: transitioned === true,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        });
        if (auditError) {
          throw new Error(`Escrow payout failure audit failed: ${auditError.message}`);
        }
        await markEventProcessed();
        return new Response(JSON.stringify({ received: true, escrow: "payout_failed" }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      const linkage = await linkExactPayoutTransfers(payout.id, connectedSoignantId);
      const { data: transfersFailed, error: transfersFailedError } = await supabaseAdmin
        .from("stripe_transfers")
        .update({
          statut: "ECHOUE",
          erreur: errMsg,
          stripe_payout_id: payout.id,
        })
        .eq("stripe_payout_id", payout.id)
        .eq("soignant_id", connectedSoignantId)
        .in("statut", ["TRANSFERE", "PAYE"])
        .select("id, soignant_id, montant_soignant, mission_id");
      if (transfersFailedError) {
        throw new Error(`Legacy payout failure reconciliation failed: ${transfersFailedError.message}`);
      }

      // Notif admin + soignant
      const { data: admins } = await supabaseAdmin.rpc("fn_list_admin_user_ids");
      const transfersArr = (transfersFailed || []) as Array<{
        id: string;
        soignant_id: string;
        montant_soignant: number;
        mission_id: string;
      }>;

      for (const t of transfersArr) {
        const { data: soignantRow } = await supabaseAdmin
          .from("soignants")
          .select("prenom, nom")
          .eq("id", t.soignant_id)
          .maybeSingle();
        const soignantNom = soignantRow ? `${soignantRow.prenom || ""} ${soignantRow.nom || ""}`.trim() : t.soignant_id;

        // Admin
        for (const adminId of (admins || []) as string[]) {
          try {
            await supabaseAdmin.functions.invoke("send-email", {
              body: {
                type: "PAYOUT_FAILED_ADMIN",
                destinataire_id: adminId,
                data: {
                  soignant_nom: soignantNom,
                  payout_id: payout.id,
                  montant: Number(t.montant_soignant).toFixed(2),
                  failure_message: errMsg,
                  failure_code: payout.failure_code || "",
                },
              },
            });
          } catch (emailErr) {
            console.error("send-email PAYOUT_FAILED_ADMIN failed:", emailErr);
          }
        }

        // Soignant
        try {
          const { data: soignantUser } = await supabaseAdmin.auth.admin.getUserById(t.soignant_id);
          const soignantEmail = soignantUser?.user?.email;
          if (soignantEmail) {
            await supabaseAdmin.functions.invoke("send-email", {
              body: {
                type: "PAYOUT_FAILED_SOIGNANT",
                destinataire_id: t.soignant_id,
                destinataire_email: soignantEmail,
                data: {
                  soignant_prenom: soignantRow?.prenom || "",
                  montant: Number(t.montant_soignant).toFixed(2),
                  failure_message: errMsg,
                  raison_simplifiee: payout.failure_code === "account_closed"
                    ? "Votre compte bancaire semble fermé."
                    : payout.failure_code === "invalid_account_number"
                    ? "Votre IBAN est invalide."
                    : "Problème avec votre compte bancaire (KYC, solde, etc.)",
                },
              },
            });
          }
        } catch (emailErr) {
          console.error("send-email PAYOUT_FAILED_SOIGNANT failed:", emailErr);
        }
      }

      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_PAYOUT_FAILED",
        p_type_ressource: "payout",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: {
          stripe_payout_id: payout.id,
          failure_code: payout.failure_code,
          failure_message: errMsg,
          amount: payout.amount,
          transfer_source_ids: linkage.sourceIds,
          transfers_linked: linkage.linked,
          transfers_marked: transfersArr.length,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`payout.failed handled: ${payout.id} → ${transfersArr.length} transfers marked ECHOUE`);
    }

    // ── payout.canceled : payout annulé ──
    if (verified.source === "CONNECT" && event.type === "payout.canceled") {
      const payout = event.data.object as Stripe.Payout;
      const connectedSoignantId = await requireConnectedSoignantId();

      if (payout.metadata?.type === "ESCROW_RELEASE") {
        const escrowId = payout.metadata?.paiement_escrow_id;
        if (!escrowId || !eventAccount) {
          throw new Error("ESCROW_RELEASE payout metadata incomplete");
        }
        const { data: transitioned, error: transitionError } = await supabaseAdmin.rpc(
          "fn_escrow_echouer_payout" as never,
          {
            p_paiement_escrow_id: escrowId,
            p_stripe_payout_id: payout.id,
            p_stripe_account_id: eventAccount,
            p_detail: "payout_canceled — payout Stripe annulé",
          } as never,
        );
        if (transitionError) {
          throw new Error(`Escrow payout cancellation persistence failed: ${transitionError.message}`);
        }
        const { error: auditError } = await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
          p_acteur_id: "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: "ESCROW_RELEASE_ANNULE",
          p_type_ressource: "mission",
          p_id_ressource: payout.metadata?.mission_id ?? null,
          p_cle_s3: null,
          p_details: {
            paiement_escrow_id: escrowId,
            stripe_payout_id: payout.id,
            stripe_account_id: eventAccount,
            soignant_id: connectedSoignantId,
            transitioned: transitioned === true,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        });
        if (auditError) {
          throw new Error(`Escrow payout cancellation audit failed: ${auditError.message}`);
        }
        await markEventProcessed();
        return new Response(JSON.stringify({ received: true, escrow: "payout_canceled" }), {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }

      const linkage = await linkExactPayoutTransfers(payout.id, connectedSoignantId);
      const { data: transfersCancelled, error: transfersCancelledError } = await supabaseAdmin
        .from("stripe_transfers")
        .update({ statut: "ANNULEE", stripe_payout_id: payout.id })
        .eq("stripe_payout_id", payout.id)
        .eq("soignant_id", connectedSoignantId)
        .eq("statut", "TRANSFERE")
        .select("id, soignant_id, montant_soignant, mission_id");
      if (transfersCancelledError) {
        throw new Error(`Legacy payout cancellation reconciliation failed: ${transfersCancelledError.message}`);
      }

      const { data: admins } = await supabaseAdmin.rpc("fn_list_admin_user_ids");
      const first = ((transfersCancelled || []) as Array<{ id: string; soignant_id: string; montant_soignant: number }>)[0];
      if (first) {
        const { data: soignantRow } = await supabaseAdmin
          .from("soignants")
          .select("prenom, nom")
          .eq("id", first.soignant_id)
          .maybeSingle();
        const soignantNom = soignantRow ? `${soignantRow.prenom || ""} ${soignantRow.nom || ""}`.trim() : first.soignant_id;
        for (const adminId of (admins || []) as string[]) {
          try {
            await supabaseAdmin.functions.invoke("send-email", {
              body: {
                type: "PAYOUT_CANCELED_ADMIN",
                destinataire_id: adminId,
                data: {
                  payout_id: payout.id,
                  soignant_nom: soignantNom,
                  montant: Number(first.montant_soignant).toFixed(2),
                },
              },
            });
          } catch (emailErr) {
            console.error("send-email PAYOUT_CANCELED_ADMIN failed:", emailErr);
          }
        }
      }

      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_PAYOUT_CANCELED",
        p_type_ressource: "payout",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: {
          stripe_payout_id: payout.id,
          amount: payout.amount,
          transfer_source_ids: linkage.sourceIds,
          transfers_linked: linkage.linked,
          transfers_marked: (transfersCancelled || []).length,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`payout.canceled handled: ${payout.id}`);
    }

    // ── charge.pending : charge en attente (SEPA) — audit only ──
    if (verified.source === "PLATFORM" && event.type === "charge.pending") {
      const charge = event.data.object as Stripe.Charge;
      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_CHARGE_PENDING",
        p_type_ressource: "charge",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: {
          stripe_charge_id: charge.id,
          payment_method_type: charge.payment_method_details?.type,
          amount: charge.amount,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`charge.pending audited: ${charge.id}`);
    }

    // ── charge.expired : charge non-capturée expirée — audit only ──
    if (verified.source === "PLATFORM" && event.type === "charge.expired") {
      const charge = event.data.object as Stripe.Charge;
      await supabaseAdmin.rpc("fn_ecrire_audit_safe", {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_CHARGE_EXPIRED",
        p_type_ressource: "charge",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: { stripe_charge_id: charge.id, amount: charge.amount },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      });
      console.log(`charge.expired audited: ${charge.id}`);
    }

    // Marquer l'event comme traité (claim atomique + lease libéré).
    await markEventProcessed();

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erreur inconnue";
    console.error("Erreur stripe-webhook:", message);
    // Libérer le lease pour qu'une livraison Stripe ultérieure puisse reprendre
    // immédiatement. Ne jamais marquer traite_le sur un échec.
    if (claimedEventId) {
      const { error: releaseError } = await supabaseAdmin
        .from("stripe_webhook_events")
        .update({
          traitement_commence_le: null,
          erreur: message.substring(0, 1000),
        })
        .eq("event_id", claimedEventId)
        .is("traite_le", null);
      if (releaseError) {
        console.error("Stripe webhook claim release failed:", releaseError.message);
      }
    }
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }
}
