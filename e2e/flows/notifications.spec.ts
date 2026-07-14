/**
 * Sprint 16 PR 2 — Tests E2E réels notifications in-app.
 *
 * Conversion du stub Sprint 7 en test fonctionnel :
 * - login soignant
 * - dashboard chargé
 * - bell icon notification présent dans le header (BarreNavigation)
 */

import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';

test.describe('Notifications in-app', () => {
  test('soignant connecté voit le bell icon notification dans le header', async ({ page }) => {
    await loginAs(page, 'soignant');

    // La navigation est rendue dès le skeleton du dashboard. Attendre un h1/h2
    // couplait ce test au temps de réponse de fn_dashboard_soignant_complet,
    // alors que la cloche était déjà utilisable (flaky CI du 14/07/2026).
    const bell = page.getByRole('button', { name: /notification/i }).first();
    await expect(bell).toBeVisible({ timeout: 15_000 });
    await expect(bell).toHaveAttribute('aria-expanded', 'false');

    // Vérifie le comportement réel, pas seulement la présence de l'icône.
    await bell.click();
    const panneau = page.getByRole('dialog', { name: 'Notifications' });
    await expect(panneau).toBeVisible();
    await expect(bell).toHaveAttribute('aria-expanded', 'true');

    await page.getByRole('button', { name: 'Fermer les notifications' }).click();
    await expect(panneau).toBeHidden();
    await expect(bell).toHaveAttribute('aria-expanded', 'false');
  });
});
