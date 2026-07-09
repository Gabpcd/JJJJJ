import { test, expect } from '@playwright/test';

/**
 * Non-régression mobile (projet `mobile-non-regression`, 390×844 tactile).
 *
 * Cible les régressions UX Safari iOS documentées dans CLAUDE.md (« Pièges
 * Safari iOS mobile ») : débordement horizontal parasite et inputs < 16px
 * (qui déclenchent le zoom auto au focus). Pages publiques uniquement —
 * aucun compte, aucun seed.
 *
 * Lancer : npm run test:e2e:regression
 */

test.describe('non-régression mobile — pages publiques', () => {
  test('accueil : rendu sans scroll horizontal', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('body')).toBeVisible();
    const debordement = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(debordement).toBeLessThanOrEqual(0);
  });

  test('connexion : inputs ≥ 16px (anti zoom auto iOS)', async ({ page }) => {
    await page.goto('/connexion');
    const email = page.locator('input[type="email"], input[name="email"]').first();
    await expect(email).toBeVisible();
    const taillePx = await email.evaluate(
      (el) => parseFloat(getComputedStyle(el).fontSize),
    );
    expect(taillePx).toBeGreaterThanOrEqual(16);
  });
});
