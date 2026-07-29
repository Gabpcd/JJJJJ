import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const root = process.cwd();
const edge = (slug: string) =>
  readFileSync(`${root}/supabase/functions/${slug}/index.ts`, "utf8");
const migration = readFileSync(
  `${root}/supabase/migrations/20260729121442_securiser_auth_et_crons_critiques.sql`,
  "utf8",
);

function handlerSource(slug: string): string {
  const source = edge(slug);
  const index = source.indexOf("Deno.serve");
  expect(index, `${slug}: Deno.serve absent`).toBeGreaterThanOrEqual(0);
  return source.slice(index);
}

function expectBefore(
  source: string,
  guard: string,
  effect: string,
  context: string,
): void {
  const guardIndex = source.indexOf(guard);
  const effectIndex = source.indexOf(effect);
  expect(guardIndex, `${context}: garde absente`).toBeGreaterThanOrEqual(0);
  expect(effectIndex, `${context}: effet témoin absent`).toBeGreaterThanOrEqual(0);
  expect(guardIndex, `${context}: effet avant garde`).toBeLessThan(effectIndex);
}

describe("comptes test exclus avant tout effet externe", () => {
  it("garde les paiements interactifs avant le premier appel Stripe", () => {
    for (const [slug, effect] of [
      ["create-invoice-payment", "await stripe.paymentIntents.retrieve"],
      ["confirm-invoice-payment", "new Stripe("],
      ["sepa-auto-charge", "await stripe.paymentIntents.retrieve"],
      ["setup-sepa", "new Stripe("],
      ["stripe-connect-onboard", "new Stripe("],
      ["stripe-connect-pay-mission", "new Stripe("],
    ] as const) {
      const source = handlerSource(slug);
      expectBefore(
        source,
        "resolveOperationalTestAccount(",
        effect,
        slug,
      );
      expect(source).toMatch(/TEST_ACCOUNT_|skipped_test/);
    }

    const disabledMissionPayment = handlerSource("create-mission-payment");
    expect(disabledMissionPayment).toContain("resolveOperationalTestAccount(");
    expect(disabledMissionPayment).toContain("TEST_ACCOUNT_PAYMENT_DISABLED");
    expect(disabledMissionPayment).not.toContain("new Stripe(");
    expect(disabledMissionPayment).not.toMatch(/await\s+stripe\./);
  });

  it("garde Defacto et les deux flux PISTE avant réseau ou mutation", () => {
    expectBefore(
      handlerSource("factor-request-advance"),
      "resolveOperationalTestAccount(",
      "provider.submitInvoice(",
      "factor-request-advance",
    );
    expectBefore(
      handlerSource("submit-to-chorus"),
      "resolveOperationalTestAccount(",
      "supabaseAdmin.storage",
      "submit-to-chorus",
    );
    expectBefore(
      handlerSource("chorus-pro-deposit"),
      "resolveOperationalTestAccount(",
      "getAccessToken(",
      "chorus-pro-deposit",
    );
    for (const slug of [
      "factor-request-advance",
      "submit-to-chorus",
      "chorus-pro-deposit",
    ]) {
      expect(handlerSource(slug)).toContain("test_skipped");
      expect(handlerSource(slug)).toContain("Classification");
    }
  });

  it("neutralise les webhooks plateforme et Connect avant le claim/métier", () => {
    const shared = readFileSync(
      `${root}/supabase/functions/_shared/stripe-webhook-handler.ts`,
      "utf8",
    );
    const handler = shared.slice(shared.indexOf("export async function handleStripeWebhook"));
    expectBefore(
      handler,
      "classifyStripeWebhookTestAccount(",
      '"fn_stripe_webhook_event_claim"',
      "stripe-webhook-handler",
    );
    expectBefore(
      handler,
      "if (testClassification.isTest)",
      "stripe.transfers.create(",
      "stripe-webhook-handler",
    );
    expect(handler).toContain('"STRIPE_WEBHOOK_TEST_SKIPPED"');
    expect(handler).toContain("await markEventProcessed()");
    expect(handler).toContain("test_skipped: true");

    expect(edge("stripe-webhook")).toContain(
      'handleStripeWebhook(req, "PLATFORM")',
    );
    expect(edge("stripe-connect-webhook")).toContain(
      'handleStripeWebhook(req, "CONNECT")',
    );
  });

  it("résout chaque webhook par tables canoniques, pas par metadata seule", () => {
    const shared = readFileSync(
      `${root}/supabase/functions/_shared/stripe-webhook-handler.ts`,
      "utf8",
    );
    const classifier = shared.slice(
      shared.indexOf("async function classifyStripeWebhookTestAccount"),
      shared.indexOf("// Audit escrow DIRECT"),
    );
    for (const table of [
      '"missions"',
      '"factures"',
      '"factures_honoraires"',
      '"paiements_escrow"',
      '"stripe_refunds_queue"',
      '"stripe_transfers"',
      '"etablissements"',
      '"stripe_connect_onboarding"',
    ]) {
      expect(classifier, `lookup canonique absent: ${table}`).toContain(table);
    }
    expect(classifier).toContain("resolveOperationalTestAccount(");
    expect(classifier).toContain("return { ok: false");
    expect(classifier).toContain(
      '["facture_id", "factures", "etablissement_id,mission_id"]',
    );
    expect(classifier).toContain(
      '"factures_honoraires",\n        "etablissement_id,soignant_id,mission_id"',
    );
  });

  it("filtre les files finance par JOIN et ne change pas les fixtures", () => {
    for (const functionName of [
      "fn_escrow_debits_a_echeance",
      "fn_escrow_releases_a_traiter",
      "fn_stripe_refunds_reels_a_traiter",
      "fn_externalisations_a_traiter",
    ]) {
      const start = migration.indexOf(
        `CREATE OR REPLACE FUNCTION public.${functionName}`,
      );
      const end = migration.indexOf("$function$;", start);
      const body = migration.slice(start, end);
      expect(start, functionName).toBeGreaterThanOrEqual(0);
      expect(body).toMatch(/est_compte_test|fn_externalisation_est_reelle/);
    }
    expect(migration).toContain("excluded_non_real");
    expect(migration).toContain("READ_ONLY_REVIEW_REQUIRED");
    expect(migration).toContain("'destructive_action_taken', false");
    const inventoryStart = migration.indexOf(
      "CREATE OR REPLACE FUNCTION public.fn_ops_inventorier_objets_stripe_test",
    );
    const inventoryEnd = migration.indexOf("$function$;", inventoryStart);
    const inventoryBody = migration.slice(inventoryStart, inventoryEnd);
    expect(inventoryBody).not.toMatch(/\b(?:UPDATE|DELETE|INSERT)\b/i);
  });

  it("priorise la source litige et autorise une seule classe système admin", () => {
    const classifierStart = migration.indexOf(
      "CREATE OR REPLACE FUNCTION private.fn_externalisation_est_reelle",
    );
    const classifierEnd = migration.indexOf("$function$;", classifierStart);
    const classifier = migration.slice(classifierStart, classifierEnd);
    expectBefore(
      classifier,
      "p_action.source = 'LITIGE_EXEC'",
      "p_action.payload ->> 'destinataire_id'",
      "fn_externalisation_est_reelle",
    );
    expectBefore(
      classifier,
      "p_action.source = 'LITIGE_EXEC'",
      "p_action.payload ->> 'mission_id'",
      "fn_externalisation_est_reelle",
    );
    expect(classifier).toContain(
      "p_action.payload ->> 'type' = 'RECLAMATION_SCORE_NOUVELLE'",
    );
    expect(classifier).toContain("FROM public.candidatures c");
    expect(classifier).toContain("c.mission_id = v_id");
    expect(classifier).toContain("p_action.payload ? 'destinataire_role'");
    expect(classifier).toContain("RETURN false");

    const worker = edge("process-externalisation-actions");
    expect(worker).toContain("EMAIL_ROLE_SYSTEME_NON_AUTORISE");
    expect(worker).toContain("ADMIN_LAUNCH_ACCESS_GROUPS.every");
    expect(worker).toContain('type: "ADMIN_BROADCAST"');
    expect(worker).toContain("idempotency_key:");
    expect(worker).toContain('sourceMatchesMission = action.source_id === mission_id');
    expect(worker).toContain('.from("candidatures")');
  });

  it("exclut les missions test dans les quatre RPC du cron litiges", () => {
    for (const functionName of [
      "fn_auto_creation_litiges_presence",
      "fn_envoyer_rappels_litiges",
      "fn_litiges_escalader_auto",
      "fn_alerter_mediation_prioritaire",
    ]) {
      const start = migration.lastIndexOf(
        `CREATE OR REPLACE FUNCTION public.${functionName}()`,
      );
      const end = migration.indexOf("$function$;", start);
      const body = migration.slice(start, end);
      expect(start, `${functionName}: override absent`).toBeGreaterThanOrEqual(0);
      expect(body, `${functionName}: filtre canonique absent`).toContain(
        "private.fn_mission_est_reelle(",
      );
      expectBefore(
        body,
        "private.fn_mission_est_reelle(",
        "public.fn_litige_push_notification(",
        functionName,
      );
    }
  });

  it("conserve le litige test in-app sans créer de file email ou SMS", () => {
    const start = migration.lastIndexOf(
      "CREATE OR REPLACE FUNCTION public.fn_litige_push_notification(",
    );
    const end = migration.indexOf("$function$;", start);
    const body = migration.slice(start, end);
    expect(start).toBeGreaterThanOrEqual(0);
    expectBefore(
      body,
      "INSERT INTO public.notifications",
      "private.fn_mission_est_reelle(",
      "fn_litige_push_notification in-app",
    );
    expectBefore(
      body,
      "v_mission_reelle IS DISTINCT FROM true",
      "INSERT INTO public.email_queue",
      "fn_litige_push_notification externe",
    );
  });

  it("filtre les deux producteurs SQL d'alertes admin encore actifs", () => {
    const reclamationsStart = migration.lastIndexOf(
      "CREATE OR REPLACE FUNCTION public.fn_alerte_reclamations_pending_old()",
    );
    const reclamationsEnd = migration.indexOf(
      "$function$;",
      reclamationsStart,
    );
    const reclamations = migration.slice(
      reclamationsStart,
      reclamationsEnd,
    );
    expect(reclamationsStart).toBeGreaterThanOrEqual(0);
    expectBefore(
      reclamations,
      "private.fn_compte_operationnel_est_reel(r.contesteur_id)",
      "INSERT INTO public.externalisation_actions",
      "jolene_alert_reclamations_pending",
    );

    const teleportationStart = migration.lastIndexOf(
      "CREATE OR REPLACE FUNCTION public.fn_detecter_teleportations()",
    );
    const teleportationEnd = migration.indexOf(
      "$function$;",
      teleportationStart,
    );
    const teleportation = migration.slice(
      teleportationStart,
      teleportationEnd,
    );
    expect(teleportationStart).toBeGreaterThanOrEqual(0);
    expect(
      [...teleportation.matchAll(
        /private\.fn_mission_est_reelle\(p\.mission_id\)/g,
      )].length,
    ).toBe(2);
    expectBefore(
      teleportation,
      "private.fn_mission_est_reelle(p.mission_id)",
      "INSERT INTO public.journaux_audit",
      "jolene_alerte_teleportation",
    );
    expect(teleportation).not.toContain("WHEN OTHERS THEN");
  });

  it("ne compte une régénération de facture qu'après un vrai succès Edge", () => {
    const litigeCron = edge("litige-escalation-cron");
    expect(litigeCron).toContain("const { data: generated, error: generationError }");
    expect(litigeCron).toContain("if (generationError)");
    expect(litigeCron).toContain('generated?.mode !== "regen"');
    expect(litigeCron).toContain("generated?.facture_id !== row.id");
    expectBefore(
      litigeCron,
      "generated?.success !== true",
      "regen_ok++",
      "litige-escalation-cron regen",
    );
    expect(litigeCron).toContain("status: success ? 200 : 500");
  });
});
