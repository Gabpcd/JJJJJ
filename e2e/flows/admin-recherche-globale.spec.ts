/**
 * Lot 20 — Recherche globale admin unifiée (une seule barre serveur).
 *
 * Prouve l'exigence de la feuille de route Lots 19-21 : la recherche unique
 * (⌘K, RPC fn_admin_recherche_globale) retrouve un soignant, un établissement
 * ET une mission — plus de double barre « serveur / locale ».
 *
 * Pattern Jolene :
 * - adminClient() (service_role, PAS d'auth.uid) → la RPC est gatée : renvoie
 *   des buckets vides (est_admin() = false).
 * - userClient(admin) → auth.uid ADMIN_PLATEFORME → résultats réels.
 * Skippé proprement si l'env (service_role / compte admin) n'est pas fourni.
 */

import { test, expect } from '@playwright/test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';

const TEST_REQS =
  !!process.env.SUPABASE_SERVICE_ROLE_KEY &&
  !!(process.env.SUPABASE_URL || process.env.PLAYWRIGHT_SUPABASE_URL);

test.describe('Lot 20 — recherche globale admin unifiée', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY + SUPABASE_URL requis');
  });

  // ── Sécurité : sans auth admin, aucun résultat ne fuit ──
  test('sans auth admin, la recherche ne retourne rien', async () => {
    const { data } = await adminClient().rpc('fn_admin_recherche_globale' as any, { p_query: 'playwright' });
    expect((data as any)?.utilisateurs).toEqual([]);
    expect((data as any)?.missions).toEqual([]);
    expect((data as any)?.factures).toEqual([]);
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
      test.skip(!admin, 'Compte admin e2e (admin@jolene.app) indisponible');
    });

    test('trouve un soignant', async () => {
      const id = await userIdByEmail('playwright-soignant@jolene.app');
      test.skip(!id, 'Compte soignant test absent — seed requis');
      const { data } = await admin!.rpc('fn_admin_recherche_globale' as any, { p_query: 'playwright-soignant' });
      const u = (((data as any)?.utilisateurs ?? []) as any[]);
      expect(u.some((x) => x.type === 'soignant')).toBe(true);
    });

    test('trouve un établissement', async () => {
      const id = await userIdByEmail('playwright-etab@jolene.app');
      test.skip(!id, 'Compte établissement test absent — seed requis');
      const { data } = await admin!.rpc('fn_admin_recherche_globale' as any, { p_query: 'playwright-etab' });
      const u = (((data as any)?.utilisateurs ?? []) as any[]);
      expect(u.some((x) => x.type === 'etablissement')).toBe(true);
    });

    test('trouve une mission (par préfixe d\'identifiant)', async () => {
      const { data: missions } = await adminClient().from('missions').select('id').order('cree_le', { ascending: false }).limit(1);
      test.skip(!missions || (missions as any[]).length === 0, 'Aucune mission en base');
      const mid = (missions as any[])[0].id as string;
      const { data } = await admin!.rpc('fn_admin_recherche_globale' as any, { p_query: mid.slice(0, 8) });
      const m = (((data as any)?.missions ?? []) as any[]);
      expect(m.some((x) => x.id === mid)).toBe(true);
    });
  });
});
