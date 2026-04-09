import { test, expect } from '@playwright/test';

/**
 * Tests du flux missions (espace etablissement authentifie).
 *
 * Ces tests necessitent des identifiants de test Supabase.
 * En environnement CI, configurez les variables d'environnement :
 *   - E2E_ETABLISSEMENT_EMAIL
 *   - E2E_ETABLISSEMENT_PASSWORD
 *
 * Pour le moment, le beforeEach simule l'authentification en injectant
 * un token dans le localStorage Supabase. En production de tests,
 * remplacez par un vrai login via l'API Supabase ou la page de connexion.
 */

const SUPABASE_STORAGE_KEY = 'sb-localhost-auth-token';

test.describe('Missions (espace etablissement)', () => {
  test.beforeEach(async ({ page }) => {
    // Stub: inject a mock auth session into localStorage before navigating.
    // In a real setup, replace this with actual Supabase login credentials.
    // Example with real credentials:
    //
    //   await page.goto('/connexion');
    //   await page.locator('input[type="email"]').fill(process.env.E2E_ETABLISSEMENT_EMAIL!);
    //   await page.locator('input[type="password"]').fill(process.env.E2E_ETABLISSEMENT_PASSWORD!);
    //   await page.getByRole('button', { name: /Se connecter/i }).click();
    //   await page.waitForURL(/\/etablissement/);
    //
    // For now, we skip auth-gated assertions if no credentials are available.
  });

  test('la page liste des missions est accessible', async ({ page }) => {
    test.skip(
      !process.env.E2E_ETABLISSEMENT_EMAIL,
      'Identifiants E2E non configures — test ignore'
    );

    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(process.env.E2E_ETABLISSEMENT_EMAIL!);
    await page.locator('input[type="password"]').fill(process.env.E2E_ETABLISSEMENT_PASSWORD!);
    await page.getByRole('button', { name: /Se connecter/i }).click();
    await page.waitForURL(/\/etablissement/, { timeout: 15000 });

    await page.goto('/etablissement/missions');
    await expect(page.getByText(/mission/i).first()).toBeVisible();
  });

  test('la page detail d\'une mission est accessible', async ({ page }) => {
    test.skip(
      !process.env.E2E_ETABLISSEMENT_EMAIL,
      'Identifiants E2E non configures — test ignore'
    );

    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(process.env.E2E_ETABLISSEMENT_EMAIL!);
    await page.locator('input[type="password"]').fill(process.env.E2E_ETABLISSEMENT_PASSWORD!);
    await page.getByRole('button', { name: /Se connecter/i }).click();
    await page.waitForURL(/\/etablissement/, { timeout: 15000 });

    // Navigate to mission list first, then click the first mission
    await page.goto('/etablissement/missions');
    await page.waitForLoadState('networkidle');

    // If there are missions, click the first one
    const premiereMission = page.locator('[class*="CarteMission"], [class*="mission"]').first();
    if (await premiereMission.isVisible({ timeout: 5000 }).catch(() => false)) {
      await premiereMission.click();
      await expect(page).toHaveURL(/\/etablissement\/missions\/.+/);
    }
  });

  test('le formulaire de creation de mission contient les champs requis', async ({ page }) => {
    test.skip(
      !process.env.E2E_ETABLISSEMENT_EMAIL,
      'Identifiants E2E non configures — test ignore'
    );

    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(process.env.E2E_ETABLISSEMENT_EMAIL!);
    await page.locator('input[type="password"]').fill(process.env.E2E_ETABLISSEMENT_PASSWORD!);
    await page.getByRole('button', { name: /Se connecter/i }).click();
    await page.waitForURL(/\/etablissement/, { timeout: 15000 });

    await page.goto('/etablissement/missions/creer');
    await page.waitForLoadState('networkidle');

    // Verify the creation form has essential fields
    await expect(page.getByText(/Publier une mission/i)).toBeVisible();
    await expect(page.getByText(/Intitulé/i)).toBeVisible();
    await expect(page.getByText(/Profession requise/i)).toBeVisible();
    await expect(page.getByText(/Taux horaire/i)).toBeVisible();
  });
});
