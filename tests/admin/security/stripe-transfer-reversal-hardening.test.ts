import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const webhook = readFileSync(
  'supabase/functions/_shared/stripe-webhook-handler.ts',
  'utf8',
);
const migration = readFileSync(
  'supabase/migrations/20260714056000_tracer_reversal_partiel_transfer.sql',
  'utf8',
);

const start = webhook.indexOf(
  'verified.source === "PLATFORM" && event.type === "transfer.reversed"',
);
const end = webhook.indexOf('// ── transfer.created', start);
const reversal = webhook.slice(start, end);

describe('Stripe transfer.reversed — total et partiel exacts', () => {
  it('relit le Transfer courant et valide toute son identité métier', () => {
    expect(start).toBeGreaterThan(0);
    expect(reversal).toContain('stripe.transfers.retrieve(eventTransfer.id)');
    expect(reversal).toContain('transfer.amount !== expectedAmount');
    expect(reversal).toContain('transfer.currency !== "eur"');
    expect(reversal).toContain('transfer.metadata?.mission_id !== row.mission_id');
    expect(reversal).toContain('transfer.metadata?.soignant_id !== row.soignant_id');
    expect(reversal).toContain('transfer.transfer_group !== `mission_${row.mission_id}`');
    expect(reversal).toContain('destinationId !== onboarding?.stripe_account_id');
    expect(reversal).toContain('sourceChargeId !== row.stripe_charge_id');
    expect(reversal).toContain('TRANSFER_REVERSAL_IDENTITE_INCOHERENTE');
  });

  it('pagine et somme les objets TransferReversal au montant Stripe courant', () => {
    expect(reversal).toContain('stripe.transfers.listReversals(transfer.id');
    expect(reversal).toContain('starting_after: reversalStartingAfter');
    expect(reversal).toContain('stripeObjectId(reversal.transfer) !== transfer.id');
    expect(reversal).toContain('reversalSum += reversal.amount');
    expect(reversal).toContain('reversalSum !== transfer.amount_reversed');
  });

  it('ne pose REMBOURSE que pour un reversal intégral', () => {
    const total = reversal.indexOf(
      'const reversalTotal = transfer.amount_reversed === transfer.amount',
    );
    const refunded = reversal.indexOf('statut: "REMBOURSE"', total);
    const partial = reversal.indexOf('stripe_reversal_statut: reversalTotal ? "TOTAL" : "PARTIEL"');

    expect(total).toBeGreaterThan(0);
    expect(refunded).toBeGreaterThan(total);
    expect(partial).toBeGreaterThan(refunded);
    expect(reversal).toContain('Reversal partiel Stripe: ${transfer.amount_reversed}/${transfer.amount}');
    expect(reversal).toContain('? ["TRANSFERE", "PAYE", "REMBOURSE"]');
    expect(reversal).toContain(': ["TRANSFERE", "PAYE"]');
  });

  it('persiste le cumul et son statut avec contraintes de schéma', () => {
    expect(migration).toContain('stripe_amount_reversed_cents integer NOT NULL DEFAULT 0');
    expect(migration).toContain("stripe_reversal_statut IN ('AUCUN', 'PARTIEL', 'TOTAL')");
    expect(reversal).toContain('stripe_amount_reversed_cents: transfer.amount_reversed');
    expect(reversal).toContain('.lte("stripe_amount_reversed_cents", transfer.amount_reversed)');
    expect(reversal).toContain('writeRequiredFinancialAudit(supabaseAdmin');
  });
});
