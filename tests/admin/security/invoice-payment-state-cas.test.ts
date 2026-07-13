import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const createPayment = readFileSync(
  'supabase/functions/create-invoice-payment/index.ts',
  'utf8',
);
const confirmPayment = readFileSync(
  'supabase/functions/confirm-invoice-payment/index.ts',
  'utf8',
);

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
    const start = createPayment.indexOf('if (existingIntent?.status === "succeeded")');
    const end = createPayment.indexOf('if (existingIntent && ["processing"', start);
    const block = createPayment.slice(start, end);

    expect(block).toContain('.in("statut", ["EMISE", "EN_RETARD"])');
    expect(block).toContain('.select("id")');
    expect(block).toContain('.maybeSingle()');
    expect(block).toContain('if (!factureSynchronisee)');
    expect(block).toContain('FACTURE_PAIEMENT_CHECKOUT_CAS_PERDU');
    expect(block).toContain('throw new Error(');
    expect(block).not.toContain('.neq("statut", "PAYEE")');
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
    const validationStart = confirmPayment.indexOf('const montantAttenduCents');
    const validationEnd = confirmPayment.indexOf('if (paymentIntent.status !== "succeeded")');
    const validation = confirmPayment.slice(validationStart, validationEnd);
    const firstConfirmed = confirmPayment.indexOf('confirmed: true');

    expect(validation).toContain('paymentIntent.metadata?.facture_id !== facture.id');
    expect(validation).toContain('paymentIntent.currency.toLowerCase() !== "eur"');
    expect(validation).toContain('paymentIntent.amount !== montantAttenduCents');
    expect(validation).toContain('paymentIntent.amount_received !== montantAttenduCents');
    expect(validation).toContain('customerPaymentIntent !== customerFacture');
    expect(validation).toContain('if (incoherences.length > 0)');
    expect(firstConfirmed).toBeGreaterThan(validationEnd);
  });

  it('ne confirme PAYEE de façon idempotente qu’après un PaymentIntent succeeded cohérent', () => {
    const succeededGate = confirmPayment.indexOf('if (paymentIntent.status !== "succeeded")');
    const idempotentSuccess = confirmPayment.indexOf('if (factureDejaPayee)', succeededGate);
    const successPayload = confirmPayment.indexOf('confirmed: true', idempotentSuccess);

    expect(idempotentSuccess).toBeGreaterThan(succeededGate);
    expect(successPayload).toBeGreaterThan(idempotentSuccess);
  });

  it('exige la ligne du CAS EMISE/EN_RETARD et renvoie un échec si elle manque', () => {
    const updateStart = confirmPayment.indexOf('const { data: factureConfirmee, error: updateError }');
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
