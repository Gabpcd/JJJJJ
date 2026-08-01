import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260801145340_securiser_purge_missions_test_gelees.sql',
  'utf8',
);
const helper = readFileSync('e2e/helpers/cleanup-mission-test.ts', 'utf8');
const workflow = readFileSync('.github/workflows/playwright-e2e.yml', 'utf8');

describe('purge des missions E2E gelées', () => {
  it('reste réservée au service_role et aux données explicitement test', () => {
    expect(migration).toContain("COALESCE(auth.role(), '') <> 'service_role'");
    expect(migration).toContain("v_mission.intitule NOT LIKE '[pw-test:%'");
    expect(migration).toContain('v_mission.etablissement_est_test IS DISTINCT FROM true');
    expect(migration).toContain("soignant_col.attname = 'soignant_id'");
    expect(migration).toContain('s.est_compte_test IS DISTINCT FROM true');
    expect(migration).toMatch(
      /REVOKE ALL ON FUNCTION public\.fn_test_purge_mission\(uuid\)[\s\S]*FROM PUBLIC, anon, authenticated/,
    );
    expect(migration).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_test_purge_mission\(uuid\)[\s\S]*TO service_role/,
    );
  });

  it('utilise les overrides audités sans modifier les gardes produit', () => {
    expect(migration).toContain("'jolene.admin_override_gel', p_mission_id::text");
    expect(migration).toContain("'jolene.admin_correction_mission_id', p_mission_id::text");
    expect(migration).toContain("v_reason constant text := 'PURGE_E2E_MISSION_TECHNIQUE'");
    expect(migration).toContain("'[PURGE_E2E_DURABLE] %'");
    expect(migration).not.toContain('CREATE OR REPLACE FUNCTION public.fn_protect_creneaux_si_facture');
    expect(migration).not.toContain('DISABLE TRIGGER');
    expect(migration).not.toContain('session_replication_role');
  });

  it('purge les enfants indirects restrictifs avant les FK mission', () => {
    for (const table of [
      'stripe_refunds_queue',
      'chorus_submissions',
      'invoice_audit_log',
      'messages_litige',
      'stripe_transfers',
      'messages_chat',
      'partages_rib',
    ]) {
      expect(migration).toContain(`DELETE FROM public.${table}`);
    }
    expect(migration).toContain(
      "CASE WHEN rel.relname = 'mission_creneaux' THEN 1 ELSE 0 END",
    );
  });

  it('n’autorise la quarantaine que sur une PR vers main avant déploiement', () => {
    expect(helper).toContain("E2E_ALLOW_FROZEN_TEST_QUARANTINE === 'true'");
    expect(helper).toContain("GITHUB_EVENT_NAME === 'pull_request'");
    expect(helper).toContain("GITHUB_BASE_REF === 'main'");
    expect(helper).toContain("error.message.includes('[PURGE_E2E_DURABLE]')");
    expect(helper).toContain("statut: 'ANNULEE_PAR_ETABLISSEMENT'");
    expect(workflow).toContain("E2E_ALLOW_FROZEN_TEST_QUARANTINE: 'true'");
  });
});
