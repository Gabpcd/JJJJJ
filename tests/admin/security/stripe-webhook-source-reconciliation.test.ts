import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const handler = readFileSync(
  'supabase/functions/_shared/stripe-webhook-handler.ts',
  'utf8',
);

describe('Stripe webhook — frontières de source P0', () => {
  it.each([
    'checkout.session.completed',
    'checkout.session.expired',
    'invoice.payment_failed',
    'payment_intent.succeeded',
    'payment_intent.payment_failed',
    'charge.succeeded',
    'charge.failed',
    'charge.dispute.created',
    'charge.dispute.closed',
    'charge.refunded',
    'charge.pending',
    'charge.expired',
    'transfer.created',
    'transfer.updated',
    'transfer.reversed',
  ])('%s ne peut être dispatché que par la source PLATFORM', (eventType) => {
    expect(handler).toContain(
      `verified.source === "PLATFORM" && event.type === "${eventType}"`,
    );
  });

  it.each([
    'account.updated',
    'payout.created',
    'payout.paid',
    'payout.failed',
    'payout.canceled',
  ])('%s ne peut être dispatché que par la source CONNECT', (eventType) => {
    expect(handler).toContain(
      `verified.source === "CONNECT" && event.type === "${eventType}"`,
    );
  });

  it('limite l’allow-list Connect aux événements de compte et payout attendus', () => {
    const connectStart = handler.indexOf('const CONNECT_EVENT_TYPES');
    const connectEnd = handler.indexOf('function eventAllowedForSource', connectStart);
    const connectAllowList = handler.slice(connectStart, connectEnd);

    expect(connectAllowList).toContain('"account.updated"');
    expect(connectAllowList).toContain('"payout.created"');
    expect(connectAllowList).toContain('"payout.paid"');
    expect(connectAllowList).toContain('"payout.failed"');
    expect(connectAllowList).toContain('"payout.canceled"');
    expect(connectAllowList).not.toContain('"checkout.session.completed"');
    expect(connectAllowList).not.toContain('"payment_intent.succeeded"');
    expect(connectAllowList).not.toContain('"charge.succeeded"');
    expect(connectAllowList).not.toContain('"transfer.created"');
  });
});

