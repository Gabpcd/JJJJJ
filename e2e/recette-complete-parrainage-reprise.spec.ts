import { expect, test } from '@playwright/test';
import { aller, attendreAPI, entrer, ids, preuve, simulerSoignant } from './helpers/recette-complete-soignant';
import { ouvrirDossierDepuisMission, remplirIdentite, simulerCompletionSoignant, verifierRppsSimule } from './helpers/recette-complete-completion-soignant';

test('parrainage : code conservé pendant la découverte puis attribué après finalisation sans dashboard', async ({ page }, info) => {
  const { state } = await simulerCompletionSoignant(page);
  state.overrides.set('fn_appliquer_parrainage', { success: true });
  await aller(page, '/inscription/soignant?ref=LIEN-RECETTE');
  await expect(page.getByLabel('Email', { exact: true })).toBeVisible();
  await ouvrirDossierDepuisMission(page);
  expect(state.calls.filter(c => c.name === 'fn_appliquer_parrainage')).toHaveLength(0);
  await remplirIdentite(page); await verifierRppsSimule(page);
  await page.getByRole('button', { name: 'Enregistrer mon profil', exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/soignant/missions/${ids.mission}$`));
  await expect.poll(() => state.calls.filter(c => c.name === 'fn_appliquer_parrainage')).toHaveLength(1);
  expect(state.calls.find(c => c.name === 'fn_appliquer_parrainage')?.body).toEqual({ p_code: 'LIEN-RECETTE' });
  await preuve(page, 'parrainage-apres-profil-sans-dashboard', info, true);
  expect(await page.evaluate(() => sessionStorage.getItem('jolene.parrainage_code'))).toBeNull();
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});

test('parrainage : panne, déconnexion et reconnexion conservent puis appliquent le même code', async ({ page }, info) => {
  const state = await simulerSoignant(page);
  state.failures.add('fn_appliquer_parrainage');
  state.overrides.set('fn_appliquer_parrainage', { success: true });
  await aller(page, '/connexion?ref=REPRISE-RECETTE');
  await expect(page.getByLabel('Email', { exact: true })).toBeVisible();
  await entrer(page, 'connexion');
  await expect.poll(() => state.calls.filter(c => c.name === 'fn_appliquer_parrainage')).toHaveLength(1);
  expect(await page.evaluate(() => sessionStorage.getItem('jolene.parrainage_code'))).toBe('REPRISE-RECETTE');
  await aller(page, '/soignant/mon-compte');
  await page.locator('main').getByRole('button', { name: /déconnecter/i }).click();
  await expect(page).not.toHaveURL(/\/soignant\//);
  state.failures.delete('fn_appliquer_parrainage');
  const avantReconnexion = state.calls.filter(c => c.name === 'fn_appliquer_parrainage').length;
  await entrer(page, 'connexion');
  await attendreAPI(page);
  expect(state.calls.filter(c => c.name === 'fn_appliquer_parrainage')).toHaveLength(avantReconnexion + 1);
  expect(state.calls.filter(c => c.name === 'fn_appliquer_parrainage').at(-1)?.body).toEqual({ p_code: 'REPRISE-RECETTE' });
  expect(await page.evaluate(() => sessionStorage.getItem('jolene.parrainage_code'))).toBeNull();
  const apresSucces = state.calls.filter(c => c.name === 'fn_appliquer_parrainage').length;
  await aller(page, '/soignant/profil'); await attendreAPI(page);
  expect(state.calls.filter(c => c.name === 'fn_appliquer_parrainage')).toHaveLength(apresSucces);
  await preuve(page, 'parrainage-reconnexion-apres-panne', info, true);
  expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
});
