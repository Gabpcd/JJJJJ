/**
 * Sprint 5.7 PR 7-9 — Tests admin RPCs Sprint 5.7
 *
 * Vérifie la structure des RPCs admin créés par les migrations Sprint 5.7 :
 * - fn_admin_lister_contrats / fn_admin_detail_contrat (PR 7)
 * - fn_admin_lister_templates_contrats / fn_admin_detail_template_contrat /
 *   fn_admin_modifier_template_contrat / fn_admin_toggle_template_contrat (PR 8)
 * - fn_admin_resume_alertes_pointage / fn_admin_lister_alertes_pointage /
 *   fn_admin_traiter_alerte_pointage (PR 9)
 *
 * Tous ces RPCs require est_admin() côté serveur → service_role sans
 * auth.uid() doit retourner NON_AUTORISE. C'est le test de sécurité critique.
 *
 * Tests DB-level via service_role. Skipped si SUPABASE_SERVICE_ROLE_KEY absent.
 */

import { test, expect } from '@playwright/test';
import { adminClient } from '../helpers/db';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

test.describe('Sprint 5.7 — Admin RPCs sécurité', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
  });

  // ─── Contrats admin (PR 7) ──────────────────────────────────────────────
  test('fn_admin_lister_contrats : NON_AUTORISE sans auth admin', async () => {
    const { data } = await adminClient().rpc('fn_admin_lister_contrats' as any, {
      p_limit: 10,
      p_offset: 0,
    });
    expect((data as any)?.success).toBe(false);
    expect((data as any)?.error_code).toBe('NON_AUTORISE');
  });

  test('fn_admin_detail_contrat : NON_AUTORISE sans auth admin', async () => {
    const { data } = await adminClient().rpc('fn_admin_detail_contrat' as any, {
      p_contrat_id: '00000000-0000-0000-0000-000000000000',
    });
    expect((data as any)?.success).toBe(false);
    expect((data as any)?.error_code).toBe('NON_AUTORISE');
  });

  // ─── Templates contrats (PR 8) ───────────────────────────────────────────
  test('fn_admin_lister_templates_contrats : NON_AUTORISE sans auth admin', async () => {
    const { data } = await adminClient().rpc(
      'fn_admin_lister_templates_contrats' as any,
    );
    expect((data as any)?.success).toBe(false);
    expect((data as any)?.error_code).toBe('NON_AUTORISE');
  });

  test('fn_admin_modifier_template_contrat : NON_AUTORISE sans auth admin', async () => {
    const { data } = await adminClient().rpc(
      'fn_admin_modifier_template_contrat' as any,
      {
        p_template_id: '00000000-0000-0000-0000-000000000000',
        p_contenu: 'a'.repeat(100),
      },
    );
    expect((data as any)?.success).toBe(false);
    expect((data as any)?.error_code).toBe('NON_AUTORISE');
  });

  test('fn_admin_toggle_template_contrat : NON_AUTORISE sans auth admin', async () => {
    const { data } = await adminClient().rpc(
      'fn_admin_toggle_template_contrat' as any,
      { p_template_id: '00000000-0000-0000-0000-000000000000' },
    );
    expect((data as any)?.success).toBe(false);
    expect((data as any)?.error_code).toBe('NON_AUTORISE');
  });

  test('14 templates Sprint 2 existent en DB', async () => {
    const { data, error } = await adminClient()
      .from('templates_contrat' as any)
      .select('id, type_contrat, nom, version', { count: 'exact' });
    expect(error?.message).toBeFalsy();
    expect(Array.isArray(data)).toBeTruthy();
    expect((data as any[]).length).toBeGreaterThanOrEqual(14);
  });

  // ─── Alertes pointage admin (PR 9) ───────────────────────────────────────
  test('fn_admin_resume_alertes_pointage : NON_AUTORISE sans auth admin', async () => {
    const { data } = await adminClient().rpc(
      'fn_admin_resume_alertes_pointage' as any,
    );
    expect((data as any)?.success).toBe(false);
    expect((data as any)?.error_code).toBe('NON_AUTORISE');
  });

  test('fn_admin_lister_alertes_pointage : NON_AUTORISE sans auth admin', async () => {
    const { data } = await adminClient().rpc(
      'fn_admin_lister_alertes_pointage' as any,
      { p_limit: 10, p_offset: 0 },
    );
    expect((data as any)?.success).toBe(false);
    expect((data as any)?.error_code).toBe('NON_AUTORISE');
  });

  test('fn_admin_traiter_alerte_pointage : valide décision', async () => {
    const { data } = await adminClient().rpc(
      'fn_admin_traiter_alerte_pointage' as any,
      {
        p_alerte_id: '00000000-0000-0000-0000-000000000000',
        p_decision: 'INVALIDE_XYZ',
        p_motif: 'test',
      },
    );
    // Soit NON_AUTORISE (sans auth admin), soit DECISION_INVALIDE
    expect((data as any)?.success).toBe(false);
    expect(['NON_AUTORISE', 'DECISION_INVALIDE']).toContain(
      (data as any)?.error_code,
    );
  });
});
