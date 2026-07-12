/**
 * Lot 21 — Suspension d'un compte : motif OBLIGATOIRE, journalisé.
 *
 * Prouve la feuille de route Lot 21.3 : « Suspendre exige un motif et l'écrit
 * dans journaux_audit (INSERT réel vérifié) ».
 *
 * Découverte au passage : la contrainte journaux_audit_action_check ne listait
 * pas SUSPENSION_COMPTE → toute suspension échouait déjà en prod (corrigé dans
 * la migration de ce lot).
 *
 * Cleanup : le compte test suspendu est réactivé en finally (CI = workers=1,
 * exécution série → pas de course avec les autres specs).
 */

import { test, expect } from '@playwright/test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';

const TEST_REQS =
  !!process.env.SUPABASE_SERVICE_ROLE_KEY &&
  !!(process.env.SUPABASE_URL || process.env.PLAYWRIGHT_SUPABASE_URL);

test.describe('Lot 21 — suspension avec motif obligatoire', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY + SUPABASE_URL requis');
  });

  // ── Sécurité : service_role (pas d'auth.uid) → refusé ──
  test('sans auth admin, la RPC est refusée', async () => {
    const { data } = await adminClient().rpc('fn_admin_suspendre_utilisateur' as any, {
      p_table: 'soignants',
      p_id: '00000000-0000-0000-0000-000000000000',
      p_suspendre: true,
      p_motif: 'x',
    });
    expect((data as any)?.error).toBeTruthy();
    expect((data as any)?.success).toBeFalsy();
  });

  test.describe('accès admin', () => {
    let admin: SupabaseClient | null = null;

    test.beforeAll(async () => {
      try {
        admin = await userClient(TEST_ACCOUNTS.admin.email, TEST_ACCOUNTS.admin.password);
      } catch {
        admin = null;
      }
    });

    test.beforeEach(() => {
      test.skip(!admin, 'Compte admin e2e indisponible');
    });

    test('suspendre SANS motif est refusé', async () => {
      const id = await userIdByEmail('playwright-soignant@jolene.app');
      test.skip(!id, 'Compte soignant test absent');
      const { data } = await admin!.rpc('fn_admin_suspendre_utilisateur' as any, {
        p_table: 'soignants',
        p_id: id,
        p_suspendre: true,
        p_motif: null,
      });
      expect((data as any)?.error).toContain('Motif obligatoire');
      expect((data as any)?.success).toBeFalsy();
    });

    test('suspendre AVEC motif réussit et écrit le motif dans journaux_audit', async () => {
      const id = await userIdByEmail('playwright-soignant@jolene.app');
      test.skip(!id, 'Compte soignant test absent');
      const motif = `e2e-lot21-suspension-${(id as string).slice(0, 8)}`;
      try {
        const { data } = await admin!.rpc('fn_admin_suspendre_utilisateur' as any, {
          p_table: 'soignants',
          p_id: id,
          p_suspendre: true,
          p_motif: motif,
        });
        expect((data as any)?.success).toBe(true);

        // INSERT réel vérifié (lecture service_role, bypass RLS).
        const { data: audit } = await adminClient()
          .from('journaux_audit' as any)
          .select('action, details')
          .eq('id_ressource', id)
          .eq('action', 'SUSPENSION_COMPTE')
          .order('cree_le', { ascending: false })
          .limit(1);
        expect(Array.isArray(audit) && audit.length).toBeTruthy();
        expect(((audit as any[])[0].details as any)?.motif).toBe(motif);
      } finally {
        // Cleanup : réactive le compte test (réactivation ne requiert pas de motif).
        await admin!.rpc('fn_admin_suspendre_utilisateur' as any, {
          p_table: 'soignants',
          p_id: id,
          p_suspendre: false,
        });
      }
    });
  });
});
