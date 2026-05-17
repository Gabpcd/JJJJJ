/**
 * Sprint 14 PR 4 — Tests E2E réels flow complet matching swipe.
 *
 * Remplace les 6 stubs Sprint 13-D PR 3 par 5 tests fonctionnels qui valident
 * les triggers + workflows end-to-end :
 * - Trigger trg_award_badges_swipe : PREMIER_SWIPE, PREMIER_SUPER_LIKE, EXPLORATEUR
 * - Trigger trg_update_streak_on_swipe : streak_count + last_activity_date
 * - Trigger trg_award_badges_match : PREMIER_MATCH sur UPDATE candidature ASSIGNEE
 *
 * Pattern : seed direct via adminClient (bypass RPC pour tester les triggers DB),
 * vérification du state via getBadges() / getStreakInfo() / SELECT direct.
 *
 * Skips honnêtes :
 * - Streak quotidien J+1/J+2 : nécessite clock mock (pg_set_local) trop intrusif
 * - Flow complet UI multi-comptes étab-accepte : couvert backend par PREMIER_MATCH test
 */

import { test, expect } from '@playwright/test';
import { adminClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';
import {
  seedMissionMatching,
  seedSwipe,
  cleanupMatchingForSoignant,
  cleanupMissionsTest,
  getBadges,
  getStreakInfo,
} from '../helpers/seed-matching';

test.describe('Sprint 14 — Flow complet matching (réels)', () => {
  let soignantId: string | null = null;

  test.beforeAll(async () => {
    soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    test.skip(!soignantId, 'Compte test playwright-soignant introuvable');
  });

  test.afterEach(async () => {
    if (soignantId) {
      await cleanupMatchingForSoignant(soignantId);
    }
    await cleanupMissionsTest();
  });

  test('Trigger trg_award_badges_swipe : 1er swipe → badge PREMIER_SWIPE', async () => {
    const mission = await seedMissionMatching({ profession: 'INFIRMIER' });
    expect(mission).toBeTruthy();

    await seedSwipe(soignantId!, mission!.id, 'LIKE');

    const badges = await getBadges(soignantId!);
    expect(badges).toContain('PREMIER_SWIPE');
  });

  test('Trigger trg_award_badges_swipe : 1er SUPER_LIKE → badge PREMIER_SUPER_LIKE', async () => {
    const mission = await seedMissionMatching({ profession: 'INFIRMIER' });
    expect(mission).toBeTruthy();

    await seedSwipe(soignantId!, mission!.id, 'SUPER_LIKE');

    const badges = await getBadges(soignantId!);
    expect(badges).toContain('PREMIER_SWIPE'); // award conjoint au 1er swipe
    expect(badges).toContain('PREMIER_SUPER_LIKE');
  });

  test('Trigger trg_award_badges_swipe : 50 swipes → badge EXPLORATEUR', async () => {
    const admin = adminClient();
    const etabId = await userIdByEmail(TEST_ACCOUNTS.etab.email);
    expect(etabId).toBeTruthy();

    // Seed 50 missions en batch + INSERT 50 swipes
    const baseDate = new Date(Date.now() + 7 * 86400000);
    const missionsPayload = Array.from({ length: 50 }, (_, i) => ({
      etablissement_id: etabId,
      intitule: `[playwright-test] explorateur ${i} ${Date.now()}`,
      description: 'Mission seed EXPLORATEUR',
      profession_requise: 'INFIRMIER',
      service: 'Test',
      debut_le: new Date(baseDate.getTime() + i * 3600000).toISOString(),
      fin_le: new Date(baseDate.getTime() + (i + 8) * 3600000).toISOString(),
      duree_heures: 8,
      taux_horaire_base: 30,
      est_urgente: false,
      statut: 'OUVERTE',
      mode_attribution: 'CANDIDATURE',
    }));

    const { data: missions, error: insertErr } = await admin
      .from('missions' as any)
      .insert(missionsPayload)
      .select('id');
    expect(insertErr).toBeFalsy();
    expect(missions).toHaveLength(50);

    const swipesPayload = (missions as Array<{ id: string }>).map((m) => ({
      soignant_id: soignantId!,
      mission_id: m.id,
      direction: 'LIKE',
    }));
    const { error: swipesErr } = await admin.from('swipes' as any).insert(swipesPayload);
    expect(swipesErr).toBeFalsy();

    const badges = await getBadges(soignantId!);
    expect(badges).toContain('PREMIER_SWIPE');
    expect(badges).toContain('EXPLORATEUR');
  });

  test('Trigger trg_update_streak_on_swipe : 1er swipe → streak=1 + last_activity_date=today', async () => {
    const mission = await seedMissionMatching({ profession: 'INFIRMIER' });
    expect(mission).toBeTruthy();

    await seedSwipe(soignantId!, mission!.id, 'LIKE');

    const streak = await getStreakInfo(soignantId!);
    expect(streak).not.toBeNull();
    expect(streak!.streak_count).toBe(1);
    expect(streak!.max_streak).toBeGreaterThanOrEqual(1);

    // last_activity_date = aujourd'hui
    const { data: row } = await adminClient()
      .from('streaks_soignant' as any)
      .select('last_activity_date')
      .eq('soignant_id', soignantId!)
      .maybeSingle();
    const today = new Date().toISOString().slice(0, 10);
    expect((row as any).last_activity_date).toBe(today);
  });

  test('Trigger trg_award_badges_match : candidature ASSIGNEE issue swipe → badge PREMIER_MATCH', async () => {
    const admin = adminClient();
    const mission = await seedMissionMatching({ profession: 'INFIRMIER' });
    expect(mission).toBeTruthy();

    // 1. Le soignant a swipé LIKE
    await seedSwipe(soignantId!, mission!.id, 'LIKE');

    // 2. INSERT candidature EN_ATTENTE
    const { data: cand, error: candErr } = await admin
      .from('candidatures' as any)
      .insert({
        soignant_id: soignantId!,
        mission_id: mission!.id,
        statut: 'EN_ATTENTE',
      })
      .select('id')
      .single();
    expect(candErr).toBeFalsy();
    const candidatureId = (cand as { id: string }).id;

    try {
      // 3. Étab accepte → UPDATE statut=ASSIGNEE → trigger doit award PREMIER_MATCH
      const { error: updErr } = await admin
        .from('candidatures' as any)
        .update({ statut: 'ASSIGNEE' })
        .eq('id', candidatureId);
      expect(updErr).toBeFalsy();

      const badges = await getBadges(soignantId!);
      expect(badges).toContain('PREMIER_MATCH');
    } finally {
      // Cleanup candidature (sinon contraintes FK rejouent)
      await admin.from('candidatures' as any).delete().eq('id', candidatureId);
    }
  });
});
