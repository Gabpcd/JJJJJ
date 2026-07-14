import { test, expect } from '@playwright/test';
import { adminClient, userClient } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';
import {
  cleanupMissionCascade,
  createEphemeralVerifiedCaregiver,
  seedCandidature,
  seedContratMissionSigne,
  seedMission,
  type EphemeralVerifiedCaregiver,
} from '../helpers/seed';

/**
 * Lot 13 — auto-validation des présences à 72 h (job cron
 * jolene_valider_presences_72h → fn_valider_presences_72h_auto).
 *
 * Backend-driven sur la prod partagée : la mission est créée au futur
 * (dec_mission_passee bloque la création au passé) puis déplacée dans le passé
 * via fn_test_update_mission (helper test, même mécanique que la recette
 * escrow) pour poser une présence dont le départ date de plus de 72 h.
 * L'appel direct de la fonction reproduit ce que le cron fait toutes les 6 h :
 * l'effet de bord sur d'autres présences éligibles est exactement celui du
 * prochain tick du cron.
 */

const seededMissionIds: string[] = [];
let caregiver: EphemeralVerifiedCaregiver | undefined;

test.beforeAll(async () => {
  caregiver = await createEphemeralVerifiedCaregiver();
});

test.afterAll(async () => {
  const erreurs: string[] = [];

  // Toujours tenter les deux niveaux de cleanup : la purge ciblée retire la
  // mission et toute sa descendance, puis la fixture supprime son profil/Auth.
  // Aucun compte soignant fixe ni aucune donnée de démonstration n'est touché.
  for (const id of seededMissionIds.splice(0)) {
    try {
      await cleanupMissionCascade(id);
    } catch (error) {
      erreurs.push(
        `mission ${id}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  if (caregiver) {
    try {
      await caregiver.cleanup();
    } catch (error) {
      erreurs.push(
        `soignant éphémère: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  if (erreurs.length > 0) {
    throw new Error(`[cleanup auto-validation 72 h] ${erreurs.join(' | ')}`);
  }
});

test('fn_valider_presences_72h_auto — présence départ >72h → validée (audit écrit)', async () => {
  const admin = adminClient();
  if (!caregiver) throw new Error('Fixture soignant éphémère absente');

  const mission = await seedMission({
    intitule: `[pw-test:auto72h] ${Date.now()}`,
    tauxHoraire: 30,
    typeContratRecherche: 'SALARIE',
  });
  expect(mission, 'seedMission').toBeTruthy();
  if (!mission) throw new Error('Mission auto-validation non créée');
  seededMissionIds.push(mission.id);

  // Suit le cycle de vie réel : candidature salariée, acceptation par
  // l'établissement authentifié, puis signature bilatérale du contrat.
  const candidature = await seedCandidature(mission.id, caregiver.id, 'SALARIE');
  expect(candidature, 'seedCandidature').toBeTruthy();
  if (!candidature) throw new Error('Candidature auto-validation non créée');

  const etablissement = await userClient(
    TEST_ACCOUNTS.etab.email,
    TEST_ACCOUNTS.etab.password,
  );
  const { data: acceptation, error: acceptationError } = await etablissement.rpc(
    'fn_traiter_candidature' as any,
    {
      p_candidature_id: candidature.id,
      p_decision: 'ACCEPTEE',
    },
  );
  expect(
    acceptationError,
    `fn_traiter_candidature: ${acceptationError?.message}`,
  ).toBeNull();
  expect((acceptation as any)?.success, (acceptation as any)?.error).toBe(true);
  expect((acceptation as any)?.choix_applique).toBe('SALARIE');

  await seedContratMissionSigne(mission.id, caregiver, {
    etablissement,
  });

  // Mission déplacée 4 jours dans le passé (helper test — bypass protections),
  // puis présence pointée arrivée/départ il y a ~4 jours (départ > 72 h).
  const debut = new Date(Date.now() - 4 * 86400000);
  const fin = new Date(debut.getTime() + 8 * 3600000);
  const { error: eU } = await admin.rpc('fn_test_update_mission' as any, {
    p_mission_id: mission.id,
    p_data: { debut_le: debut.toISOString(), fin_le: fin.toISOString() },
  });
  expect(eU).toBeNull();

  const { data: missionPreparee, error: missionPrepareeError } = await admin
    .from('missions')
    .select('statut, soignant_assigne_id, type_contrat_applique, debut_le, fin_le')
    .eq('id', mission.id)
    .single();
  expect(missionPrepareeError).toBeNull();
  expect((missionPreparee as any)?.statut).toBe('ASSIGNEE');
  expect((missionPreparee as any)?.soignant_assigne_id).toBe(caregiver.id);
  expect((missionPreparee as any)?.type_contrat_applique).toBe('SALARIE');
  expect(new Date((missionPreparee as any)?.debut_le).getTime()).toBe(debut.getTime());
  expect(new Date((missionPreparee as any)?.fin_le).getTime()).toBe(fin.getTime());

  const { error: eP } = await admin.from('presences').insert({
    mission_id: mission.id, soignant_id: caregiver.id,
    pointage_arrivee_le: new Date(debut.getTime() + 5 * 60000).toISOString(),
    pointage_depart_le: fin.toISOString(),
    valide_par_etablissement: false,
  });
  expect(eP).toBeNull();

  // Exécute ce que le cron exécute.
  const { error: eRun } = await admin.rpc('fn_valider_presences_72h_auto' as any);
  expect(eRun).toBeNull();

  const { data: after } = await admin
    .from('presences')
    .select('valide_par_etablissement, valide_auto_72h_le')
    .eq('mission_id', mission.id)
    .single();
  expect((after as any).valide_par_etablissement).toBe(true);
  expect((after as any).valide_auto_72h_le).not.toBeNull();
});
