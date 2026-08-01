import Stripe from "npm:stripe@20.4.1";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  findInvoiceCheckoutSessionInconsistencies,
  findInvoicePaymentIntentInconsistencies,
} from "./invoice-payment-intent.ts";
import { assertStripeSecretMode, isProductionRuntime } from "./stripe-production.ts";
import { releaseStripePaymentFlowClaimForExpiredSession } from "./stripe-payment-flow-claim.ts";
import { writeRequiredFinancialAudit } from "./financial-audit.ts";
import {
  requireAcquiredStripeSourceCharge,
  StripeSourceChargeValidationError,
} from "./stripe-source-charge.ts";
import {
  escrowPayoutInconsistencies,
  type EscrowPayoutExpectation,
} from "./stripe-escrow-payout.ts";
import { resolveOperationalTestAccount } from "./test-account.ts";

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

function stripeObjectId(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && "id" in value) {
    const id = (value as { id?: unknown }).id;
    return typeof id === "string" ? id : null;
  }
  return null;
}

type StripeTestClassification =
  | { ok: true; isTest: boolean; matchedCanonicalSource: boolean }
  | { ok: false; error: string };

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function stripeMetadata(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object" || !("metadata" in value)) return {};
  const metadata = (value as { metadata?: unknown }).metadata;
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) return {};
  return Object.fromEntries(
    Object.entries(metadata as Record<string, unknown>).filter(
      (entry): entry is [string, string] => typeof entry[1] === "string",
    ),
  );
}

function objectString(value: unknown, key: string): string | null {
  if (!value || typeof value !== "object" || !(key in value)) return null;
  const raw = (value as Record<string, unknown>)[key];
  return typeof raw === "string" && raw.length > 0 ? raw : stripeObjectId(raw);
}

/**
 * Classification serveur des webhooks liés à une fixture.
 *
 * Les metadata Stripe ne servent qu'à retrouver une ligne canonique. La
 * décision finale relit toujours est_compte_test en base; une erreur de lecture
 * échoue fermée (500/retry Stripe), tandis qu'un événement sans provenance
 * reconnue poursuit les validations métier strictes déjà présentes plus bas.
 */
async function classifyStripeWebhookTestAccount(
  admin: ReturnType<typeof createClient>,
  event: Stripe.Event,
  source: StripeWebhookSource,
): Promise<StripeTestClassification> {
  const object = event.data.object as unknown;
  const metadata = stripeMetadata(object);
  const accountIds = new Set<string>();
  let matchedCanonicalSource = false;

  const addAccountId = (candidate: unknown) => {
    if (typeof candidate === "string" && UUID_PATTERN.test(candidate)) {
      accountIds.add(candidate);
    }
  };
  const addCanonicalRowAccounts = (
    row: Record<string, unknown> | null,
  ) => {
    if (!row) return;
    matchedCanonicalSource = true;
    addAccountId(row.etablissement_id);
    addAccountId(row.soignant_id);
    addAccountId(row.soignant_assigne_id);
  };
  const queryMaybeSingle = async (
    table: string,
    select: string,
    column: string,
    value: string,
  ): Promise<Record<string, unknown> | null> => {
    const { data, error } = await admin
      .from(table)
      .select(select)
      .eq(column, value)
      .maybeSingle();
    if (error) {
      throw new Error(`${table}.${column}: ${error.message}`);
    }
    return data as Record<string, unknown> | null;
  };

  try {
    // Identifiants métier issus des metadata : ils sont revalidés par lookup.
    const missionIds = new Set<string>();
    for (const candidate of [
      metadata.mission_id,
      objectString(object, "client_reference_id"),
    ]) {
      if (candidate && UUID_PATTERN.test(candidate)) missionIds.add(candidate);
    }
    for (const missionId of missionIds) {
      addCanonicalRowAccounts(
        await queryMaybeSingle(
          "missions",
          "etablissement_id,soignant_assigne_id",
          "id",
          missionId,
        ),
      );
    }

    for (const [metadataKey, table, select] of [
      ["facture_id", "factures", "etablissement_id,mission_id"],
      ["facture_commission_id", "factures", "etablissement_id,mission_id"],
      [
        "facture_honoraires_id",
        "factures_honoraires",
        "etablissement_id,soignant_id,mission_id",
      ],
      [
        "avoir_id",
        "factures_honoraires",
        "etablissement_id,soignant_id,mission_id",
      ],
      [
        "facture_origine_id",
        "factures_honoraires",
        "etablissement_id,soignant_id,mission_id",
      ],
    ] as const) {
      const rowId = metadata[metadataKey];
      if (!rowId || !UUID_PATTERN.test(rowId)) continue;
      addCanonicalRowAccounts(
        await queryMaybeSingle(
          table,
          select,
          "id",
          rowId,
        ),
      );
    }

    const escrowId = metadata.paiement_escrow_id;
    if (escrowId && UUID_PATTERN.test(escrowId)) {
      addCanonicalRowAccounts(
        await queryMaybeSingle(
          "paiements_escrow",
          "etablissement_id,soignant_id,mission_id",
          "id",
          escrowId,
        ),
      );
    }

    const queueId = metadata.queue_id;
    if (queueId && UUID_PATTERN.test(queueId)) {
      const queue = await queryMaybeSingle(
        "stripe_refunds_queue",
        "paiement_escrow_id,avoir_id,facture_origine_id",
        "id",
        queueId,
      );
      if (queue) {
        matchedCanonicalSource = true;
        const queueEscrowId = queue.paiement_escrow_id;
        if (typeof queueEscrowId === "string") {
          addCanonicalRowAccounts(
            await queryMaybeSingle(
              "paiements_escrow",
              "etablissement_id,soignant_id,mission_id",
              "id",
              queueEscrowId,
            ),
          );
        }
        const queueInvoiceId = queue.avoir_id || queue.facture_origine_id;
        if (typeof queueInvoiceId === "string") {
          addCanonicalRowAccounts(
            await queryMaybeSingle(
              "factures_honoraires",
              "etablissement_id,soignant_id,mission_id",
              "id",
              queueInvoiceId,
            ),
          );
        }
      }
    }

    // PaymentIntent/Transfer Stripe -> lignes métier. Aucun metadata n'est
    // nécessaire pour reconnaître un ancien objet live déjà enregistré.
    let paymentIntentId: string | null = null;
    if (event.type.startsWith("payment_intent.")) {
      paymentIntentId = objectString(object, "id");
    } else {
      paymentIntentId = objectString(object, "payment_intent");
    }
    if (paymentIntentId?.startsWith("pi_")) {
      for (const [table, select] of [
        ["paiements_escrow", "etablissement_id,soignant_id,mission_id"],
        ["factures", "etablissement_id,mission_id"],
        ["factures_honoraires", "etablissement_id,soignant_id,mission_id"],
        ["paiements_mission", "etablissement_id,mission_id"],
        ["stripe_transfers", "etablissement_id,soignant_id,mission_id"],
      ] as const) {
        addCanonicalRowAccounts(
          await queryMaybeSingle(
            table,
            select,
            "stripe_payment_intent_id",
            paymentIntentId,
          ),
        );
      }
    }

    const transferId = event.type.startsWith("transfer.")
      ? objectString(object, "id")
      : null;
    if (transferId?.startsWith("tr_")) {
      addCanonicalRowAccounts(
        await queryMaybeSingle(
          "stripe_transfers",
          "etablissement_id,soignant_id,mission_id",
          "stripe_transfer_id",
          transferId,
        ),
      );
    }

    // Customer plateforme et compte Connect sont résolus par les mappings DB,
    // jamais par les noms/emails portés par Stripe.
    const customerId = objectString(object, "customer");
    if (customerId?.startsWith("cus_")) {
      addCanonicalRowAccounts(
        await queryMaybeSingle(
          "etablissements",
          "id",
          "stripe_customer_id",
          customerId,
        ).then((row) =>
          row ? { etablissement_id: row.id } : null
        ),
      );
    }
    if (source === "CONNECT" && event.account) {
      addCanonicalRowAccounts(
        await queryMaybeSingle(
          "stripe_connect_onboarding",
          "soignant_id",
          "stripe_account_id",
          event.account,
        ),
      );
    }

    // Les IDs de compte contenus dans les metadata restent uniquement des
    // pointeurs de lookup; resolveOperationalTestAccount relit la base.
    addAccountId(metadata.etablissement_id);
    addAccountId(metadata.soignant_id);

    for (const accountId of accountIds) {
      const classification = await resolveOperationalTestAccount(
        admin,
        accountId,
      );
      if (!classification.ok) {
        return { ok: false, error: classification.error };
      }
      matchedCanonicalSource = true;
      if (classification.isTest) {
        return { ok: true, isTest: true, matchedCanonicalSource: true };
      }
    }

    return { ok: true, isTest: false, matchedCanonicalSource };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "classification indisponible",
    };
  }
}

