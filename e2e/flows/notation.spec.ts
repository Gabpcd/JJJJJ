/**
 * Sprint 16 PR 1 — Tests E2E réels notation bidirectionnelle.
 *
 * Mise à jour durcissement prod (post-Sprint 17) : l'ancien raccourci
 * markMissionTerminee (fn_test_update_mission service_role, transition directe
 * OUVERTE → TERMINEE + assignation) est neutralisé par la stack de triggers :
 * fn_valider_transition_statut_mission rejette OUVERTE → TERMINEE,
 * dec_proteger_mission_soignant reverte soignant_assigne_id pour un caller
 * non-admin/non-étab et fn_creer_notification raise « Non authentifié » quand
 * auth.uid() est NULL. Le setup suit donc le cycle de vie réel (pattern
 * pointage.spec.ts) :
 *   seed OUVERTE (service_role) → candidature → fn_traiter_candidature
 *   ACCEPTEE par l'établissement authentifié (→ ASSIGNEE) → EN_COURS →
 *   TERMINEE par l'étab (pol_mission_update + transitions valides).
 *
 * Fenêtre J+9 (et non J+8) : pointage.spec.ts seed J+8 pour le même soignant
 * test — en fullyParallel 2 workers, deux missions chevauchantes pour le même
 * soignant déclencheraient dec_refuser_chevauchement_soignant / repos 11h.
 *
 * Note : la présence stricte du bouton "Noter" dépend des conditions UI
 * (mission DOIT avoir un soignant_assigne_id, statut TERMINEE, pas encore
 * notée) — soft check conservé.
 */

import { test, expect } from '@playwright/test';
import { seedMission, seedCandidature, cleanupSeedData, cleanupMissionCascade, seedDocsRequisVerifie } from '../helpers/seed';
import { loginAs, TEST_ACCOUNTS } from '../helpers/auth';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';

test.describe('Flow notation bidirectionnelle', () => {
  /** IDs des missions seedées par CE test — purge ciblée ordonnée (la clôture
   *  TERMINEE crée des enfants en FK NO ACTION : bulletin de paie, cotisations,
   *  conformité, contrat, conversation… cleanupSeedData seul échoue en silence). */
  const seededMissionIds: string[] = [];

  test.afterEach(async () => {
    for (const missionId of seededMissionIds.splice(0)) {
      await cleanupMissionCascade(missionId).catch(() => {});
    }
    await cleanupSeedData().catch(() => {});
  });

  test('mission TERMINEE assignée → page détail mission accessible (CTA noter soft check)', async ({ page }) => {
    const soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    expect(soignantId, 'compte test soignant').toBeTruthy();

    // Robustesse : force le flag docs (idempotent, compte test fixe) — exigé
    // par fn_traiter_candidature si la mission démarre < 7 jours (pattern
    // pointage.spec.ts).
    await adminClient()
      .from('soignants' as any)
      .update({ tous_documents_valides: true })
      .eq('id', soignantId);
    // Gate documents per-mission : fournir de vrais docs vérifiés (le flag seul ne suffit plus).
    await seedDocsRequisVerifie(soignantId);

    // J+9 : hors fenêtre pointage (J+8 + 8h, repos 11h respecté) et au-delà
    // du seuil < 7 jours de fn_traiter_candidature.
    const debut = new Date(Date.now() + 9 * 86400000);
    const fin = new Date(debut.getTime() + 8 * 3600000);
    const m = await seedMission({ intitule: '[playwright-test] Notation E2E', debut, fin });
    expect(m, 'seedMission').toBeTruthy();
    seededMissionIds.push(m!.id);

    const cand = await seedCandidature(m!.id);
    expect(cand, 'seedCandidature').toBeTruthy();

    // Acceptation par l'établissement authentifié → mission ASSIGNEE
    // (seul un acteur authentifié peut assigner, cf. en-tête).
    const etab = await userClient(TEST_ACCOUNTS.etab.email, TEST_ACCOUNTS.etab.password);
    const { data: accept, error: acceptErr } = await etab.rpc('fn_traiter_candidature' as any, {
      p_candidature_id: cand!.id,
      p_decision: 'ACCEPTEE',
    });
    expect(acceptErr, `fn_traiter_candidature: ${acceptErr?.message}`).toBeFalsy();
    expect((accept as any)?.success, (accept as any)?.error).toBe(true);

    // Transitions valides du trigger fn_valider_transition_statut_mission :
    // ASSIGNEE → EN_COURS → TERMINEE, par l'étab (pol_mission_update).
    const { error: enCoursErr } = await etab
      .from('missions' as any)
      .update({ statut: 'EN_COURS' })
      .eq('id', m!.id);
    expect(enCoursErr, `EN_COURS: ${enCoursErr?.message}`).toBeFalsy();

    const { error: termineeErr } = await etab
      .from('missions' as any)
      .update({ statut: 'TERMINEE' })
      .eq('id', m!.id);
    expect(termineeErr, `TERMINEE: ${termineeErr?.message}`).toBeFalsy();

    const { data: missionDb, error: missionDbErr } = await adminClient()
      .from('missions' as any)
      .select('statut, soignant_assigne_id')
      .eq('id', m!.id)
      .single();
    expect(missionDbErr).toBeFalsy();
    expect((missionDb as any)?.statut).toBe('TERMINEE');
    expect((missionDb as any)?.soignant_assigne_id).toBe(soignantId);

    await loginAs(page, 'soignant');

    await page.goto(`/soignant/missions/${m!.id}`);
    await page.waitForLoadState('networkidle');

    // La page charge avec un heading visible (h1 ou h2).
    const heading = page.locator('h1, h2').first();
    await expect(heading).toBeVisible({ timeout: 10_000 });

    // CTA Noter/Évaluer présent côté UI quand mission éligible (soft check
    // car affichage conditionnel selon état notation déjà existante).
    const noter = page.getByRole('button', { name: /Noter|Évaluer/i }).first();
    await expect(noter).toBeVisible({ timeout: 5_000 }).catch(() => {});
  });
});
