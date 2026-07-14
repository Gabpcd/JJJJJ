import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260714068000_securiser_suspension_comptes_auth.sql',
  'utf8',
);

describe('suspension admin opposable et réversible uniquement par provenance', () => {
  it('bloque aussi les access tokens déjà émis au niveau Data API', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_pre_request_compte_actif()');
    expect(migration).toContain("SET pgrst.db_pre_request = 'public.fn_pre_request_compte_actif'");
    expect(migration).toContain("NOTIFY pgrst, 'reload config'");
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_pre_request_compte_actif\(\)[\s\S]*TO anon, authenticated, service_role/,
    );
  });

  it('conserve le ban antérieur et suit la valeur CAS lors des suspensions répétées', () => {
    expect(migration).toContain('banned_until_avant timestamptz');
    expect(migration).toContain('banned_until_pose timestamptz NOT NULL');
    expect(migration).toContain('v_banned_until_courant IS NOT DISTINCT FROM v_pose_precedente');
    expect(migration).toMatch(
      /UPDATE public\.suspensions_auth_admin[\s\S]*SET banned_until_pose = v_banned_until_pose/,
    );
    expect(migration).toMatch(
      /UPDATE auth\.users u[\s\S]*SET banned_until = sa\.banned_until_avant[\s\S]*u\.banned_until IS NOT DISTINCT FROM sa\.banned_until_pose/,
    );
  });

  it('interdit de transformer un effacement RGPD en suspension réversible', () => {
    expect(migration).toContain('CREATE TABLE IF NOT EXISTS public.suspensions_profils_admin');
    expect(migration).toContain('Aucune suspension administrateur réversible pour ce compte');
    expect(migration).toContain('Compte supprimé au titre du RGPD');
    expect(migration).toContain("LIKE '%@supprime.jolene.app'");
    expect(migration).toContain("? 'COMPTE_SUPPRIME_RGPD'");
    expect(migration).toContain("j.action = 'RGPD_SUPPRESSION_COMPTE'");
    expect(migration).toContain("j.action = 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT'");
  });

  it('retire également Storage aux comptes suspendus', () => {
    for (const policy of [
      'pol_storage_jolene_insert',
      'pol_storage_jolene_select',
      'justificatifs_insert_auth',
      'justificatifs_select_auth',
      'pol_contrats_signes_select',
      'soignant_lit_ses_attestations',
      'soignant_supprime_ses_attestations',
      'soignant_upload_ses_attestations',
    ]) {
      expect(migration).toContain(`CREATE POLICY ${policy}`);
    }
    expect(migration.match(/public\.fn_compte_auth_actif\(\)/g)?.length).toBeGreaterThanOrEqual(14);
  });
});
