import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260903194000_preserver_heures_reelles_pointage.sql',
  'utf8',
);

const scanner = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.fn_scanner_code_pointage'),
  migration.indexOf('CREATE OR REPLACE FUNCTION public.fn_declarer_fin_retroactive'),
);
const retroactive = migration.slice(
  migration.indexOf('CREATE OR REPLACE FUNCTION public.fn_declarer_fin_retroactive'),
  migration.indexOf('REVOKE ALL ON FUNCTION public.fn_scanner_code_pointage'),
);

describe('intégrité financière du pointage', () => {
  it('enregistre les ouvertures et fermetures aux heures réellement scannées', () => {
    expect(scanner).toContain("v_now timestamptz := now()");
    expect(scanner).toContain('v_now,\n      NULL');
    expect(scanner).toContain('SET fin = v_now');
    expect(scanner).toContain('pointage_arrivee_le');
    expect(scanner).toContain('v_mission.id, auth.uid(), v_now');
    expect(scanner).toContain('pointage_depart_le = v_now');
    expect(scanner).not.toContain("v_creneau_debut + INTERVAL '15 minutes'");
  });

  it('isole l’arrondi au quart d’heure dans la seule piste d’audit', () => {
    expect(scanner).toContain('v_arrondi_audit := fn_arrondir_quart_heure(v_now)');
    expect(scanner).toContain('v_now, v_arrondi_audit, v_creneau_id');
    expect(scanner).toContain("'horodatage_effectif', v_now");
    expect(scanner).toContain("'horodatage_arrondi', v_arrondi_audit");
  });

  it('clôture rétroactivement à l’heure déclarée et resynchronise la présence', () => {
    expect(retroactive).toContain('SET fin = p_heure_fin');
    expect(retroactive).toContain('pointage_depart_le = p_heure_fin');
    expect(retroactive).toContain('heures_reelles = (');
    expect(retroactive).toContain("'fin_declaree', p_heure_fin");
    expect(retroactive).not.toContain("v_creneau_debut + INTERVAL '15 minutes'");
  });

  it('maintient les droits et l’inventaire SECURITY DEFINER', () => {
    expect(migration).toContain('TO authenticated, service_role');
    expect(migration).toContain('private.security_definer_inventory');
    expect(migration).toContain('pg_catalog.md5(p.prosrc)');
    expect(migration).toContain('$assert_pointage_exact_security$');
  });
});
