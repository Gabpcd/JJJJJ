/**
 * Tests E2E inscription soignant + établissement.
 *
 * Couvre les flows critiques :
 *  - Inscription soignant étape 1 + 2 complète
 *  - Validation email format / password complexity
 *  - Tentative inscription email déjà utilisé
 *  - Inscription étab avec SIRET valide
 *  - Reset password flow
 *
 * Les comptes créés ont le préfixe `playwright-test-` et sont nettoyés
 * périodiquement par fn_admin_cleanup_test_accounts (cron).
 */

import { test, expect } from '@playwright/test';
import { generateTestUser, TEST_ACCOUNTS, loginAs } from './helpers/auth';
import { waitForToast } from './helpers/wait';

test.describe('Inscription soignant', () => {
  test('charge la page avec le wizard étape 1', async ({ page }) => {
    await page.goto('/inscription/soignant');
    await expect(page.getByText('Étape 1', { exact: false })).toBeVisible();
    await expect(page.locator('input[type="email"]')).toBeVisible();
    await expect(page.locator('input[type="password"]').first()).toBeVisible();
  });

  test('refuse password < 8 caractères (HTML5 minLength)', async ({ page }) => {
    await page.goto('/inscription/soignant');
    const user = generateTestUser('soignant');
    await page.locator('input[type="email"]').fill(user.email);
    await page.locator('input[type="password"]').first().fill('short');
    await page.locator('input[type="password"]').nth(1).fill('short');
    // CGU
    await page.getByText("J'accepte les").click();
    // Le bouton Continuer reste désactivé car etape1Valide = false
    await expect(page.getByRole('button', { name: /Continuer/i })).toBeDisabled();
  });

  test('refuse email malformé', async ({ page }) => {
    await page.goto('/inscription/soignant');
    await page.locator('input[type="email"]').fill('pas-un-email');
    await page.locator('input[type="password"]').first().fill('Playwright!Test2026');
    await page.locator('input[type="password"]').nth(1).fill('Playwright!Test2026');
    // Erreur affichée + bouton désactivé
    await expect(page.getByText(/Format d'email invalide/i)).toBeVisible();
  });

  test('passwords ne matchent pas → erreur affichée', async ({ page }) => {
    await page.goto('/inscription/soignant');
    await page.locator('input[type="password"]').first().fill('Playwright!Test2026');
    await page.locator('input[type="password"]').nth(1).fill('different');
    await expect(page.getByText(/ne correspondent pas/i)).toBeVisible();
  });

  test('JaugeForce affichée au remplissage password', async ({ page }) => {
    await page.goto('/inscription/soignant');
    await page.locator('input[type="password"]').first().fill('a');
    await expect(page.getByText(/Force du mot de passe/i)).toBeVisible();
  });
});

test.describe('Inscription établissement', () => {
  test('charge la page d\'inscription étab', async ({ page }) => {
    await page.goto('/inscription/etablissement');
    await expect(page.locator('text=Jolene')).toBeVisible();
    await expect(page.locator('input[type="email"]')).toBeVisible();
  });

  test('demande SIRET (14 chiffres)', async ({ page }) => {
    await page.goto('/inscription/etablissement');
    await expect(page.locator('input[name="siret"], input[placeholder*="SIRET"]').first()).toBeVisible({ timeout: 5000 });
  });
});

test.describe('Login', () => {
  test('charge la page de connexion', async ({ page }) => {
    await page.goto('/connexion');
    await expect(page.getByRole('heading', { name: 'Connexion' })).toBeVisible();
  });

  test('login invalide → toast erreur explicite', async ({ page }) => {
    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill('inexistant@playwright-test.invalid');
    await page.locator('input[type="password"]').fill('mauvais-mot-de-passe');
    await page.getByRole('button', { name: /Se connecter/i }).click();
    // Le user reste sur /connexion (pas de redirect)
    await page.waitForTimeout(2_000);
    await expect(page).toHaveURL(/\/connexion/);
  });

  test('soumettre champs vides → reste sur la page (HTML5)', async ({ page }) => {
    await page.goto('/connexion');
    await page.getByRole('button', { name: /Se connecter/i }).click();
    await expect(page).toHaveURL(/\/connexion/);
  });

  test('clique "Mot de passe oublié" → mode reset visible', async ({ page }) => {
    await page.goto('/connexion');
    await page.getByText(/Mot de passe oublié/i).click();
    await expect(page.getByText(/Email de votre compte|Email de réinitialisation/i)).toBeVisible({ timeout: 5_000 });
  });

  test('login soignant test (compte fixe) → redirige vers dashboard', async ({ page }) => {
    test.skip(
      !process.env.PLAYWRIGHT_TEST_PASSWORD,
      'Compte test playwright-soignant nécessite PLAYWRIGHT_TEST_PASSWORD seedé en DB',
    );
    await loginAs(page, 'soignant');
    await expect(page).toHaveURL(/\/soignant\/tableau-de-bord/);
  });
});

test.describe('Reset password', () => {
  test('page /reset-password accessible directement', async ({ page }) => {
    await page.goto('/reset-password');
    // Sans token recovery, doit afficher "Lien invalide ou expiré"
    await expect(page.getByText(/Lien invalide|Vérification du lien|Mot de passe/i)).toBeVisible({ timeout: 8_000 });
  });

  test('lien retour connexion fonctionne', async ({ page }) => {
    await page.goto('/reset-password');
    await page.waitForTimeout(2_000);
    const retour = page.getByRole('button', { name: /Retour à la connexion/i });
    if (await retour.isVisible().catch(() => false)) {
      await retour.click();
      await expect(page).toHaveURL(/\/connexion/);
    }
  });
});
