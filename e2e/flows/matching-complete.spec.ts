/**
 * Sprint 14 PR 4 — Tests E2E réels flow complet matching swipe.
 *
 * Remplace les 6 stubs Sprint 13-D PR 3 par 5 tests fonctionnels qui valident
 * les triggers + workflows end-to-end :
 * - Trigger trg_award_badges_swipe : PREMIER_SWIPE, PREMIER_SUPER_LIKE, EXPLORATEUR
 * - Trigger trg_update_streak_on_swipe : streak_count + last_activity_date
 * - Trigger trg_award_badges_match : PREMIER_MATCH sur UPDATE candidature ACCEPTEE
 *
 * Pattern : seed via fn_test_seed_mission (RPC service_role, GUC bypass anti-seed
 * financier — l'INSERT direct dans missions est rejeté par le trigger anti-seed
 * dès que les majorations nuit/dimanche rendent total_brut ≠ taux×durée),
 * vérification du state via getBadges() / getStreakInfo() / SELECT direct.
 * Cleanup missions CIBLÉ par IDs trackés (PAS cleanupMissionsTest global : avec
 * fullyParallel + 2 workers CI, le DELETE LIKE '[playwright-test]%' supprimait
 * les missions fraîchement seedées par l'autre worker → FK flaky).
 * Intitulés en préfixe '[pw-test:match]' (PAS '[playwright-test]') : la purge
 * globale cleanupSeedData (helpers/seed.ts — afterEach de candidature.spec.ts
 * et notation.spec.ts) supprime en LIKE '[playwright-test]%' les missions de
 * l'étab test partagé. En fullyParallel 2 workers, elle effaçait nos missions
 * entre le seed et l'INSERT swipes → FK 23503 swipes_mission_id_fkey (run CI
 * 27418384516). Le préfixe immune échappe au LIKE ; la purge ciblée par IDs
 * trackés reste la voie de cleanup.
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
  getBadges,
  getStreakInfo,
  PREFIX_MISSION_MATCHING,
} from '../helpers/seed-matching';

// Les tests partagent le compte soignant test et l'afterEach purge TOUTES ses
// données matching (swipes/badges/streaks) : en fullyParallel 2 workers, deux
// tests de CE fichier exécutés en concurrence se voleraient leurs données
// (badge attendu supprimé par l'afterEach de l'autre). mode 'default' =
// exécution séquentielle dans un seul worker, sans le skip-on-failure du mode
// 'serial' (même pattern que anti-triche-pointage.spec.ts).
test.describe.configure({ mode: 'default' });

test.describe('Sprint 14 — Flow complet matching (réels)', () => {
  let soignantId: string | null = null;
  /** IDs des missions seedées par CE worker — purge ciblée en afterEach. */
  const seededMissionIds: string[] = [];

  /** Wrapper seedMissionMatching qui tracke l'ID pour le cleanup ciblé. */
  async function seedMission(opts: Parameters<typeof seedMissionMatching>[0] = {}) {
    const mission = await seedMissionMatching(opts);
    if (mission) seededMissionIds.push(mission.id);
    return mission;
  }

  test.beforeAll(async () => {
    soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    test.skip(!soignantId, 'Compte test playwright-soignant introuvable');
  });

  test.afterEach(async () => {
    if (soignantId) {
      await cleanupMatchingForSoignant(soignantId);
    }
    if (seededMissionIds.length > 0) {
      await adminClient()
        .from('missions' as any)
        .delete()
        .in('id', seededMissionIds.splice(0));
    }
  });

  test('Trigger trg_award_badges_swipe : 1er swipe → badge PREMIER_SWIPE', async () => {
    const mission = await seedMission({ profession: 'IDE' });
    expect(mission).toBeTruthy();

    await seedSwipe(soignantId!, mission!.id, 'LIKE');

    const badges = await getBadges(soignantId!);
    expect(badges).toContain('PREMIER_SWIPE');
  });

  test('Trigger trg_award_badges_swipe : 1er SUPER_LIKE → badge PREMIER_SUPER_LIKE', async () => {
    const mission = await seedMission({ profession: 'IDE' });
    expect(mission).toBeTruthy();

    await seedSwipe(soignantId!, mission!.id, 'SUPER_LIKE');

    const badges = await getBadges(soignantId!);
    expect(badges).toContain('PREMIER_SWIPE'); // award conjoint au 1er swipe
    expect(badges).toContain('PREMIER_SUPER_LIKE');
  });

  test('Trigger trg_award_badges_swipe : 50 swipes → badge EXPLORATEUR', async () => {
    // Ce scénario crée volontairement 50 missions distantes avant de valider
    // le seuil du trigger. Sur un Supabase chargé, les RPC + le cleanup ciblé
    // dépassent légitimement les 30 s globales sans que le produit ait échoué.
    test.slow();

    const admin = adminClient();

    // Seed 50 missions via fn_test_seed_mission (l'INSERT direct en batch est
    // rejeté par le trigger anti-seed : les missions à cheval sur la nuit ont
    // un total_brut majoré CCN ≠ taux×durée). Chunks de 10 pour limiter la charge.
    const baseDate = new Date(Date.now() + 7 * 86400000);
    const missionIds: string[] = [];
    for (let start = 0; start < 50; start += 10) {
      const batch = await Promise.all(
        Array.from({ length: 10 }, (_, j) => {
          const i = start + j;
          return seedMission({
            profession: 'IDE',
            intitule: `${PREFIX_MISSION_MATCHING} explorateur ${i} ${Date.now()}`,
            debut: new Date(baseDate.getTime() + i * 3600000),
          });
        }),
      );
      for (const m of batch) {
        expect(m, 'seedMission explorateur').toBeTruthy();
        missionIds.push(m!.id);
      }
    }
    expect(missionIds).toHaveLength(50);

    // 1er swipe seul (statement séparé) : les triggers AFTER ROW d'un INSERT
    // multi-lignes voient TOUTES les lignes du statement (count=50 pour chaque
    // ligne) → PREMIER_SWIPE (count=1 strict) ne serait jamais attribué.
    const { error: firstSwipeErr } = await admin
      .from('swipes' as any)
      .insert({ soignant_id: soignantId!, mission_id: missionIds[0], direction: 'LIKE' });
    expect(firstSwipeErr).toBeFalsy();

    // Les 49 suivants en batch : chaque trigger voit count=50 → EXPLORATEUR.
    const swipesPayload = missionIds.slice(1).map((missionId) => ({
      soignant_id: soignantId!,
      mission_id: missionId,
      direction: 'LIKE',
    }));
    const { error: swipesErr } = await admin.from('swipes' as any).insert(swipesPayload);
    expect(swipesErr).toBeFalsy();

    const badges = await getBadges(soignantId!);
    expect(badges).toContain('PREMIER_SWIPE');
    expect(badges).toContain('EXPLORATEUR');
  });

  test('Trigger trg_update_streak_on_swipe : 1er swipe → streak=1 + last_activity_date=today', async () => {
    const mission = await seedMission({ profession: 'IDE' });
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

  test('Trigger trg_award_badges_match : candidature ACCEPTEE issue swipe → badge PREMIER_MATCH', async () => {
    const admin = adminClient();
    const mission = await seedMission({ profession: 'IDE' });
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
      // 3. Étab accepte → UPDATE statut=ACCEPTEE → trigger doit award PREMIER_MATCH
      const { error: updErr } = await admin
        .from('candidatures' as any)
        .update({ statut: 'ACCEPTEE' })
        .eq('id', candidatureId);
      expect(updErr).toBeFalsy();

      const badges = await getBadges(soignantId!);
      expect(badges).toContain('PREMIER_MATCH');
    } finally {
      // Cleanup : le passage à ACCEPTEE déclenche aussi trg_candidature_acceptee_chat
      // (ouvre une conversation liée à la mission) → la purger d'abord, sinon la FK
      // conversations.mission_id bloque le DELETE missions de l'afterEach.
      await admin.from('conversations' as any).delete().eq('mission_id', mission!.id);
      await admin.from('candidatures' as any).delete().eq('id', candidatureId);
    }
  });
});
