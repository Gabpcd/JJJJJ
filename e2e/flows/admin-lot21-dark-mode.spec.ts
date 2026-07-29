/** Recette AA sombre des six écrans admin principaux — Lot 21.7. */
import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';
import { expectNoCriticalA11y, runAxe } from '../helpers/axe';

const ACTIF = !!(
  process.env.JOLENE_ADMIN_CANONICAL_PASSWORD
  || process.env.PLAYWRIGHT_ADMIN_PASSWORD
);
const PAGES = [
  '/admin',
  '/admin/utilisateurs',
  '/admin/missions',
  '/admin/verification-etablissements',
  '/admin/facturation',
  '/admin/status',
] as const;

test.describe('Lot 21 — contraste AA admin en mode sombre', () => {
  test.beforeEach(() => {
    test.skip(
      !ACTIF,
      'JOLENE_ADMIN_CANONICAL_PASSWORD requis pour la recette admin authentifiée',
    );
  });

  test('les six écrans principaux passent axe en sombre', async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    await loginAs(page, 'admin');
    await page.evaluate(() => localStorage.setItem('theme', 'dark'));

    for (const route of PAGES) {
      await page.goto(route);
      await expect(page.locator('html')).toHaveClass(/dark/);
      await expect(page.locator('#main-content')).toBeVisible();
      const resultat = await runAxe(page, { include: '#main-content' });
      expectNoCriticalA11y(resultat, testInfo);
    }
  });
});
