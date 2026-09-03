import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260903201000_securiser_cloture_anticipee_admin.sql',
), 'utf8');

describe('clôture de mission après arbitrage admin', () => {
  it('bloque tout segment ouvert et toute mission sans départ', () => {
    expect(migration).toContain("'error_code', 'SEGMENT_OUVERT'");
    expect(migration).toContain("'error_code', 'AUCUN_DEPART'");
    expect(migration.indexOf("'error_code', 'SEGMENT_OUVERT'"))
      .toBeLessThan(migration.indexOf("'error_code', 'AVANT_DERNIER_CRENEAU'"));
  });

  it('exige un admin et un litige actif avant le dernier créneau', () => {
    expect(migration).toContain('IF NOT v_est_admin THEN');
    expect(migration).toContain("'error_code', 'LITIGE_ACTIF_REQUIS'");
    expect(migration).toContain("'MEDIATION_EN_COURS'");
    expect(migration).toContain("'REVUE_ADMIN'");
  });

  it('journalise explicitement la clôture anticipée et conserve les droits bornés', () => {
    expect(migration).toContain("'CLOTURE_ANTICIPEE_APRES_ARBITRAGE'");
    expect(migration).toContain("'litige_id', v_litige_id");
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.fn_terminer_mission(uuid) FROM PUBLIC');
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.fn_terminer_mission(uuid) TO authenticated');
  });
});
