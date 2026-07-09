import { test, expect } from '@playwright/test';
import { adminClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';
import { seedMissionMatching } from '../helpers/seed-matching';
import { cleanupMissionCascade } from '../helpers/seed';

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

const seeded: string[] = [];

test.afterAll(async () => {
  const admin = adminClient();
  for (const id of seeded) {
    await admin.from('presences').delete().eq('mission_id', id);
    await cleanupMissionCascade(id);
  }
});

test('fn_valider_presences_72h_auto — présence départ >72h → validée (audit écrit)', async () => {
  const admin = adminClient();
  const soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
  expect(soignantId).toBeTruthy();

  const mission = await seedMissionMatching({ intitule: `[pw-test:auto72h] ${Date.now()}`, tauxHoraire: 30 });
  expect(mission).toBeTruthy();
  seeded.push(mission!.id);

  // Mission déplacée 4 jours dans le passé (helper test — bypass protections),
  // puis présence pointée arrivée/départ il y a ~4 jours (départ > 72 h).
  const debut = new Date(Date.now() - 4 * 86400000);
  const fin = new Date(debut.getTime() + 8 * 3600000);
  const { error: eU } = await admin.rpc('fn_test_update_mission' as any, {
    p_mission_id: mission!.id,
    p_data: { debut_le: debut.toISOString(), fin_le: fin.toISOString(), soignant_assigne_id: soignantId },
  });
  expect(eU).toBeNull();
  await admin.from('missions').update({ soignant_assigne_id: soignantId }).eq('id', mission!.id);

  const { error: eP } = await admin.from('presences').insert({
    mission_id: mission!.id, soignant_id: soignantId,
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
    .eq('mission_id', mission!.id)
    .single();
  expect((after as any).valide_par_etablissement).toBe(true);
  expect((after as any).valide_auto_72h_le).not.toBeNull();
});
