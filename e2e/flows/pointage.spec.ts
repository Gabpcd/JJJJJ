/**
 * Sprint 16 PR 4 — Tests E2E réels pointage.
 *
 * Mise à jour durcissement prod (post-Sprint 17) : l'ancien raccourci
 * markMissionTerminee (fn_test_update_mission service_role, transition directe
 * OUVERTE → TERMINEE) est désormais neutralisé par la stack de triggers :
 * - fn_valider_transition_statut_mission rejette OUVERTE → TERMINEE
 *   (est_admin() = false pour service_role, auth.uid() NULL) ;
 * - dec_proteger_mission_soignant reverte silencieusement soignant_assigne_id
 *   pour un caller non-admin/non-étab ;
 * - fn_creer_notification (appelée par dec_notifier_changement_mission) raise
 *   « Non authentifié » quand auth.uid() est NULL.
 *
 * Le test suit donc le cycle de vie réel :
 *   seed OUVERTE (service_role) → candidature → fn_traiter_candidature
 *   ACCEPTEE par l'établissement authentifié (→ ASSIGNEE) → EN_COURS →
 *   TERMINEE par l'établissement (pol_mission_update + transitions valides).
 *
 * Skip honnête documenté : workflow pointage UI complet (GPS + code arrivée
 * + fenêtre temporelle) testé manuellement. Les RPCs de pointage (QR, code
 * secours, pings GPS) sont couvertes par anti-triche-pointage.spec.ts.
 */

import { test, expect } from '@playwright/test';
import { seedMission, seedCandidature, seedDocsRequisVerifie } from '../helpers/seed';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';

test.describe('Flow pointage soignant', () => {
  /** IDs des missions seedées par CE test — purge ciblée (la purge globale
   *  cleanupSeedData échoue désormais en silence sur les FK NO ACTION). */
  const seededMissionIds: string[] = [];

  // La clôture TERMINEE crée des enfants en FK NO ACTION vers missions
  // (bulletin de paie, cotisations, conformité, contrat, conversation…) :
  // purge ordonnée obligatoire avant le DELETE missions.
  test.afterEach(async () => {
    const admin = adminClient();
    for (const missionId of seededMissionIds.splice(0)) {
      const enfants = [
        'conformite_travail',
        'cotisations_sociales',
        'bulletins_paie',
        'contrats_travail_missions',
        'contrats_mission',
        'presences',
        'scans_pointage',
        'messages_mission',
        'conversations',
        'candidatures',
      ];
      for (const table of enfants) {
        await admin.from(table as any).delete().eq('mission_id', missionId).then(() => {}, () => {});
      }
      await admin.from('missions' as any).delete().eq('id', missionId).then(() => {}, () => {});
    }
  });

  test('seed mission + acceptation étab + clôture → statut DB = TERMINEE', async () => {
    const soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    expect(soignantId, 'compte test soignant').toBeTruthy();

    // Debout J+8 : au-delà du seuil < 7 jours de fn_traiter_candidature qui
    // exigerait tous_documents_valides + RCP. On force quand même le flag docs
    // (idempotent, compte test fixe) pour rester robuste aux triggers de
    // vérification documentaire à l'assignation.
    await adminClient()
      .from('soignants' as any)
      .update({ tous_documents_valides: true })
      .eq('id', soignantId);
    // Gate documents per-mission : fournir de vrais docs vérifiés (le flag seul ne suffit plus).
    await seedDocsRequisVerifie(soignantId);

    const debut = new Date(Date.now() + 8 * 86400000);
    const fin = new Date(debut.getTime() + 8 * 3600000);
    const m = await seedMission({ intitule: '[playwright-test] Pointage E2E', debut, fin });
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
    expect(acceptErr).toBeFalsy();
    expect((accept as any)?.success, (accept as any)?.error).toBe(true);

    // Transitions valides du trigger fn_valider_transition_statut_mission :
    // ASSIGNEE → EN_COURS → TERMINEE, par l'étab (pol_mission_update).
    const { error: enCoursErr } = await etab
      .from('missions' as any)
      .update({ statut: 'EN_COURS' })
      .eq('id', m!.id);
    expect(enCoursErr).toBeFalsy();

    const { error: termineeErr } = await etab
      .from('missions' as any)
      .update({ statut: 'TERMINEE' })
      .eq('id', m!.id);
    expect(termineeErr).toBeFalsy();

    const { data, error } = await adminClient()
      .from('missions' as any)
      .select('statut, soignant_assigne_id')
      .eq('id', m!.id)
      .single();

    expect(error).toBeFalsy();
    expect((data as any)?.statut).toBe('TERMINEE');
    expect((data as any)?.soignant_assigne_id).toBe(soignantId);
  });
});
