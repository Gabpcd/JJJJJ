import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const sourceCharge = readFileSync(
  'supabase/functions/_shared/stripe-source-charge.ts',
  'utf8',
);
const createInvoice = readFileSync(
  'supabase/functions/create-invoice-payment/index.ts',
  'utf8',
);
const confirmInvoice = readFileSync(
  'supabase/functions/confirm-invoice-payment/index.ts',
  'utf8',
);
const sepa = readFileSync(
  'supabase/functions/sepa-auto-charge/index.ts',
  'utf8',
);
const webhook = readFileSync(
  'supabase/functions/_shared/stripe-webhook-handler.ts',
  'utf8',
);

describe('Stripe — Charge source réellement acquise avant PAYEE', () => {
  it('centralise tous les contrôles anti-remboursement, litige et divergence comptable', () => {
    expect(sourceCharge).toContain('stripe.charges.retrieve(chargeId)');
    expect(sourceCharge).toContain('if (charge.refunded)');
    expect(sourceCharge).toContain('if (charge.amount_refunded > 0)');
    expect(sourceCharge).toContain('if (charge.disputed)');
    expect(sourceCharge).toContain('if (!charge.paid)');
    expect(sourceCharge).toContain('if (charge.status !== "succeeded")');
    expect(sourceCharge).toContain('if (charge.amount !== expected.amountCents)');
    expect(sourceCharge).toContain('if (charge.currency.toLowerCase() !== expectedCurrency)');
    expect(sourceCharge).toContain('if (objectId(charge.customer) !== expected.customerId)');
    expect(sourceCharge).toContain('if (objectId(charge.payment_intent) !== paymentIntent.id)');
  });

  it('protège la reprise de PI réussi et la Session Checkout complète', () => {
    const succeededStart = createInvoice.indexOf('if (existingIntent?.status === "succeeded")');
    const succeededUpdate = createInvoice.indexOf('statut: "PAYEE"', succeededStart);
    const succeededGuard = createInvoice.indexOf(
      'requireAcquiredStripeSourceCharge(stripe, existingIntent',
      succeededStart,
    );
    const sessionValidator = createInvoice.slice(
      createInvoice.indexOf('const verifierSessionReutilisable'),
      createInvoice.indexOf('const auditerSessionIncoherente'),
    );

    expect(succeededGuard).toBeGreaterThan(succeededStart);
    expect(succeededGuard).toBeLessThan(succeededUpdate);
    expect(sessionValidator).toContain('requireSucceededIntent');
    expect(sessionValidator).toContain(
      'requireAcquiredStripeSourceCharge(stripe, sessionPaymentIntent',
    );
    expect(sessionValidator).toContain('source_charge.${check}');
  });

  it('protège confirm-invoice-payment avant tout succès idempotent ou CAS PAYEE', () => {
    const succeededStatus = confirmInvoice.indexOf(
      'if (paymentIntent.status !== "succeeded")',
    );
    const guard = confirmInvoice.indexOf(
      'requireAcquiredStripeSourceCharge(stripe, paymentIntent',
      succeededStatus,
    );
    const alreadyPaid = confirmInvoice.indexOf('if (factureDejaPayee)', guard);
    const payeeUpdate = confirmInvoice.indexOf('statut: "PAYEE"', guard);

    expect(guard).toBeGreaterThan(succeededStatus);
    expect(guard).toBeLessThan(alreadyPaid);
    expect(guard).toBeLessThan(payeeUpdate);
    expect(confirmInvoice).toContain('source_charge.${check}');
  });

  it('protège les deux webhooks de facture avant leur écriture PAYEE', () => {
    const validator = webhook.slice(
      webhook.indexOf('const loadAndValidateInvoicePayment'),
      webhook.indexOf('const loadAndValidateEscrowPayment'),
    );
    expect(validator).toContain('paymentIntent.status !== "succeeded"');
    expect(validator).toContain('requireAcquiredStripeSourceCharge(stripe, paymentIntent');
    expect(validator).toContain('source_charge.${check}');

    for (const marker of [
      '"checkout.session.completed"',
      '"payment_intent.succeeded"',
    ]) {
      expect(webhook).toContain(marker);
    }
  });

  it('ne rapproche SEPA succeeded que si sa Charge reste acquise, y compris en reprise', () => {
    const calls = sepa.match(/requireAcquiredStripeSourceCharge\(/g) || [];
    expect(calls.length).toBeGreaterThanOrEqual(3);
    expect(sepa).toContain('claimedIntent.status === "succeeded" && claimSourceChargeAcquired');
    expect(sepa).toContain('intentStatus === "succeeded" && recoveredSourceChargeAcquired');
    expect(sepa).toContain('SOURCE_CHARGE_NOT_ACQUIRED');
    expect(sepa).toContain('statut: "EN_RETARD"');
  });
});
