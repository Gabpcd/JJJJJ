import { test, expect } from '@playwright/test';

test.describe('Authentification', () => {
  test.describe('Page de connexion', () => {
    test.beforeEach(async ({ page }) => {
      await page.goto('/connexion');
    });

    test('charge la page de connexion correctement', async ({ page }) => {
      await expect(page.getByRole('heading', { name: 'Connexion' })).toBeVisible();
      // Le mot "Jolene" apparaît plusieurs fois (logo + footer) → .first() est intentionnel
      await expect(page.getByText('Jolene').first()).toBeVisible();
    });

    test('affiche les champs email et mot de passe', async ({ page }) => {
      await expect(page.locator('input[type="email"]')).toBeVisible();
      // Plusieurs inputs password (form connexion + reset si visible) → first()
      await expect(page.locator('input[type="password"]').first()).toBeVisible();
    });

    test('affiche le bouton de soumission', async ({ page }) => {
      // data-testid évite l'ambiguïté avec "Se connecter avec Pro Santé Connect"
      await expect(page.getByTestId('login-submit')).toBeVisible();
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
      await page.locator('input[type="password"]').first().fill('motdepassefaux');
      await page.getByTestId('login-submit').click();

      // Sonner toast or notification should appear with an error
      const erreur = page.locator('[data-sonner-toast][data-type="error"], [role="status"]');
      await expect(erreur.first()).toBeVisible({ timeout: 10000 });
    });

    test('soumettre sans remplir les champs affiche une erreur', async ({ page }) => {
      await page.getByTestId('login-submit').click();
      // HTML5 validation ou notif app empêche soumission → reste sur /connexion
      await expect(page).toHaveURL(/\/connexion/);
    });
  });

  test.describe('Page inscription soignant', () => {
    test('charge la page d\'inscription soignant', async ({ page }) => {
      await page.goto('/inscription/soignant');
      await expect(page.getByText('Jolene').first()).toBeVisible();
      await expect(page.locator('input[type="email"]')).toBeVisible();
    });
  });

  test.describe('Page inscription etablissement', () => {
    test('charge la page d\'inscription etablissement', async ({ page }) => {
      await page.goto('/inscription/etablissement');
      await expect(page.getByText('Jolene').first()).toBeVisible();
      await expect(page.locator('input[type="email"]')).toBeVisible();
    });
  });
});
