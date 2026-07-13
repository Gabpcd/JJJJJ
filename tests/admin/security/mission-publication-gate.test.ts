import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713222000_durcir_verifications_preproduction.sql'),
  'utf8',
);

describe('gate de publication des missions', () => {
  it('applique le gate unique aux INSERT directs via le trigger', () => {
    expect(migration).toMatch(
      /CREATE OR REPLACE FUNCTION public\.fn_trg_verifier_onboarding_etab\(\)[\s\S]*public\.fn_blocage_publication_etab\(NEW\.etablissement_id\)/i,
    );
  });

  it('ne conserve pas le bypass client par custom GUC', () => {
    const hardenedTrigger = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_trg_verifier_onboarding_etab\(\)[\s\S]*?\$\$;/i,
    )?.[0] || '';
    expect(hardenedTrigger).not.toContain("current_setting('app.internal_operation'");
    expect(hardenedTrigger).toContain("auth.role() = 'service_role'");
  });
});
