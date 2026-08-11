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
 * La fixture garantit les conditions UI du bouton "Noter l'établissement" :
 * mission assignée, statut TERMINEE et aucune notation existante.
 */

import { test, expect } from '@playwright/test';
import {
  cleanupMissionCascade,
  createEphemeralVerifiedCaregiver,
  seedCandidature,
  seedContratMissionSigne,
  seedMission,
  type EphemeralVerifiedCaregiver,
} from '../helpers/seed';
import { TEST_ACCOUNTS } from '../helpers/auth';
import { adminClient, userClient } from '../helpers/db';

test.describe('Flow notation bidirectionnelle', () => {
  // Ce parcours exécute le cycle métier complet en base (candidature,
  // contrat, transitions puis purge FK). En CI, ce setup consomme à lui seul
  // l'essentiel des 30 s par défaut avant même les assertions d'interface.
  // Les attentes UI restent ciblées sur le contenu et le CTA attendus.
  test.describe.configure({ timeout: 90_000 });

  /** IDs des missions seedées par CE test — purge ciblée ordonnée (la clôture
   *  TERMINEE crée des enfants en FK NO ACTION : bulletin de paie, cotisations,
   *  conformité, contrat, conversation… cleanupSeedData seul échoue en silence). */
  const seededMissionIds: string[] = [];
  let caregiver: EphemeralVerifiedCaregiver;

  test.beforeAll(async () => {
    caregiver = await createEphemeralVerifiedCaregiver();
  });

  test.afterEach(async () => {
    for (const missionId of seededMissionIds.splice(0)) {
      await cleanupMissionCascade(missionId);
    }
  });

  test.afterAll(async () => {
    await caregiver?.cleanup();
  });

  test('mission TERMINEE assignée → CTA Noter l’établissement visible', async ({ page }) => {
    const soignantId = caregiver.id;

    // J+9 : hors fenêtre pointage (J+8 + 8h, repos 11h respecté) et au-delà
    // du seuil < 7 jours de fn_traiter_candidature.
    const debut = new Date(Date.now() + 9 * 86400000);
    const fin = new Date(debut.getTime() + 8 * 3600000);
    const m = await seedMission({ intitule: '[pw-test:notation] Notation E2E', debut, fin });
    expect(m, 'seedMission').toBeTruthy();
    seededMissionIds.push(m!.id);

    const cand = await seedCandidature(m!.id, soignantId);
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
    await seedContratMissionSigne(m!.id, caregiver, { etablissement: etab });

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

    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(caregiver.email);
    await page.locator('input[type="password"]').first().fill(caregiver.password);
    await page.getByTestId('login-submit').click();
    await expect(page).toHaveURL(/\/soignant\/tableau-de-bord/, { timeout: 15_000 });

    await page.goto(`/soignant/missions/${m!.id}`);
    // La messagerie Realtime garde volontairement une connexion réseau
    // ouverte sur cette page. Attendre "networkidle" rendait donc le test
    // dépendant d'un silence réseau qui n'arrive pas toujours, alors que le
    // contenu et le CTA étaient déjà rendus.
    await page.waitForLoadState('domcontentloaded');

    // Le titre métier doit remplacer le loader : un simple heading d'erreur ou
    // de chargement prolongé ne doit pas faire passer cette régression.
    await expect(page.getByRole('heading', { name: m!.intitule, exact: true }))
      .toBeVisible({ timeout: 30_000 });

    // Régression stricte : une mission éligible doit permettre au soignant de
    // noter l'établissement. Une disparition du CTA fait désormais échouer le test.
    const noter = page.getByRole('button', { name: /Noter l'établissement/i });
    await expect(noter).toBeVisible({ timeout: 30_000 });
  });
});
