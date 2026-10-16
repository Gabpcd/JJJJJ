import { describe, expect, it } from 'vitest';
import { processStandardConnectPayouts, reconcileStandardPayoutEvent, standardPayoutMetadata } from '../../../supabase/functions/_shared/stripe-standard-payout';
import type { StandardPayoutWork } from '../../../supabase/functions/_shared/stripe-standard-payout';
import type Stripe from 'stripe';

const uuid = (n: number) => `98400000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const NOW = Date.parse('2026-10-16T12:00:00Z');
function simulation() {
  const w: StandardPayoutWork = { id: uuid(1), missionId: uuid(2), soignantId: uuid(3), etablissementId: uuid(4),
    factureHonoraireId: uuid(5), accountId: 'acct_fixture', customerId: 'cus_fixture', transferId: 'tr_fixture',
    paymentIntentId: 'pi_fixture', chargeId: 'ch_fixture', amountCents: 10000, totalCents: 11800,
    livemode: false, state: 'WAITING', attempt: 0, payoutId: null, previousPayoutId: null, firstPostAt: null };
  const state = { work: w, available: true, globalBalance: 10000, mode: 'manual', ownerMatches: true,
    refunded: false, disputed: false, reversed: false, net: 10000, admitted: true, claimed: true,
    lostResponse: false, persistenceFailure: false, createCalls: [] as Array<{ params: any; options: any }>,
    rpcCalls: [] as Array<{ name: string; args: any }>, payouts: [] as any[], saturated: false, wrongDestination: false,
    returned: true, returnAvailable: true, currentPayout: null as any };
  const payout = (status = 'pending', attempt = state.work.attempt) => ({ id: `po_fixture${attempt}`, amount: 10000,
    currency: 'eur', livemode: false, automatic: false, status, metadata: { ...standardPayoutMetadata(state.work), attempt: String(attempt) },
    failure_balance_transaction: ['failed', 'canceled'].includes(status) && state.returned ? 'txn_returned' : null });
  const db = { async rpc(name: string, args: any) {
    state.rpcCalls.push({ name, args });
    if (name === 'fn_connect_payouts_a_traiter') return { data: [{ id: w.id }], error: null };
    if (name === 'fn_connect_payout_prendre') return { data: state.claimed ? { ...state.work } : null, error: null };
    if (name === 'fn_connect_payout_demarrer') {
      if (state.admitted) state.work.firstPostAt ||= new Date(NOW).toISOString();
      return { data: state.admitted, error: null };
    }
    if (name === 'fn_connect_payout_constater') {
      if (state.persistenceFailure) return { data: null, error: { message: 'unavailable' } };
      state.work.payoutId = args.p_payout.id;
      state.work.state = ['failed', 'canceled'].includes(args.p_payout.status) ? 'FAILED' : args.p_payout.status === 'paid' ? 'PAID' : 'SUBMITTED';
      return { data: { recorded: true }, error: null };
    }
    if (name === 'fn_connect_payout_reessayer') {
      state.work = { ...state.work, state: 'WAITING', payoutId: null, previousPayoutId: args.p_previous_id,
        firstPostAt: null, attempt: state.work.attempt + 1 };
      return { data: true, error: null };
    }
    if (name === 'fn_connect_payout_reporter') return { data: null, error: null };
    throw new Error(`Unexpected RPC ${name}`);
  } };
  const stripe = {
    accounts: { retrieve: async () => ({ id: w.accountId, metadata: { soignant_id: state.ownerMatches ? w.soignantId : uuid(99) },
      settings: { payouts: { schedule: { interval: state.mode } } }, payouts_enabled: true, charges_enabled: true,
      details_submitted: true, requirements: {}, capabilities: { transfers: 'active' } }) },
    transfers: { retrieve: async () => ({ id: w.transferId, amount: 10000, currency: 'eur', livemode: false,
      destination: state.wrongDestination ? 'acct_other' : w.accountId, source_transaction: w.chargeId, destination_payment: 'py_destination',
      transfer_group: `facture_${w.factureHonoraireId}`, reversed: state.reversed, amount_reversed: state.reversed ? 10000 : 0,
      metadata: { mission_id: w.missionId, soignant_id: w.soignantId, facture_honoraires_id: w.factureHonoraireId, payment_scope: 'INVOICE' } }) },
    paymentIntents: { retrieve: async () => ({ id: w.paymentIntentId, status: 'succeeded', amount: 11800, amount_received: 11800,
      currency: 'eur', livemode: false, customer: w.customerId, latest_charge: w.chargeId }) },
    customers: { retrieve: async () => ({ id: w.customerId, livemode: false, metadata: { etablissement_id: w.etablissementId } }) },
    charges: { retrieve: async (chargeId: string, options?: any) => {
      if (chargeId === 'py_destination') {
        expect(options).toEqual({ stripeAccount: w.accountId });
        return { id: chargeId, source_transfer: w.transferId, amount: 10000, currency: 'eur', livemode: false,
          paid: true, captured: true, refunded: false, amount_refunded: 0, balance_transaction: 'txn_destination' };
      }
      return { id: w.chargeId, amount: 11800, currency: 'eur', livemode: false, payment_intent: w.paymentIntentId,
        customer: w.customerId, paid: true, captured: true, status: 'succeeded', refunded: state.refunded,
        amount_refunded: state.refunded ? 100 : 0, disputed: state.disputed };
    } },
    balanceTransactions: { retrieve: async (tx: string, options: any) => {
      expect(options).toEqual({ stripeAccount: w.accountId });
      return tx === 'txn_returned'
        ? { id: tx, source: state.currentPayout.id, amount: 10000, net: 10000, currency: 'eur', status: state.returnAvailable ? 'available' : 'pending', available_on: NOW / 1000 - 1 }
        : { id: tx, source: 'py_destination', amount: 10000, net: state.net, currency: 'eur', status: state.available ? 'available' : 'pending', available_on: NOW / 1000 - 1 };
    } },
    balance: { retrieve: async (options: any) => {
      expect(options).toEqual({ stripeAccount: w.accountId });
      return { available: [{ currency: 'eur', amount: state.globalBalance, source_types: { card: state.globalBalance } }] };
    } },
    payouts: {
      list: async (_params: any, options: any) => {
        expect(options).toEqual({ stripeAccount: w.accountId });
        return { data: state.payouts, has_more: state.saturated };
      },
      retrieve: async () => state.currentPayout || state.payouts[0],
      create: async (params: any, options: any) => {
        state.createCalls.push({ params, options });
        const p = { ...payout(), metadata: params.metadata };
        state.payouts.push(p);
        if (state.lostResponse) { state.lostResponse = false; throw new Error('response lost'); }
        return p;
      },
    },
  } as unknown as Stripe;
  const run = (now = NOW) => processStandardConnectPayouts(db, stripe, { now, owner: () => uuid(90) });
  const lastReport = () => state.rpcCalls.filter(c => c.name === 'fn_connect_payout_reporter').at(-1)?.args;
  return { state, stripe, db, payout, run, lastReport };
}

describe('standard Connect bank payouts — real helper, simulated provider', () => {
  it('creates exactly practitioner amount on the exact connected account after reservation', async () => {
    const s = simulation(); expect(await s.run()).toMatchObject({ checked: 1, errors: 0 });
    expect(s.state.createCalls).toHaveLength(1);
    expect(s.state.createCalls[0]).toMatchObject({ params: { amount: 10000, currency: 'eur', source_type: 'card' },
      options: { stripeAccount: 'acct_fixture', idempotencyKey: `connect_payout_${uuid(1)}_0` } });
    expect(s.state.rpcCalls.findIndex(c => c.name === 'fn_connect_payout_demarrer')).toBeLessThan(s.state.rpcCalls.findIndex(c => c.name === 'fn_connect_payout_constater'));
    expect(s.state.work.state).toBe('SUBMITTED');
  });
  it('global funds from escrow never replace pending funds of the exact transfer', async () => {
    const s = simulation(); s.state.available = false; s.state.globalBalance = 1000000;
    expect(await s.run()).toMatchObject({ deferred: 1 }); expect(s.state.createCalls).toHaveLength(0);
    expect(s.lastReport()).toMatchObject({ p_code: 'WAITING_FUNDS', p_review: false });
  });
  it.each(['refunded', 'disputed', 'reversed', 'wrongDestination'] as const)('refuses source %s before any payout', async key => {
    const s = simulation(); s.state[key] = true; expect(await s.run()).toMatchObject({ review: 1 });
    expect(s.state.createCalls).toHaveLength(0);
  });
  it.each(['owner', 'schedule', 'net'])('refuses wrong %s rather than consuming another balance contribution', async key => {
    const s = simulation(); if (key === 'owner') s.state.ownerMatches = false;
    if (key === 'schedule') s.state.mode = 'daily'; if (key === 'net') s.state.net = 9999;
    expect(await s.run()).toMatchObject({ review: 1 }); expect(s.state.createCalls).toHaveLength(0);
  });
  it('closed SQL admission performs no provider write', async () => {
    const s = simulation(); s.state.admitted = false; expect(await s.run()).toMatchObject({ deferred: 1 });
    expect(s.state.createCalls).toHaveLength(0);
  });
  it('a competing lease performs no provider write', async () => {
    const s = simulation(); s.state.claimed = false; expect(await s.run()).toMatchObject({ examined: 0 });
    expect(s.state.createCalls).toHaveLength(0);
  });
  it('recovers response loss without a second create, even after twenty hours', async () => {
    const s = simulation(); s.state.lostResponse = true; expect(await s.run()).toMatchObject({ errors: 1 });
    expect(await s.run(NOW + 21 * 3600000)).toMatchObject({ checked: 1 }); expect(s.state.createCalls).toHaveLength(1);
  });
  it('recovers persistence failure without a second create', async () => {
    const s = simulation(); s.state.persistenceFailure = true; await s.run();
    s.state.persistenceFailure = false; await s.run(); expect(s.state.createCalls).toHaveLength(1);
  });
  it('ambiguous expired create without object requires review, not a new idempotency key', async () => {
    const s = simulation(); s.state.work.firstPostAt = new Date(NOW - 21 * 3600000).toISOString();
    expect(await s.run()).toMatchObject({ review: 1 }); expect(s.state.createCalls).toHaveLength(0);
    expect(s.lastReport()).toMatchObject({ p_code: 'AMBIGUOUS_CREATE_EXPIRED' });
  });
  it('incomplete pagination refuses absence and creation', async () => {
    const s = simulation(); s.state.saturated = true; expect(await s.run()).toMatchObject({ review: 1 });
    expect(s.state.createCalls).toHaveLength(0);
  });
  it('duplicate matching payouts require review', async () => {
    const s = simulation(); s.state.payouts = [s.payout(), { ...s.payout(), id: 'po_other' }];
    expect(await s.run()).toMatchObject({ review: 1 }); expect(s.state.createCalls).toHaveLength(0);
  });
  it('known failed payout does not retry while returned funds are pending', async () => {
    const s = simulation(); s.state.currentPayout = s.payout('failed'); s.state.work.payoutId = s.state.currentPayout.id;
    s.state.returnAvailable = false; expect(await s.run()).toMatchObject({ deferred: 1 });
    expect(s.state.createCalls).toHaveLength(0); expect(s.state.work.state).toBe('FAILED');
  });
  it('certain failure and returned funds use a new attempt, never a second client charge', async () => {
    const s = simulation(); s.state.currentPayout = s.payout('failed'); s.state.work.payoutId = s.state.currentPayout.id;
    expect(await s.run()).toMatchObject({ checked: 1 }); expect(s.state.createCalls).toHaveLength(1);
    expect(s.state.createCalls[0].options.idempotencyKey).toBe(`connect_payout_${uuid(1)}_1`);
  });
  it('stale paid event rereads current failed provider object', async () => {
    const s = simulation(); s.state.currentPayout = s.payout('failed');
    await reconcileStandardPayoutEvent(s.db, s.stripe, s.state.work.accountId, s.state.currentPayout.id);
    expect(s.state.work.state).toBe('FAILED'); expect(s.state.createCalls).toHaveLength(0);
  });
});
