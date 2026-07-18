import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const connect = readFileSync(
  'supabase/functions/stripe-connect-pay-mission/index.ts',
  'utf8',
);
const webhook = readFileSync(
  'supabase/functions/_shared/stripe-webhook-handler.ts',
  'utf8',
);
const standardInvoice = readFileSync(
  'supabase/functions/create-invoice-payment/index.ts',
  'utf8',
);
const sepaInvoice = readFileSync(
  'supabase/functions/sepa-auto-charge/index.ts',
  'utf8',
);
const flowClaim = readFileSync(
  'supabase/functions/_shared/stripe-payment-flow-claim.ts',
  'utf8',
);
const flowClaimMigration = readFileSync(
  'supabase/migrations/20260714014000_verrouiller_flux_paiement_stripe_mission.sql',
  'utf8',
);
const sourceChargeGuard = readFileSync(
  'supabase/functions/_shared/stripe-source-charge.ts',
  'utf8',
);
const connectReconciliationMigration = readFileSync(
  'supabase/migrations/20260714034156_rapprocher_paiement_connect_atomique.sql',
  'utf8',
);
const weeklyInvoiceMigration = readFileSync(
  'supabase/migrations/20260718122441_fiabiliser_pointage_facturation_hebdo_chorus.sql',
  'utf8',
);

