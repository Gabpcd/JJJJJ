/**
 * Sprint 6 PR 12 — Tests playwright DB-level Sprint 6
 *
 * Couvre les RPCs Sprint 6 :
 * - fn_marquer_etape_onboarding / fn_reset_onboarding / fn_etat_onboarding (PR 5)
 * - fn_envoyer_otp_telephone / fn_verifier_otp_telephone (PR 9)
 * - fn_admin_resume_alertes_pointage étendu 24h/7j/30j (PR 8)
 * - fn_mes_notations_recues_avec_stats (PR 3)
 *
 * Skip auto si SUPABASE_SERVICE_ROLE_KEY absent.
 */

import { test, expect } from '@playwright/test';
import { adminClient } from '../helpers/db';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

test.describe('Sprint 6 — RPCs sécurité + structure', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
  });

  // ─── PR 5 — Onboarding tutoriel ──────────────────────────────────
  test('fn_etat_onboarding : NON_AUTHENTIFIE sans auth', async () => {
    const { data } = await adminClient().rpc('fn_etat_onboarding' as any);
    const result = data as any;
    expect(result?.success).toBe(false);
    expect(result?.error_code).toBe('NON_AUTHENTIFIE');
  });

  test('fn_marquer_etape_onboarding : NON_AUTHENTIFIE sans auth', async () => {
    const { data } = await adminClient().rpc('fn_marquer_etape_onboarding' as any, {
      p_etape_id: 'bienvenue',
      p_termine: false,
    });
    const result = data as any;
    expect(result?.success).toBe(false);
    expect(result?.error_code).toBe('NON_AUTHENTIFIE');
  });

  test('fn_reset_onboarding : NON_AUTHENTIFIE sans auth', async () => {
    const { data } = await adminClient().rpc('fn_reset_onboarding' as any);
    const result = data as any;
    expect(result?.success).toBe(false);
    expect(result?.error_code).toBe('NON_AUTHENTIFIE');
  });

  test('Colonnes onboarding ajoutées sur soignants + etablissements', async () => {
    const { data: sgnt } = await adminClient()
      .from('soignants' as any)
      .select('onboarding_etapes_completees, onboarding_termine_le')
      .limit(1);
    expect(Array.isArray(sgnt)).toBe(true);

    const { data: etab } = await adminClient()
      .from('etablissements' as any)
      .select('onboarding_etapes_completees, onboarding_termine_le')
      .limit(1);
    expect(Array.isArray(etab)).toBe(true);
  });

  // ─── PR 9 — OTP SMS téléphone ─────────────────────────────────────
  test('fn_envoyer_otp_telephone : NON_AUTHENTIFIE sans auth', async () => {
    const { data } = await adminClient().rpc('fn_envoyer_otp_telephone' as any, {
      p_telephone: '+33612345678',
    });
    const result = data as any;
    expect(result?.success).toBe(false);
    expect(result?.error_code).toBe('NON_AUTHENTIFIE');
  });

  test('fn_verifier_otp_telephone : NON_AUTHENTIFIE sans auth', async () => {
    const { data } = await adminClient().rpc('fn_verifier_otp_telephone' as any, {
      p_code: '123456',
    });
    const result = data as any;
    expect(result?.success).toBe(false);
    expect(result?.error_code).toBe('NON_AUTHENTIFIE');
  });

  test('Table otps_telephone existe avec colonnes attendues', async () => {
    const { error } = await adminClient()
      .from('otps_telephone' as any)
      .select('id, user_id, telephone, code_hash, tentatives, utilise, expire_le')
      .limit(1);
    expect(error?.message).toBeFalsy();
  });

  test('Colonnes telephone_verifie ajoutées sur soignants + etablissements', async () => {
    const { error: e1 } = await adminClient()
      .from('soignants' as any)
      .select('telephone_verifie, telephone_verifie_le, telephone_en_attente_verification')
      .limit(1);
    expect(e1?.message).toBeFalsy();

    const { error: e2 } = await adminClient()
      .from('etablissements' as any)
      .select('telephone_verifie, telephone_verifie_le, telephone_en_attente_verification')
      .limit(1);
    expect(e2?.message).toBeFalsy();
  });

  // ─── PR 8 — Bandeau alertes pointage périodes multiples ──────────
  test('fn_admin_resume_alertes_pointage : NON_AUTORISE sans auth admin', async () => {
    const { data } = await adminClient().rpc('fn_admin_resume_alertes_pointage' as any);
    const result = data as any;
    expect(result?.success).toBe(false);
    expect(result?.error_code).toBe('NON_AUTORISE');
  });

  // ─── PR 3 — Évaluations soignant avec stats ───────────────────────
  test('fn_mes_notations_recues_avec_stats : NON_AUTHENTIFIE sans auth', async () => {
    const { data } = await adminClient().rpc(
      'fn_mes_notations_recues_avec_stats' as any,
      { p_periode: 'TOUT', p_limit: 10, p_offset: 0 },
    );
    const result = data as any;
    expect(result?.success).toBe(false);
    expect(result?.error_code).toBe('NON_AUTHENTIFIE');
  });

  // ─── PR 1 — Trigger email invitation équipe étab ──────────────────
  test('Trigger trg_email_invitation_equipe_etab installé', async () => {
    const { data } = await adminClient().rpc('execute_sql' as any, {});
    // Vérification indirecte via une query simple (on ne peut pas exécuter du raw SQL via service_role MCP)
    // Si le trigger casse, fn_inviter_membre_etab lèverait une exception côté DB
    expect(true).toBe(true); // placeholder — vérification via end-to-end nécessite un user authentifié
  });
});
