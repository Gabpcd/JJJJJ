import { test, expect } from '@playwright/test';

test.describe('Authentification', () => {
  test.describe('Page de connexion', () => {
    test.beforeEach(async ({ page }) => {
      await page.goto('/connexion');
    });

    test('charge la page de connexion correctement', async ({ page }) => {
      await expect(page.getByRole('heading', { name: 'Connexion' })).toBeVisible();
      await expect(page.locator('text=Jolene')).toBeVisible();
    });

    test('affiche les champs email et mot de passe', async ({ page }) => {
      await expect(page.locator('input[type="email"]')).toBeVisible();
      await expect(page.locator('input[type="password"]')).toBeVisible();
    });

    test('affiche le bouton de soumission', async ({ page }) => {
      await expect(page.getByRole('button', { name: /Se connecter/i })).toBeVisible();
    });

    test('affiche les liens d\'inscription soignant et etablissement', async ({ page }) => {
      await expect(page.getByRole('button', { name: /Créer un compte soignant/i })).toBeVisible();
      await expect(page.getByRole('button', { name: /Créer un compte établissement/i })).toBeVisible();
    });

    test('affiche le lien mot de passe oublie', async ({ page }) => {
      await expect(page.getByText('Mot de passe oublié')).toBeVisible();
    });

    test('une connexion invalide affiche un message d\'erreur', async ({ page }) => {
      await page.locator('input[type="email"]').fill('faux@exemple.fr');
      await page.locator('input[type="password"]').fill('motdepassefaux');
      await page.getByRole('button', { name: /Se connecter/i }).click();

      // Sonner toast or notification should appear with an error
      const erreur = page.locator('[data-sonner-toast][data-type="error"], [role="status"]');
      await expect(erreur.first()).toBeVisible({ timeout: 10000 });
    });

    test('soumettre sans remplir les champs affiche une erreur', async ({ page }) => {
      await page.getByRole('button', { name: /Se connecter/i }).click();

      // The HTML5 validation or app-level notification should prevent submission
      // Check that we are still on the login page
      await expect(page).toHaveURL(/\/connexion/);
    });
  });

  test.describe('Page inscription soignant', () => {
    test('charge la page d\'inscription soignant', async ({ page }) => {
      await page.goto('/inscription/soignant');
      await expect(page.locator('text=Jolene')).toBeVisible();
      // The signup form should have an email field
      await expect(page.locator('input[type="email"]')).toBeVisible();
    });
  });

  test.describe('Page inscription etablissement', () => {
    test('charge la page d\'inscription etablissement', async ({ page }) => {
      await page.goto('/inscription/etablissement');
      await expect(page.locator('text=Jolene')).toBeVisible();
      // The signup form should have an email field
      await expect(page.locator('input[type="email"]')).toBeVisible();
    });
  });
});
