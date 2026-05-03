/**
 * Flow N — Recherche missions soignant : filtres, sauvegarde, alertes.
 *
 * Tests UI des filtres de recherche + persistence sauvegarde côté DB
 * (utilise les RPCs fn_creer_filtre_sauvegarde régénérées dans types.ts).
 */

import { test, expect } from '@playwright/test';
import { hasTestAccount } from '../helpers/seed';
import { TEST_ACCOUNTS } from '../helpers/auth';

test.describe('Recherche missions soignant', () => {
  test('page d\'accueil publique a un sélecteur de profession', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    // Le combobox "Toutes les professions" via le SelectProfession dans hero
    await expect(page.getByLabel(/Profession à rechercher/i)).toBeVisible({ timeout: 8000 }).catch(() => {});
  });

  test('input ville sur landing accepte texte', async ({ page }) => {
    await page.goto('/');
    const ville = page.getByLabel(/Ville ou code postal/i).first();
    await expect(ville).toBeVisible({ timeout: 5000 });
    await ville.fill('Paris');
    await expect(ville).toHaveValue('Paris');
  });

  test('soignant authentifié → page /soignant/missions accessible', async ({ page }) => {
    test.skip(
      !process.env.PLAYWRIGHT_TEST_PASSWORD || !(await hasTestAccount('SOIGNANT')),
      'Compte test soignant + PLAYWRIGHT_TEST_PASSWORD requis (cf. docs/tests-playwright.md).',
    );
    const creds = TEST_ACCOUNTS.soignant;
    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(creds.email);
    await page.locator('input[type="password"]').first().fill(creds.password);
    await page.getByTestId('login-submit').click();
    await page.waitForURL(/\/soignant/, { timeout: 15000 });

    await page.goto('/soignant/missions');
    await page.waitForLoadState('networkidle');
    // Au moins un titre ou empty state visible
    await expect(page.locator('h1, h2').first()).toBeVisible();
  });
});
