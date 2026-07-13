import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const edge = readFileSync(
  join(process.cwd(), 'supabase/functions/escrow-release/index.ts'),
  'utf8',
);

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713221941_verrou_release_escrow_debite.sql'),
  'utf8',
);

describe('release escrow — débit confirmé obligatoire', () => {
  it('exclut en base toute file dont l’escrow exact n’est pas DEBITE', () => {
    expect(migration).toMatch(/AND pe\.statut = 'DEBITE'/);
    expect(migration).toContain('fn_escrow_releases_a_traiter');
  });

  it('relit puis réserve atomiquement DEBITE avant de créer le payout', () => {
    expect(edge).toContain('.select("statut, stripe_payout_id")');
    expect(edge).toContain('escrowCourant.statut !== "DEBITE"');
    expect(edge).toMatch(/\.eq\("statut", "DEBITE"\)[\s\S]{0,500}stripe\.payouts\.create/);
    expect(edge.indexOf('.eq("statut", "DEBITE")')).toBeLessThan(edge.indexOf('stripe.payouts.create'));
  });

  it('ne transforme jamais INITIE en DEBITE dans le consumer de payout', () => {
    expect(edge).not.toMatch(/statut:\s*"DEBITE"[\s\S]{0,180}\.eq\("statut",\s*"INITIE"\)/);
  });

  it('réutilise une tentative ambiguë et versionne seulement après un payout terminal connu', () => {
    expect(edge).toContain('release_${rel.paiement_escrow_id}_after_${precedent.id}');
    expect(edge).toContain('["pending", "in_transit", "paid"]');
    expect(edge).toContain('if (releaseReservee)');
  });
});