describe('Stripe Connect — aucune seconde charge après capture', () => {
  it('réserve atomiquement la mission avant tout Checkout standard ou Connect', () => {
    const standardAcquire = standardInvoice.indexOf('acquireStripePaymentFlowClaim(');
    const standardCreate = standardInvoice.indexOf('stripe.checkout.sessions.create(');
    const standardBind = standardInvoice.indexOf(
      'bindStripePaymentFlowClaimSession(',
      standardCreate,
    );
    const connectLegacySearch = connect.indexOf('const standardInvoiceClaim');
    const connectAcquire = connect.indexOf(
      'const paymentFlowClaim = await acquireStripePaymentFlowClaim(',
      connectLegacySearch,
    );
    const connectCreate = connect.indexOf('stripe.checkout.sessions.create({');

    expect(flowClaimMigration).toContain('resource_key text PRIMARY KEY');
    expect(flowClaimMigration).toContain("'CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION', 'LEGACY_UNKNOWN'");
    expect(weeklyInvoiceMigration).toContain("'CONNECT_INVOICE'");
    expect(flowClaim).toContain('.rpc("fn_stripe_payment_flow_claim"');
    expect(standardAcquire).toBeGreaterThan(0);
    expect(standardAcquire).toBeLessThan(standardCreate);
    expect(standardBind).toBeGreaterThan(standardCreate);
    expect(connectLegacySearch).toBeGreaterThan(0);
    expect(connectLegacySearch).toBeLessThan(connectAcquire);
    expect(connectAcquire).toBeLessThan(connectCreate);
  });

  it('verrouille facture puis toutes ses missions, y compris une facture agrégée', () => {
    expect(flowClaimMigration).toContain("'FACTURE:' || p_facture_id::text");
    expect(flowClaimMigration).toContain("'MISSION:' || f.mission_id::text");
    expect(flowClaimMigration).toContain('WHERE m.facture_id = p_facture_id');
    expect(flowClaimMigration).toContain(
      'array_agg(DISTINCT r.resource_key ORDER BY r.resource_key)',
    );
    expect(flowClaimMigration).toContain(
      'pg_advisory_xact_lock(hashtextextended(v_resource, 0))',
    );
    expect(flowClaimMigration).toContain('c.resource_key = ANY(v_resources)');
    expect(flowClaimMigration).toContain(
      'c.flow <> p_flow OR c.owner_token <> p_owner_token',
    );
    expect(flowClaimMigration).toContain("p_flow NOT IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION')");
    expect(flowClaimMigration).toContain("'LEGACY_UNKNOWN'::text AS flow");
    expect(flowClaimMigration).not.toContain('mode_paiement_commission =');
  });

  it('distingue Checkout, SEPA et Connect sur les mêmes clés d’exclusion', () => {
    const standardAcquire = standardInvoice.indexOf('acquireStripePaymentFlowClaim(');
    const standardCreate = standardInvoice.indexOf('stripe.checkout.sessions.create(');
    const sepaAcquire = sepaInvoice.indexOf('acquireStripePaymentFlowClaim(');
    const sepaCreate = sepaInvoice.indexOf('stripe.paymentIntents.create({');

    expect(standardInvoice).toContain('mission_id: null');
    expect(standardInvoice).toContain('facture_id: facture.id');
    expect(standardInvoice).toContain('flow: "CHECKOUT_INVOICE"');
    expect(standardInvoice).toContain('FACTURE_RESERVEE_SEPA');
    expect(sepaInvoice).toContain('mission_id: null');
    expect(sepaInvoice).toContain('facture_id: f.id');
    expect(sepaInvoice).toContain('flow: "SEPA_INVOICE"');
    expect(sepaInvoice).toContain('bindStripePaymentFlowClaimIntent(');
    expect(connect).toContain('facture_id: null');
    expect(connect).toContain('flow: "CONNECT_MISSION"');
    expect(connect).toContain('facture_id: factureCommission!.id');
    expect(connect).toContain('flow: "CONNECT_INVOICE"');
    expect(weeklyInvoiceMigration).toContain(
      "v_resources := ARRAY['FACTURE:' || p_facture_id::text]",
    );
    expect(standardAcquire).toBeLessThan(standardCreate);
    expect(sepaAcquire).toBeLessThan(sepaCreate);
  });

  it('reprend toujours le PI du claim SEPA avant toute nouvelle création', () => {
    const claimBranch = sepaInvoice.indexOf('if (claimedPaymentIntentId)');
    const create = sepaInvoice.indexOf('stripe.paymentIntents.create({');
    const recovery = sepaInvoice.slice(claimBranch, create);

    expect(claimBranch).toBeGreaterThan(0);
    expect(claimBranch).toBeLessThan(create);
    expect(recovery).toContain('stripe.paymentIntents.retrieve(claimedPaymentIntentId)');
    expect(recovery).toContain('findInvoicePaymentIntentInconsistencies(claimedIntent');
    expect(recovery).toContain('stripe_payment_intent_id: claimedIntent.id');
    expect(recovery).toContain('claimedIntent.status === "succeeded"');
    expect(recovery).toContain('claimedIntent.status !== "processing"');
    expect(recovery).toContain('.select("id")');
    expect(recovery).toContain('if (claimReconcileError || !claimReconciled)');
    expect(recovery).toContain('recovered_from_claim: true');
    expect(recovery).toContain('continue;');
    expect(recovery).not.toContain('paymentIntents.create');
  });

  it('lie aussi un PI SEPA créé mais incohérent pour interdire tout second débit tardif', () => {
    const mismatch = sepaInvoice.indexOf(
      'if (stripeErr?.code === "INVOICE_PAYMENT_MISMATCH")',
    );
    const audit = sepaInvoice.indexOf(
      'SEPA_PAYMENT_INTENT_INCOHERENT',
      mismatch,
    );
    const block = sepaInvoice.slice(mismatch, audit);

    expect(mismatch).toBeGreaterThan(0);
    expect(block).toContain('if (knownIntent?.id && paymentFlowClaim?.acquired)');
    expect(block).toContain('bindStripePaymentFlowClaimIntent(');
    expect(block).toContain('knownIntent.id');
  });

  it('refuse Connect lorsqu’un Checkout standard embedded ouvert existe déjà', () => {
    const searchStart = connect.indexOf('const sessionsCustomer');
    const reject = connect.indexOf('error: "PAIEMENT_FACTURE_DEJA_REVENDIQUE"', searchStart);
    const connectAcquire = connect.indexOf(
      'const paymentFlowClaim = await acquireStripePaymentFlowClaim(',
      searchStart,
    );
    const searchBlock = connect.slice(searchStart, reject);

    expect(searchBlock).toContain('candidate.metadata?.facture_id === factureCommission.id');
    expect(searchBlock).toContain('["open", "complete"].includes(candidate.status || "")');
    expect(reject).toBeGreaterThan(searchStart);
    expect(reject).toBeLessThan(connectAcquire);
    expect(standardInvoice).toContain('ui_mode = "embedded"');
    expect(standardInvoice).toContain('bindStripePaymentFlowClaimSession(');
  });

  it('traite toute Session complète avant la création d’un nouveau Checkout', () => {
    const completeById = connect.indexOf('if (precedente.status === "complete")');
    const completeBySearch = connect.indexOf(
      'const sessionCompleteMission = sessionCompleteHistorique ?? sessionsMission.find(',
    );
    const createCheckout = connect.indexOf('stripe.checkout.sessions.create({');
    const retryStatusesStart = connect.indexOf('const statutAutoriseNouvelleTentative');
    const retryStatusesEnd = connect.indexOf(';', retryStatusesStart);

    expect(completeById).toBeGreaterThan(0);
    expect(completeBySearch).toBeGreaterThan(completeById);
    expect(completeBySearch).toBeLessThan(createCheckout);
    expect(connect.slice(retryStatusesStart, retryStatusesEnd)).not.toContain('ECHOUE');
    expect(connect).not.toContain(
      'status === "complete" && !statutAutoriseNouvelleTentative',
    );
    expect(connect).toContain('status: "complete"');
    expect(connect).toContain('completeStartingAfter');
    expect(connect).toContain('pageComplete.has_more');
  });

  it('rejoue seulement le transfert d’une charge acquise avec la clé de la Session', () => {
    const start = connect.indexOf('const relancerTransfertEchoueSansRecharger');
    const end = connect.indexOf('let checkoutIdempotencyKey', start);
    const recovery = connect.slice(start, end);

    expect(start).toBeGreaterThan(0);
    expect(recovery).toContain(
      '!["ECHOUE", "CHARGE_REUSSI"].includes(transferStatutCourant || "")',
    );
    expect(recovery).toContain('paymentIntent.status !== "succeeded"');
    expect(recovery).toContain('paymentIntent.amount_received !== totalCents');
    expect(recovery).toContain('stripe.transfers.create({');
    expect(recovery).toContain('source_transaction: chargeId');
    expect(recovery).toContain('transfer_${session.id}');
    expect(recovery).toContain('.eq("statut", transferStatutCourant)');
    expect(recovery).toContain('statut: "TRANSFERE"');
    expect(recovery).not.toContain('stripe.checkout.sessions.create');
  });

  it('refuse le retry si la Charge source est remboursée, contestée ou incohérente', () => {
    const start = connect.indexOf('const relancerTransfertEchoueSansRecharger');
    const end = connect.indexOf('let checkoutIdempotencyKey', start);
    const recovery = connect.slice(start, end);
    const chargeValidation = recovery.indexOf('requireAcquiredStripeSourceCharge(');
    const transferCreate = recovery.indexOf('stripe.transfers.create({');

    expect(chargeValidation).toBeGreaterThan(0);
    expect(chargeValidation).toBeLessThan(transferCreate);
    expect(sourceChargeGuard).toContain('stripe.charges.retrieve(chargeId)');
    expect(sourceChargeGuard).toContain('charge.refunded');
    expect(sourceChargeGuard).toContain('charge.amount_refunded > 0');
    expect(sourceChargeGuard).toContain('charge.disputed');
    expect(sourceChargeGuard).toContain('!charge.paid');
    expect(sourceChargeGuard).toContain('charge.status !== "succeeded"');
    expect(sourceChargeGuard).toContain('charge.amount !== expected.amountCents');
    expect(sourceChargeGuard).toContain('charge.currency.toLowerCase() !== expectedCurrency');
    expect(sourceChargeGuard).toContain('objectId(charge.customer) !== expected.customerId');
    expect(sourceChargeGuard).toContain('objectId(charge.payment_intent) !== paymentIntent.id');
    expect(recovery).toContain('source_transaction: chargeId');
  });
});

