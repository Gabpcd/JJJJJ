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
    // L'application conserve des connexions Supabase actives (Realtime, rafraîchissements) :
    // « networkidle » n'est jamais atteint de façon fiable et faisait échouer le test au
    // premier essai (navigationTimeout 15 s, runs 41351520555 et 41358095141). L'assertion
    // sur le titre suffit à attendre le rendu de la page.
    await expect(page.locator('h1, h2').first()).toBeVisible({ timeout: 10_000 });
  });

  test('étab authentifié peut accéder à /etablissement/pool-urgence', async ({ page }) => {
    await loginAs(page, 'etab');

    await page.goto('/etablissement/pool-urgence');
    await expect(page).toHaveURL(/\/etablissement\/pool-urgence$/);
    // Ce filtre apparaît après le chargement, contrairement au titre du skeleton.
    await expect(page.getByRole('combobox', { name: 'Filtrer par profession', exact: true })).toBeVisible();

    await expect(page.locator('h1, h2').first()).toBeVisible({ timeout: 10_000 });
  });
});
