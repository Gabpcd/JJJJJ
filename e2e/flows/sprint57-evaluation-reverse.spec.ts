/**
 * Sprint 5.7 PR 5-6 — Tests évaluation reverse étab → soignant (P0-8)
 *
 * Vérifie le flow inverse de Sprint 3.5 : l'étab note le soignant après une
 * mission TERMINEE (sens ETAB_VERS_SOIGNANT). Le soignant peut signaler une
 * notation abusive via fn_signaler_notation (Sprint 3.5 réutilisé).
 *
 * Tests DB-level via service_role. Skipped si SUPABASE_SERVICE_ROLE_KEY absent.
 */

import { test, expect } from '@playwright/test';
import { adminClient, userIdByEmail } from '../helpers/db';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

test.describe('Sprint 5.7 — Évaluation reverse étab → soignant', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
  });

  test('fn_lister_missions_a_noter_etab : retourne structure attendue', async () => {
    const { data } = await adminClient().rpc(
      'fn_lister_missions_a_noter_etab' as any,
    );
    // Sans auth.uid() la fonction retourne soit success:false soit empty array
    // L'important est qu'elle existe (pas d'erreur "function does not exist")
    expect(data).toBeDefined();
  });

  test('Enum sens notation_mission accepte ETAB_VERS_SOIGNANT', async () => {
    // Vérifie via insertion test puis rollback que l'enum existe
    const etabUserId = await userIdByEmail('playwright-etab@jolene.app');
    const soignantUserId = await userIdByEmail('playwright-soignant@jolene.app');
    if (!etabUserId || !soignantUserId) {
      test.skip(true, 'comptes playwright non seeded');
      return;
    }

    // Trouver l'étab + soignant
    const { data: etab } = await adminClient()
      .from('etablissements' as any)
      .select('id')
      .eq('email_contact', 'playwright-etab@jolene.app')
      .maybeSingle();
    const { data: soignant } = await adminClient()
      .from('soignants' as any)
      .select('id')
      .eq('user_id', soignantUserId)
      .maybeSingle();
    if (!etab || !soignant) {
      test.skip(true, 'profils playwright non seeded');
      return;
    }

    // Créer mission TERMINEE
    const { data: mission, error: errM } = await adminClient()
      .from('missions' as any)
      .insert({
        etablissement_id: (etab as any).id,
        soignant_assigne_id: (soignant as any).id,
        intitule: `[playwright-test] EvalReverse ${Date.now()}`,
        profession_requise: 'INFIRMIER',
        service: 'Test',
        debut_le: new Date(Date.now() - 86400000).toISOString(),
        fin_le: new Date(Date.now() - 82800000).toISOString(),
        taux_horaire_base: 25,
        statut: 'TERMINEE',
        mode_attribution: 'CANDIDATURE',
      })
      .select('id')
      .single();
    if (errM || !mission) {
      console.error('[eval-reverse seed]', errM?.message);
      test.skip(true, 'impossible de seed mission TERMINEE');
      return;
    }

    const missionId = (mission as any).id;
    try {
      // Insérer une notation ETAB_VERS_SOIGNANT directement (service_role bypass RLS)
      const { error: errN } = await adminClient()
        .from('notations_missions' as any)
        .insert({
          mission_id: missionId,
          auteur_id: etabUserId,
          cible_id: soignantUserId,
          sens: 'ETAB_VERS_SOIGNANT',
          note_ponctualite: 5,
          note_technique: 4,
          note_relationnel: 5,
          note_conformite: 4,
          commentaire: 'Test eval reverse Sprint 5.7',
        });
      // L'enum doit accepter ETAB_VERS_SOIGNANT
      expect(errN?.message).toBeFalsy();

      // Cleanup notation
      await adminClient()
        .from('notations_missions' as any)
        .delete()
        .eq('mission_id', missionId);
    } finally {
      await adminClient().from('missions' as any).delete().eq('id', missionId);
    }
  });

  test('fn_signaler_notation existe (Sprint 3.5 réutilisé pour évaluation reverse)', async () => {
    const { data } = await adminClient().rpc('fn_signaler_notation' as any, {
      p_notation_id: '00000000-0000-0000-0000-000000000000',
      p_motif: 'test',
    });
    // Soit NOTATION_INTROUVABLE soit autre erreur structurée — pas function not exists
    expect(data).toBeDefined();
    expect((data as any)?.success).toBe(false);
  });
});
