import { expect, test } from '@playwright/test';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids, preuveMission } from './helpers/recette-complete-mission';

test('Blocage : panne, reprise et rechargement sans faux statut ni erreur JavaScript', async ({ context, page }, info) => {
  const { state, installer } = creerSuiviSimule();
  state.mission.statut = 'TERMINEE';
  state.mission.soignant_assigne_id = ids.soignant;
  state.contratCree = true;
  await installer(context, 'SOIGNANT');
  let lecture = 0;
  let signalerLectureSuspendue!: () => void;
  const lectureSuspendue = new Promise<void>(resolve => { signalerLectureSuspendue = resolve; });
  let reprendreLecture!: () => void;
  const reprise = new Promise<void>(resolve => { reprendreLecture = resolve; });
  await context.route('**/rest/v1/rpc/fn_est_bloque', async route => {
    lecture++;
    if (lecture === 1) return route.abort('failed');
    if (lecture === 3) { signalerLectureSuspendue(); await reprise; return route.abort('aborted').catch(() => {}); }
    return route.fulfill({ status: 200, contentType: 'application/json', body: 'true' });
  });
  await context.route('**/rest/v1/rpc/fn_debloquer_utilisateur', route => route.abort('failed'));
  const erreurs: string[] = [];
  page.on('pageerror', error => erreurs.push(error.message));
  const url = `/soignant/missions/${ids.mission}`;
  await page.goto(url);
  await expect(page.getByText('Statut de blocage indisponible.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Bloquer', exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Réessayer le statut de blocage' }).click();
  const debloquer = page.getByRole('button', { name: 'Débloquer', exact: true });
  await expect(debloquer).toBeVisible();
  await debloquer.click();
  await expect(page.getByText(/Action impossible pour le moment/)).toBeVisible();
  await expect(debloquer).toBeEnabled();
  await page.reload();
  await lectureSuspendue;
  await page.reload();
  reprendreLecture();
  await expect(debloquer).toBeVisible();
  expect(erreurs).toEqual([]);
  expect(state.errors).toEqual([]);
  await preuveMission(page, info, 'blocage-reprise-apres-panne-et-rechargement');
});