// Audit escrow DIRECT en table (pas via le rpc fn_ecrire_audit_safe) : le
// binding PostgREST de ce RPC 9-params sérialise les uuid en « null » →
// « invalid input syntax for type uuid » → l'audit edge échouait silencieusement
// (trou d'observabilité prod découvert par la recette escrow, run #11 du
// 09/07/2026). Le service_role bypasse la RLS : l'insert direct est fiable.
async function auditEscrow(admin: any, action: string, missionId: string | null, details: unknown) {
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
  if (error) throw new Error(`audit escrow webhook insert: ${error.message}`);
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
    apiVersion: "2026-02-25.clover",
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

    // Classification canonique avant la première écriture (y compris le claim
    // idempotent). Une indisponibilité DB fait réessayer Stripe; aucun événement
    // ne passe « réel par défaut ».
    const testClassification = await classifyStripeWebhookTestAccount(
      supabaseAdmin,
      event,
      verified.source,
    );
    if (!testClassification.ok) {
      throw new Error(
        `Stripe test-account classification failed: ${testClassification.error}`,
      );
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

    // Les objets Stripe live historiques créés pendant la phase de test
    // peuvent encore émettre des webhooks. Après claim idempotent mais avant
    // toute mutation métier, transfert, notification ou lecture Stripe
    // supplémentaire, neutraliser ceux rattachés canoniquement à une fixture.
    if (testClassification.isTest) {
      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "ADMIN_ACTION",
        p_type_ressource: "stripe_webhook_event",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: {
          evenement: "STRIPE_WEBHOOK_TEST_SKIPPED",
          test_skipped: true,
          source_webhook: verified.source,
          stripe_event_id: event.id,
          stripe_event_type: event.type,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      }, "Stripe test webhook skip audit failed");
      await markEventProcessed();
      console.info(
        `Stripe webhook test_skipped: source=${verified.source} type=${event.type}`,
      );
      return new Response(
        JSON.stringify({ received: true, test_skipped: true }),
        {
          status: 200,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        },
      );
    }

    const loadAndValidateInvoicePayment = async (
      factureId: string,
      paymentIntent: Stripe.PaymentIntent,
      context: "checkout.session.completed" | "payment_intent.succeeded",
      session?: Stripe.Checkout.Session,
    ) => {
      const { data: facture, error: factureError } = await supabaseAdmin
        .from("factures")
        .select(
          "id, statut, type_document, numero_facture, montant_ttc, etablissement_id, stripe_payment_intent_id, etablissements(stripe_customer_id)",
        )
        .eq("id", factureId)
        .maybeSingle();
      if (factureError || !facture) {
        throw new Error(
          `Stripe invoice validation lookup failed: ${factureError?.message || "row missing"}`,
        );
      }

      const relation = facture.etablissements as
        | { stripe_customer_id?: string | null }
        | Array<{ stripe_customer_id?: string | null }>
        | null;
      const customerId = (Array.isArray(relation)
        ? relation[0]?.stripe_customer_id
        : relation?.stripe_customer_id) || "";
      const amountCents = Math.round(Number(facture.montant_ttc ?? 0) * 100);
      const incoherences: string[] = [];
      if (facture.type_document !== "FACTURE") {
        incoherences.push("invoice.type_document");
      }
      if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
        incoherences.push("invoice.amount_invalid");
      }
      if (!customerId) incoherences.push("invoice.customer_missing");
      incoherences.push(...findInvoicePaymentIntentInconsistencies(paymentIntent, {
        factureId: facture.id,
        etablissementId: facture.etablissement_id,
        customerId,
        amountCents,
        currency: "eur",
      }).map((check) => `payment_intent.${check}`));
      if (paymentIntent.status !== "succeeded") {
        incoherences.push("payment_intent.status");
      } else if (customerId && Number.isSafeInteger(amountCents) && amountCents > 0) {
        try {
          await requireAcquiredStripeSourceCharge(stripe, paymentIntent, {
            customerId,
            amountCents,
            currency: "eur",
          });
        } catch (error) {
          if (!(error instanceof StripeSourceChargeValidationError)) throw error;
          incoherences.push(...error.checks.map((check) => `source_charge.${check}`));
        }
      }
      if (
        facture.stripe_payment_intent_id
        && facture.stripe_payment_intent_id !== paymentIntent.id
      ) {
        incoherences.push("invoice.payment_intent_id");
      }

      if (session) {
        incoherences.push(...findInvoiceCheckoutSessionInconsistencies(session, {
          factureId: facture.id,
          etablissementId: facture.etablissement_id,
          customerId,
          amountCents,
          currency: "eur",
        }).map((check) => `checkout_session.${check}`));
        const sessionPaymentIntentId = typeof session.payment_intent === "string"
          ? session.payment_intent
          : session.payment_intent?.id || null;
        if (sessionPaymentIntentId !== paymentIntent.id) {
          incoherences.push("checkout_session.payment_intent");
        }
        if (session.payment_status !== "paid") {
          incoherences.push("checkout_session.payment_status");
        }
      }

      if (incoherences.length > 0) {
        await writeRequiredFinancialAudit(supabaseAdmin, {
          p_acteur_id: facture.etablissement_id,
          p_type_acteur: "SYSTEME",
          p_action: "ADMIN_ACTION",
          p_type_ressource: "facture",
          p_id_ressource: facture.id,
          p_cle_s3: null,
          p_details: {
            evenement: "FACTURE_PAIEMENT_STRIPE_IDENTITE_INCOHERENTE",
            contexte: context,
            stripe_event_id: event.id,
            stripe_payment_intent_id: paymentIntent.id,
            stripe_session_id: session?.id || null,
            incoherences,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        }, "Stripe invoice mismatch audit failed");
        throw new Error(
          `Stripe invoice identity mismatch (${context}): ${incoherences.join(",")}`,
        );
      }

      return facture;
    };

    const loadAndValidateEscrowPayment = async (
      paymentIntent: Stripe.PaymentIntent,
      requireSucceeded: boolean,
    ) => {
      const escrowId = paymentIntent.metadata?.paiement_escrow_id || "";
      const { data: escrow, error: escrowError } = await supabaseAdmin
        .from("paiements_escrow")
        .select(
          "id, statut, mission_id, etablissement_id, soignant_id, montant_total_cents, honoraires_cents, commission_cents, stripe_payment_intent_id",
        )
        .eq("id", escrowId)
        .maybeSingle();
      if (escrowError || !escrow) {
        throw new Error(
          `Escrow PaymentIntent lookup failed: ${escrowError?.message || "row missing"}`,
        );
      }
      const { data: etablissement, error: etablissementError } = await supabaseAdmin
        .from("etablissements")
        .select("stripe_customer_id")
        .eq("id", escrow.etablissement_id)
        .maybeSingle();
      const { data: onboarding, error: onboardingError } = await supabaseAdmin
        .from("stripe_connect_onboarding")
        .select("stripe_account_id, statut")
        .eq("soignant_id", escrow.soignant_id)
        .maybeSingle();
      const customerId = etablissement?.stripe_customer_id || "";
      const destinationId = typeof paymentIntent.transfer_data?.destination === "string"
        ? paymentIntent.transfer_data.destination
        : paymentIntent.transfer_data?.destination?.id || null;
      const paymentCustomerId = typeof paymentIntent.customer === "string"
        ? paymentIntent.customer
        : paymentIntent.customer?.id || null;
      const incoherences: string[] = [];
      if (escrow.stripe_payment_intent_id !== paymentIntent.id) {
        incoherences.push("escrow.payment_intent_id");
      }
      if (paymentIntent.metadata?.type !== "ESCROW_MISSION_PAYMENT") {
        incoherences.push("payment_intent.type");
      }
      if (paymentIntent.metadata?.mission_id !== escrow.mission_id) {
        incoherences.push("payment_intent.mission_id");
      }
      if (paymentIntent.metadata?.etablissement_id !== escrow.etablissement_id) {
        incoherences.push("payment_intent.etablissement_id");
      }
      if (paymentIntent.metadata?.soignant_id !== escrow.soignant_id) {
        incoherences.push("payment_intent.soignant_id");
      }
      if (
        paymentIntent.amount !== escrow.montant_total_cents
        || paymentIntent.currency !== "eur"
      ) incoherences.push("payment_intent.amount_or_currency");
      if (paymentIntent.application_fee_amount !== escrow.commission_cents) {
        incoherences.push("payment_intent.application_fee_amount");
      }
      if (paymentCustomerId !== customerId) incoherences.push("payment_intent.customer");
      if (
        onboardingError || onboarding?.statut !== "COMPLET"
        || destinationId !== onboarding?.stripe_account_id
      ) incoherences.push("payment_intent.destination");
      if (etablissementError || !customerId) incoherences.push("etablissement.customer");
      if (
        requireSucceeded
        && (paymentIntent.status !== "succeeded"
          || paymentIntent.amount_received !== escrow.montant_total_cents)
      ) incoherences.push("payment_intent.status_or_received");
      if (
        requireSucceeded
        && paymentIntent.status === "succeeded"
        && customerId
        && Number.isSafeInteger(escrow.montant_total_cents)
        && escrow.montant_total_cents > 0
      ) {
        try {
          await requireAcquiredStripeSourceCharge(stripe, paymentIntent, {
            customerId,
            amountCents: escrow.montant_total_cents,
            currency: "eur",
          });
        } catch (error) {
          if (!(error instanceof StripeSourceChargeValidationError)) throw error;
          incoherences.push(...error.checks.map((check) => `source_charge.${check}`));
        }
      }
      if (customerId) {
        const customer = await stripe.customers.retrieve(customerId);
        if (customer.deleted || customer.metadata?.etablissement_id !== escrow.etablissement_id) {
          incoherences.push("customer.tenant_metadata");
        }
      }
      if (incoherences.length > 0) {
        await writeRequiredFinancialAudit(supabaseAdmin, {
          p_acteur_id: escrow.etablissement_id,
          p_type_acteur: "SYSTEME",
          p_action: "ADMIN_ACTION",
          p_type_ressource: "mission",
          p_id_ressource: escrow.mission_id,
          p_cle_s3: null,
          p_details: {
            evenement: "ESCROW_PAYMENT_INTENT_IDENTITE_INCOHERENTE",
            paiement_escrow_id: escrow.id,
            stripe_payment_intent_id: paymentIntent.id,
            incoherences,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        }, "Escrow mismatch audit failed");
        throw new Error(`Escrow PaymentIntent identity mismatch: ${incoherences.join(",")}`);
      }
      return escrow;
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

    const loadAndValidateEscrowPayout = async (
      payout: Stripe.Payout,
      connectedSoignantId: string,
      expectedStatus: "paid" | "failed" | "canceled",
    ) => {
      const escrowId = payout.metadata?.paiement_escrow_id || "";
      const { data: escrow, error: escrowError } = await supabaseAdmin
        .from("paiements_escrow")
        .select(
          "id, mission_id, soignant_id, honoraires_cents, stripe_payout_id, statut",
        )
        .eq("id", escrowId)
        .maybeSingle();
      if (escrowError || !escrow) {
        throw new Error(
          `Escrow payout lookup failed: ${escrowError?.message || "row missing"}`,
        );
      }

      const expected: EscrowPayoutExpectation = {
        paiementEscrowId: escrow.id,
        missionId: escrow.mission_id,
        soignantId: escrow.soignant_id,
        amountCents: Number(escrow.honoraires_cents),
      };
      const incoherences = escrowPayoutInconsistencies(payout, expected);
      if (payout.status !== expectedStatus) incoherences.push("event.status");
      if (escrow.stripe_payout_id !== payout.id) incoherences.push("escrow.payout_id");
      if (escrow.soignant_id !== connectedSoignantId) {
        incoherences.push("escrow.connected_soignant");
      }
      if (!Number.isSafeInteger(expected.amountCents) || expected.amountCents <= 0) {
        incoherences.push("escrow.amount_invalid");
      }

      if (incoherences.length > 0) {
        await writeRequiredFinancialAudit(supabaseAdmin, {
          p_acteur_id: escrow.soignant_id,
          p_type_acteur: "SYSTEME",
          p_action: "ADMIN_ACTION",
          p_type_ressource: "mission",
          p_id_ressource: escrow.mission_id,
          p_cle_s3: null,
          p_details: {
            evenement: "ESCROW_PAYOUT_IDENTITE_INCOHERENTE",
            stripe_event_id: event.id,
            stripe_payout_id: payout.id,
            paiement_escrow_id: escrow.id,
            statut_escrow: escrow.statut,
            incoherences,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        }, "Escrow payout mismatch audit failed");
        throw new Error(`Escrow payout identity mismatch: ${incoherences.join(",")}`);
      }
      return escrow;
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

        const paymentIntentId = typeof session.payment_intent === "string"
          ? session.payment_intent
          : session.payment_intent?.id || null;
        const missionId = session.metadata?.mission_id || null;
        if (!paymentIntentId || !missionId) {
          throw new Error("Paid Connect checkout missing PaymentIntent or mission binding");
        }
        const connectPaymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);

        const { data: validatedTransferClaim, error: validatedTransferClaimError } =
          await supabaseAdmin
            .from("stripe_transfers")
            .select(
              "id, mission_id, facture_id, facture_honoraire_id, soignant_id, etablissement_id, statut, montant_soignant, montant_commission, montant_total, stripe_checkout_session_id, stripe_payment_intent_id, stripe_transfer_id",
            )
            .eq("mission_id", missionId)
            .eq("stripe_checkout_session_id", session.id)
            .maybeSingle();

        const { data: validatedMission, error: validatedMissionError } = await supabaseAdmin
          .from("missions")
          .select(
            "id, etablissement_id, soignant_assigne_id, statut, type_contrat_applique, net_a_payer, montant_commission_ht, montant_commission_tva, montant_commission_ttc, commission_facturee, intitule",
          )
          .eq("id", missionId)
          .maybeSingle();
        if (validatedMissionError || !validatedMission) {
          throw new Error(
            `Connect mission validation lookup failed: ${validatedMissionError?.message || "row missing"}`,
          );
        }
        const soignantId = validatedMission.soignant_assigne_id;
        const { data: validatedEtablissement, error: validatedEtablissementError } =
          await supabaseAdmin
            .from("etablissements")
            .select("stripe_customer_id")
            .eq("id", validatedMission.etablissement_id)
            .maybeSingle();
        const { data: validatedOnboarding, error: validatedOnboardingError } =
          await supabaseAdmin
            .from("stripe_connect_onboarding")
            .select("stripe_account_id, statut")
            .eq("soignant_id", soignantId)
            .maybeSingle();
        const factureHonorairesId = session.metadata?.facture_honoraires_id || null;
        const invoiceScopedPayment = session.metadata?.payment_scope === "INVOICE";
        const sessionFactureCommissionId = session.metadata?.facture_commission_id || "";
        const { data: validatedFactureHonoraires, error: validatedFactureHonorairesError } =
          factureHonorairesId
            ? await supabaseAdmin
              .from("factures_honoraires")
              .select("id, statut, montant_ttc, mission_id, soignant_id, etablissement_id, stripe_payment_intent_id, periode_debut, periode_fin, est_facture_finale_mission")
              .eq("id", factureHonorairesId)
              .maybeSingle()
            : { data: null, error: null };
        const commissionQuery = supabaseAdmin
          .from("factures")
          .select("id, statut, montant_ht, montant_tva, montant_ttc, mission_id, facture_honoraire_id, etablissement_id, stripe_payment_intent_id")
          .eq("type_document", "FACTURE")
          .neq("statut", "ANNULEE");
        const { data: validatedFactureCommission, error: validatedFactureCommissionError } =
          sessionFactureCommissionId
            ? await commissionQuery.eq("id", sessionFactureCommissionId).maybeSingle()
            : await commissionQuery.eq("mission_id", missionId).maybeSingle();

        const connectedAccountId = validatedOnboarding?.stripe_account_id || "";
        const customerId = validatedEtablissement?.stripe_customer_id || "";
        const soignantCents = Math.round(Number(validatedFactureHonoraires?.montant_ttc ?? 0) * 100);
        const commissionCents = Math.round(Number(validatedFactureCommission?.montant_ttc ?? 0) * 100);
        const totalCents = soignantCents + commissionCents;
        const chargeId = connectPaymentIntent.latest_charge
          ? typeof connectPaymentIntent.latest_charge === "string"
            ? connectPaymentIntent.latest_charge
            : connectPaymentIntent.latest_charge.id
          : null;
        const incoherences: string[] = [];
        const factureHonorairesPayable = Boolean(
          validatedFactureHonoraires
          && ["EMISE", "EN_RETARD"].includes(validatedFactureHonoraires.statut)
          && (!validatedFactureHonoraires.stripe_payment_intent_id
            || validatedFactureHonoraires.stripe_payment_intent_id === paymentIntentId),
        );
        const factureHonorairesDejaReconcilee = Boolean(
          validatedFactureHonoraires?.statut === "PAYEE"
          && validatedFactureHonoraires.stripe_payment_intent_id === paymentIntentId,
        );
        if (
          validatedTransferClaimError || !validatedTransferClaim
          || validatedTransferClaim.mission_id !== missionId
          || validatedTransferClaim.soignant_id !== soignantId
          || validatedTransferClaim.etablissement_id !== validatedMission.etablissement_id
          || (invoiceScopedPayment
            && validatedTransferClaim.facture_honoraire_id !== factureHonorairesId)
          || (invoiceScopedPayment
            && validatedTransferClaim.facture_id !== sessionFactureCommissionId)
          || !["EN_ATTENTE", "TRANSFERE", "CHARGE_REUSSI", "PAYE"].includes(
            validatedTransferClaim.statut,
          )
          || Math.round(Number(validatedTransferClaim.montant_soignant) * 100) !== soignantCents
          || Math.round(Number(validatedTransferClaim.montant_commission) * 100) !== commissionCents
          || Math.round(Number(validatedTransferClaim.montant_total) * 100) !== totalCents
          || Boolean(
            validatedTransferClaim.stripe_payment_intent_id
            && validatedTransferClaim.stripe_payment_intent_id !== paymentIntentId,
          )
        ) incoherences.push("transfer_claim.identity");
        if (
          (!invoiceScopedPayment && validatedMission.statut !== "TERMINEE")
          || (invoiceScopedPayment && !["EN_COURS", "TERMINEE"].includes(validatedMission.statut))
          || validatedMission.type_contrat_applique !== "LIBERAL"
          || !soignantId
        ) incoherences.push("mission.state_or_contract");
        if (validatedEtablissementError || !customerId) incoherences.push("etablissement.customer");
        if (
          validatedOnboardingError || validatedOnboarding?.statut !== "COMPLET"
          || !connectedAccountId
        ) incoherences.push("onboarding.account");
        if (
          validatedFactureHonorairesError || !validatedFactureHonoraires
          || (!factureHonorairesPayable && !factureHonorairesDejaReconcilee)
          || validatedFactureHonoraires.mission_id !== missionId
          || validatedFactureHonoraires.soignant_id !== soignantId
          || validatedFactureHonoraires.etablissement_id !== validatedMission.etablissement_id
          || Math.round(Number(validatedFactureHonoraires.montant_ttc ?? 0) * 100) !== soignantCents
          || (invoiceScopedPayment
            && validatedMission.statut === "EN_COURS"
            && (validatedFactureHonoraires.est_facture_finale_mission
              || validatedFactureHonoraires.periode_fin >= new Date().toISOString().slice(0, 10)))
        ) incoherences.push("facture_honoraires.identity");
        if (
          validatedFactureCommissionError
          || (validatedFactureCommission
            ? !(
                (["EMISE", "EN_RETARD"].includes(validatedFactureCommission.statut)
                  && (!validatedFactureCommission.stripe_payment_intent_id
                    || validatedFactureCommission.stripe_payment_intent_id === paymentIntentId))
                || (validatedFactureCommission.statut === "PAYEE"
                  && validatedFactureCommission.stripe_payment_intent_id === paymentIntentId)
              )
              || validatedFactureCommission.etablissement_id !== validatedMission.etablissement_id
              || (invoiceScopedPayment
                && validatedFactureCommission.facture_honoraire_id !== factureHonorairesId)
              || Math.round(Number(validatedFactureCommission.montant_ttc ?? 0) * 100) !== commissionCents
              || (sessionFactureCommissionId !== validatedFactureCommission.id
                && !(sessionFactureCommissionId === ""
                  && validatedFactureCommission.statut === "PAYEE"
                  && validatedFactureCommission.stripe_payment_intent_id === paymentIntentId))
            : sessionFactureCommissionId !== "")
        ) incoherences.push("facture_commission.identity");
        if (
          !Number.isSafeInteger(soignantCents) || soignantCents <= 0
          || !Number.isSafeInteger(commissionCents) || commissionCents <= 0
          || !Number.isSafeInteger(totalCents) || totalCents <= 0
        ) incoherences.push("amounts.invalid");
        if (session.client_reference_id !== missionId) incoherences.push("session.reference");
        if (session.metadata?.etablissement_id !== validatedMission.etablissement_id) {
          incoherences.push("session.etablissement_id");
        }
        if (session.metadata?.soignant_id !== soignantId) incoherences.push("session.soignant_id");
        if (session.metadata?.connected_account_id !== connectedAccountId) {
          incoherences.push("session.connected_account_id");
        }
        if (session.metadata?.soignant_cents !== String(soignantCents)) {
          incoherences.push("session.soignant_cents");
        }
        if (session.metadata?.commission_cents !== String(commissionCents)) {
          incoherences.push("session.commission_cents");
        }
        if (
          session.metadata?.payment_scope !== (invoiceScopedPayment ? "INVOICE" : "MISSION")
          && (invoiceScopedPayment || session.metadata?.payment_scope !== undefined)
        ) {
          incoherences.push("session.payment_scope");
        }
        if (session.amount_total !== totalCents || session.currency !== "eur") {
          incoherences.push("session.amount_or_currency");
        }
        if (typeof session.customer === "string" ? session.customer !== customerId : session.customer?.id !== customerId) {
          incoherences.push("session.customer");
        }
        if (
          connectPaymentIntent.status !== "succeeded"
          || connectPaymentIntent.amount !== totalCents
          || connectPaymentIntent.amount_received !== totalCents
          || connectPaymentIntent.currency !== "eur"
          || (typeof connectPaymentIntent.customer === "string"
            ? connectPaymentIntent.customer !== customerId
            : connectPaymentIntent.customer?.id !== customerId)
          || connectPaymentIntent.metadata?.mission_id !== missionId
          || connectPaymentIntent.metadata?.type !== "CONNECT_MISSION_PAYMENT"
          || connectPaymentIntent.metadata?.etablissement_id !== validatedMission.etablissement_id
          || connectPaymentIntent.metadata?.soignant_id !== soignantId
          || connectPaymentIntent.metadata?.connected_account_id !== connectedAccountId
          || connectPaymentIntent.metadata?.soignant_cents !== String(soignantCents)
          || connectPaymentIntent.metadata?.commission_cents !== String(commissionCents)
          || (
            connectPaymentIntent.metadata?.payment_scope !== (invoiceScopedPayment ? "INVOICE" : "MISSION")
            && (invoiceScopedPayment || connectPaymentIntent.metadata?.payment_scope !== undefined)
          )
          || connectPaymentIntent.metadata?.facture_honoraires_id !== factureHonorairesId
          || (connectPaymentIntent.metadata?.facture_commission_id || "")
            !== sessionFactureCommissionId
          || !chargeId
        ) incoherences.push("payment_intent.identity");
        if (customerId) {
          const customer = await stripe.customers.retrieve(customerId);
          if (customer.deleted || customer.metadata?.etablissement_id !== validatedMission.etablissement_id) {
            incoherences.push("customer.tenant_metadata");
          }
        }

        if (incoherences.length > 0) {
          await writeRequiredFinancialAudit(supabaseAdmin, {
            p_acteur_id: validatedMission.etablissement_id,
            p_type_acteur: "SYSTEME",
            p_action: "ADMIN_ACTION",
            p_type_ressource: "mission",
            p_id_ressource: missionId,
            p_cle_s3: null,
            p_details: {
              evenement: "CONNECT_PAIEMENT_IDENTITE_INCOHERENTE",
              stripe_session_id: session.id,
              stripe_payment_intent_id: paymentIntentId,
              incoherences,
            },
            p_ip: null,
            p_navigateur: "stripe-webhook",
          }, "Connect mismatch audit failed");
          throw new Error(`Paid Connect checkout identity mismatch: ${incoherences.join(",")}`);
        }
        if (!chargeId) {
          throw new Error("Paid Connect checkout has no source charge");
        }

        // Le PaymentIntent peut rester `succeeded` après un remboursement ou
        // une contestation. Avant de créer — ou même de reprendre — le
        // transfert, vérifier la Charge qui constitue réellement la source des
        // fonds. Un retry webhook tardif échoue ainsi fermé.
        const sourceCharge = await requireAcquiredStripeSourceCharge(
          stripe,
          connectPaymentIntent,
          { customerId, amountCents: totalCents, currency: "eur" },
        );
        if (sourceCharge.id !== chargeId) {
          throw new Error("Paid Connect source charge changed during reconciliation");
        }

        if (missionId && soignantId && connectedAccountId && soignantCents > 0) {
          // HOTFIX double transfert — garde idempotente AVANT transfers.create :
          // si un transfer définitif existe déjà pour cette mission (retry Stripe
          // après timeout, ré-livraison), on ne recrée RIEN. Statuts définitifs =
          // même liste que stripe-connect-pay-mission (:271). REMBOURSE exclu :
          // un re-paiement légitime après remboursement doit pouvoir re-transférer.
          const transferExistant = validatedTransferClaim;
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
              ? await stripe.transfers.retrieve(transferExistant!.stripe_transfer_id as string)
              : await stripe.transfers.create({
                amount: soignantCents,
                currency: "eur",
                destination: connectedAccountId,
                source_transaction: chargeId,
                transfer_group: invoiceScopedPayment
                  ? `facture_${factureHonorairesId}`
                  : `mission_${missionId}`,
                metadata: {
                  mission_id: missionId,
                  soignant_id: soignantId || "",
                  facture_honoraires_id: factureHonorairesId || "",
                  payment_scope: invoiceScopedPayment ? "INVOICE" : "MISSION",
                },
              }, { idempotencyKey: `transfer_${session.id}` });
            const transferDestinationId = typeof transfer.destination === "string"
              ? transfer.destination
              : transfer.destination?.id || null;
            const transferSourceId = typeof transfer.source_transaction === "string"
              ? transfer.source_transaction
              : transfer.source_transaction?.id || null;
            if (
              transfer.amount !== soignantCents
              || transfer.currency !== "eur"
              || transferDestinationId !== connectedAccountId
              || transferSourceId !== chargeId
              || transfer.metadata?.mission_id !== missionId
              || transfer.metadata?.soignant_id !== soignantId
            ) {
              throw new Error("Existing or created Stripe transfer identity mismatch");
            }
            mouvementStripeConfirme = true;
            if (transferDejaCree) {
              console.log(
                `Transfer ${transfer.id} déjà créé pour mission ${missionId}; reprise de la réconciliation locale`,
              );
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
                .eq("stripe_checkout_session_id", session.id)
                .eq("statut", "EN_ATTENTE")
                .eq("montant_soignant", soignantCents / 100)
                .eq("montant_commission", commissionCents / 100)
                .eq("montant_total", totalCents / 100)
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

            // Toutes les valeurs financières viennent de la mission validée
            // avant le mouvement Stripe, jamais des metadata de la Session.
            const missionRow = validatedMission;

            if (!existingPayment) {
              const { error: paiementInsertErr } = await supabaseAdmin
                .from("paiements_soignant")
                .insert({
                  mission_id: missionId,
                  facture_honoraire_id: factureHonorairesId,
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

            // Le mode de paiement est mission-level, mais une semaine payée ne
            // solde pas la mission entière. commission_facturee ne passe à true
            // qu'avec la facture finale.
            const { data: missionUpdated, error: missionUpdateError } = await supabaseAdmin
              .from("missions")
              .update({
                mode_paiement_soignant: "STRIPE_CONNECT",
                commission_facturee: invoiceScopedPayment
                  ? Boolean(validatedFactureHonoraires?.est_facture_finale_mission)
                    || Boolean(validatedMission.commission_facturee)
                  : true,
                modifie_le: new Date().toISOString(),
              })
              .eq("id", missionId)
              .in("statut", invoiceScopedPayment ? ["EN_COURS", "TERMINEE"] : ["TERMINEE"])
              .eq("type_contrat_applique", "LIBERAL")
              .eq("soignant_assigne_id", soignantId)
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
            const commissionTtc = Number(validatedFactureCommission?.montant_ttc || 0);
            const commissionHt = Number(validatedFactureCommission?.montant_ht || 0);
            const commissionTva = Number(validatedFactureCommission?.montant_tva || 0);
            if (commissionTtc > 0 && missionRow?.etablissement_id) {
              const numeroFactureCommission = `FACT-STRIPE-${nowIso.split("T")[0]}-${missionId.split("-")[0]}`;
              if (validatedFactureCommission) {
                if (
                  validatedFactureCommission.statut !== "PAYEE"
                  || validatedFactureCommission.stripe_payment_intent_id !== paymentIntentId
                ) {
                  const { data: factPaid, error: factPaidError } = await supabaseAdmin
                    .from("factures")
                    .update({
                      statut: "PAYEE",
                      date_paiement: nowIso,
                      stripe_payment_intent_id: paymentIntentId,
                      mode_paiement: "STRIPE",
                      modifie_le: nowIso,
                    })
                    .eq("id", validatedFactureCommission.id)
                    .eq("mission_id", missionId)
                    .eq("etablissement_id", missionRow.etablissement_id)
                    .eq("montant_ttc", validatedFactureCommission.montant_ttc)
                    .or(
                      `stripe_payment_intent_id.is.null,stripe_payment_intent_id.eq.${paymentIntentId}`,
                    )
                    .in("statut", ["EMISE", "EN_RETARD"])
                    .select("id")
                    .maybeSingle();
                  if (factPaidError || !factPaid) {
                    throw new Error(
                      `Commission invoice reconciliation failed: ${factPaidError?.message || "row missing"}`,
                    );
                  }
                }
              } else {
                const { data: factCreated, error: factErr } = await supabaseAdmin
                  .from("factures")
                  .insert({
                    etablissement_id: missionRow.etablissement_id,
                    mission_id: missionId,
                    facture_honoraire_id: factureHonorairesId,
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
                  await writeRequiredFinancialAudit(supabaseAdmin, {
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
                  }, "Commission invoice creation audit failed");
                }
              }
            }

            // [CP-STRIPE-2 H1/H7/H14] Propagation du paiement vers factures_honoraires :
            // - stripe_payment_intent_id rempli pour les avoirs AUTO_STRIPE futurs
            // - transition statut EMISE/EN_RETARD → PAYEE
            // - invoke send-email PAIEMENT_RAPIDE_RECU (notif soignant)
            // Le guard `in statut EMISE/EN_RETARD` couvre H4 pour la facture honoraires
            // (une facture ANNULEE/REMPLACEE ne peut pas repasser PAYEE par ce chemin).
            if (factureHonorairesId && paymentIntentId) {
              const { data: factureUpdated, error: factureError } = await supabaseAdmin
                .from("factures_honoraires")
                .update({
                  stripe_payment_intent_id: paymentIntentId,
                  statut: "PAYEE",
                  date_paiement: new Date().toISOString().split("T")[0],
                })
                .eq("id", factureHonorairesId)
                .eq("mission_id", missionId)
                .eq("soignant_id", soignantId)
                .eq("etablissement_id", validatedMission.etablissement_id)
                .eq("montant_ttc", validatedFactureHonoraires!.montant_ttc)
                .or(
                  `stripe_payment_intent_id.is.null,stripe_payment_intent_id.eq.${paymentIntentId}`,
                )
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
                  await writeRequiredFinancialAudit(supabaseAdmin, {
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
                  }, "Caregiver invoice anomaly audit failed");
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
            await writeRequiredFinancialAudit(supabaseAdmin, {
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
            }, "Connect transfer audit failed");

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

            const { data: failedTransferPersisted, error: updateErr } = await supabaseAdmin
              .from("stripe_transfers")
              .update({
                statut: "EN_ATTENTE",
                erreur: errorLabel.substring(0, 2000),
              })
              .eq("mission_id", missionId)
              .eq("stripe_checkout_session_id", session.id)
              .eq("statut", "EN_ATTENTE")
              .select("id")
              .maybeSingle();
            if (updateErr || !failedTransferPersisted) {
              const { data: concurrentTransfer, error: concurrentTransferError } =
                await supabaseAdmin
                  .from("stripe_transfers")
                  .select("statut, stripe_checkout_session_id, stripe_payment_intent_id")
                  .eq("mission_id", missionId)
                  .eq("stripe_checkout_session_id", session.id)
                  .maybeSingle();
              if (
                concurrentTransferError || !concurrentTransfer
                || !["CHARGE_REUSSI", "TRANSFERE", "PAYE"].includes(
                  concurrentTransfer.statut,
                )
                || concurrentTransfer.stripe_payment_intent_id !== paymentIntentId
              ) {
                throw new Error(
                  `Failed transfer persistence failed: ${updateErr?.message || concurrentTransferError?.message || "state conflict"}`,
                );
              }
            }

            await writeRequiredFinancialAudit(supabaseAdmin, {
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
            }, "Failed transfer audit failed");
            throw new Error(
              `Connect transfer failed; Stripe event must retry: ${stripeErrMsg}`,
            );
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

      const sessionPaymentIntentId = typeof session.payment_intent === "string"
        ? session.payment_intent
        : session.payment_intent?.id || null;
      if (!sessionPaymentIntentId) {
        const { data: invoiceWithoutIntent } = await supabaseAdmin
          .from("factures")
          .select("etablissement_id")
          .eq("id", factureId)
          .maybeSingle();
        if (invoiceWithoutIntent?.etablissement_id) {
          await writeRequiredFinancialAudit(supabaseAdmin, {
            p_acteur_id: invoiceWithoutIntent.etablissement_id,
            p_type_acteur: "SYSTEME",
            p_action: "ADMIN_ACTION",
            p_type_ressource: "facture",
            p_id_ressource: factureId,
            p_cle_s3: null,
            p_details: {
              evenement: "FACTURE_PAIEMENT_STRIPE_IDENTITE_INCOHERENTE",
              contexte: "checkout.session.completed",
              stripe_event_id: event.id,
              stripe_session_id: session.id,
              incoherences: ["checkout_session.payment_intent_missing"],
            },
            p_ip: null,
            p_navigateur: "stripe-webhook",
          }, "Missing checkout PaymentIntent audit failed");
        }
        throw new Error(`Paid checkout ${session.id} has no PaymentIntent`);
      }
      const checkoutPaymentIntent = await stripe.paymentIntents.retrieve(
        sessionPaymentIntentId,
      );
      // Validation cryptographique/Stripe complète AVANT toute idempotence ou
      // écriture PAYEE : un ancien Checkout ne peut solder un montant modifié.
      const existingFacture = await loadAndValidateInvoicePayment(
        factureId,
        checkoutPaymentIntent,
        "checkout.session.completed",
        session,
      );

      if (
        existingFacture?.statut === "PAYEE"
        && existingFacture.stripe_payment_intent_id === checkoutPaymentIntent.id
      ) {
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
          stripe_payment_intent_id: checkoutPaymentIntent.id,
          stripe_hosted_url: session.url,
          modifie_le: new Date().toISOString(),
        })
        .eq("id", factureId)
        .eq("montant_ttc", existingFacture.montant_ttc)
        .or(
          `stripe_payment_intent_id.is.null,stripe_payment_intent_id.eq.${checkoutPaymentIntent.id}`,
        )
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
        await writeRequiredFinancialAudit(supabaseAdmin, {
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
        }, "Invalid invoice state audit failed");
        throw new Error(
          `Captured checkout cannot reconcile invoice ${factureId} in status ${factureInvalide?.statut || "missing"}`,
        );
      }

      // Alias pour la suite du bloc (audit + email) — factureUpdated tient déjà
      // numero_facture, etablissement_id, montant_ttc grâce au .select() ci-dessus.
      const facture = factureUpdated;

      // Write audit log
      if (facture) {
        await writeRequiredFinancialAudit(supabaseAdmin, {
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
        }, "Paid invoice audit failed");

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
      const validatedEscrow = await loadAndValidateEscrowPayment(pi, true);
      const escrowId = validatedEscrow.id;
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
          .eq("stripe_payment_intent_id", pi.id)
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
      const validatedEscrow = await loadAndValidateEscrowPayment(pi, false);
      const escrowId = validatedEscrow.id;
      if (escrowId) {
        const { data: incidentTarget, error: incidentTargetError } = await supabaseAdmin
          .from("paiements_escrow")
          .select("id")
          .eq("id", escrowId)
          .eq("statut", "INITIE")
          .eq("stripe_payment_intent_id", pi.id)
          .maybeSingle();
        if (incidentTargetError) {
          throw new Error(
            `Escrow failure target lookup failed: ${incidentTargetError.message}`,
          );
        }
        if (incidentTarget) {
          const failMsg = pi.last_payment_error?.message
            || pi.last_payment_error?.code
            || "payment_intent.payment_failed";
          const { error: escrowIncidentError } = await supabaseAdmin.rpc(
            "fn_escrow_marquer_echec_debit",
            {
              p_paiement_escrow_id: escrowId,
              p_detail: String(failMsg).substring(0, 500),
            },
          );
          if (escrowIncidentError) {
            throw new Error(`Escrow payment failure reconciliation failed: ${escrowIncidentError.message}`);
          }
        } else {
          console.warn(`Escrow ${escrowId} no longer INITIE; stale payment_failed ignored`);
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
        // Même l'événement payment_intent.succeeded signé ne suffit pas : son
        // identité comptable doit correspondre à l'état courant de la facture.
        const validatedPaymentIntentFacture = await loadAndValidateInvoicePayment(
          factureId,
          paymentIntent,
          "payment_intent.succeeded",
        );
        const { data: paymentIntentFactureUpdated, error: paymentIntentFactureError } =
          await supabaseAdmin
          .from("factures")
          .update({
            statut: "PAYEE",
            date_paiement: new Date().toISOString(),
            stripe_payment_intent_id: paymentIntent.id,
            modifie_le: new Date().toISOString(),
          })
          .eq("id", factureId)
          .eq("montant_ttc", validatedPaymentIntentFacture.montant_ttc)
          .or(
            `stripe_payment_intent_id.is.null,stripe_payment_intent_id.eq.${paymentIntent.id}`,
          )
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
      if (
        charge.payment_method_details?.type === "sepa_debit"
        && charge.metadata?.type === "commission_reservation"
      ) {
        const missionId = charge.metadata?.mission_id;
        if (missionId) {
          const chargePaymentIntentId = typeof charge.payment_intent === "string"
            ? charge.payment_intent
            : charge.payment_intent?.id || null;
          if (!chargePaymentIntentId) {
            throw new Error(`SEPA charge ${charge.id} missing PaymentIntent`);
          }
          const sepaPaymentIntent = await stripe.paymentIntents.retrieve(chargePaymentIntentId);
          const { data: paiementMission, error: paiementMissionError } = await supabaseAdmin
            .from("paiements_mission")
            .select("id, statut, montant_ttc, etablissement_id, stripe_payment_intent_id")
            .eq("mission_id", missionId)
            .eq("stripe_payment_intent_id", chargePaymentIntentId)
            .maybeSingle();
          const { data: mission, error: missionLookupError } = await supabaseAdmin
            .from("missions")
            .select("etablissement_id, montant_commission_ttc, type_contrat_applique")
            .eq("id", missionId)
            .maybeSingle();
          const { data: etablissement, error: etablissementLookupError } = mission?.etablissement_id
            ? await supabaseAdmin
              .from("etablissements")
              .select("stripe_customer_id")
              .eq("id", mission.etablissement_id)
              .maybeSingle()
            : { data: null, error: null };
          const expectedCents = Math.round(Number(paiementMission?.montant_ttc ?? 0) * 100);
          const piCustomerId = typeof sepaPaymentIntent.customer === "string"
            ? sepaPaymentIntent.customer
            : sepaPaymentIntent.customer?.id || null;
          const stripeCustomer = piCustomerId
            ? await stripe.customers.retrieve(piCustomerId)
            : null;
          const stripeCustomerIsValid = Boolean(
            stripeCustomer
            && !("deleted" in stripeCustomer && stripeCustomer.deleted)
            && stripeCustomer.metadata?.etablissement_id === mission?.etablissement_id,
          );
          if (
            missionLookupError || !mission || paiementMissionError || !paiementMission
            || etablissementLookupError
            || paiementMission.etablissement_id !== mission.etablissement_id
            || paiementMission.stripe_payment_intent_id !== sepaPaymentIntent.id
            || !["EN_ATTENTE", "AUTORISE", "CAPTURE"].includes(paiementMission.statut)
            || sepaPaymentIntent.status !== "succeeded"
            || sepaPaymentIntent.amount !== expectedCents
            || sepaPaymentIntent.amount_received !== expectedCents
            || sepaPaymentIntent.currency !== "eur"
            || piCustomerId !== etablissement?.stripe_customer_id
            || !stripeCustomerIsValid
            || sepaPaymentIntent.metadata?.mission_id !== missionId
            || sepaPaymentIntent.metadata?.etablissement_id !== mission.etablissement_id
            || sepaPaymentIntent.metadata?.type !== "commission_reservation"
            || charge.amount !== expectedCents
            || charge.currency !== "eur"
          ) {
            throw new Error(
              `SEPA mission payment identity mismatch: ${missionLookupError?.message || paiementMissionError?.message || "invalid binding"}`,
            );
          }

          const { data: paymentCaptured, error: paymentCaptureError } = await supabaseAdmin
            .from("paiements_mission")
            .update({
              statut: "CAPTURE",
              capture_le: new Date().toISOString(),
              stripe_charge_id: charge.id,
            })
            .eq("id", paiementMission.id)
            .eq("stripe_payment_intent_id", sepaPaymentIntent.id)
            .eq("montant_ttc", paiementMission.montant_ttc)
            .in("statut", ["EN_ATTENTE", "AUTORISE"])
            .select("id")
            .maybeSingle();
          if (paymentCaptureError || (!paymentCaptured && paiementMission.statut !== "CAPTURE")) {
            throw new Error(
              `SEPA payment reconciliation failed: ${paymentCaptureError?.message || "row missing"}`,
            );
          }

          // Mark commission as invoiced
          const { data: commissionMissionUpdated, error: commissionMissionError } = await supabaseAdmin
            .from("missions")
            .update({ commission_facturee: true, modifie_le: new Date().toISOString() })
            .eq("id", missionId)
            .eq("etablissement_id", mission.etablissement_id)
            .eq("montant_commission_ttc", mission.montant_commission_ttc)
            .select("id")
            .maybeSingle();
          if (commissionMissionError || !commissionMissionUpdated) {
            throw new Error(
              `SEPA mission reconciliation failed: ${commissionMissionError?.message || "row missing"}`,
            );
          }

          // RGPD Art. 32 : audit du prélèvement SEPA
          if (mission?.etablissement_id) {
            await writeRequiredFinancialAudit(supabaseAdmin, {
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
            }, "SEPA capture audit failed");
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
        .eq("stripe_invoice_id", stripeInvoiceId)
        .in("statut", ["EMISE", "EN_RETARD"]);

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
          .eq("stripe_checkout_session_id", expiredSession.id)
          .eq("statut", "EN_ATTENTE");
        if (checkoutExpiryError) {
          throw new Error(`Expired checkout reconciliation failed: ${checkoutExpiryError.message}`);
        }
        await releaseStripePaymentFlowClaimForExpiredSession(
          supabaseAdmin,
          "CONNECT_MISSION",
          expiredSession.id,
        );

        console.log(`Connect checkout expired for mission ${expiredMissionId}, transfer reset to ECHOUE`);
      }

      // For facture payments, just log — the facture stays EMISE
      const expiredFactureId = expiredSession.metadata?.facture_id;
      if (expiredFactureId) {
        await releaseStripePaymentFlowClaimForExpiredSession(
          supabaseAdmin,
          "CHECKOUT_INVOICE",
          expiredSession.id,
        );
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
      const paymentIntentId = stripeObjectId(charge.payment_intent);
      if (paymentIntentId) {
        const failedPaymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
        const factureId = failedPaymentIntent.metadata?.facture_id || "";
        // Connect et escrow n'ont pas de facture commission standard dans ce
        // flux. Sans metadata facture exacte, l'événement reste informatif.
        if (factureId) {
          const { data: facture, error: failedChargeLookupError } = await supabaseAdmin
            .from("factures")
            .select(
              "id, numero_facture, type_document, etablissement_id, montant_ttc, statut, stripe_payment_intent_id, etablissements(stripe_customer_id)",
            )
            .eq("id", factureId)
            .maybeSingle();
          if (failedChargeLookupError || !facture) {
            throw new Error(
              `Failed charge invoice lookup failed: ${failedChargeLookupError?.message || "row missing"}`,
            );
          }
          if (facture.type_document !== "FACTURE") {
            throw new Error(`Failed charge cannot mutate ${facture.type_document}`);
          }
          const relation = facture.etablissements as
            | { stripe_customer_id?: string | null }
            | Array<{ stripe_customer_id?: string | null }>
            | null;
          const customerId = (Array.isArray(relation)
            ? relation[0]?.stripe_customer_id
            : relation?.stripe_customer_id) || "";
          const amountCents = Math.round(Number(facture.montant_ttc ?? 0) * 100);
          const chargeCustomerId = typeof charge.customer === "string"
            ? charge.customer
            : charge.customer?.id || null;
          const incoherences: string[] = [
            ...findInvoicePaymentIntentInconsistencies(
              failedPaymentIntent,
              {
                factureId: facture.id,
                etablissementId: facture.etablissement_id,
                customerId,
                amountCents,
                currency: "eur",
              },
            ),
          ];
          if (
            !Number.isSafeInteger(amountCents) || amountCents <= 0
            || charge.amount !== amountCents
            || charge.currency !== "eur"
            || chargeCustomerId !== customerId
            || stripeObjectId(charge.payment_intent) !== failedPaymentIntent.id
            || stripeObjectId(failedPaymentIntent.latest_charge) !== charge.id
            || charge.status !== "failed"
            || charge.paid
          ) incoherences.push("charge.identity");
          if (customerId) {
            const customer = await stripe.customers.retrieve(customerId);
            if (
              customer.deleted
              || customer.metadata?.etablissement_id !== facture.etablissement_id
            ) incoherences.push("customer.tenant_metadata");
          }
          if (incoherences.length > 0) {
            throw new Error(`Failed charge identity mismatch: ${incoherences.join(",")}`);
          }

          const isCurrentAttempt = !facture.stripe_payment_intent_id
            || facture.stripe_payment_intent_id === paymentIntentId;
          let failedChargeUpdated: { id: string } | null = null;
          if (isCurrentAttempt && ["EMISE", "EN_RETARD"].includes(facture.statut)) {
            let failedChargeUpdateQuery = supabaseAdmin
              .from("factures")
              .update({
                statut: "EN_RETARD",
                stripe_payment_intent_id: paymentIntentId,
                modifie_le: new Date().toISOString(),
              })
              .eq("id", facture.id)
              .eq("montant_ttc", facture.montant_ttc)
              .in("statut", ["EMISE", "EN_RETARD"]);
            failedChargeUpdateQuery = facture.stripe_payment_intent_id
              ? failedChargeUpdateQuery.eq(
                "stripe_payment_intent_id",
                facture.stripe_payment_intent_id,
              )
              : failedChargeUpdateQuery.is("stripe_payment_intent_id", null);
            const { data, error: failedChargeUpdateError } = await failedChargeUpdateQuery
              .select("id")
              .maybeSingle();
            failedChargeUpdated = data;
            if (failedChargeUpdateError) {
              throw new Error(`Failed charge invoice reconciliation failed: ${failedChargeUpdateError.message}`);
            }
          }

          let reconciliation = failedChargeUpdated ? "MARKED_OVERDUE" : "STALE_OR_TERMINAL";
          if (!failedChargeUpdated) {
            const { data: concurrentFacture, error: concurrentFactureError } = await supabaseAdmin
              .from("factures")
              .select("statut, stripe_payment_intent_id")
              .eq("id", facture.id)
              .maybeSingle();
            if (concurrentFactureError || !concurrentFacture) {
              throw new Error(
                `Failed charge invoice state lookup failed: ${concurrentFactureError?.message || "row missing"}`,
              );
            }
            const staleAttempt = Boolean(
              concurrentFacture.stripe_payment_intent_id
              && concurrentFacture.stripe_payment_intent_id !== paymentIntentId,
            );
            const alreadyReconciled = concurrentFacture.statut === "EN_RETARD"
              && concurrentFacture.stripe_payment_intent_id === paymentIntentId;
            const terminalInvoice = ["PAYEE", "ANNULEE"].includes(concurrentFacture.statut);
            if (!staleAttempt && !alreadyReconciled && !terminalInvoice) {
              throw new Error(`Failed charge cannot reconcile invoice ${facture.id}`);
            }
            reconciliation = staleAttempt
              ? "STALE_ATTEMPT_IGNORED"
              : alreadyReconciled
              ? "ALREADY_RECONCILED"
              : "TERMINAL_INVOICE_IGNORED";
          }

          // Notif étab
          if (failedChargeUpdated) try {
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

          await writeRequiredFinancialAudit(supabaseAdmin, {
            p_acteur_id: facture.etablissement_id,
            p_type_acteur: "SYSTEME",
            p_action: "FINANCE_CHARGE_FAILED",
            p_type_ressource: "facture",
            p_id_ressource: facture.id,
            p_cle_s3: null,
            p_details: {
              stripe_charge_id: charge.id,
              stripe_payment_intent_id: paymentIntentId,
              failure_code: charge.failure_code,
              failure_message: charge.failure_message,
              amount: charge.amount,
              current_attempt: isCurrentAttempt,
              invoice_status: facture.statut,
              reconciliation,
            },
            p_ip: null,
            p_navigateur: "stripe-webhook",
          }, "Failed charge audit failed");
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

      await writeRequiredFinancialAudit(supabaseAdmin, {
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
      }, "Dispute creation audit failed");
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

      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: transfer?.etablissement_id || "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_DISPUTE_CLOSE",
        p_type_ressource: "mission",
        p_id_ressource: transfer?.mission_id || null,
        p_cle_s3: null,
        p_details: { dispute_id: dispute.id, status: dispute.status, amount: dispute.amount },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      }, "Dispute closure audit failed");
      console.log(`charge.dispute.closed handled: ${dispute.id} → ${dispute.status}`);
    }

    // ── charge.refunded : rapprochement exact Refund → queue → avoir/escrow ──
    if (verified.source === "PLATFORM" && event.type === "charge.refunded") {
      const charge = event.data.object as Stripe.Charge;
      const paymentIntentId = stripeObjectId(charge.payment_intent);
      if (!paymentIntentId) throw new Error(`Refunded charge ${charge.id} missing PaymentIntent`);
      const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
      if (
        stripeObjectId(paymentIntent.latest_charge) !== charge.id
        || charge.currency !== "eur"
      ) {
        throw new Error(`Refunded charge ${charge.id} source mismatch`);
      }

      const refunds: Stripe.Refund[] = [];
      let refundStartingAfter: string | undefined;
      do {
        const page = await stripe.refunds.list({
          charge: charge.id,
          limit: 100,
          ...(refundStartingAfter ? { starting_after: refundStartingAfter } : {}),
        });
        refunds.push(...page.data);
        refundStartingAfter = page.has_more ? page.data.at(-1)?.id : undefined;
      } while (refundStartingAfter);

      const succeededRefundAmount = refunds
        .filter((refund) => refund.status === "succeeded")
        .reduce((sum, refund) => sum + refund.amount, 0);
      if (succeededRefundAmount !== charge.amount_refunded) {
        throw new Error(
          `Refunded charge ${charge.id} amount mismatch (${succeededRefundAmount}/${charge.amount_refunded})`,
        );
      }

      const queueRefunds = refunds.filter((refund) => Boolean(refund.metadata?.queue_id));
      const queueIds = new Set<string>();
      for (const refund of queueRefunds) {
        const queueId = refund.metadata?.queue_id || "";
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(queueId)) {
          throw new Error(`Refund ${refund.id} has invalid queue metadata`);
        }
        if (queueIds.has(queueId)) {
          throw new Error(`Multiple refunds claim queue ${queueId}`);
        }
        queueIds.add(queueId);

        const { data: queueRow, error: queueError } = await supabaseAdmin
          .from("stripe_refunds_queue")
          .select(
            "id, avoir_id, facture_origine_id, paiement_escrow_id, stripe_payment_intent_id, montant_cts, statut, stripe_refund_id, reverse_transfer, refund_application_fee_cts, absorbe_plateforme, escrow_statut_avant_remboursement",
          )
          .eq("id", queueId)
          .maybeSingle();
        if (queueError || !queueRow) {
          throw new Error(
            `Refund queue lookup failed: ${queueError?.message || "row missing"}`,
          );
        }

        const incoherences: string[] = [];
        if (queueRow.stripe_payment_intent_id !== paymentIntentId) {
          incoherences.push("queue.payment_intent");
        }
        if (
          queueRow.stripe_refund_id
          && queueRow.stripe_refund_id !== refund.id
        ) incoherences.push("queue.refund_id");
        if (refund.amount !== queueRow.montant_cts) incoherences.push("refund.amount");
        if (refund.currency !== "eur") incoherences.push("refund.currency");
        if (stripeObjectId(refund.charge) !== charge.id) incoherences.push("refund.charge");
        if (stripeObjectId(refund.payment_intent) !== paymentIntentId) {
          incoherences.push("refund.payment_intent");
        }
        if ((refund.metadata?.avoir_id || "") !== (queueRow.avoir_id || "")) {
          incoherences.push("refund.avoir_id");
        }
        if (
          (refund.metadata?.facture_origine_id || "")
          !== (queueRow.facture_origine_id || "")
        ) incoherences.push("refund.facture_origine_id");
        if (
          (refund.metadata?.paiement_escrow_id || "")
          !== (queueRow.paiement_escrow_id || "")
        ) incoherences.push("refund.paiement_escrow_id");
        const expectedOrigin = queueRow.paiement_escrow_id ? "ESCROW" : "AVOIR";
        if (refund.metadata?.source !== "jolene_refunds_cron") {
          incoherences.push("refund.source");
        }
        if (refund.metadata?.origin_type !== expectedOrigin) {
          incoherences.push("refund.origin_type");
        }
        if (refund.metadata?.reverse_transfer !== String(queueRow.reverse_transfer)) {
          incoherences.push("refund.reverse_transfer");
        }
        if (refund.metadata?.absorbe_plateforme !== String(queueRow.absorbe_plateforme)) {
          incoherences.push("refund.absorbe_plateforme");
        }
        if (
          refund.metadata?.refund_application_fee_cts
          !== String(queueRow.refund_application_fee_cts)
        ) incoherences.push("refund.refund_application_fee_cts");
        if (
          refund.status === "succeeded"
          && queueRow.reverse_transfer
          && !refund.transfer_reversal
        ) incoherences.push("refund.transfer_reversal");

        if (queueRow.avoir_id) {
          const { data: avoir, error: avoirError } = await supabaseAdmin
            .from("factures_honoraires")
            .select(
              "id, type_document, statut, mode_remboursement, facture_precedente_id, montant_ttc, reference_remboursement, etablissement_id, mission_id, soignant_id",
            )
            .eq("id", queueRow.avoir_id)
            .maybeSingle();
          const { data: factureOrigine, error: factureOrigineError } =
            queueRow.facture_origine_id
              ? await supabaseAdmin
                .from("factures_honoraires")
                .select(
                  "id, type_document, statut, montant_ttc, stripe_payment_intent_id, etablissement_id, mission_id, soignant_id",
                )
                .eq("id", queueRow.facture_origine_id)
                .maybeSingle()
              : { data: null, error: null };
          const avoirCents = Math.round(Math.abs(Number(avoir?.montant_ttc ?? 0)) * 100);
          if (avoirError || !avoir) incoherences.push("avoir.missing");
          else {
            if (avoir.type_document !== "AVOIR") incoherences.push("avoir.type_document");
            if (avoir.mode_remboursement !== "AUTO_STRIPE") {
              incoherences.push("avoir.mode_remboursement");
            }
            if (avoirCents !== queueRow.montant_cts) incoherences.push("avoir.amount");
            if (avoir.facture_precedente_id !== queueRow.facture_origine_id) {
              incoherences.push("avoir.facture_precedente_id");
            }
            if (
              avoir.statut === "REMBOURSE"
              && avoir.reference_remboursement !== refund.id
            ) incoherences.push("avoir.reference_remboursement");
          }
          if (factureOrigineError || !factureOrigine) {
            incoherences.push("facture_origine.missing");
          } else if (avoir) {
            if (factureOrigine.type_document !== "FACTURE") {
              incoherences.push("facture_origine.type_document");
            }
            if (factureOrigine.statut !== "PAYEE") {
              incoherences.push("facture_origine.statut");
            }
            if (factureOrigine.stripe_payment_intent_id !== paymentIntentId) {
              incoherences.push("facture_origine.payment_intent");
            }
            if (
              factureOrigine.etablissement_id !== avoir.etablissement_id
              || factureOrigine.mission_id !== avoir.mission_id
              || factureOrigine.soignant_id !== avoir.soignant_id
            ) incoherences.push("avoir.facture_origine_identity");
            if (refund.metadata?.mission_id !== (avoir.mission_id || "")) {
              incoherences.push("refund.mission_id");
            }
            if (refund.metadata?.etablissement_id !== avoir.etablissement_id) {
              incoherences.push("refund.etablissement_id");
            }
          }
          if (
            queueRow.paiement_escrow_id
            || queueRow.reverse_transfer
            || queueRow.absorbe_plateforme
            || Number(queueRow.refund_application_fee_cts) !== 0
          ) incoherences.push("avoir.queue_flags");
        }

        if (queueRow.paiement_escrow_id) {
          const { data: escrow, error: escrowError } = await supabaseAdmin
            .from("paiements_escrow")
            .select(
              "id, mission_id, etablissement_id, soignant_id, stripe_payment_intent_id, montant_total_cents, honoraires_cents, commission_cents, statut",
            )
            .eq("id", queueRow.paiement_escrow_id)
            .maybeSingle();
          if (escrowError || !escrow) incoherences.push("escrow.missing");
          else {
            if (escrow.stripe_payment_intent_id !== paymentIntentId) {
              incoherences.push("escrow.payment_intent");
            }
            if (queueRow.montant_cts > Number(escrow.montant_total_cents || 0)) {
              incoherences.push("escrow.amount");
            }
            if (!['REMBOURSE_EN_COURS', 'REMBOURSE'].includes(escrow.statut)) {
              incoherences.push("escrow.statut");
            }
            const prior = queueRow.escrow_statut_avant_remboursement;
            const beforeRelease = prior === "DEBITE" || prior === "DISPONIBLE";
            const afterRelease = prior === "PAYE";
            const honorairesRefund = Number(queueRow.montant_cts)
              - Number(queueRow.refund_application_fee_cts);
            const expectedFee = honorairesRefund === Number(escrow.honoraires_cents)
              ? Number(escrow.commission_cents)
              : Math.round(
                Number(escrow.commission_cents) * honorairesRefund
                  / Number(escrow.honoraires_cents),
              );
            if (
              (!beforeRelease && !afterRelease)
              || queueRow.reverse_transfer !== beforeRelease
              || queueRow.absorbe_plateforme !== afterRelease
              || honorairesRefund <= 0
              || honorairesRefund > Number(escrow.honoraires_cents)
              || Number(queueRow.refund_application_fee_cts) !== expectedFee
              || (beforeRelease && honorairesRefund !== Number(escrow.honoraires_cents))
              || queueRow.avoir_id
              || queueRow.facture_origine_id
            ) incoherences.push("escrow.queue_flags");
            if (
              paymentIntent.metadata?.type !== "ESCROW_MISSION_PAYMENT"
              || paymentIntent.metadata?.paiement_escrow_id !== escrow.id
              || paymentIntent.metadata?.mission_id !== escrow.mission_id
              || paymentIntent.metadata?.etablissement_id !== escrow.etablissement_id
              || paymentIntent.metadata?.soignant_id !== escrow.soignant_id
              || Number(paymentIntent.metadata?.honoraires_cents)
                !== Number(escrow.honoraires_cents)
              || Number(paymentIntent.metadata?.commission_cents)
                !== Number(escrow.commission_cents)
              || paymentIntent.amount !== Number(escrow.montant_total_cents)
              || paymentIntent.application_fee_amount !== Number(escrow.commission_cents)
            ) incoherences.push("escrow.payment_provenance");
            if (refund.metadata?.mission_id !== escrow.mission_id) {
              incoherences.push("refund.mission_id");
            }
            if (refund.metadata?.etablissement_id !== escrow.etablissement_id) {
              incoherences.push("refund.etablissement_id");
            }
          }
        }

        // Un paiement Connect utilise un separate transfer. Même un Refund
        // exact ne peut solder la queue tant que le reversal exact n'est pas
        // confirmé côté plateforme ET côté Stripe.
        if (paymentIntent.metadata?.type === "CONNECT_MISSION_PAYMENT") {
          const { data: transferRow, error: transferError } = await supabaseAdmin
            .from("stripe_transfers")
            .select("stripe_transfer_id, statut, reversed_le")
            .eq("stripe_payment_intent_id", paymentIntentId)
            .maybeSingle();
          if (
            transferError || !transferRow?.stripe_transfer_id
            || transferRow.statut !== "REMBOURSE" || !transferRow.reversed_le
          ) {
            incoherences.push("connect.transfer_not_reversed");
          } else {
            const transferStripe = await stripe.transfers.retrieve(
              transferRow.stripe_transfer_id,
            );
            if (!transferStripe.reversed || transferStripe.amount_reversed < transferStripe.amount) {
              incoherences.push("connect.stripe_transfer_not_reversed");
            }
          }
        }

        if (incoherences.length > 0) {
          await writeRequiredFinancialAudit(supabaseAdmin, {
            p_acteur_id: "00000000-0000-0000-0000-000000000000",
            p_type_acteur: "SYSTEME",
            p_action: "ADMIN_ACTION",
            p_type_ressource: "stripe_refunds_queue",
            p_id_ressource: queueId,
            p_cle_s3: null,
            p_details: {
              evenement: "REFUND_IDENTITE_INCOHERENTE",
              stripe_refund_id: refund.id,
              stripe_charge_id: charge.id,
              incoherences,
            },
            p_ip: null,
            p_navigateur: "stripe-webhook",
          }, "Refund mismatch audit failed");
          throw new Error(`Refund ${refund.id} identity mismatch: ${incoherences.join(",")}`);
        }

        const status = refund.status || "";
        if (!["succeeded", "failed", "canceled"].includes(status)) {
          throw new Error(`Refund ${refund.id} not terminal (${status || "unknown"})`);
        }
        const { data: rapprochement, error: rapprochementError } = await supabaseAdmin.rpc(
          "fn_stripe_refund_rapprocher",
          {
            p_queue_id: queueId,
            p_stripe_refund_id: refund.id,
            p_resultat: status.toUpperCase(),
            p_detail: refund.failure_reason || null,
            p_finalise_le: new Date().toISOString(),
          },
        );
        const rapprochementResult = rapprochement as { success?: boolean; error?: string } | null;
        if (rapprochementError || rapprochementResult?.success !== true) {
          throw new Error(
            `Refund reconciliation failed: ${rapprochementError?.message || rapprochementResult?.error || "RPC rejected"}`,
          );
        }
      }

      // Ne jamais acquitter silencieusement un Refund réussi sans queue_id.
      // Les refunds du worker legacy portent externalisation_action_id ; un
      // refund Dashboard/non géré déclenche un gel escrow ou un recouvrement
      // standard explicite avant que l'événement soit acquitté.
      const nonQueueSucceededRefunds = refunds.filter(
        (refund) => refund.status === "succeeded" && !refund.metadata?.queue_id,
      );
      const anomalyRefundIds: string[] = [];
      const externalisationRefundIds: string[] = [];
      for (const refund of nonQueueSucceededRefunds) {
        if (
          stripeObjectId(refund.charge) !== charge.id
          || stripeObjectId(refund.payment_intent) !== paymentIntentId
          || refund.currency !== "eur"
          || refund.amount <= 0
        ) {
          throw new Error(`Non-queue refund ${refund.id} source mismatch`);
        }

        const actionId = refund.metadata?.externalisation_action_id;
        if (actionId) {
          const { data: action, error: actionError } = await supabaseAdmin
            .from("externalisation_actions")
            .select("id, type_action, payload, statut")
            .eq("id", actionId)
            .maybeSingle();
          const missionId = action?.payload?.mission_id;
          const { data: mission, error: missionError } = missionId
            ? await supabaseAdmin
              .from("missions")
              .select("id, etablissement_id, stripe_payment_intent_id")
              .eq("id", missionId)
              .maybeSingle()
            : { data: null, error: null };
          if (
            actionError || !action || missionError || !mission
            || !["STRIPE_REFUND_TOTAL", "STRIPE_REFUND_PARTIEL"].includes(action.type_action)
            || mission.stripe_payment_intent_id !== paymentIntentId
            || refund.metadata?.mission_id !== mission.id
            || refund.metadata?.etablissement_id !== mission.etablissement_id
            || refund.metadata?.source !== "process_externalisation_actions"
          ) {
            throw new Error(
              `Externalisation refund ${refund.id} identity mismatch: ${actionError?.message || missionError?.message || "invalid binding"}`,
            );
          }
          const { data: actionAck, error: actionAckError } = await supabaseAdmin.rpc(
            "fn_externalisation_succes",
            {
              p_id: action.id,
              p_resultat: {
                refund_id: refund.id,
                payment_intent_id: paymentIntentId,
                charge_id: charge.id,
                amount: refund.amount,
                status: refund.status,
                source: "stripe_webhook",
              },
            },
          );
          if (actionAckError || actionAck?.success !== true) {
            throw new Error(
              `Externalisation refund ${refund.id} acknowledgement failed: ${actionAckError?.message || JSON.stringify(actionAck)}`,
            );
          }
          externalisationRefundIds.push(refund.id);
          continue;
        }

        const { data: escrow, error: escrowError } = await supabaseAdmin
          .from("paiements_escrow")
          .select("id, mission_id, etablissement_id, statut")
          .eq("stripe_payment_intent_id", paymentIntentId)
          .maybeSingle();
        if (escrowError) {
          throw new Error(`Unmanaged refund escrow lookup failed: ${escrowError.message}`);
        }
        if (escrow) {
          const { error: escrowIncidentError } = await supabaseAdmin.rpc(
            "fn_escrow_marquer_incident",
            {
              p_paiement_escrow_id: escrow.id,
              p_type_incident: "DISPUTE",
              p_detail: `Refund Stripe non géré ${refund.id} — payout bloqué`,
            },
          );
          if (escrowIncidentError) {
            throw new Error(
              `Unmanaged escrow refund freeze failed: ${escrowIncidentError.message}`,
            );
          }
          anomalyRefundIds.push(refund.id);
          continue;
        }

        const { data: invoice, error: invoiceError } = await supabaseAdmin
          .from("factures")
          .select("id, statut, montant_ttc, etablissement_id, etablissements(stripe_customer_id)")
          .eq("stripe_payment_intent_id", paymentIntentId)
          .maybeSingle();
        if (invoiceError) {
          throw new Error(`Unmanaged refund invoice lookup failed: ${invoiceError.message}`);
        }
        if (invoice) {
          const relation = invoice.etablissements as
            | { stripe_customer_id?: string | null }
            | Array<{ stripe_customer_id?: string | null }>
            | null;
          const expectedCustomerId = (Array.isArray(relation)
            ? relation[0]?.stripe_customer_id
            : relation?.stripe_customer_id) || null;
          if (
            Math.round(Number(invoice.montant_ttc) * 100) !== paymentIntent.amount
            || paymentIntent.metadata?.facture_id !== invoice.id
            || paymentIntent.metadata?.etablissement_id !== invoice.etablissement_id
            || stripeObjectId(paymentIntent.customer) !== expectedCustomerId
          ) {
            throw new Error(`Unmanaged invoice refund ${refund.id} identity mismatch`);
          }
          const { data: invoiceRecovery, error: invoiceRecoveryError } = await supabaseAdmin
            .from("factures")
            .update({ statut: "EN_RETARD", modifie_le: new Date().toISOString() })
            .eq("id", invoice.id)
            .eq("statut", "PAYEE")
            .eq("stripe_payment_intent_id", paymentIntentId)
            .select("id")
            .maybeSingle();
          if (
            invoiceRecoveryError
            || (!invoiceRecovery && invoice.statut !== "EN_RETARD")
          ) {
            throw new Error(
              `Unmanaged invoice refund recovery failed: ${invoiceRecoveryError?.message || "state conflict"}`,
            );
          }
          anomalyRefundIds.push(refund.id);
          continue;
        }

        const { data: missionPayment, error: missionPaymentError } = await supabaseAdmin
          .from("paiements_mission")
          .select("id, mission_id, etablissement_id, montant_ttc, statut")
          .eq("stripe_payment_intent_id", paymentIntentId)
          .maybeSingle();
        if (missionPaymentError) {
          throw new Error(
            `Unmanaged refund mission-payment lookup failed: ${missionPaymentError.message}`,
          );
        }
        if (missionPayment) {
          if (
            paymentIntent.metadata?.type !== "commission_reservation"
            || paymentIntent.metadata?.mission_id !== missionPayment.mission_id
            || paymentIntent.metadata?.etablissement_id !== missionPayment.etablissement_id
            || Math.round(Number(missionPayment.montant_ttc) * 100) !== paymentIntent.amount
          ) {
            throw new Error(`Unmanaged mission refund ${refund.id} identity mismatch`);
          }
          const { data: missionRefunded, error: missionRefundError } = await supabaseAdmin
            .from("paiements_mission")
            .update({ statut: "REMBOURSE", rembourse_le: new Date().toISOString() })
            .eq("id", missionPayment.id)
            .eq("statut", "CAPTURE")
            .eq("stripe_payment_intent_id", paymentIntentId)
            .select("id")
            .maybeSingle();
          if (
            missionRefundError
            || (!missionRefunded && missionPayment.statut !== "REMBOURSE")
          ) {
            throw new Error(
              `Unmanaged mission refund persistence failed: ${missionRefundError?.message || "state conflict"}`,
            );
          }
          anomalyRefundIds.push(refund.id);
          continue;
        }

        await writeRequiredFinancialAudit(supabaseAdmin, {
          p_acteur_id: "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: "ADMIN_ACTION",
          p_type_ressource: "charge",
          p_id_ressource: null,
          p_cle_s3: null,
          p_details: {
            evenement: "STRIPE_REFUND_SANS_PROVENANCE",
            stripe_event_id: event.id,
            stripe_refund_id: refund.id,
            stripe_charge_id: charge.id,
            stripe_payment_intent_id: paymentIntentId,
            montant_cts: refund.amount,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        }, "Unmanaged refund audit failed");
        throw new Error(`Unmanaged Stripe refund ${refund.id} has no business provenance`);
      }

      await writeRequiredFinancialAudit(supabaseAdmin, {
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
          refunds_queue_rapproches: queueRefunds.map((refund) => refund.id),
          refunds_externalisation_rapproches: externalisationRefundIds,
          refunds_anormaux_mis_en_securite: anomalyRefundIds,
        },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      }, "Refunded charge audit failed");
      console.log(`charge.refunded handled: ${charge.id}`);
    }

    // ── transfer.reversed : transfer annulé ──
    if (verified.source === "PLATFORM" && event.type === "transfer.reversed") {
      const eventTransfer = event.data.object as Stripe.Transfer;
      // Relire l'objet courant : un ancien événement partiel livré après le
      // reversal total ne doit jamais faire régresser le cumul local.
      const transfer = await stripe.transfers.retrieve(eventTransfer.id);
      const { data: row, error: reversedTransferLookupError } = await supabaseAdmin
        .from("stripe_transfers")
        .select(
          "id, mission_id, soignant_id, etablissement_id, facture_honoraire_id, montant_soignant, statut, stripe_charge_id, stripe_amount_reversed_cents, stripe_reversal_statut",
        )
        .eq("stripe_transfer_id", transfer.id)
        .maybeSingle();
      if (reversedTransferLookupError) {
        throw new Error(`Reversed transfer lookup failed: ${reversedTransferLookupError.message}`);
      }

      if (row) {
        const { data: onboarding, error: onboardingError } = await supabaseAdmin
          .from("stripe_connect_onboarding")
          .select("stripe_account_id")
          .eq("soignant_id", row.soignant_id)
          .maybeSingle();
        const expectedAmount = Math.round(Number(row.montant_soignant) * 100);
        const destinationId = stripeObjectId(transfer.destination);
        const sourceChargeId = stripeObjectId(transfer.source_transaction);
        const missionTransferGroup = `mission_${row.mission_id}`;
        const invoiceTransferGroup = row.facture_honoraire_id
          ? `facture_${row.facture_honoraire_id}`
          : null;
        const paymentScope = transfer.metadata?.payment_scope || "";
        const metadataFactureId = transfer.metadata?.facture_honoraires_id || "";
        const missionGroupMatches = transfer.transfer_group === missionTransferGroup;
        const invoiceGroupMatches = Boolean(
          invoiceTransferGroup && transfer.transfer_group === invoiceTransferGroup
        );
        const metadataFactureMatches = Boolean(
          row.facture_honoraire_id && metadataFactureId === row.facture_honoraire_id
        );
        const incoherences: string[] = [];
        if (!Number.isSafeInteger(expectedAmount) || expectedAmount <= 0) {
          incoherences.push("db.amount");
        }
        if (transfer.amount !== expectedAmount) incoherences.push("transfer.amount");
        if (transfer.currency !== "eur") incoherences.push("transfer.currency");
        if (transfer.metadata?.mission_id !== row.mission_id) {
          incoherences.push("transfer.mission_id");
        }
        if (transfer.metadata?.soignant_id !== row.soignant_id) {
          incoherences.push("transfer.soignant_id");
        }
        // Les paiements historiques n'avaient pas payment_scope. Leur groupe
        // canonique reste vérifiable depuis la ligne locale : mission_<id> ou,
        // pour une facture hebdomadaire, facture_<facture_honoraire_id>.
        let groupScopeValid = false;
        if (paymentScope === "MISSION") {
          groupScopeValid = missionGroupMatches
            && (!metadataFactureId || metadataFactureMatches);
        } else if (paymentScope === "INVOICE") {
          groupScopeValid = invoiceGroupMatches && metadataFactureMatches;
        } else if (!paymentScope) {
          groupScopeValid = missionGroupMatches
            || (invoiceGroupMatches && (!metadataFactureId || metadataFactureMatches));
        }
        if (!groupScopeValid) {
          incoherences.push("transfer.group_scope");
        }
        if (onboardingError || destinationId !== onboarding?.stripe_account_id) {
          incoherences.push("transfer.destination");
        }
        if (row.stripe_charge_id && sourceChargeId !== row.stripe_charge_id) {
          incoherences.push("transfer.source_charge");
        }
        if (
          transfer.amount_reversed <= 0
          || transfer.amount_reversed > transfer.amount
          || transfer.reversed !== (transfer.amount_reversed === transfer.amount)
        ) incoherences.push("transfer.reversal_totals");

        let reversalStartingAfter: string | undefined;
        let reversalSum = 0;
        do {
          const reversals = await stripe.transfers.listReversals(transfer.id, {
            limit: 100,
            ...(reversalStartingAfter ? { starting_after: reversalStartingAfter } : {}),
          });
          for (const reversal of reversals.data) {
            if (
              reversal.currency !== "eur"
              || stripeObjectId(reversal.transfer) !== transfer.id
              || !Number.isSafeInteger(reversal.amount)
              || reversal.amount <= 0
            ) incoherences.push(`reversal.${reversal.id}`);
            reversalSum += reversal.amount;
          }
          reversalStartingAfter = reversals.has_more
            ? reversals.data.at(-1)?.id
            : undefined;
          if (reversals.has_more && !reversalStartingAfter) {
            throw new Error(`Transfer ${transfer.id} reversal pagination incomplete`);
          }
        } while (reversalStartingAfter);
        if (reversalSum !== transfer.amount_reversed) {
          incoherences.push("reversals.sum");
        }

        if (incoherences.length > 0) {
          await writeRequiredFinancialAudit(supabaseAdmin, {
            p_acteur_id: row.soignant_id,
            p_type_acteur: "SYSTEME",
            p_action: "ADMIN_ACTION",
            p_type_ressource: "mission",
            p_id_ressource: row.mission_id,
            p_cle_s3: null,
            p_details: {
              evenement: "TRANSFER_REVERSAL_IDENTITE_INCOHERENTE",
              stripe_transfer_id: transfer.id,
              amount_reversed: transfer.amount_reversed,
              incoherences,
            },
            p_ip: null,
            p_navigateur: "stripe-webhook",
          }, "Transfer reversal mismatch audit failed");
          throw new Error(`Reversed transfer identity mismatch: ${incoherences.join(",")}`);
        }

        const reversalTotal = transfer.amount_reversed === transfer.amount;
        const { data: reversedTransferUpdated, error: reversedTransferError } = await supabaseAdmin
          .from("stripe_transfers")
          .update({
            ...(reversalTotal ? {
              statut: "REMBOURSE",
              reversed_le: new Date().toISOString(),
              erreur: null,
            } : {
              erreur: `Reversal partiel Stripe: ${transfer.amount_reversed}/${transfer.amount}`,
            }),
            stripe_amount_reversed_cents: transfer.amount_reversed,
            stripe_reversal_statut: reversalTotal ? "TOTAL" : "PARTIEL",
          })
          .eq("id", row.id)
          .eq("stripe_transfer_id", transfer.id)
          .in(
            "statut",
            reversalTotal
              ? ["TRANSFERE", "PAYE", "REMBOURSE"]
              : ["TRANSFERE", "PAYE"],
          )
          .lte("stripe_amount_reversed_cents", transfer.amount_reversed)
          .select("id")
          .maybeSingle();
        if (reversedTransferError || !reversedTransferUpdated) {
          throw new Error(
            `Reversed transfer reconciliation failed: ${reversedTransferError?.message || "state conflict"}`,
          );
        }
        await writeRequiredFinancialAudit(supabaseAdmin, {
          p_acteur_id: row.soignant_id,
          p_type_acteur: "SYSTEME",
          p_action: "FINANCE_TRANSFER_REVERSED",
          p_type_ressource: "mission",
          p_id_ressource: row.mission_id,
          p_cle_s3: null,
          p_details: {
            stripe_transfer_id: transfer.id,
            amount: transfer.amount,
            amount_reversed: transfer.amount_reversed,
            reversal_total: reversalTotal,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        }, "Transfer reversal audit failed");
      } else {
        throw new Error(`Reversed transfer ${transfer.id} has no local binding`);
      }
      console.log(`transfer.reversed handled: ${transfer.id}`);
    }

    // ── transfer.created : audit only ──
    if (verified.source === "PLATFORM" && event.type === "transfer.created") {
      const transfer = event.data.object as Stripe.Transfer;
      await writeRequiredFinancialAudit(supabaseAdmin, {
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
      }, "Transfer creation audit failed");
      console.log(`transfer.created audited: ${transfer.id}`);
    }

    // ── transfer.updated : audit only ──
    if (verified.source === "PLATFORM" && event.type === "transfer.updated") {
      const transfer = event.data.object as Stripe.Transfer;
      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_TRANSFER_UPDATED",
        p_type_ressource: "transfer",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: { stripe_transfer_id: transfer.id, metadata: transfer.metadata },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      }, "Transfer update audit failed");
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
      await writeRequiredFinancialAudit(supabaseAdmin, {
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
      }, "Payout creation audit failed");
      console.log(`payout.created audited: ${payout.id}`);
    }

    // ── payout.paid : argent arrivé sur compte soignant ──
    if (verified.source === "CONNECT" && event.type === "payout.paid") {
      const payout = event.data.object as Stripe.Payout;
      const connectedSoignantId = await requireConnectedSoignantId();

      // Payout escrow : confirmation atomique et exacte par escrow + payout +
      // compte Connect. C'est ici seulement que l'escrow devient PAYE.
      if (payout.metadata?.type === "ESCROW_RELEASE") {
        if (!eventAccount) {
          throw new Error("ESCROW_RELEASE payout metadata incomplete");
        }
        const validatedEscrowPayout = await loadAndValidateEscrowPayout(
          payout,
          connectedSoignantId,
          "paid",
        );
        const escrowId = validatedEscrowPayout.id;
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

        await writeRequiredFinancialAudit(supabaseAdmin, {
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
        }, "Escrow payout audit failed");
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

      await writeRequiredFinancialAudit(supabaseAdmin, {
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
      }, "Paid payout audit failed");
      console.log(`payout.paid handled: ${payout.id} → ${(transfersToMark || []).length} transfers marked PAYE`);
    }

    // ── payout.failed : payout échoué (RIB invalide, compte fermé, etc.) ──
    if (verified.source === "CONNECT" && event.type === "payout.failed") {
      const payout = event.data.object as Stripe.Payout;
      const connectedSoignantId = await requireConnectedSoignantId();
      const errMsg = payout.failure_message || "payout.failed";

      if (payout.metadata?.type === "ESCROW_RELEASE") {
        if (!eventAccount) {
          throw new Error("ESCROW_RELEASE payout metadata incomplete");
        }
        const validatedEscrowPayout = await loadAndValidateEscrowPayout(
          payout,
          connectedSoignantId,
          "failed",
        );
        const escrowId = validatedEscrowPayout.id;
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
        await writeRequiredFinancialAudit(supabaseAdmin, {
          p_acteur_id: "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: "ADMIN_ACTION",
          p_type_ressource: "mission",
          p_id_ressource: payout.metadata?.mission_id ?? null,
          p_cle_s3: null,
          p_details: {
            evenement: "ESCROW_RELEASE_ECHOUE",
            paiement_escrow_id: escrowId,
            stripe_payout_id: payout.id,
            stripe_account_id: eventAccount,
            soignant_id: connectedSoignantId,
            failure_code: payout.failure_code,
            transitioned: transitioned === true,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        }, "Escrow payout failure audit failed");
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

      await writeRequiredFinancialAudit(supabaseAdmin, {
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
      }, "Failed payout audit failed");
      console.log(`payout.failed handled: ${payout.id} → ${transfersArr.length} transfers marked ECHOUE`);
    }

    // ── payout.canceled : payout annulé ──
    if (verified.source === "CONNECT" && event.type === "payout.canceled") {
      const payout = event.data.object as Stripe.Payout;
      const connectedSoignantId = await requireConnectedSoignantId();

      if (payout.metadata?.type === "ESCROW_RELEASE") {
        if (!eventAccount) {
          throw new Error("ESCROW_RELEASE payout metadata incomplete");
        }
        const validatedEscrowPayout = await loadAndValidateEscrowPayout(
          payout,
          connectedSoignantId,
          "canceled",
        );
        const escrowId = validatedEscrowPayout.id;
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
        await writeRequiredFinancialAudit(supabaseAdmin, {
          p_acteur_id: "00000000-0000-0000-0000-000000000000",
          p_type_acteur: "SYSTEME",
          p_action: "ADMIN_ACTION",
          p_type_ressource: "mission",
          p_id_ressource: payout.metadata?.mission_id ?? null,
          p_cle_s3: null,
          p_details: {
            evenement: "ESCROW_RELEASE_ANNULE",
            paiement_escrow_id: escrowId,
            stripe_payout_id: payout.id,
            stripe_account_id: eventAccount,
            soignant_id: connectedSoignantId,
            transitioned: transitioned === true,
          },
          p_ip: null,
          p_navigateur: "stripe-webhook",
        }, "Escrow payout cancellation audit failed");
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

      await writeRequiredFinancialAudit(supabaseAdmin, {
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
      }, "Canceled payout audit failed");
      console.log(`payout.canceled handled: ${payout.id}`);
    }

    // ── charge.pending : charge en attente (SEPA) — audit only ──
    if (verified.source === "PLATFORM" && event.type === "charge.pending") {
      const charge = event.data.object as Stripe.Charge;
      await writeRequiredFinancialAudit(supabaseAdmin, {
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
      }, "Pending charge audit failed");
      console.log(`charge.pending audited: ${charge.id}`);
    }

    // ── charge.expired : charge non-capturée expirée — audit only ──
    if (verified.source === "PLATFORM" && event.type === "charge.expired") {
      const charge = event.data.object as Stripe.Charge;
      await writeRequiredFinancialAudit(supabaseAdmin, {
        p_acteur_id: "00000000-0000-0000-0000-000000000000",
        p_type_acteur: "SYSTEME",
        p_action: "FINANCE_CHARGE_EXPIRED",
        p_type_ressource: "charge",
        p_id_ressource: null,
        p_cle_s3: null,
        p_details: { stripe_charge_id: charge.id, amount: charge.amount },
        p_ip: null,
        p_navigateur: "stripe-webhook",
      }, "Expired charge audit failed");
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
