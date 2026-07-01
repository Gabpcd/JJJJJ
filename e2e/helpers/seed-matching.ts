/**
 * Helpers seed Sprint 14 PR 1 — Matching swipe Hinge-style.
 *
 * Fournit les fixtures nécessaires aux tests E2E matching :
 * - seedMissionMatching : crée mission OUVERTE avec params explicites
 * - seedSwipe : INSERT direct swipes (bypass quota, pour pré-setup)
 * - seedMatchingScore : pré-calcule un score (skip cron horaire)
 * - cleanupMatchingForSoignant : purge swipes/scores/badges/streaks/quota d'un soignant
 *
 * Réutilise `userIdByEmail()` + `adminClient()` de db.ts.
 * Conventions de nommage : tous les seeds préfixent intitule par [playwright-test].
 */

import { adminClient, userIdByEmail } from './db';
import { TEST_ACCOUNTS } from './auth';

export type SwipeDirEnum = 'LIKE' | 'DISLIKE' | 'SUPER_LIKE';

/**
 * Préfixe intitule des missions seedées matching.
 *
 * VOLONTAIREMENT distinct de '[playwright-test]' : cleanupSeedData
 * (helpers/seed.ts, appelé en afterEach par candidature.spec.ts +
 * notation.spec.ts) purge les missions de l'étab test en LIKE
 * '[playwright-test]%'. Avec fullyParallel + 2 workers CI, cette purge
 * supprimait les missions matching fraîchement seedées par l'AUTRE worker
 * → FK swipes_mission_id_fkey 23503 (run CI 27418384516). Le préfixe
 * immune reste identifiable comme donnée de test mais échappe au LIKE.
 */
export const PREFIX_MISSION_MATCHING = '[pw-test:match]';

/**
 * Crée une mission OUVERTE attribuée au compte étab test.
 * Retourne {id, etablissement_id} ou null si seed échoue.
 */
export async function seedMissionMatching(opts: {
  intitule?: string;
  profession?: string;
  tauxHoraire?: number;
  estUrgente?: boolean;
  debut?: Date;
  dureeHeures?: number;
} = {}): Promise<{ id: string; etablissement_id: string } | null> {
  const etabId = await userIdByEmail(TEST_ACCOUNTS.etab.email);
  if (!etabId) {
    console.error('[seed-matching] Compte étab test introuvable');
    return null;
  }

  // J+7 à heure RONDE (06:00 UTC = 07h/08h Paris) — jamais l'heure du run,
  // pour qu'un résidu de seed (cleanup raté) ne trahisse pas une donnée de test.
  const debut = opts.debut || (() => { const d = new Date(Date.now() + 7 * 86400000); d.setUTCHours(6, 0, 0, 0); return d; })();
  const duree = opts.dureeHeures || 8;
  const fin = new Date(debut.getTime() + duree * 3600000);

  const { data: missionId, error } = await adminClient().rpc('fn_test_seed_mission' as any, {
    p_data: {
      etablissement_id: etabId,
      intitule: opts.intitule || `${PREFIX_MISSION_MATCHING} Match ${Date.now()}`,
      description: 'Mission seed matching swipe',
      profession_requise: opts.profession || 'IDE',
      service: 'Test',
      debut_le: debut.toISOString(),
      fin_le: fin.toISOString(),
      duree_heures: duree,
      taux_horaire_base: opts.tauxHoraire ?? 30,
      est_urgente: opts.estUrgente ?? false,
      statut: 'OUVERTE',
      mode_attribution: 'CANDIDATURE',
    },
  });

  if (error) {
    console.error('[seed-matching] seedMissionMatching failed:', error.message);
    return null;
  }
  return { id: missionId as string, etablissement_id: etabId };
}

/**
 * INSERT direct dans swipes (bypass RLS + bypass quota super-likes).
 * Utile pour pré-setup : "le soignant a déjà 49 swipes, on teste le 50e".
 */
export async function seedSwipe(
  soignantId: string,
  missionId: string,
  direction: SwipeDirEnum,
): Promise<{ id: string } | null> {
  const { data, error } = await adminClient()
    .from('swipes' as any)
    .insert({ soignant_id: soignantId, mission_id: missionId, direction })
    .select('id')
    .single();
  if (error) {
    console.error('[seed-matching] seedSwipe failed:', error.message);
    return null;
  }
  return data as { id: string };
}

