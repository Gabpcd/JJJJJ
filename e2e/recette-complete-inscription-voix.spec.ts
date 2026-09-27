import { expect, test } from '@playwright/test';
import { ouvrirDossierDepuisMission, remplirIdentite, simulerCompletionSoignant } from './helpers/recette-complete-completion-soignant';
import { aller, attendreAPI, preuve } from './helpers/recette-complete-soignant';

test('inscription : vouvoiement du dossier et de ses erreurs, retour libre à l’espace soignant', async ({ page }, info) => {
  const { state, completion } = await simulerCompletionSoignant(page);
  state.overrides.set('fn_types_exercice_autorises', ['SALARIE']);
  await page.goto('/inscription/soignant');
  await expect(page.getByRole('heading', { name: 'Créez votre compte.', exact: true })).toBeVisible();
  await expect(page.getByText('Découvrez les missions. Votre dossier professionnel se complète ensuite.', { exact: true })).toBeVisible();
  await attendreAPI(page);
  await ouvrirDossierDepuisMission(page);
  await expect(page.getByText('Votre profession ne peut pas exercer en libéral. Seuls CDD et Salarié sont disponibles.', { exact: true })).toBeVisible();
  await remplirIdentite(page);
  completion.professionRppsCorrespond = false;
  await page.getByPlaceholder(/^11 chiffres/).fill('10000000000');
  const alerte = page.getByRole('alert').filter({ hasText: 'Ce RPPS correspond à la profession' });
  await expect(alerte).toContainText('Vérifiez votre numéro ou votre profession.');
  await expect(page.getByRole('heading', { name: 'Vos informations professionnelles', exact: true })).toBeVisible();
  await expect(page.locator('form')).not.toContainText(/\b(?:[Tt]u|[Tt]on|[Tt]a|[Tt]es|[Tt]e)\b/);
  await page.getByRole('button', { name: 'Enregistrer mon profil', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'Vérifiez les informations suivantes' })).toContainText('cohérence du RPPS');
  expect(completion.soumissions).toEqual([]);
  await preuve(page, 'inscription-voix-vous-erreur-rpps', info, true);
  await aller(page, '/soignant/tableau-de-bord');
  await expect(page.locator('main')).toContainText(/Tes missions|tes missions|ton profil|ton compte|tu peux/);
  await preuve(page, 'espace-soignant-voix-conservee', info);
  expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]);
});
