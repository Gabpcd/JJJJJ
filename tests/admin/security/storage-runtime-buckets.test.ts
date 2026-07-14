import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260714005200_declarer_buckets_prives_runtime.sql'),
  'utf8',
);

describe('buckets runtime versionnés', () => {
  it('déclare les deux buckets privés avec des limites explicites', () => {
    expect(migration).toContain("'contrats-signes'");
    expect(migration).toContain("'justificatifs'");
    expect(migration.match(/INSERT INTO storage\.buckets/g)).toHaveLength(2);
    expect(migration.match(/false,\s*\n\s*(?:5242880|10485760)/g)).toHaveLength(2);
  });

  it('ne réintroduit pas la fausse politique deny qui ouvrait les autres buckets', () => {
    expect(migration).toContain('DROP POLICY IF EXISTS pol_contrats_signes_insert_deny');
    expect(migration).not.toMatch(/CREATE POLICY pol_contrats_signes_insert_deny/i);
    expect(migration).not.toContain("bucket_id <> 'contrats-signes'");
  });

  it('limite la lecture aux participants du contrat ou à un admin validé', () => {
    expect(migration).toContain('public.est_admin()');
    expect(migration).toContain('cm.soignant_id = (SELECT auth.uid())');
    expect(migration).toContain('cm.etablissement_id = public.mon_etablissement_id()');
  });
});