/**
 * Pré-calcule un matching_score (skip le cron horaire pour les tests).
 * Force un score arbitraire ou laisse fn_calculer_score_matching faire le calcul.
 */
export async function seedMatchingScore(
  soignantId: string,
  missionId: string,
  scoreForce?: number,
): Promise<{ score: number } | null> {
  let score = scoreForce;
  if (score == null) {
    const { data, error } = await adminClient().rpc('fn_calculer_score_matching' as any, {
      p_soignant_id: soignantId,
      p_mission_id: missionId,
    });
    if (error) {
      console.error('[seed-matching] fn_calculer_score_matching failed:', error.message);
      return null;
    }
    score = (data as any)?.score ?? 0;
  }

  const { error } = await adminClient()
    .from('matching_scores' as any)
    .upsert(
      {
        soignant_id: soignantId,
        mission_id: missionId,
        score_global: score,
        breakdown: scoreForce != null ? { test_forced: true } : {},
        calcule_le: new Date().toISOString(),
      },
      { onConflict: 'soignant_id,mission_id' },
    );
  if (error) {
    console.error('[seed-matching] seedMatchingScore upsert failed:', error.message);
    return null;
  }
  return { score: score! };
}

/**
 * Purge complète des données matching pour un soignant donné.
 * Appeler dans test.afterEach pour isolation des tests.
 */
export async function cleanupMatchingForSoignant(soignantId: string): Promise<void> {
  const admin = adminClient();
  // Ordre : swipes + matching_scores + super_swipes_quota + streaks + badges
  await admin.from('swipes' as any).delete().eq('soignant_id', soignantId);
  await admin.from('matching_scores' as any).delete().eq('soignant_id', soignantId);
  await admin.from('super_swipes_quota' as any).delete().eq('soignant_id', soignantId);
  await admin.from('streaks_soignant' as any).delete().eq('soignant_id', soignantId);
  await admin.from('badges_soignant' as any).delete().eq('soignant_id', soignantId);
}

/**
 * Purge missions test (anciens seeds '[playwright-test]%' + seeds immunes
 * '[pw-test:%').
 *
 * ATTENTION : purge GLOBALE — ne JAMAIS appeler en afterEach d'une spec
 * fullyParallel (supprime les missions fraîchement seedées par l'autre
 * worker → FK flaky, cf. en-têtes matching-backend/matching-complete).
 * Réservé à un nettoyage manuel hors exécution parallèle.
 */
export async function cleanupMissionsTest(): Promise<void> {
  const admin = adminClient();
  await admin.from('missions' as any).delete().like('intitule', '[playwright-test]%');
  await admin.from('missions' as any).delete().like('intitule', '[pw-test:%');
}

/** Récupère le streak actuel d'un soignant via RPC (côté admin). */
export async function getStreakInfo(soignantId: string): Promise<{
  streak_count: number;
  max_streak: number;
} | null> {
  const { data, error } = await adminClient()
    .from('streaks_soignant' as any)
    .select('streak_count, max_streak')
    .eq('soignant_id', soignantId)
    .maybeSingle();
  if (error || !data) return null;
  return data as { streak_count: number; max_streak: number };
}

/** Récupère les badges d'un soignant (lecture admin). */
export async function getBadges(soignantId: string): Promise<string[]> {
  const { data } = await adminClient()
    .from('badges_soignant' as any)
    .select('badge_type')
    .eq('soignant_id', soignantId);
  return ((data as any[]) || []).map((b) => b.badge_type);
}

/** Récupère le quota super-likes restant du jour pour un soignant. */
export async function getSuperLikesRestant(soignantId: string): Promise<number> {
  const today = new Date().toISOString().slice(0, 10);
  const { data } = await adminClient()
    .from('super_swipes_quota' as any)
    .select('count')
    .eq('soignant_id', soignantId)
    .eq('date', today)
    .maybeSingle();
  const used = (data as any)?.count ?? 0;
  return Math.max(0, 5 - used);
}
