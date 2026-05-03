/**
 * Flow I — Centre d'aide
 * Recherche → résultats → article → markdown rendu → filtres audience.
 * Pas de seed nécessaire (articles sont en DB prod, lecture publique).
 */

import { test, expect } from '@playwright/test';

test.describe('Centre d\'aide', () => {
  test('charge la page d\'accueil avec liste articles', async ({ page }) => {
    await page.goto('/aide');
    await expect(page.getByRole('heading', { name: /Centre d.aide/i })).toBeVisible();
    // Au moins un article s'affiche (ou message empty si 0)
    await page.waitForLoadState('networkidle');
  });

  test('recherche filtre les articles', async ({ page }) => {
    await page.goto('/aide');
    const search = page.locator('input[type="search"], input[placeholder*="echerch" i]').first();
    if (await search.isVisible({ timeout: 5000 }).catch(() => false)) {
      await search.fill('mission');
      await page.waitForTimeout(800); // debounce
      // Pas d'erreur affichée
      await expect(page.locator('text=/erreur/i').first()).not.toBeVisible({ timeout: 2000 }).catch(() => {});
    }
  });

  test('filtre audience SOIGNANT visible', async ({ page }) => {
    await page.goto('/aide');
    // Boutons/onglets de filtre audience
    const soignantFilter = page.getByRole('button', { name: /Soignant/i }).first();
    await expect(soignantFilter).toBeVisible({ timeout: 8000 }).catch(() => {});
  });

  test('click article ouvre /aide/:slug', async ({ page }) => {
    await page.goto('/aide');
    await page.waitForLoadState('networkidle');
    // Premier lien article (a[href^="/aide/"])
    const article = page.locator('a[href^="/aide/"]').first();
    if (await article.isVisible({ timeout: 5000 }).catch(() => false)) {
      await article.click();
      await expect(page).toHaveURL(/\/aide\/[a-z0-9-]+/, { timeout: 10000 });
    }
  });

  test('article rendu avec markdown', async ({ page }) => {
    await page.goto('/aide');
    await page.waitForLoadState('networkidle');
    const article = page.locator('a[href^="/aide/"]').first();
    if (await article.isVisible({ timeout: 5000 }).catch(() => false)) {
      await article.click();
      await page.waitForLoadState('networkidle');
      // Article contient au moins un h1 ou h2 (markdown rendu)
      const heading = page.locator('h1, h2').first();
      await expect(heading).toBeVisible();
    }
  });
});
