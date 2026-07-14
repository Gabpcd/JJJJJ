import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { findInvoicePaymentIntentInconsistencies } from '../../../supabase/functions/_shared/invoice-payment-intent';

const createPayment = readFileSync(
  'supabase/functions/create-invoice-payment/index.ts',
  'utf8',
);
const confirmPayment = readFileSync(
  'supabase/functions/confirm-invoice-payment/index.ts',
  'utf8',
);
const sharedValidator = readFileSync(
  'supabase/functions/_shared/invoice-payment-intent.ts',
  'utf8',
);

const coherentIntent = {
  id: 'pi_facture',
  status: 'succeeded',
  amount: 12_345,
  amount_received: 12_345,
  currency: 'eur',
  customer: 'cus_etab',
  metadata: {
    facture_id: 'facture-a',
    etablissement_id: 'etab-a',
  },
};

const expectedIdentity = {
  factureId: 'facture-a',
  etablissementId: 'etab-a',
  customerId: 'cus_etab',
  amountCents: 12_345,
  currency: 'eur',
};

describe('Paiement facture — états et rapprochement atomique', () => {
  it('n’autorise création ou reprise Checkout que pour EMISE et EN_RETARD', () => {
    const gateStart = createPayment.indexOf('const statutsPayables = ["EMISE", "EN_RETARD"]');
    const stripeInit = createPayment.indexOf("step = '6_stripe_init'");
    const gate = createPayment.slice(gateStart, stripeInit);

    expect(gateStart).toBeGreaterThan(0);
    expect(gateStart).toBeLessThan(stripeInit);
    expect(gate).toContain('if (!statutsPayables.includes(facture.statut))');
    expect(gate).toContain('status: dejaPayee ? 400 : 409');
    expect(gate).toContain('status: facture.statut');
  });

  it('rapproche un PaymentIntent réussi avec un CAS strict et audite toute perte', () => {
    const validation = createPayment.indexOf('findInvoicePaymentIntentInconsistencies(existingIntent');
    const start = createPayment.indexOf('if (existingIntent?.status === "succeeded")');
    const end = createPayment.indexOf('if (existingIntent && ["processing"', start);
    const block = createPayment.slice(start, end);

    expect(validation).toBeGreaterThan(-1);
    expect(validation).toBeLessThan(start);
    expect(block).toContain('.in("statut", ["EMISE", "EN_RETARD"])');
    expect(block).toContain('.select("id")');
    expect(block).toContain('.maybeSingle()');
    expect(block).toContain('if (!factureSynchronisee)');
    expect(block).toContain('FACTURE_PAIEMENT_CHECKOUT_CAS_PERDU');
    expect(block).toContain('throw new Error(');
    expect(block).not.toContain('.neq("statut", "PAYEE")');
  });

  it('grave facture et établissement dans la Session et le PaymentIntent créés', () => {
    const checkoutBlock = createPayment.slice(
      createPayment.indexOf('const sessionParams'),
      createPayment.indexOf('if (embedded)'),
    );
    expect(checkoutBlock.match(/facture_id: facture\.id/g)).toHaveLength(2);
    expect(checkoutBlock.match(/etablissement_id: facture\.etablissement_id/g)).toHaveLength(2);
  });

  it('ne réexpose une Session open qu’après validation de son identité et de son montant', () => {
    const openBranch = createPayment.indexOf(
      'if (existingSession?.status === "open" && existingSession.expires_at * 1000 > Date.now())',
    );
    const validation = createPayment.indexOf(
      'await verifierSessionReutilisable(existingSession, false)',
      openBranch,
    );
    const resumed = createPayment.indexOf('resumed: true', openBranch);

    expect(openBranch).toBeGreaterThan(0);
    expect(validation).toBeGreaterThan(openBranch);
    expect(resumed).toBeGreaterThan(validation);
    expect(createPayment.slice(openBranch, resumed)).toContain(
      'stripe.checkout.sessions.expire(existingSession.id)',
    );
  });

  it('lie la Session créée par CAS ou l’expire sans exposer son secret', () => {
    const sessionCreate = createPayment.indexOf('stripe.checkout.sessions.create(');
    const cas = createPayment.indexOf('let factureLieeQuery = supabaseAdmin', sessionCreate);
    const response = createPayment.indexOf('client_secret: session.client_secret', cas);
    const block = createPayment.slice(cas, response);

    expect(cas).toBeGreaterThan(sessionCreate);
    expect(block).toContain('.in("statut", ["EMISE", "EN_RETARD"])');
    expect(block).toContain('.select("id")');
    expect(block).toContain('.maybeSingle()');
    expect(block).toContain('if (updateError || !factureLiee)');
    expect(block).toContain('stripe.checkout.sessions.expire(session.id)');
    expect(block).toContain('FACTURE_CHECKOUT_CAS_PERDU_COMPENSE');
    expect(response).toBeGreaterThan(cas);
  });
});

