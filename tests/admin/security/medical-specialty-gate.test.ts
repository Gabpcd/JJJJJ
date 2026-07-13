import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713222000_durcir_verifications_preproduction.sql'),
  'utf8',
);

describe('spécialité médicale vérifiée', () => {
  it('sépare la spécialité déclarée de celle utilisée par le matching', () => {
    expect(migration).toContain('specialite_medicale_declaree');
    expect(migration).toMatch(/REVOKE UPDATE \(specialite_medicale, specialite_code, specialite_source\)/i);
    expect(migration).toMatch(/specialite_medicale = NULL[\s\S]*specialite_verifiee, false\) = false/i);
  });

  it('rend les champs RPPS immuables pour le soignant', () => {
    expect(migration).toMatch(/fn_protect_specialite_medicale_verifiee[\s\S]*NEW\.specialite_medicale := OLD\.specialite_medicale/i);
    expect(migration).toMatch(/NEW\.specialite_verifiee := OLD\.specialite_verifiee/i);
  });
});
