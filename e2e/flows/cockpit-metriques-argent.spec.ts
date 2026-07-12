/**
 * Lot 19 — Cockpit fondateur à source unique (métriques d'argent).
 *
 * Prouve les exigences de la passation MODE AUTONOME §3 :
 * - `fn_admin_metriques_argent` est la SOURCE UNIQUE : le KPI et la carte du
 *   cockpit lisent le même objet (garanti côté code) ; ici on prouve que la
 *   RPC est cohérente, gatée admin, et que ses dérivés ne divergent pas.
 * - Le compteur « établissements à valider » == le count RÉEL de la file de
 *   travail (fn_admin_lister_etablissements_a_verifier). C'est le fix du
 *   « KPI 10 vs file 6 ».
 * - Le second cockpit (fn_admin_cockpit_fondateur) lit ses montants headline
 *   depuis la même source → GMV / revenus strictement identiques.
 *
 * Pattern Jolene :
 * - adminClient() (service_role, PAS d'auth.uid) → doit être REFUSÉ (gate).
 * - userClient(admin) (auth.uid ADMIN_PLATEFORME) → accès réel.
 * Skippé proprement si l'environnement (service_role / publishable / compte
 * admin) n'est pas fourni.
 */

import { test, expect } from '@playwright/test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { adminClient, userClient } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';

const TEST_REQS =
  !!process.env.SUPABASE_SERVICE_ROLE_KEY &&
  !!(process.env.SUPABASE_URL || process.env.PLAYWRIGHT_SUPABASE_URL);

test.describe('Lot 19 — Cockpit métriques argent (source unique)', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY + SUPABASE_URL requis');
  });

  // ── Sécurité : la RPC est gatée admin (service_role sans auth.uid = refusé) ──
  test('fn_admin_metriques_argent : refus sans auth admin', async () => {
    const { data } = await adminClient().rpc('fn_admin_metriques_argent' as any);
    expect((data as any)?.error).toBeTruthy();
    // Aucune métrique d'argent ne fuit dans la réponse d'erreur.
    expect((data as any)?.commission).toBeUndefined();
    expect((data as any)?.gmv).toBeUndefined();
  });

  // ── Accès admin réel : structure, invariants, source unique du compteur ──────
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
      test.skip(!admin, 'Compte admin e2e (admin@jolene.app) indisponible — auth requise');
    });

    test('structure complète + invariants HT/TTC et réel/test', async () => {
      const { data, error } = await admin!.rpc('fn_admin_metriques_argent' as any);
      expect(error).toBeFalsy();
      const m = data as any;

      // 4 métriques présentes, chacune avec split réel/test.
      for (const bloc of ['commission', 'encaisse', 'facturable', 'gmv']) {
        expect(m[bloc], `bloc ${bloc}`).toBeDefined();
      }
      // Toutes les valeurs sont des nombres ≥ 0 (pas de NaN / null).
      const nums = [
        m.commission.total_reel, m.commission.total_test, m.commission.mois_reel, m.commission.tva_reel,
        m.encaisse.ht_reel, m.encaisse.ttc_reel, m.encaisse.ht_test,
        m.facturable.ht_reel, m.gmv.total_reel, m.gmv.total_test,
      ];
      for (const v of nums) {
        expect(typeof Number(v)).toBe('number');
        expect(Number.isFinite(Number(v))).toBe(true);
        expect(Number(v)).toBeGreaterThanOrEqual(0);
      }
      // Invariant définitionnel : Facturable == Commission totale (même source).
      expect(Number(m.facturable.ht_reel)).toBeCloseTo(Number(m.commission.total_reel), 2);
      // TTC ≥ HT (la TVA ne peut pas rendre l'encaissé TTC inférieur au HT).
      expect(Number(m.encaisse.ttc_reel)).toBeGreaterThanOrEqual(Number(m.encaisse.ht_reel));
      // Le compteur et le flag test sont bien typés.
      expect(typeof Number(m.etab_a_valider)).toBe('number');
      expect(typeof m.a_des_donnees_test).toBe('boolean');
    });

    test('etab_a_valider == count réel de la file de vérification (fix 10 vs 6)', async () => {
      const { data: metriques } = await admin!.rpc('fn_admin_metriques_argent' as any);
      const { data: file } = await admin!.rpc('fn_admin_lister_etablissements_a_verifier' as any, { p_limit: 500 });
      const nFile = ((file as any)?.etablissements ?? []).length;
      const nCompteur = Number((metriques as any)?.etab_a_valider);
      // La file est plafonnée à 500 (LEAST(p_limit,500)) ; le compteur ne l'est pas.
      // Sous 500 → égalité stricte (le fix « 10 vs 6 ») ; au plafond → le compteur couvre au moins la file.
      if (nFile < 500) {
        expect(nCompteur).toBe(nFile);
      } else {
        expect(nCompteur).toBeGreaterThanOrEqual(nFile);
      }
    });

    test('fn_admin_cockpit_fondateur lit la même source (GMV / revenus identiques)', async () => {
      const { data: argent } = await admin!.rpc('fn_admin_metriques_argent' as any);
      const { data: cockpit } = await admin!.rpc('fn_admin_cockpit_fondateur' as any);
      const a = argent as any;
      const c = cockpit as any;
      expect(Number(c.gmv_total)).toBeCloseTo(Number(a.gmv.total_reel), 2);
      expect(Number(c.revenue_total)).toBeCloseTo(Number(a.commission.total_reel), 2);
      expect(Number(c.revenue_mois)).toBeCloseTo(Number(a.commission.mois_reel), 2);
    });
  });
});
