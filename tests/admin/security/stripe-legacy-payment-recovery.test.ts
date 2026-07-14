import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260714014000_verrouiller_flux_paiement_stripe_mission.sql',
  'utf8',
);
const checkout = readFileSync(
  'supabase/functions/create-invoice-payment/index.ts',
  'utf8',
);
const claimHelper = readFileSync(
  'supabase/functions/_shared/stripe-payment-flow-claim.ts',
  'utf8',
);

describe('Stripe — adoption fail-closed des paiements historiques', () => {
  it('convertit LEGACY_UNKNOWN par une RPC service-role atomique et jamais vers Connect', () => {
    const start = migration.indexOf(
      'CREATE OR REPLACE FUNCTION public.fn_stripe_payment_flow_adopter_legacy(',
    );
    const end = migration.indexOf(
      '-- Backfill prioritaire des paiements Connect',
      start,
    );
    const adoption = migration.slice(start, end);

    expect(start).toBeGreaterThan(0);
    expect(adoption).toContain("p_flow NOT IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE')");
    expect(adoption).not.toContain("p_flow NOT IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION')");
    expect(adoption).toContain("<> 'service_role'");
    expect(adoption).toContain(
      '(p_stripe_checkout_session_id IS NULL AND p_stripe_payment_intent_id IS NULL)',
    );
    expect(adoption).toContain("p_stripe_checkout_session_id !~ '^cs_(test|live)_[A-Za-z0-9]+$'");
    expect(adoption).toContain("p_stripe_payment_intent_id !~ '^pi_[A-Za-z0-9]+$'");
    expect(adoption).toContain(
      'pg_advisory_xact_lock(hashtextextended(v_resource, 0))',
    );
    expect(adoption).toContain("'STRIPE_SESSION:' || p_stripe_checkout_session_id");
    expect(adoption).toContain("'STRIPE_INTENT:' || p_stripe_payment_intent_id");
    expect(adoption).toContain('FOR UPDATE');
    expect(adoption).toContain(
      'v_facture_payment_intent_id IS DISTINCT FROM p_stripe_payment_intent_id',
    );
    expect(adoption).toContain(
      "c.flow = 'LEGACY_UNKNOWN' AND c.owner_token = v_legacy_owner_token",
    );
    expect(adoption).toContain('c.flow = p_flow AND c.owner_token = p_owner_token');
    expect(adoption).toContain(
      'v_session_ids[1] IS DISTINCT FROM p_stripe_checkout_session_id',
    );
    expect(adoption).toContain(
      'v_intent_ids[1] IS DISTINCT FROM p_stripe_payment_intent_id',
    );
    expect(adoption).toContain('Objet Stripe déjà revendiqué par un autre paiement');
    expect(adoption).toContain('UPDATE public.stripe_payment_flow_claims c');
    expect(adoption).toContain('ON CONFLICT (resource_key) DO NOTHING');
    expect(adoption).toContain('v_claim_count <> cardinality(v_resources)');
    expect(adoption).toContain("'FACTURE_LEGACY_STRIPE_ADOPTEE'");
    expect(adoption).toContain('v_audit := public.fn_ecrire_audit_safe(');
    expect(adoption).toContain('Audit adoption Stripe legacy non écrit');
    expect(adoption).toContain('REVOKE ALL ON FUNCTION');
    expect(adoption).toContain('TO service_role;');
  });

  it('relit et valide les objets Stripe exacts avant de prendre possession du claim', () => {
    const legacyStart = checkout.indexOf(
      'if (paymentFlowClaim.claim.flow === "LEGACY_UNKNOWN")',
    );
    const adopt = checkout.indexOf(
      'await adoptLegacyStripePaymentFlowClaim(',
      legacyStart,
    );
    const reacquire = checkout.indexOf(
      'paymentFlowClaim = await acquireStripePaymentFlowClaim(',
      adopt,
    );
    const create = checkout.indexOf('stripe.checkout.sessions.create(');
    const recovery = checkout.slice(legacyStart, adopt);

    expect(legacyStart).toBeGreaterThan(0);
    expect(recovery).toContain('await findMatchingPaymentIntent(');
    expect(recovery).toContain('await findMatchingCheckoutSession(');
    expect(recovery).toContain('stripe.paymentIntents.retrieve(legacyClaimIntentId)');
    expect(recovery).toContain('stripe.paymentIntents.retrieve(sessionPaymentIntentId)');
    expect(recovery).toContain('findInvoiceCheckoutSessionInconsistencies(');
    expect(recovery).toContain('findInvoicePaymentIntentInconsistencies(');
    expect(recovery).toContain('await requireAcquiredStripeSourceCharge(');
    expect(recovery).toContain('stripe_evidence.missing');
    expect(recovery).toContain('LEGACY_PAYMENT_REVIEW_REQUIRED');
    expect(adopt).toBeGreaterThan(legacyStart);
    expect(reacquire).toBeGreaterThan(adopt);
    expect(reacquire).toBeLessThan(create);
    expect(checkout.slice(adopt, reacquire)).not.toContain('stripe.checkout.sessions.create(');
  });

  it('bloque les historiques ambigus au lieu de choisir arbitrairement une charge', () => {
    expect(checkout).toContain('Multiple actionable PaymentIntents for invoice');
    expect(checkout).toContain('Multiple actionable Checkout Sessions for invoice');
    expect(checkout).toContain('payment_intent_claim_different_de_la_recherche');
    expect(checkout).toContain('checkout_et_payment_intent_differents');
    expect(checkout).toContain('FACTURE_LEGACY_STRIPE_AMBIGU');
    expect(checkout).toContain('FACTURE_LEGACY_STRIPE_INCOHERENTE');
  });

  it('vérifie la réponse SQL d’adoption puis réacquiert le même owner', () => {
    const helperStart = claimHelper.indexOf(
      'export async function adoptLegacyStripePaymentFlowClaim(',
    );
    const helperEnd = claimHelper.indexOf(
      'export async function bindStripePaymentFlowClaimSession(',
      helperStart,
    );
    const helper = claimHelper.slice(helperStart, helperEnd);

    expect(helper).toContain('"fn_stripe_payment_flow_adopter_legacy"');
    expect(helper).toContain('!expected.facture_id');
    expect(helper).toContain('expected.mission_id !== null');
    expect(helper).toContain('result.flow !== expected.flow');
    expect(helper).toContain('result.owner_token !== expected.owner_token');
    expect(helper).toContain('result.resources.length === 0');
    expect(helper).toContain(
      'result.stripe_checkout_session_id !== evidence.stripeCheckoutSessionId',
    );
    expect(helper).toContain(
      'result.stripe_payment_intent_id !== evidence.stripePaymentIntentId',
    );
  });
});
