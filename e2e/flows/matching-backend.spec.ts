/**
 * Sprint 14 PR 2 — Tests E2E réels backend matching swipe Hinge-style.
 *
 * Remplace les stubs Sprint 13-A par 8 tests fonctionnels qui valident :
 * - fn_calculer_score_matching : structure score + breakdown, filtre dur profession
 * - fn_enregistrer_swipe : LIKE/DISLIKE/SUPER_LIKE, quota 5/jour, re-swipe interdit
 * - fn_obtenir_missions_swipe : exclusion missions swipées + tri score DESC
 * - RLS : un utilisateur non-soignant ne voit pas les swipes d'un soignant
 *
 * Pattern Jolene :
 * - adminClient() (service_role) : seed/cleanup
 * - userClient(email, password) : auth.uid() pour RPCs SECURITY DEFINER
 * - cleanup missions CIBLÉ par IDs trackés (PAS cleanupMissionsTest global :
 *   avec fullyParallel + 2 workers CI, le DELETE LIKE '[playwright-test]%'
 *   supprimait les missions fraîchement seedées par l'autre worker → FK
 *   swipes_mission_id_fkey / matching_scores_mission_id_fkey flaky).
 */

import { test, expect } from '@playwright/test';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';
import {
  seedMissionMatching,
  seedSwipe,
  seedMatchingScore,
  cleanupMatchingForSoignant,
  PREFIX_MISSION_MATCHING,
} from '../helpers/seed-matching';

