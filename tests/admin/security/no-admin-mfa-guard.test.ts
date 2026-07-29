import { describe, expect, it } from 'vitest';
import {
  findMigrationMfaViolations,
  findRuntimeMfaViolations,
} from '../../../scripts/check-no-admin-mfa.mjs';

describe('garde anti-réintroduction MFA administrateur', () => {
  it('détecte les exigences AAL2 réelles dans le runtime', () => {
    expect(
      findRuntimeMfaViolations(
        "const claims = await auth.getClaims(token); if (claims.aal !== 'aal2') throw new Error();",
      ),
    ).toContain('lecture de claims MFA');
    expect(
      findRuntimeMfaViolations(
        "await supabase.auth.mfa.enroll({ factorType: 'totp' });",
      ),
    ).toContain('API Supabase MFA');
    expect(
      findRuntimeMfaViolations(
        "await fetch('https://example.test/functions/v1/admin-2fa');",
      ),
    ).toContain('ancienne fonction admin-2fa');
  });

  it('détecte une future migration qui exige auth.jwt AAL2', () => {
    const violations = findMigrationMfaViolations(`
      CREATE FUNCTION public.est_admin_valide() RETURNS boolean AS $$
        SELECT COALESCE(auth.jwt() ->> 'aal', '') = 'aal2';
      $$ LANGUAGE sql;
    `);
    expect(violations).toContain('exigence auth.jwt/AAL2');
  });

  it('détecte la recréation admin-2fa ou l’écriture de facteurs Auth', () => {
    expect(
      findMigrationMfaViolations(`
        SELECT net.http_post(url := 'https://example.test/functions/v1/admin-2fa');
      `),
    ).toContain('réintroduction admin-2fa');
    expect(
      findMigrationMfaViolations(`
        INSERT INTO auth.mfa_factors(id, factor_type) VALUES ('x', 'totp');
      `),
    ).toContain('écriture dans les tables MFA Auth');
  });

  it('autorise commentaires, assertions d’absence, DROP et DELETE de purge', () => {
    expect(
      findMigrationMfaViolations(`
        -- auth.jwt() ->> 'aal' = 'aal2' est désormais interdit.
        DO $assert_no_admin_mfa$
        BEGIN
          IF pg_get_functiondef('public.est_admin()'::regprocedure)
             ILIKE '%auth.jwt()%aal%aal2%' THEN
            RAISE EXCEPTION 'AAL2 réintroduit';
          END IF;
        END
        $assert_no_admin_mfa$;
        DROP FUNCTION IF EXISTS public."admin-2fa"();
        DELETE FROM auth.mfa_factors WHERE user_id IS NOT NULL;
      `),
    ).toEqual([]);
  });
});
