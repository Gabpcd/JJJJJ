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
 * (dec_mission_passee bloque la création au passé), puis son unique créneau
 * PREVISIONNEL est daté dans le passé avant toute candidature. La
 * synchronisation canonique des créneaux dérive alors l'enveloppe de la mission
 * avant son gel : aucun champ contractuel n'est modifié après l'acceptation.
 * Un créneau EFFECTIF fermé matérialise ensuite le pointage réel dont le départ
 * date de plus de 72 h.
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
  // La purge d'une mission gelée traverse volontairement toute sa descendance
  // financière, contractuelle et Auth sur la base distante. Elle doit pouvoir
  // terminer proprement même lorsque Supabase répond lentement, sans provoquer
  // un retry du scénario métier déjà réussi.
  test.setTimeout(90_000);

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
  // Cycle d'intégration distant complet : mission et planning historiques,
  // candidature, acceptation, contrat signé, présence, cron et audit. À 30 s,
  // Playwright pouvait lancer le teardown pendant une écriture encore en vol,
  // puis la purge rendait artificiellement la mission « non affectée ».
  test.slow();

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

  // Le seed doit d'abord publier au futur. Avant de créer la candidature (qui
  // gèle le planning), on date le créneau exact quatre jours dans le passé.
  // trg_sync_creneaux recalcule debut_le/fin_le/nb_creneaux sur la mission : le
  // test n'a donc aucun besoin de contourner le gel après acceptation.
  const debut = new Date(Date.now() - 4 * 86400000);
  const fin = new Date(debut.getTime() + 8 * 3600000);
  const arrivee = new Date(debut.getTime() + 5 * 60000);
  const { data: planningHistorique, error: planningHistoriqueError } = await admin
    .from('mission_creneaux')
    .update({ debut: debut.toISOString(), fin: fin.toISOString() })
    .eq('mission_id', mission.id)
    .eq('type_creneau', 'PREVISIONNEL')
    .eq('est_pause', false)
    .select('id, debut, fin, ordre');
  expect(
    planningHistoriqueError,
    `planning historique: ${planningHistoriqueError?.message}`,
  ).toBeNull();
  expect(planningHistorique, 'un unique créneau PREVISIONNEL historique').toHaveLength(1);
  expect(new Date((planningHistorique as any[])[0].debut).getTime()).toBe(debut.getTime());
  expect(new Date((planningHistorique as any[])[0].fin).getTime()).toBe(fin.getTime());
  const ordreEffectif = Math.max(
    ...(planningHistorique as Array<{ ordre: number }>).map(({ ordre }) => ordre),
  ) + 1;

  const { data: missionAvantGel, error: missionAvantGelError } = await admin
    .from('missions')
    .select('debut_le, fin_le, nb_creneaux')
    .eq('id', mission.id)
    .single();
  expect(missionAvantGelError).toBeNull();
  expect(new Date((missionAvantGel as any)?.debut_le).getTime()).toBe(debut.getTime());
  expect(new Date((missionAvantGel as any)?.fin_le).getTime()).toBe(fin.getTime());
  expect((missionAvantGel as any)?.nb_creneaux).toBe(1);

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

  const { data: missionPreparee, error: missionPrepareeError } = await admin
    .from('missions')
    .select('statut, soignant_assigne_id, type_contrat_applique, debut_le, fin_le, nb_creneaux')
    .eq('id', mission.id)
    .single();
  expect(missionPrepareeError).toBeNull();
  expect((missionPreparee as any)?.statut).toBe('ASSIGNEE');
  expect((missionPreparee as any)?.soignant_assigne_id).toBe(caregiver.id);
  expect((missionPreparee as any)?.type_contrat_applique).toBe('SALARIE');
  expect(new Date((missionPreparee as any)?.debut_le).getTime()).toBe(debut.getTime());
  expect(new Date((missionPreparee as any)?.fin_le).getTime()).toBe(fin.getTime());
  expect((missionPreparee as any)?.nb_creneaux).toBe(1);

  // Le segment EFFECTIF fermé représente le pointage réel. Il reste
  // modifiable après l'acceptation, contrairement au planning PREVISIONNEL
  // contractuel, et permet au garde de validation de constater un départ fini.
  const { data: planningEffectif, error: planningEffectifError } = await admin
    .from('mission_creneaux')
    .insert({
      mission_id: mission.id,
      debut: arrivee.toISOString(),
      fin: fin.toISOString(),
      est_pause: false,
      // Même stratégie que fn_scanner_code_pointage : l'ordre est unique pour
      // toute la mission, indépendamment de PREVISIONNEL/EFFECTIF.
      ordre: ordreEffectif,
      type_creneau: 'EFFECTIF',
    })
    .select('id, debut, fin')
    .single();
  expect(
    planningEffectifError,
    `planning effectif: ${planningEffectifError?.message}`,
  ).toBeNull();
  expect(new Date((planningEffectif as any)?.debut).getTime()).toBe(arrivee.getTime());
  expect(new Date((planningEffectif as any)?.fin).getTime()).toBe(fin.getTime());

  const { error: eP } = await admin.from('presences').insert({
    mission_id: mission.id, soignant_id: caregiver.id,
    pointage_arrivee_le: arrivee.toISOString(),
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
