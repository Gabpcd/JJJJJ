import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');

describe('régressions lancement — paiements critiques', () => {
  it('réutilise la Session Connect préparée depuis la fiche mission', () => {
    const detail = read('src/pages/DetailMission.tsx');
    const checkout = read('src/components/StripeEmbeddedCheckout.tsx');

    expect(detail).toContain('preparedClientSecret={connectClientSecret}');
    expect(checkout).toContain('preparedClientSecret?: string | null');
    expect(checkout).toContain('if (preparedClientSecret)');
    expect(checkout).toContain('setClientSecret(preparedClientSecret)');
    expect(checkout).toContain('if (preparedClientSecret) {');
  });

  it('ne recompte pas le miroir paiements_soignant des transfers Connect', () => {
    const migration = read(
      'supabase/migrations/20260801212950_dedupliquer_revenus_connect_soignant.sql',
    );

    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_mes_revenus_connect');
    expect(migration).toMatch(/FROM public\.paiements_soignant[\s\S]*stripe_transfer_id IS NULL/);
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.fn_mes_revenus_connect(date)');
    expect(migration).toContain('private.security_definer_inventory');
  });

  it('valide le transfer_group selon la portée mission ou facture', () => {
    const webhook = read('supabase/functions/_shared/stripe-webhook-handler.ts');
    const reversalStart = webhook.indexOf(
      'verified.source === "PLATFORM" && event.type === "transfer.reversed"',
    );
    const reversalEnd = webhook.indexOf('// ── transfer.created', reversalStart);
    const reversal = webhook.slice(reversalStart, reversalEnd);

    expect(reversal).toContain('facture_honoraire_id');
    expect(reversal).toContain('const missionTransferGroup = `mission_${row.mission_id}`');
    expect(reversal).toContain('const invoiceTransferGroup = row.facture_honoraire_id');
    expect(reversal).toContain('transfer.metadata?.payment_scope');
    expect(reversal).toContain('transfer.metadata?.facture_honoraires_id');
    expect(reversal).toContain('transfer.group_scope');
  });
});