describe('Stripe webhook — réconciliation retryable après mouvement', () => {
  it('reprend la réconciliation locale d’un transfert déjà créé sans recréer les fonds', () => {
    const lookupStart = handler.indexOf('const { data: transferExistant');
    const movementStart = handler.indexOf('let mouvementStripeConfirme', lookupStart);
    const createStart = handler.indexOf('stripe.transfers.create', movementStart);
    const paymentReconciliation = handler.indexOf('const { data: existingPayment', createStart);
    const prefix = handler.slice(lookupStart, movementStart);

    expect(lookupStart).toBeGreaterThan(0);
    expect(prefix).not.toContain('markEventProcessed');
    expect(handler.slice(movementStart, paymentReconciliation)).toContain('transferDejaCree');
    expect(handler.slice(movementStart, paymentReconciliation)).toContain('reprise de la réconciliation locale');
    expect(handler.slice(movementStart, paymentReconciliation)).toContain('transfer_${session.id}');
  });

  it('relâche le claim et renvoie 500 si une écriture critique échoue après le transfert', () => {
    const movementStart = handler.indexOf('let mouvementStripeConfirme');
    const catchStart = handler.indexOf('} catch (transferErr: any)', movementStart);
    const catchEnd = handler.indexOf('await markEventProcessed()', catchStart);
    const catchBlock = handler.slice(catchStart, catchEnd);

    expect(handler).toContain('mouvementStripeConfirme = true');
    expect(catchBlock).toContain('if (mouvementStripeConfirme)');
    expect(catchBlock).toContain('Post-transfer reconciliation failed; Stripe event must retry');
    expect(catchBlock).toContain('throw new Error');
    expect(handler).toContain('traitement_commence_le: null');
    expect(handler).toContain('status: 500');
  });

  it('propage toutes les erreurs de réconciliation financière critiques', () => {
    for (const message of [
      'Transfer persistence failed after Stripe success',
      'Caregiver payment reconciliation lookup failed',
      'Mission reconciliation lookup failed',
      'Caregiver payment persistence failed',
      'Mission payment reconciliation failed',
      'Commission invoice lookup failed',
      'Commission invoice persistence failed',
      'Caregiver invoice reconciliation failed',
      'Caregiver invoice state lookup failed',
    ]) {
      expect(handler).toContain(`throw new Error(`);
      expect(handler).toContain(message);
    }
    expect(handler).not.toContain('console.error("paiements_soignant insert failed:"');
    expect(handler).not.toContain('console.error("factures (commission) insert failed:"');
    expect(handler).not.toContain('console.error("factures_honoraires update failed:"');
  });

  it('ne clôt plus un checkout capturé si la facture locale est irréconciliable', () => {
    const standardFlowStart = handler.indexOf('// ── Standard facture payment flow ──');
    const anomalyStart = handler.indexOf('if (!factureUpdated)', standardFlowStart);
    const anomalyEnd = handler.indexOf('// Alias pour la suite du bloc', anomalyStart);
    const anomalyBlock = handler.slice(anomalyStart, anomalyEnd);

    expect(anomalyBlock).toContain('Captured checkout cannot reconcile invoice');
    expect(anomalyBlock).toContain('throw new Error');
    expect(anomalyBlock).not.toContain('markEventProcessed');
  });

  it('ne marque une facture checkout PAYEE que lorsque Stripe confirme paid', () => {
    const standardFlowStart = handler.indexOf('// ── Standard facture payment flow ──');
    const payeeUpdate = handler.indexOf('statut: "PAYEE"', standardFlowStart);
    const paidGate = handler.indexOf('session.payment_status !== "paid"', standardFlowStart);
    const gateBlock = handler.slice(paidGate, handler.indexOf('const factureId', paidGate));

    expect(paidGate).toBeGreaterThan(standardFlowStart);
    expect(paidGate).toBeLessThan(payeeUpdate);
    expect(gateBlock).toContain('invoice_payment_not_paid');
    expect(gateBlock).toContain('payment_intent.succeeded');
    expect(gateBlock).toContain('await markEventProcessed()');
  });
});

describe('Stripe webhook — incidents financiers retryables', () => {
  const branch = (eventType: string, nextEventType: string) => {
    const start = handler.indexOf(`event.type === "${eventType}"`);
    const end = handler.indexOf(`event.type === "${nextEventType}"`, start + 1);
    expect(start).toBeGreaterThan(0);
    expect(end).toBeGreaterThan(start);
    return handler.slice(start, end);
  };

  it('propage les échecs DB de charge.failed tout en gardant l’email non bloquant', () => {
    const block = branch('charge.failed', 'charge.dispute.created');

    expect(block).toContain('failedChargeLookupError');
    expect(block).toContain('failedChargeUpdateError');
    expect(block).toContain('failedChargeAuditError');
    expect(block).toContain('throw new Error(`Failed charge');
    expect(block).toContain('catch (emailErr)');
  });

  it('propage lookup, RPC incident, update et audit de charge.dispute.created', () => {
    const block = branch('charge.dispute.created', 'charge.dispute.closed');

    expect(block).toContain('escrowDisputeLookupError');
    expect(block).toContain('escrowDisputeIncidentError');
    expect(block).toContain('disputeTransferLookupError');
    expect(block).toContain('disputeTransferUpdateError');
    expect(block).toContain('disputeCreatedAuditError');
    expect(block).toContain('catch (emailErr)');
  });

  it('propage lookup, update et audit de charge.dispute.closed', () => {
    const block = branch('charge.dispute.closed', 'charge.refunded');

    expect(block).toContain('closedDisputeLookupError');
    expect(block).toContain('closedDisputeUpdateError');
    expect(block).toContain('disputeClosedAuditError');
    expect(block).toContain('throw new Error(`Closed dispute');
    expect(block).toContain('catch (emailErr)');
  });
});
