/**
 * Sprint 7 PR 9 — Tests playwright DB-level Sprint 7
 *
 * Couvre les RPCs Sprint 7 :
 * - fn_audit_rls_strict (PR 3) : admin requis
 * - fn_admin_force_supprimer_compte (PR 7) : admin requis si existe
 * - Suite Sprint 5/6 RPCs déjà testées
 *
 * Skip auto si SUPABASE_SERVICE_ROLE_KEY absent.
 */

import { test, expect } from '@playwright/test';
import { adminClient } from '../helpers/db';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

test.describe('Sprint 7 — RPCs sécurité + structure', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
  });

  // ─── PR 3 — Audit RLS ─────────────────────────────────────────────
  test('fn_audit_rls_strict : Admin requis (service_role bypasse mais auth.uid()=NULL)', async () => {
    const { data } = await adminClient().rpc('fn_audit_rls_strict' as any);
    const result = data as any;
    // En service_role sans auth.uid() : v_uid IS NULL → bloque
    expect(result?.success).toBe(false);
    expect(result?.error).toContain('Admin');
  });

  // ─── Suite Sprint 5/6 (revérification structure)  ──────────────────
  test('Tables existent : evenements_score_soignant + evenements_score_etab', async () => {
    const { error: e1 } = await adminClient()
      .from('evenements_score_soignant' as any)
      .select('id, type_evenement, points, contestable')
      .limit(1);
    expect(e1?.message).toBeFalsy();

    const { error: e2 } = await adminClient()
      .from('evenements_score_etab' as any)
      .select('id, type_evenement, points, contestable')
      .limit(1);
    expect(e2?.message).toBeFalsy();
  });

  test('Table otps_telephone existe (Sprint 6 PR 9)', async () => {
    const { error } = await adminClient()
      .from('otps_telephone' as any)
      .select('id, user_id, telephone, tentatives, utilise')
      .limit(1);
    expect(error?.message).toBeFalsy();
  });

  test('Tables invitations_etablissement + membres_etablissement existent (Sprint 5.7 PR 1)', async () => {
    const { error: e1 } = await adminClient()
      .from('invitations_etablissement' as any)
      .select('id, role_propose, statut, token')
      .limit(1);
    expect(e1?.message).toBeFalsy();

    const { error: e2 } = await adminClient()
      .from('membres_etablissement' as any)
      .select('id, role, actif, etablissement_id')
      .limit(1);
    expect(e2?.message).toBeFalsy();
  });

  // ─── PR 7 — RGPD tools (RPC optionnelle) ────────────────────────────
  test('fn_admin_force_supprimer_compte : structure renvoie erreur si absente OU NON_AUTHENTIFIE', async () => {
    const { data, error } = await adminClient().rpc(
      'fn_admin_force_supprimer_compte' as any,
      { p_email: 'test@example.invalid', p_motif: 'test sprint 7 placeholder min 30 chars audit' },
    );
    // Soit fonction absente (404 / undefined function), soit elle existe et renvoie NON_AUTORISE
    if (error) {
      expect(error.message).toMatch(/function|exist|not found/i);
    } else {
      expect((data as any)?.success).toBe(false);
    }
  });
});
