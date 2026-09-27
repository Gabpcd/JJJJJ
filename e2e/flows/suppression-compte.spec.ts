import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';

// La suppression effective avec le service utilisateur est dans staging/comptes.spec.ts.
// Cette suite partagée ne supprime aucun compte et ne remplace jamais l'action
// utilisateur par auth.admin.deleteUser sous un titre trompeur.
test('le compte connecté accède à la confirmation réelle de suppression et peut annuler', async ({ page }) => {
  await loginAs(page, 'soignant');
  await page.goto('/soignant/profil?tab=confidentialite#suppression-compte');
  await expect(page.getByRole('heading', { name: 'Suppression de compte', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Supprimer mon compte', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Supprimer définitivement' })).toBeDisabled();
  await page.getByPlaceholder('Tape SUPPRIMER').fill('SUPPRIMER');
  await expect(page.getByRole('button', { name: 'Supprimer définitivement' })).toBeEnabled();
  await page.getByRole('button', { name: 'Annuler', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Supprimer définitivement' })).toHaveCount(0);
});
