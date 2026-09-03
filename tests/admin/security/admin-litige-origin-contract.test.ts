import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260903212000_reparer_creation_litige_admin.sql',
  'utf8',
);

describe('création de litige par le back-office', () => {
  it('respecte la contrainte fermée et conserve l’acteur admin dans l’audit', () => {
    expect(migration).toContain("v_mission.etablissement_id, 'SYSTEME'");
    expect(migration).toContain("v_user_id, 'ADMIN', 'LITIGE_FORCE_CREATION'");
    expect(migration).toContain("'origine_litige', 'SYSTEME_ADMIN'");
    expect(migration).not.toContain('DROP CONSTRAINT');
  });

  it('reste inaccessible à un compte non-admin', () => {
    expect(migration).toContain('NOT public.est_admin()');
    expect(migration).toContain('REVOKE ALL ON FUNCTION');
  });
});
