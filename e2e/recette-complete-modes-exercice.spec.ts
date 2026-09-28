import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { simulerCompletionSoignant, ouvrirDossierDepuisMission } from './helpers/recette-complete-completion-soignant';
import { simulerSoignant, entrer, aller, attendreAPI, sansDebordement } from './helpers/recette-complete-soignant';

const salarie = (page: Page) => page.getByRole('checkbox', { name: 'Salarié (CDD compris)', exact: true });
const liberal = (page: Page) => page.getByRole('checkbox', { name: 'Libéral', exact: true });
async function capture(page: Page, nom: string, info: TestInfo) {
  await attendreAPI(page);
  await sansDebordement(page);
  const dossier = process.env.RECETTE_DIR ? `${process.env.RECETTE_DIR}/${info.project.name}` : info.outputPath('preuves');
  await mkdir(dossier, { recursive: true });
  await writeFile(`${dossier}/${nom}.txt`, await page.locator('body').ariaSnapshot());
  await page.screenshot({ path: `${dossier}/${nom}.png`, fullPage: true, animations: 'disabled' });
}

test('modes : inscription rapide libre, choix des deux modes, brouillon et profession salariée', async ({ page }, info) => {
  const { state, completion } = await simulerCompletionSoignant(page);
  await ouvrirDossierDepuisMission(page);
  await salarie(page).check(); await liberal(page).check();
  await expect(page.getByRole('checkbox', { name: 'Contrat à Durée Déterminée (CDD)', exact: true })).toHaveCount(0);
  await capture(page, 'dossier-deux-modes', info);
  state.failures.add('fn_enregistrer_parcours_inscription');
  await page.getByRole('button', { name: 'Enregistrer et continuer plus tard', exact: true }).click();
  await expect(page.getByRole('alert')).toBeVisible();
  await expect(salarie(page)).toBeChecked(); await expect(liberal(page)).toBeChecked();
  state.failures.delete('fn_enregistrer_parcours_inscription');
  await page.getByRole('button', { name: 'Enregistrer et continuer plus tard', exact: true }).click();
  await expect(page).toHaveURL(/\/soignant\/recherche-missions$/);
  expect(completion.soumissions).toEqual([]); expect(state.mode).toBe('minimal');
  await ouvrirDossierDepuisMission(page, false);
  await expect(salarie(page)).toBeChecked(); await expect(liberal(page)).toBeChecked();
  state.overrides.set('fn_types_exercice_autorises', ['SALARIE']);
  await page.getByRole('combobox', { name: 'Profession *', exact: true }).click();
  await page.getByTestId('profession-option-AS').click();
  await expect(page.getByText('Le mode libéral n’est pas proposé pour votre profession sur Jolene. Le mode salarié comprend les CDD et les CDD courts.', { exact: true })).toBeVisible();
  await expect(salarie(page)).toBeChecked(); await expect(liberal(page)).toHaveCount(0);
  await capture(page, 'dossier-aide-soignante', info);
  expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]);
});

for (const profession of ['AS', 'IDE']) test(`modes : profil ${profession}, contrat historique conservé et reprise après erreur`, async ({ page }, info) => {
  const state = await simulerSoignant(page);
  Object.assign(state.profile, { profession, types_contrat_acceptes: 'CDD,VACATION', annees_experience: 2 });
  state.overrides.set('fn_types_exercice_autorises', profession === 'AS' ? ['SALARIE'] : ['SALARIE', 'LIBERAL', 'MIXTE']);
  await entrer(page, 'connexion');
  await aller(page, '/soignant/profil?tab=preferences');
  await expect(salarie(page)).toBeChecked();
  if (profession === 'IDE') await liberal(page).check();
  else await expect(liberal(page)).toHaveCount(0);
  const contrats = profession === 'IDE' ? ['CDD', 'VACATION', 'LIBERAL'] : ['CDD', 'VACATION'];
  state.failures.add('fn_modifier_mon_profil');
  await page.getByRole('button', { name: 'Enregistrer les modifications', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'Une erreur est survenue. Veuillez réessayer.' })).toBeVisible();
  await expect(salarie(page)).toBeChecked();
  state.failures.delete('fn_modifier_mon_profil');
  await page.getByRole('button', { name: 'Enregistrer les modifications', exact: true }).click();
  await expect(page.getByText('Profil mis à jour avec succès !', { exact: true }).first()).toBeVisible();
  expect(state.calls.filter(c => c.name === 'fn_modifier_mon_profil' && c.body?.p_types_contrat).at(-1)?.body.p_types_contrat).toEqual(contrats);
  await aller(page, '/soignant/profil?tab=preferences');
  await expect(salarie(page)).toBeChecked();
  if (profession === 'IDE') await expect(liberal(page)).toBeChecked();
  await capture(page, `profil-${profession}-historique-conserve`, info);
  expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]);
});

test('modes : PSC facultatif, préférences restaurées, référentiel indisponible puis récupéré', async ({ page }, info) => {
  const state = await simulerSoignant(page);
  state.profile.types_contrat_acceptes = 'VACATION';
  state.overrides.set('fn_accepter_cgu_decouverte_soignant', { ok: true });
  await entrer(page, 'connexion');
  state.failures.add('fn_types_exercice_autorises');
  await aller(page, '/inscription/soignant/completion');
  await page.getByRole('checkbox', { name: /J'accepte les/ }).check();
  await expect(page.getByRole('button', { name: 'Découvrir les missions', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Personnaliser mes préférences (facultatif)', exact: true }).click();
  await expect(salarie(page)).toBeChecked(); await expect(liberal(page)).toHaveCount(0);
  await expect(page.getByRole('status')).toContainText('Vérification temporairement indisponible');
  await capture(page, 'psc-erreur-referentiel-choix-conserve', info);
  state.failures.delete('fn_types_exercice_autorises');
  await page.getByRole('button', { name: 'Réessayer la vérification', exact: true }).click();
  await liberal(page).check(); await expect(salarie(page)).toBeChecked();
  state.failures.add('soignants');
  await page.getByRole('button', { name: 'Découvrir les missions', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'Une erreur est survenue. Veuillez réessayer.' })).toBeVisible();
  await expect(salarie(page)).toBeChecked(); await expect(liberal(page)).toBeChecked();
  state.failures.delete('soignants');
  await page.getByRole('button', { name: 'Découvrir les missions', exact: true }).click();
  await expect(page).toHaveURL(/\/soignant\/recherche-missions$/);
  expect(state.profile.types_contrat_acceptes).toBe('VACATION,LIBERAL');
  await aller(page, '/inscription/soignant/completion');
  await page.getByRole('button', { name: 'Personnaliser mes préférences (facultatif)', exact: true }).click();
  await expect(salarie(page)).toBeChecked(); await expect(liberal(page)).toBeChecked();
  await capture(page, 'psc-deux-modes-restaures', info);
  // Continuer sans personnaliser ne doit envoyer aucune écriture de préférences.
  await page.getByRole('button', { name: 'Compléter mes préférences plus tard', exact: true }).click();
  await page.getByRole('checkbox', { name: /J'accepte les/ }).check();
  const ecritures = state.calls.filter(c => c.name === 'soignants' && c.method === 'PATCH').length;
  await page.getByRole('button', { name: 'Découvrir les missions', exact: true }).click();
  await expect(page).toHaveURL(/\/soignant\/recherche-missions$/);
  expect(state.calls.filter(c => c.name === 'soignants' && c.method === 'PATCH')).toHaveLength(ecritures);
  expect(state.errors).toEqual([]); expect(state.unknown).toEqual([]);
});
