/**
 * Sprint 16 PR 2 — Tests E2E réels pool urgence.
 *
 * Conversion des 2 stubs Sprint 7 en tests fonctionnels :
 * - soignant authentifié → page paramètres accessible
 * - étab authentifié → page /etablissement/pool-urgence accessible
 *
 * Note : SMS réels Twilio non envoyés en test (rate limit + côté tarification).
 * Workflow d'envoi déclenché par fn_trg_auto_proposition_pool_urgence couvert
 * en backend hors Playwright.
 */

import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';

test.describe('Flow pool urgence', () => {
  test('soignant authentifié peut accéder à /soignant/parametres (préférences pool urgence)', async ({ page }) => {
    await loginAs(page, 'soignant');

    await page.goto('/soignant/parametres');
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1, h2').first()).toBeVisible({ timeout: 10_000 });
  });

  test('étab authentifié peut accéder à /etablissement/pool-urgence', async ({ page }) => {
    await loginAs(page, 'etab');

    await page.goto('/etablissement/pool-urgence');
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1, h2').first()).toBeVisible({ timeout: 10_000 });
  });
});
