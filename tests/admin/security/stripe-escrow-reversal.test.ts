import { describe, expect, it, vi } from 'vitest';
import { requireEscrowReversalBinding } from '../../../supabase/functions/_shared/stripe-escrow-reversal';

function fixture() {
  const escrow = { id: 'escrow', mission_id: 'mission', soignant_id: 'soignant', etablissement_id: 'etab',
    stripe_payment_intent_id: 'pi', montant_total_cents: 28356, honoraires_cents: 24000, commission_cents: 4356 };
  const transfer = { id: 'tr', amount: 28356, amount_reversed: 28356, reversed: true, currency: 'eur',
    livemode: false, source_transaction: 'ch', destination: 'acct', transfer_group: 'mission_mission', metadata: {} };
  const charge = { id: 'ch', payment_intent: 'pi', transfer: 'tr', amount: 28356, currency: 'eur', livemode: false, paid: true, status: 'succeeded' };
  const pi = { id: 'pi', latest_charge: 'ch', status: 'succeeded', amount: 28356, amount_received: 28356,
    application_fee_amount: 4356, currency: 'eur', livemode: false, transfer_data: { destination: 'acct' },
    metadata: { type: 'ESCROW_MISSION_PAYMENT', paiement_escrow_id: 'escrow', mission_id: 'mission', soignant_id: 'soignant', etablissement_id: 'etab' } };
  const reversal = { id: 'trr', source_refund: 're', transfer: 'tr', amount: 28356, currency: 'eur' };
  const refund = { id: 're', charge: 'ch', payment_intent: 'pi', transfer_reversal: 'trr', amount: 28356, currency: 'eur', status: 'succeeded',
    metadata: { queue_id: 'queue', source: 'jolene_refunds_cron', origin_type: 'ESCROW', paiement_escrow_id: 'escrow', mission_id: 'mission', etablissement_id: 'etab', reverse_transfer: 'true', absorbe_plateforme: 'false', refund_application_fee_cts: '4356' } };
  const queue = { id: 'queue', paiement_escrow_id: 'escrow', stripe_payment_intent_id: 'pi', stripe_refund_id: 're', montant_cts: 28356, reverse_transfer: true, absorbe_plateforme: false, refund_application_fee_cts: 4356 };
  const rows: Record<string, any> = { paiements_escrow: escrow, stripe_connect_onboarding: { stripe_account_id: 'acct' }, stripe_refunds_queue: queue };
  const db = { from: vi.fn((table: string) => ({ select: () => ({ eq: (column: string, value: string) => ({ maybeSingle: async () => ({ data: rows[table]?.[column] === value || (table === 'stripe_connect_onboarding' && value === 'soignant') ? rows[table] : null, error: null }) }) }) })) };
  const stripe = { charges: { retrieve: vi.fn(async () => charge) }, paymentIntents: { retrieve: vi.fn(async () => pi) }, refunds: { retrieve: vi.fn(async () => refund) }, transfers: { listReversals: vi.fn(async () => ({ data: [reversal], has_more: false })) } };
  const run = () => requireEscrowReversalBinding(stripe as any, db as any, transfer as any);
  return { escrow, transfer, charge, pi, reversal, refund, queue, rows, stripe, db, run };
}

describe('Escrow destination charge reversal', () => {
  it('binds the gross Stripe transfer to the same escrow/refund without changing financial state', async () => {
    const f = fixture();
    await expect(f.run()).resolves.toEqual(f.escrow);
    expect(f.stripe.transfers.listReversals).toHaveBeenCalledWith('tr', { limit: 100 });
    expect(f.db.from.mock.calls.map(([table]) => table)).toEqual(['paiements_escrow', 'stripe_connect_onboarding', 'stripe_refunds_queue']);
  });
  it('acknowledges the reversal even while its customer refund is pending, without confirming it', async () => {
    const f = fixture(); f.refund.status = 'pending'; f.queue.stripe_refund_id = '';
    await expect(f.run()).resolves.toEqual(f.escrow);
  });
  it.each([
    ['foreign escrow', (f: ReturnType<typeof fixture>) => { f.pi.metadata.paiement_escrow_id = 'other'; }],
    ['foreign caregiver', f => { f.pi.metadata.soignant_id = 'other'; }],
    ['foreign institution', f => { f.pi.metadata.etablissement_id = 'other'; }],
    ['foreign destination', f => { f.transfer.destination = 'other'; }],
    ['wrong intent destination', f => { f.pi.transfer_data.destination = 'other'; }],
    ['net amount instead of gross', f => { f.transfer.amount = 24000; }],
    ['wrong commission', f => { f.pi.application_fee_amount = 4355; }],
    ['other transfer', f => { f.charge.transfer = 'other'; }],
    ['other latest charge', f => { f.pi.latest_charge = 'other'; }],
    ['unpaid charge', f => { f.charge.paid = false; }],
    ['foreign group', f => { f.transfer.transfer_group = 'mission_other'; }],
    ['mixed test/live', f => { f.transfer.livemode = true; }],
    ['foreign currency', f => { f.transfer.currency = 'usd'; }],
    ['missing local binding', f => { f.rows.paiements_escrow = null; }],
    ['other reversal source', f => { f.reversal.source_refund = ''; }],
    ['wrong reversal amount', f => { f.reversal.amount--; }],
    ['wrong reversal transfer', f => { f.reversal.transfer = 'other'; }],
    ['foreign refund charge', f => { f.refund.charge = 'other'; }],
    ['foreign refund intent', f => { f.refund.payment_intent = 'other'; }],
    ['foreign refund reversal', f => { f.refund.transfer_reversal = 'other'; }],
    ['failed refund', f => { f.refund.status = 'failed'; }],
    ['unowned refund', f => { f.refund.metadata.queue_id = ''; }],
    ['other queue escrow', f => { f.queue.paiement_escrow_id = 'other'; }],
    ['other queue intent', f => { f.queue.stripe_payment_intent_id = 'other'; }],
    ['other queue refund', f => { f.queue.stripe_refund_id = 'other'; }],
    ['disabled reverse flag', f => { f.queue.reverse_transfer = false; }],
    ['wrong refund source', f => { f.refund.metadata.source = 'external'; }],
    ['incomplete sum', f => { f.transfer.amount_reversed--; f.transfer.reversed = false; }],
  ] as [string, (f: ReturnType<typeof fixture>) => void][])('rejects %s', async (_, mutate) => {
    const f = fixture(); mutate(f); await expect(f.run()).rejects.toThrow('ESCROW_REVERSAL_IDENTITY_MISMATCH');
  });
  it('rejects an incomplete page and repeated reversals instead of looping or acknowledging', async () => {
    const f = fixture(); f.stripe.transfers.listReversals.mockResolvedValue({ data: [], has_more: true });
    await expect(f.run()).rejects.toThrow('pagination_incomplete');
    const g = fixture(); g.stripe.transfers.listReversals.mockResolvedValue({ data: [g.reversal], has_more: true });
    await expect(g.run()).rejects.toThrow('duplicate_reversal');
  });
});