test.describe('Sprint 14 — Backend matching (réels)', () => {
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
    test.skip(!soignantId, 'Compte test playwright-soignant introuvable — seed Supabase requis');
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

  test('fn_calculer_score_matching : retourne score 0-100 + breakdown JSONB', async () => {
    const admin = adminClient();
    const { data: soignant } = await admin
      .from('soignants' as any)
      .select('profession')
      .eq('id', soignantId!)
      .maybeSingle();
    const profession = (soignant as any)?.profession || 'IDE';

    const mission = await seedMission({ profession, tauxHoraire: 35 });
    expect(mission, 'seedMissionMatching').toBeTruthy();

    const { data, error } = await admin.rpc('fn_calculer_score_matching' as any, {
      p_soignant_id: soignantId!,
      p_mission_id: mission!.id,
    });

    expect(error).toBeFalsy();
    expect(data).toHaveProperty('score');
    expect(data).toHaveProperty('breakdown');
    const score = (data as any).score;
    expect(typeof score).toBe('number');
    expect(score).toBeGreaterThanOrEqual(0);
    expect(score).toBeLessThanOrEqual(100);

    const breakdown = (data as any).breakdown;
    // Soit filtre dur (distance manquante OK car neutre) soit softs présents
    if (!breakdown.filtre_dur_ko) {
      expect(breakdown).toHaveProperty('tarif');
      expect(breakdown).toHaveProperty('distance');
      expect(breakdown).toHaveProperty('etablissement');
      expect(breakdown).toHaveProperty('urgence');
    }
  });

  test('fn_calculer_score_matching : profession incompatible → score 0 + breakdown filtre_dur_ko', async () => {
    const admin = adminClient();
    const { data: soignant } = await admin
      .from('soignants' as any)
      .select('profession')
      .eq('id', soignantId!)
      .maybeSingle();
    const professionSoignant = (soignant as any)?.profession || 'IDE';
    // Choisir une profession qui diffère — valeurs de l'enum DB type_profession
    // (le libellé DB du kiné est 'KINE', PAS 'KINESITHERAPEUTE' — cf. constantes.ts)
    const professionIncompatible = professionSoignant === 'KINE' ? 'AS' : 'KINE';

    const mission = await seedMission({ profession: professionIncompatible });
    expect(mission).toBeTruthy();

    const { data, error } = await admin.rpc('fn_calculer_score_matching' as any, {
      p_soignant_id: soignantId!,
      p_mission_id: mission!.id,
    });
    expect(error).toBeFalsy();
    expect((data as any).score).toBe(0);
    expect((data as any).breakdown.filtre_dur_ko).toBe('profession_incompatible');
  });

  test('fn_enregistrer_swipe : LIKE → ok:true + INSERT swipes', async () => {
    const mission = await seedMission({ profession: 'IDE' });
    expect(mission).toBeTruthy();

    const client = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const { data, error } = await client.rpc('fn_enregistrer_swipe' as any, {
      p_mission_id: mission!.id,
      p_direction: 'LIKE',
    });

    expect(error).toBeFalsy();
    expect((data as any).ok).toBe(true);
    expect((data as any).direction).toBe('LIKE');
    expect((data as any).swipe_id).toBeTruthy();

    // Vérifier que le swipe est bien en DB
    const { data: swipes } = await adminClient()
      .from('swipes' as any)
      .select('direction')
      .eq('soignant_id', soignantId!)
      .eq('mission_id', mission!.id);
    expect(swipes).toHaveLength(1);
    expect((swipes as any)[0].direction).toBe('LIKE');
  });

  test('fn_enregistrer_swipe : ⭐ = FAVORI illimité (D1) — sauvegarde, aucune candidature, pas de quota', async () => {
    // Ce scénario vérifie neuf échanges réels avec Supabase (seed, auth, RPC,
    // quatre lectures métier et nettoyage). Sous charge CI, leur durée cumulée
    // peut légitimement dépasser les 30 s globaux sans qu'aucun appel échoue.
    // On conserve toutes les assertions et on adapte seulement le budget du
    // scénario d'intégration distant.
    test.slow();

    // D1 (Lot 6c) : le super-like « candidature prioritaire 5/jour » est
    // remplacé par la sauvegarde illimitée. SUPER_LIKE (anciens bundles)
    // est traité comme FAVORI — même avec un quota historique consommé.
    await adminClient()
      .from('super_swipes_quota' as any)
      .upsert(
        { soignant_id: soignantId!, date: new Date().toISOString().slice(0, 10), count: 5 },
        { onConflict: 'soignant_id,date' },
      );

    const mission = await seedMission({ profession: 'IDE' });
    expect(mission).toBeTruthy();

    const client = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const { data, error } = await client.rpc('fn_enregistrer_swipe' as any, {
      p_mission_id: mission!.id,
      p_direction: 'SUPER_LIKE', // rétro-compat → FAVORI
    });
    expect(error).toBeFalsy();
    expect((data as any).ok).toBe(true);
    expect((data as any).direction).toBe('FAVORI');
    expect((data as any).sauvegardee).toBe(true);

    // Le swipe est enregistré en FAVORI + la mission est sauvegardée
    const { data: swipes } = await adminClient()
      .from('swipes' as any)
      .select('direction')
      .eq('soignant_id', soignantId!)
      .eq('mission_id', mission!.id);
    expect(swipes).toHaveLength(1);
    expect((swipes as any)[0].direction).toBe('FAVORI');

    const { data: sauvegarde } = await adminClient()
      .from('missions_sauvegardees' as any)
      .select('id')
      .eq('soignant_id', soignantId!)
      .eq('mission_id', mission!.id);
    expect(sauvegarde).toHaveLength(1);

    // AUCUNE candidature créée (un favori n'est pas une candidature)
    const { data: candidatures } = await adminClient()
      .from('candidatures')
      .select('id')
      .eq('soignant_id', soignantId!)
      .eq('mission_id', mission!.id);
    expect(candidatures).toHaveLength(0);

    // Cleanup de la sauvegarde pour l'idempotence du test
    await adminClient()
      .from('missions_sauvegardees' as any)
      .delete()
      .eq('soignant_id', soignantId!)
      .eq('mission_id', mission!.id);
  });

  test('fn_enregistrer_swipe : re-swipe même mission → mission_deja_swipee', async () => {
    const mission = await seedMission({ profession: 'IDE' });
    expect(mission).toBeTruthy();

    // 1er swipe LIKE (via INSERT direct pour bypass auth)
    await seedSwipe(soignantId!, mission!.id, 'LIKE');

    // 2e swipe via RPC (auth) avec direction différente
    const client = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const { data, error } = await client.rpc('fn_enregistrer_swipe' as any, {
      p_mission_id: mission!.id,
      p_direction: 'DISLIKE',
    });
    expect(error).toBeFalsy();
    expect((data as any).ok).toBe(false);
    expect((data as any).error).toBe('mission_deja_swipee');
  });

  test('fn_obtenir_missions_swipe : exclut les missions déjà swipées', async () => {
    const m1 = await seedMission({ profession: 'IDE', intitule: `${PREFIX_MISSION_MATCHING} m1` });
    const m2 = await seedMission({ profession: 'IDE', intitule: `${PREFIX_MISSION_MATCHING} m2` });
    expect(m1 && m2).toBeTruthy();

    // Soignant a déjà swipé m1
    await seedSwipe(soignantId!, m1!.id, 'LIKE');

    const client = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const { data, error } = await client.rpc('fn_obtenir_missions_swipe' as any, { p_limit: 50 });
    expect(error).toBeFalsy();

    const missions = ((data as any).missions || []) as Array<{ mission_id: string }>;
    const ids = missions.map((m) => m.mission_id);
    expect(ids).not.toContain(m1!.id);
    expect(ids).toContain(m2!.id);
  });

  test('fn_obtenir_missions_swipe : tri par score DESC', async () => {
    const m1 = await seedMission({ profession: 'IDE', intitule: `${PREFIX_MISSION_MATCHING} low` });
    const m2 = await seedMission({ profession: 'IDE', intitule: `${PREFIX_MISSION_MATCHING} high` });
    expect(m1 && m2).toBeTruthy();

    // Forcer scores : m1=30, m2=85
    await seedMatchingScore(soignantId!, m1!.id, 30);
    await seedMatchingScore(soignantId!, m2!.id, 85);

    const client = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const { data } = await client.rpc('fn_obtenir_missions_swipe' as any, { p_limit: 50 });

    const missions = ((data as any).missions || []) as Array<{ mission_id: string; score: number }>;
    const seedIds = [m1!.id, m2!.id];
    const seedOnly = missions.filter((m) => seedIds.includes(m.mission_id));
    expect(seedOnly).toHaveLength(2);
    // m2 (score 85) doit apparaître avant m1 (score 30)
    const idxHigh = seedOnly.findIndex((m) => m.mission_id === m2!.id);
    const idxLow = seedOnly.findIndex((m) => m.mission_id === m1!.id);
    expect(idxHigh).toBeLessThan(idxLow);
  });

  test('RLS swipes : un compte étab ne voit pas les swipes d\'un soignant', async () => {
    const mission = await seedMission({ profession: 'IDE' });
    expect(mission).toBeTruthy();
    await seedSwipe(soignantId!, mission!.id, 'LIKE');

    // Connexion compte étab (pas soignant) → RLS doit cacher
    const etabClient = await userClient(TEST_ACCOUNTS.etab.email, TEST_ACCOUNTS.etab.password);
    const { data } = await etabClient
      .from('swipes' as any)
      .select('id')
      .eq('soignant_id', soignantId!)
      .eq('mission_id', mission!.id);
    expect(data || []).toHaveLength(0);
  });
});
