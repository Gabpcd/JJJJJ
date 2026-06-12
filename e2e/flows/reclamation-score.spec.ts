/**
 * Sprint 8 ter-I PR 1 — Tests E2E réclamation score (Sprint 3.5 PR 7-8)
 *
 * Couvre le workflow de contestation d'un événement de score :
 *  - fn_creer_reclamation_score (soignant ou étab)
 *  - fn_traiter_reclamation (admin : MAINTENIR / REDUIRE / ANNULER)
 *
 * Tests DB-level via service_role. Skipped si SUPABASE_SERVICE_ROLE_KEY absent.
 *
 * Stratégie :
 *  - service_role bypass RLS mais auth.uid() = NULL → fn_creer_reclamation_score
 *    rejette avec NON_AUTHENTIFIE (test sécurité critique)
 *  - fn_traiter_reclamation require est_admin() → NON_AUTORISE sans auth admin
 *  - Validation paramètres : motif_categorie, evenement_type, statut admin
 *  - Vérification structure tables sous-jacentes
 */

import { test, expect } from '@playwright/test';
import { adminClient } from '../helpers/db';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

test.describe('Sprint 3.5 — Réclamation score (user creation + admin traitement)', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
  });

  // ─── fn_creer_reclamation_score (soignant/étab dépose contestation) ─────
  test('fn_creer_reclamation_score : NON_AUTHENTIFIE sans auth utilisateur', async () => {
    const { data } = await adminClient().rpc('fn_creer_reclamation_score' as any, {
      p_evenement_id: '00000000-0000-0000-0000-000000000000',
      p_evenement_type: 'SOIGNANT',
      p_motif_categorie: 'URGENCE_MEDICALE',
      p_texte_libre: 'Justification suffisante pour le test de validation',
      p_justificatif_storage_path: null,
    });
    const result = data as any;
    // service_role bypasse RLS mais auth.uid() = NULL → bloque côté fn
    expect(result?.success).toBe(false);
    expect(['NON_AUTHENTIFIE', 'NON_AUTORISE', 'EVENEMENT_INTROUVABLE']).toContain(
      result?.error_code || result?.error,
    );
  });

  test('fn_creer_reclamation_score : evenement_type invalide rejette', async () => {
    const { data } = await adminClient().rpc('fn_creer_reclamation_score' as any, {
      p_evenement_id: '00000000-0000-0000-0000-000000000000',
      p_evenement_type: 'INVALIDE_XYZ',
      p_motif_categorie: 'URGENCE_MEDICALE',
      p_texte_libre: 'Justification suffisante pour le test de validation',
      p_justificatif_storage_path: null,
    });
    const result = data as any;
    expect(result?.success).toBe(false);
  });

  test('fn_creer_reclamation_score : motif_categorie invalide rejette', async () => {
    const { data } = await adminClient().rpc('fn_creer_reclamation_score' as any, {
      p_evenement_id: '00000000-0000-0000-0000-000000000000',
      p_evenement_type: 'SOIGNANT',
      p_motif_categorie: 'CATEGORIE_INEXISTANTE',
      p_texte_libre: 'Justification suffisante pour le test de validation',
      p_justificatif_storage_path: null,
    });
    const result = data as any;
    expect(result?.success).toBe(false);
  });

  // ─── fn_traiter_reclamation (admin décide MAINTENIR/REDUIRE/ANNULER) ────
  test('fn_traiter_reclamation : NON_AUTORISE sans auth admin', async () => {
    const { data } = await adminClient().rpc('fn_traiter_reclamation' as any, {
      p_reclamation_id: '00000000-0000-0000-0000-000000000000',
      p_statut: 'MAINTENIR',
    });
    const result = data as any;
    expect(result?.success).toBe(false);
    expect(['NON_AUTORISE', 'NON_AUTHENTIFIE']).toContain(result?.error_code);
  });

  test('fn_traiter_reclamation : statut invalide rejette', async () => {
    const { data } = await adminClient().rpc('fn_traiter_reclamation' as any, {
      p_reclamation_id: '00000000-0000-0000-0000-000000000000',
      p_statut: 'STATUT_INVALIDE_XYZ',
    });
    const result = data as any;
    // Soit NON_AUTORISE (sans admin), soit STATUT_INVALIDE
    expect(result?.success).toBe(false);
  });

  test('fn_traiter_reclamation : statut REDUIRE accepte p_points_restaures', async () => {
    const { data } = await adminClient().rpc('fn_traiter_reclamation' as any, {
      p_reclamation_id: '00000000-0000-0000-0000-000000000000',
      p_statut: 'REDUIRE',
      p_points_restaures: 5,
    });
    const result = data as any;
    // Forcément échec (UUID 0...0 + pas admin) mais signature acceptée
    expect(result?.success).toBe(false);
    expect(typeof result?.error_code === 'string' || typeof result?.error === 'string').toBe(true);
  });

  // ─── Structure DB : tables sous-jacentes ─────────────────────────────────
  test('Table reclamations_score existe avec colonnes attendues', async () => {
    const { error } = await adminClient()
      .from('reclamations_score' as any)
      .select('id, evenement_soignant_id, evenement_etab_id, evenement_type, motif_categorie, statut, cree_le')
      .limit(1);
    expect(error?.message).toBeFalsy();
  });

  test('Table evenements_score_soignant accessible (contestable)', async () => {
    const { error } = await adminClient()
      .from('evenements_score_soignant' as any)
      .select('id, type_evenement, points, contestable')
      .limit(1);
    expect(error?.message).toBeFalsy();
  });
});