describe('Confirmation facture — identité Stripe stricte', () => {
  it('refuse les états non payables avant tout accès Stripe', () => {
    const gateStart = confirmPayment.indexOf('const statutsTransitionPaiement = ["EMISE", "EN_RETARD"]');
    const stripeInit = confirmPayment.indexOf('const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")');
    const gate = confirmPayment.slice(gateStart, stripeInit);

    expect(gateStart).toBeGreaterThan(0);
    expect(gateStart).toBeLessThan(stripeInit);
    expect(gate).toContain('!statutsTransitionPaiement.includes(facture.statut)');
    expect(gate).toContain('confirmed: false');
    expect(gate).toContain('status: 409');
  });

  it('valide facture_id, devise EUR, montant reçu et customer avant tout succès', () => {
    const validationStart = confirmPayment.indexOf('findInvoicePaymentIntentInconsistencies(paymentIntent');
    const validationEnd = confirmPayment.indexOf('if (paymentIntent.status !== "succeeded")');
    const firstConfirmed = confirmPayment.indexOf('confirmed: true');

    expect(validationStart).toBeGreaterThan(-1);
    expect(validationStart).toBeLessThan(validationEnd);
    expect(sharedValidator).toContain('paymentIntent.metadata?.facture_id !== expected.factureId');
    expect(sharedValidator).toContain('paymentIntent.metadata?.etablissement_id !== expected.etablissementId');
    expect(sharedValidator).toContain('objectId(paymentIntent.customer) !== expected.customerId');
    expect(sharedValidator).toContain('paymentIntent.currency.toLowerCase() !== expectedCurrency');
    expect(sharedValidator).toContain('paymentIntent.amount !== expected.amountCents');
    expect(sharedValidator).toContain('paymentIntent.amount_received !== expected.amountCents');
    expect(firstConfirmed).toBeGreaterThan(validationEnd);
  });

  it.each([
    ['customer', { customer: 'cus_autre' }, 'customer'],
    ['montant', { amount: 12_344 }, 'amount'],
    ['montant reçu', { amount_received: 12_344 }, 'amount_received'],
    ['devise', { currency: 'usd' }, 'currency'],
    ['facture metadata', { metadata: { ...coherentIntent.metadata, facture_id: 'facture-b' } }, 'facture_id'],
    ['établissement metadata', { metadata: { ...coherentIntent.metadata, etablissement_id: 'etab-b' } }, 'etablissement_id'],
  ])('refuse un PaymentIntent avec un mauvais %s', (_label, override, expectedFailure) => {
    const inconsistencies = findInvoicePaymentIntentInconsistencies(
      { ...coherentIntent, ...override },
      expectedIdentity,
    );
    expect(inconsistencies).toContain(expectedFailure);
  });

  it('accepte l’identité comptable exacte et tolère amount_received=0 tant que le paiement est en cours', () => {
    expect(findInvoicePaymentIntentInconsistencies(coherentIntent, expectedIdentity)).toEqual([]);
    expect(findInvoicePaymentIntentInconsistencies(
      { ...coherentIntent, status: 'processing', amount_received: 0 },
      expectedIdentity,
    )).toEqual([]);
  });

  it('ne confirme PAYEE de façon idempotente qu’après un PaymentIntent succeeded cohérent', () => {
    const succeededGate = confirmPayment.indexOf('if (paymentIntent.status !== "succeeded")');
    const idempotentSuccess = confirmPayment.indexOf('if (factureDejaPayee)', succeededGate);
    const successPayload = confirmPayment.indexOf('confirmed: true', idempotentSuccess);

    expect(idempotentSuccess).toBeGreaterThan(succeededGate);
    expect(successPayload).toBeGreaterThan(idempotentSuccess);
  });

  it('exige la ligne du CAS EMISE/EN_RETARD et renvoie un échec si elle manque', () => {
    const updateStart = confirmPayment.indexOf('let confirmationQuery = supabaseAdmin');
    const successStart = confirmPayment.indexOf('return new Response(JSON.stringify({\n      confirmed: true', updateStart);
    const block = confirmPayment.slice(updateStart, successStart);

    expect(block).toContain('.in("statut", ["EMISE", "EN_RETARD"])');
    expect(block).toContain('.select("id")');
    expect(block).toContain('.maybeSingle()');
    expect(block).toContain('if (!factureConfirmee)');
    expect(block).toContain('FACTURE_PAIEMENT_CONFIRMATION_CAS_PERDU');
    expect(block).toContain('confirmed: false');
    expect(block).toContain('status: 409');
    expect(block).not.toContain('.neq("statut", "PAYEE")');
  });
});