describe('Stripe Connect — réconciliation comptable exacte', () => {
  it('refuse aussi côté webhook une Charge remboursée, contestée ou incohérente', () => {
    const connectStart = webhook.indexOf('Paid Connect checkout has no source charge');
    const transferCreate = webhook.indexOf('stripe.transfers.create({', connectStart);
    const chargeGuard = webhook.slice(connectStart, transferCreate);

    expect(connectStart).toBeGreaterThan(0);
    expect(chargeGuard).toContain('requireAcquiredStripeSourceCharge(');
    expect(chargeGuard).toContain('{ customerId, amountCents: totalCents, currency: "eur" }');
    expect(chargeGuard).toContain('sourceCharge.id !== chargeId');
    expect(sourceChargeGuard).toContain('charge.refunded');
    expect(sourceChargeGuard).toContain('charge.amount_refunded > 0');
    expect(sourceChargeGuard).toContain('charge.disputed');
  });

  it('rend retryable un échec de transfert au lieu d’acquitter le webhook', () => {
    const catchStart = webhook.indexOf('} catch (transferErr: any)');
    const catchEnd = webhook.indexOf('await markEventProcessed()', catchStart);
    const failure = webhook.slice(catchStart, catchEnd);

    expect(failure).toContain('FINANCE_TRANSFER_FAILED');
    expect(failure).toContain('Connect transfer failed; Stripe event must retry');
    expect(failure).toContain('throw new Error(');
    expect(failure).not.toContain('return new Response');
  });

  it('solde la facture commission existante exacte avec le PI Connect', () => {
    const start = webhook.indexOf('if (validatedFactureCommission)');
    const end = webhook.indexOf('} else {', start);
    const update = webhook.slice(start, end);

    expect(update).toContain('statut: "PAYEE"');
    expect(update).toContain('stripe_payment_intent_id: paymentIntentId');
    expect(update).toContain('.eq("id", validatedFactureCommission.id)');
    expect(update).toContain('.eq("mission_id", missionId)');
    expect(update).toContain('.eq("etablissement_id", missionRow.etablissement_id)');
    expect(update).toContain('.eq("montant_ttc", validatedFactureCommission.montant_ttc)');
    expect(update).toContain(
      'stripe_payment_intent_id.is.null,stripe_payment_intent_id.eq.${paymentIntentId}',
    );
    expect(update).toContain('.in("statut", ["EMISE", "EN_RETARD"])');
    expect(webhook).toContain(
      'validatedFactureCommission.stripe_payment_intent_id === paymentIntentId',
    );
  });

  it('accepte atomiquement PI NULL ou le même PI dans les deux CAS facture', () => {
    const standardStart = webhook.indexOf('// ── Standard facture payment flow ──');
    const standardEnd = webhook.indexOf('// ── Escrow 7b-D', standardStart);
    const standard = webhook.slice(standardStart, standardEnd);
    const backupStart = webhook.indexOf(
      '// Handle payment_intent.succeeded (backup reconciliation)',
    );
    const backupEnd = webhook.indexOf('// Handle SEPA debit charge succeeded', backupStart);
    const backup = webhook.slice(backupStart, backupEnd);
    const validatorStart = webhook.indexOf('const loadAndValidateInvoicePayment');
    const validatorEnd = webhook.indexOf('const loadAndValidateEscrowPayment', validatorStart);
    const validator = webhook.slice(validatorStart, validatorEnd);

    expect(standard).toContain(
      'stripe_payment_intent_id.is.null,stripe_payment_intent_id.eq.${checkoutPaymentIntent.id}',
    );
    expect(backup).toContain(
      'stripe_payment_intent_id.is.null,stripe_payment_intent_id.eq.${paymentIntent.id}',
    );
    expect(validator).toContain('facture.stripe_payment_intent_id !== paymentIntent.id');
  });

  it('répare atomiquement toutes les écritures locales après un Transfer acquis', () => {
    const helperStart = connect.indexOf('const rapprocherSessionConnectPayee');
    const checkoutCreate = connect.indexOf('stripe.checkout.sessions.create({');
    const helper = connect.slice(helperStart, checkoutCreate);

    expect(helperStart).toBeGreaterThan(0);
    expect(helper).toContain('requireAcquiredStripeSourceCharge(');
    expect(helper).toContain('stripe.transfers.retrieve(trace.stripe_transfer_id)');
    expect(helper).toContain('transfer.amount_reversed > 0');
    expect(helper).toContain('"fn_stripe_connect_rapprocher_local"');
    expect(connect).toContain('statut: "RAPPROCHE"');
    expect(connectReconciliationMigration).toContain(
      'CREATE UNIQUE INDEX IF NOT EXISTS uniq_paiements_soignant_stripe_transfer',
    );
    expect(connectReconciliationMigration).toContain('FOR UPDATE');
    expect(connectReconciliationMigration).toContain('SET statut = CASE');
    expect(connectReconciliationMigration).toContain("WHEN statut = 'PAYE' THEN 'PAYE'");
    expect(connectReconciliationMigration).toContain("SET statut = 'PAYEE'");
    expect(connectReconciliationMigration).toContain(
      'ON CONFLICT (stripe_transfer_id) WHERE stripe_transfer_id IS NOT NULL',
    );
    expect(connectReconciliationMigration).toContain('commission_facturee = true');
    expect(connectReconciliationMigration).toContain("'FINANCE_TRANSFER_CONNECT'");
  });
});
