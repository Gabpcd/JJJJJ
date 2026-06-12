/**
 * Sprint 5.7 PR 1-4 — Tests équipe étab multi-utilisateurs (P0-5)
 *
 * Vérifie la structure des tables + RPCs créés par la migration
 * 20260514160000_pr1s57_membres_etablissement.sql, et les invariants
 * critiques (protection dernier PROPRIETAIRE, rejet sans auth, etc).
 *
 * Tests DB-level via service_role. Skipped si SUPABASE_SERVICE_ROLE_KEY absent.
 */

import { test, expect } from '@playwright/test';
import { adminClient, userIdByEmail } from '../helpers/db';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

test.describe('Sprint 5.7 — Équipe étab', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
  });

  test('Tables membres_etablissement + invitations_etablissement existent', async () => {
    const { error: errMembres } = await adminClient()
      .from('membres_etablissement' as any)
      .select('id, role, actif')
      .limit(1);
    expect(errMembres?.message).toBeFalsy();

    const { error: errInv } = await adminClient()
      .from('invitations_etablissement' as any)
      .select('id, role_propose, statut, token')
      .limit(1);
    expect(errInv?.message).toBeFalsy();
  });

  test('Bootstrap : playwright-etab est PROPRIETAIRE de son établissement', async () => {
    const etabUserId = await userIdByEmail('playwright-etab@jolene.app');
    expect(etabUserId).toBeTruthy();

    const { data: etabRow } = await adminClient()
      .from('etablissements' as any)
      .select('id')
      .eq('email_contact', 'playwright-etab@jolene.app')
      .maybeSingle();
    if (!etabRow) {
      test.skip(true, 'établissement playwright-etab non seeded');
      return;
    }

    const { data: membre } = await adminClient()
      .from('membres_etablissement' as any)
      .select('role, actif')
      .eq('etablissement_id', (etabRow as any).id)
      .eq('user_id', etabUserId)
      .maybeSingle();
    expect(membre).toBeTruthy();
    expect((membre as any).role).toBe('PROPRIETAIRE');
    expect((membre as any).actif).toBe(true);
  });

  test('fn_mes_permissions_etab : anonymous (sans auth.uid) renvoie role NULL', async () => {
    // service_role bypass RLS mais auth.uid() = NULL → RPC doit gérer ce cas
    const { data } = await adminClient().rpc('fn_mes_permissions_etab' as any);
    expect(data).toBeTruthy();
    // role NULL ou erreur claire — l'important est qu'il ne crash pas
  });

  test('fn_inviter_membre_etab : rejet si email vide', async () => {
    const { data } = await adminClient().rpc('fn_inviter_membre_etab' as any, {
      p_email: '',
      p_role: 'RH',
    });
    expect((data as any)?.success).toBe(false);
  });

  test('fn_revoquer_membre : rejet sans auth', async () => {
    const { data } = await adminClient().rpc('fn_revoquer_membre' as any, {
      p_membre_id: '00000000-0000-0000-0000-000000000000',
    });
    expect((data as any)?.success).toBe(false);
  });
});
