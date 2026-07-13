import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const FUNCTIONS_ROOT = 'supabase/functions';
const STRIPE_WEBHOOK_HANDLER = `${FUNCTIONS_ROOT}/_shared/stripe-webhook-handler.ts`;

function edgeFunctionSourcesUsingStripeSecret(): Array<{ name: string; source: string }> {
  return readdirSync(FUNCTIONS_ROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== '_shared')
    .flatMap((entry) => {
      const path = join(FUNCTIONS_ROOT, entry.name, 'index.ts');
      try {
        const source = readFileSync(path, 'utf8');
        return source.includes('STRIPE_SECRET_KEY') ? [{ name: entry.name, source }] : [];
      } catch {
        return [];
      }
    });
}

describe('Stripe — garde production et idempotence P0', () => {
  it('refuse une clé non live sur le projet Supabase de production', () => {
    const helper = readFileSync(`${FUNCTIONS_ROOT}/_shared/stripe-production.ts`, 'utf8');

    expect(helper).toContain("PRODUCTION_PROJECT_REF = 'flripxtsyegjshnhzjkz'");
    expect(helper).toContain("secret.startsWith('sk_live_')");
    expect(helper).toContain("Deno.env.get('SUPABASE_URL')");
  });

  it('branche la garde sur toute fonction qui utilise la clé secrète hors diagnostic', () => {
    const functions = edgeFunctionSourcesUsingStripeSecret();
    const diagnosticOnly = new Set(['stripe-config-health']);

    for (const fn of functions) {
      if (diagnosticOnly.has(fn.name)) continue;
      expect(fn.source, `${fn.name} doit refuser sk_test_* en production`)
        .toContain('assertStripeSecretMode');
    }

    expect(functions.map((fn) => fn.name)).toContain('stripe-config-health');
  });

  it('conserve une clé d’idempotence stable sur chaque création financière critique', () => {
    const expectedKeys: Record<string, string[]> = {
      'create-invoice-payment': ['invoice_checkout_${facture.id}'],
      'create-mission-payment': ['mission_payment_${mission.id}'],
      'escrow-debit-echeance': ['escrow_debit_${esc.id}'],
      'escrow-release': ['release_${rel.paiement_escrow_id}'],
      'process-externalisation-actions': [
        'externalisation_refund_${action.id}',
        'externalisation_transfer_${action.id}',
        'parrainage_transfer_${parrainage_id}_${role}',
      ],
      'process-stripe-refunds': ['refund_queue_${item.id}'],
      'stripe-connect-pay-mission': ['connect_checkout_${mission_id}'],
    };

    for (const [name, keys] of Object.entries(expectedKeys)) {
      const source = readFileSync(join(FUNCTIONS_ROOT, name, 'index.ts'), 'utf8');
      for (const key of keys) {
        expect(source, `${name} doit utiliser ${key}`).toContain(key);
      }
    }

    const webhook = readFileSync(STRIPE_WEBHOOK_HANDLER, 'utf8');
    expect(webhook).toContain('transfer_${session.id}');
  });

  it('avance la version seulement après une tentative Stripe terminale ou abandonnée connue', () => {
    const mission = readFileSync(`${FUNCTIONS_ROOT}/create-mission-payment/index.ts`, 'utf8');
    const facture = readFileSync(`${FUNCTIONS_ROOT}/create-invoice-payment/index.ts`, 'utf8');
    const debit = readFileSync(`${FUNCTIONS_ROOT}/escrow-debit-echeance/index.ts`, 'utf8');
    const release = readFileSync(`${FUNCTIONS_ROOT}/escrow-release/index.ts`, 'utf8');
    const connect = readFileSync(`${FUNCTIONS_ROOT}/stripe-connect-pay-mission/index.ts`, 'utf8');

    expect(mission).toContain('mission_payment_${mission.id}_after_${precedent.id}');
    expect(mission).not.toContain('delete().eq("id", existingPayment.id)');
    expect(facture).toContain('invoice_checkout_${facture.id}_after_${existingSession.id}');
    expect(facture).toContain('resumed: true');
    expect(debit).toContain('escrow_debit_${esc.id}_after_${precedent.id}');
    expect(debit).toContain('.eq("tentatives_debit", esc.tentatives_debit ?? 0)');
    expect(debit).toContain('err?.payment_intent ?? err?.raw?.payment_intent');
    expect(debit).toContain('stripe_payment_intent_id: failedIntentId');
    expect(release).toContain('release_${rel.paiement_escrow_id}_after_${precedent.id}');
    expect(connect).toContain('connect_checkout_${mission_id}_after_${versionPrecedente}');
    expect(connect).toContain('stripe_checkout_session_id: session.id');
    expect(connect).toContain('cree_le: new Date().toISOString()');
  });

  it('récupère une Checkout Session Connect même si son INSERT DB initial a échoué', () => {
    const connect = readFileSync(`${FUNCTIONS_ROOT}/stripe-connect-pay-mission/index.ts`, 'utf8');
    const migration = readFileSync(
      'supabase/migrations/20260713222631_versionner_sessions_checkout_connect.sql',
      'utf8',
    );

    expect(connect).toContain('stripe.checkout.sessions.list({ customer: customerId, limit: 100 })');
    expect(connect).toContain('candidate.metadata?.mission_id === mission_id');
    expect(connect).toContain('derniereSessionMission.status === "open"');
    expect(connect).toContain('resumed: true');
    expect(connect).toContain('connect_checkout_${mission_id}_after_${derniereSessionMission.id}');
    expect(migration).toContain('stripe_checkout_session_id text');
    expect(migration).toContain('CREATE UNIQUE INDEX IF NOT EXISTS uniq_stripe_transfers_checkout_session');
  });

  it('ne casse pas la Session Connect partagée lors de la course du premier INSERT', () => {
    const connect = readFileSync(`${FUNCTIONS_ROOT}/stripe-connect-pay-mission/index.ts`, 'utf8');

    expect(connect).toContain('insErr?.code === "23505"');
    expect(connect).toContain('.eq("stripe_checkout_session_id", session.id)');
    expect(connect).toContain('Math.round(Number(gagnant.montant_total) * 100) === totalCents');
    expect(connect).toContain('if (!sessionPartageeParConcurrent)');
    expect(connect).toContain('concurrent_session_reused: sessionPartageeParConcurrent');
  });

  it('laisse un statut métier terminal ouvrir une nouvelle génération après une ancienne Session complète', () => {
    const connect = readFileSync(`${FUNCTIONS_ROOT}/stripe-connect-pay-mission/index.ts`, 'utf8');

    expect(connect).toContain('["ECHOUE", "REMBOURSE", "ANNULEE"]');
    expect(connect).toContain('precedente.status === "complete" && !statutAutoriseNouvelleTentative');
    expect(connect).toContain('derniereSessionMission.status === "complete" && !statutAutoriseNouvelleTentative');
    expect(connect).toContain('connect_checkout_${mission_id}_after_${derniereSessionMission.id}');
  });

  it('ne crée pas un second paiement de facture tant qu’un PI est actif et versionne après échec Checkout', () => {
    const facture = readFileSync(`${FUNCTIONS_ROOT}/create-invoice-payment/index.ts`, 'utf8');

    expect(facture).toContain('"requires_action", "requires_confirmation"');
    expect(facture).toContain('existingSession?.status === "complete" && !intentTerminalConnu');
    expect(facture).toContain('await stripe.checkout.sessions.expire(existingSession.id)');
    expect(facture).not.toContain('checkout expiration failed');
  });

  it('fige le PaymentIntent renvoyé dans une erreur SEPA au lieu de le rejouer', () => {
    const source = readFileSync(`${FUNCTIONS_ROOT}/sepa-auto-charge/index.ts`, 'utf8');

    expect(source).toMatch(
      /stripeErr\?\.payment_intent\s*\?\?\s*stripeErr\?\.raw\?\.payment_intent/,
    );
    expect(source).toContain('stripe.paymentIntents.retrieve(knownIntentId)');
    expect(source).toContain('stripe_payment_intent_id: knownIntentId');
    expect(source).toContain('intentStatus !== "processing"');
    expect(source).toContain('recoveredUpdate.statut = "EN_RETARD"');
    expect(source).toContain('.in("statut", ["EMISE", "EN_RETARD"])');
    expect(source).toContain('.is("stripe_payment_intent_id", null)');
  });

  it('n’écoute aucun événement Stripe transfer.failed inexistant', () => {
    const webhook = readFileSync(STRIPE_WEBHOOK_HANDLER, 'utf8');
    expect(webhook).not.toContain('event.type === "transfer.failed"');
    expect(webhook).toContain('event.type === "transfer.reversed"');
  });

  it('diagnostique la clé live et le webhook Stripe de production sans effet de bord', () => {
    const health = readFileSync(`${FUNCTIONS_ROOT}/stripe-config-health/index.ts`, 'utf8');

    expect(health).toContain("fetch('https://api.stripe.com/v1/balance'");
    expect(health).toContain("fetch('https://api.stripe.com/v1/webhook_endpoints?limit=100'");
    expect(health).toContain("const supabaseBase = (Deno.env.get('SUPABASE_URL')");
    expect(health).toContain('`${supabaseBase}/functions/v1/stripe-webhook`');
    expect(health).toContain('`${supabaseBase}/functions/v1/stripe-connect-webhook`');
    expect(health).toContain('STRIPE_PLATFORM_WEBHOOK_SECRET');
    expect(health).toContain('STRIPE_CONNECT_WEBHOOK_SECRET');
    expect(health).toContain('platform !== connect');
    expect(health).toContain("'checkout.session.completed'");
    expect(health).toContain("'payment_intent.succeeded'");
    expect(health).toContain("'account.updated'");
    expect(health).toContain("'payout.failed'");
    expect(health).toContain('platform_webhook_events_complete');
    expect(health).toContain('connect_webhook_events_complete');
    expect(health).toContain("const WEBHOOK_API_VERSION = '2025-08-27.basil'");
    expect(health).not.toContain('2026-02-25.clover');
    expect(health).toContain('production_ready: productionReady');
    expect(health).not.toMatch(/sk_(?:live|test)_[A-Za-z0-9]+/);
  });

  it('sépare cryptographiquement les événements plateforme et Connect', () => {
    const webhook = readFileSync(STRIPE_WEBHOOK_HANDLER, 'utf8');
    const platformEntrypoint = readFileSync(`${FUNCTIONS_ROOT}/stripe-webhook/index.ts`, 'utf8');
    const connectEntrypoint = readFileSync(`${FUNCTIONS_ROOT}/stripe-connect-webhook/index.ts`, 'utf8');

    expect(webhook).toContain('STRIPE_PLATFORM_WEBHOOK_SECRET');
    expect(webhook).toContain('STRIPE_CONNECT_WEBHOOK_SECRET');
    expect(webhook).toContain('platform === connect');
    expect(webhook).toContain('isProductionRuntime() && (!platform || !connect)');
    expect(webhook).toContain('constructEventAsync');
    expect(webhook).toContain('verified.source !== expectedSource');
    expect(webhook).toContain('(verified.source === "CONNECT" && !eventAccount)');
    expect(platformEntrypoint).toContain('handleStripeWebhook(req, "PLATFORM")');
    expect(connectEntrypoint).toContain('handleStripeWebhook(req, "CONNECT")');
  });

  it('acquitte sans écriture tout événement Stripe test reçu sur la production', () => {
    const webhook = readFileSync(STRIPE_WEBHOOK_HANDLER, 'utf8');

    expect(webhook).toContain('isProductionRuntime() && event.livemode !== true');
    expect(webhook).toContain('skipped: "non_live_event"');
    expect(webhook.indexOf('event.livemode !== true')).toBeLessThan(
      webhook.indexOf('fn_stripe_webhook_event_claim'),
    );
  });

  it('applique une allow-list stricte par source avant tout claim ou dispatch', () => {
    const webhook = readFileSync(STRIPE_WEBHOOK_HANDLER, 'utf8');
    const platformStart = webhook.indexOf('const PLATFORM_EVENT_TYPES');
    const connectStart = webhook.indexOf('const CONNECT_EVENT_TYPES');
    const allowFunctionStart = webhook.indexOf('function eventAllowedForSource');
    const platformAllowList = webhook.slice(platformStart, connectStart);
    const connectAllowList = webhook.slice(connectStart, allowFunctionStart);

    expect(platformAllowList).toContain('"checkout.session.completed"');
    expect(platformAllowList).toContain('"transfer.reversed"');
    expect(platformAllowList).not.toContain('"account.updated"');
    expect(platformAllowList).not.toContain('"payout.paid"');
    expect(connectAllowList).toContain('"account.updated"');
    expect(connectAllowList).toContain('"payout.created"');
    expect(connectAllowList).toContain('"payout.paid"');
    expect(connectAllowList).not.toContain('"checkout.session.completed"');
    expect(connectAllowList).not.toContain('"transfer.created"');
    expect(webhook).toContain('skipped: "source_event_not_allowed"');
    expect(webhook.indexOf('if (!eventAllowedForSource')).toBeLessThan(
      webhook.indexOf('fn_stripe_webhook_event_claim'),
    );
  });

  it('claim les événements atomiquement et échoue fermé si la persistance casse', () => {
    const webhook = readFileSync(STRIPE_WEBHOOK_HANDLER, 'utf8');
    const migration = readFileSync(
      'supabase/migrations/20260713227000_securiser_webhooks_stripe_connect.sql',
      'utf8',
    );

    expect(webhook).toContain('fn_stripe_webhook_event_claim');
    expect(webhook).toContain('claimStatus === "PROCESSING"');
    expect(webhook).toContain('Idempotence claim failed');
    expect(webhook).not.toContain('Idempotence check failed (continuing)');
    expect(migration).toContain("RETURN 'CLAIMED'");
    expect(migration).toContain("RETURN 'PROCESSING'");
    expect(migration).toContain("RETURN 'PROCESSED'");
    expect(migration).toContain("traitement_commence_le < now() - interval '5 minutes'");
  });

  it('ne marque jamais globalement des transferts à partir d’un payout Connect', () => {
    const webhook = readFileSync(STRIPE_WEBHOOK_HANDLER, 'utf8');
    const migration = readFileSync(
      'supabase/migrations/20260713227000_securiser_webhooks_stripe_connect.sql',
      'utf8',
    );

    expect(webhook).not.toContain('stripe_payout_id.is.null');
    expect(webhook).toContain('stripe.balanceTransactions.list');
    expect(webhook).toContain('payout: payoutId');
    expect(webhook).toContain('{ stripeAccount }');
    expect(webhook).toContain('sourceId?.startsWith("tr_")');
    expect(webhook).toContain('fn_stripe_lier_payout_transfers');
    expect(webhook).toContain('.eq("stripe_payout_id", payout.id)');
    expect(webhook).toContain('.eq("soignant_id", connectedSoignantId)');
    expect(webhook).toContain('fn_escrow_confirmer_payout');
    expect(webhook).toContain('fn_escrow_echouer_payout');
    expect(migration).toContain('FOR UPDATE');
    expect(migration).toContain('Transfer déjà lié à un autre payout');
    expect(migration).toContain('st.stripe_transfer_id = ANY(p_stripe_transfer_ids)');
  });

  it('attend payout.paid avant de solder un escrow et incrémenter la confiance', () => {
    const release = readFileSync(`${FUNCTIONS_ROOT}/escrow-release/index.ts`, 'utf8');
    const migration = readFileSync(
      'supabase/migrations/20260713227000_securiser_webhooks_stripe_connect.sql',
      'utf8',
    );

    expect(release).toContain('statut: "RELEASE_PLANIFIE"');
    expect(release).not.toContain('statut: "PAYE"');
    expect(release).not.toContain('fn_escrow_incrementer_confiance');
    expect(migration).toContain("SET statut = 'PAYE'");
    expect(migration).toContain('PERFORM public.fn_escrow_incrementer_confiance');
    expect(migration).toContain("v_row.statut NOT IN ('RELEASE_PLANIFIE', 'PAYE')");
  });
});
