/**
 * Visual regression tests — capture screenshots des pages critiques et
 * compare aux baselines committées dans `e2e/visual.spec.ts-snapshots/`.
 *
 * Tolérance : `maxDiffPixels: 200` + `threshold: 0.15` pour absorber le
 * jitter d'antialiasing entre runs CI.
 *
 * Génération des baselines :
 *   1. Lancer le workflow `playwright-visual-update.yml` (workflow_dispatch)
 *   2. Le workflow run `npx playwright test e2e/visual --update-snapshots`
 *      sur Chromium et commit les screenshots via PR auto.
 *   3. Merger la PR.
 *
 * En local : `npx playwright test e2e/visual --update-snapshots --project=chromium`
 *
 * En CI (sans baseline) : le test échoue avec "missing snapshot" — c'est
 * le signal pour générer.
 */

import { test, expect } from '@playwright/test';

test.describe('Visual regression — pages critiques', () => {
  // Skip sur projets non-chromium : les baselines sont générées sur Chromium uniquement
  test.beforeEach((_fixtures, testInfo) => {
    test.skip(testInfo.project.name !== 'chromium', 'Visual regression : Chromium uniquement');
  });

const SNAPSHOT_OPTIONS = {
  maxDiffPixels: 200,
  threshold: 0.15,
  fullPage: false, // viewport seulement, plus stable
  animations: 'disabled' as const,
};

  test('landing /', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveScreenshot('landing.png', SNAPSHOT_OPTIONS);
  });

  test('connexion', async ({ page }) => {
    await page.goto('/connexion');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveScreenshot('connexion.png', SNAPSHOT_OPTIONS);
  });

  test('inscription soignant étape 1', async ({ page }) => {
    await page.goto('/inscription/soignant');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveScreenshot('inscription-soignant-etape1.png', SNAPSHOT_OPTIONS);
  });

  test('inscription établissement étape 1', async ({ page }) => {
    await page.goto('/inscription/etablissement');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveScreenshot('inscription-etablissement-etape1.png', SNAPSHOT_OPTIONS);
  });

  test('aide', async ({ page }) => {
    await page.goto('/aide');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveScreenshot('aide.png', SNAPSHOT_OPTIONS);
  });

  test('accessibilité (page déclaration)', async ({ page }) => {
    await page.goto('/accessibilite');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveScreenshot('accessibilite.png', SNAPSHOT_OPTIONS);
  });

  test('reset password (état lien invalide)', async ({ page }) => {
    await page.goto('/reset-password');
    await page.waitForTimeout(2500); // attendre la décision recovery session
    await expect(page).toHaveScreenshot('reset-password.png', SNAPSHOT_OPTIONS);
  });

  test('404', async ({ page }) => {
    await page.goto('/cette-page-nexiste-pas');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveScreenshot('404.png', SNAPSHOT_OPTIONS);
  });
});
