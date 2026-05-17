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

    // Dashboard chargé après loginAs (heading visible)
    await expect(page.locator('h1, h2').first()).toBeVisible({ timeout: 10_000 });

    // Bell icon (lucide Bell) — aria-label inclut "notification" ou "Notifications"
    // Cf. BarreNavigation header soignant Sprint 7.
    const bell = page.getByRole('button', { name: /notification/i }).first();
    await expect(bell).toBeVisible({ timeout: 8_000 });
  });
});
