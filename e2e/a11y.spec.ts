/**
 * Tests d'accessibilité automatisés via axe-core.
 *
 * Audit WCAG 2.1 AA (tags wcag2a, wcag2aa, wcag21a, wcag21aa).
 * Les violations CRITIQUES et SÉRIEUSES font échouer le test.
 * Les violations MODÉRÉES et MINEURES sont loggées en warning (non-bloquant).
 *
 * Pour ajouter une page : un test 'page X — axe a11y'.
 */

import { test, expect } from '@playwright/test';
import { runAxe, expectNoCriticalA11y } from './helpers/axe';

test.describe('Accessibilité — pages publiques', () => {
  test('/ landing — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');
    const results = await runAxe(page);
    expectNoCriticalA11y(results, testInfo);
  });

  test('/connexion — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
    await page.goto('/connexion');
    await page.waitForLoadState('domcontentloaded');
    const results = await runAxe(page);
    expectNoCriticalA11y(results, testInfo);
  });

  test('/reset-password — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
    await page.goto('/reset-password');
    // Attendre que la décision recovery session arrive (loading initial)
    await page.waitForTimeout(2_000);
    const results = await runAxe(page);
    expectNoCriticalA11y(results, testInfo);
  });

  test('/inscription/soignant — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
    await page.goto('/inscription/soignant');
    await page.waitForLoadState('domcontentloaded');
    const results = await runAxe(page);
    expectNoCriticalA11y(results, testInfo);
  });

  test('/inscription/etablissement — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
    await page.goto('/inscription/etablissement');
    await page.waitForLoadState('domcontentloaded');
    const results = await runAxe(page);
    expectNoCriticalA11y(results, testInfo);
  });

  test('/inscription/succes — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
    await page.goto('/inscription/succes?role=soignant');
    await page.waitForLoadState('domcontentloaded');
    const results = await runAxe(page);
    expectNoCriticalA11y(results, testInfo);
  });

  test('/aide — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
    await page.goto('/aide');
    await page.waitForLoadState('networkidle');
    const results = await runAxe(page);
    expectNoCriticalA11y(results, testInfo);
  });

  test('/accessibilite — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
    await page.goto('/accessibilite');
    await page.waitForLoadState('domcontentloaded');
    const results = await runAxe(page);
    expectNoCriticalA11y(results, testInfo);
  });

  test('/404 — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
    await page.goto('/cette-page-nexiste-pas');
    await page.waitForLoadState('domcontentloaded');
    const results = await runAxe(page);
    expectNoCriticalA11y(results, testInfo);
  });
});

test.describe('Accessibilité — skip-to-content', () => {
  test('skip-to-content link visible au focus', async ({ page }) => {
    await page.goto('/');
    // Pressé Tab une fois → le skip link doit recevoir focus
    await page.keyboard.press('Tab');
    const skipLink = page.locator('.skip-to-content');
    await expect(skipLink).toBeFocused();
    await expect(skipLink).toHaveText(/Aller au contenu principal/i);
  });
});
