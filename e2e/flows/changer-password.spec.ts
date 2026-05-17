/**
 * Sprint 16 PR 3 — Tests E2E réels modifier mot de passe.
 *
 * Conversion du stub #1 en test réel :
 * - soignant authentifié → page /soignant/parametres accessible + heading
 *
 * Skip honnête conservé pour le test #2 (flow complet changement + restore) :
 * casser puis restaurer le mot de passe du compte test fixe en CI mutualisé
 * est risqué (race condition entre runs parallèles, mot de passe restauré
 * via service_role qui ne peut PAS appeler auth.admin.updateUserById pour
 * remettre un hash de password — limitation Supabase API). Le flow réel est
 * couvert par les tests de PageResetPassword (UI identique, même API
 * supabase.auth.updateUser).
 */

import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';

test.describe('Modifier mot de passe', () => {
  test('soignant authentifié peut accéder à /soignant/parametres', async ({ page }) => {
    await loginAs(page, 'soignant');

    await page.goto('/soignant/parametres');
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1').first()).toBeVisible({ timeout: 10_000 });
  });

  test('flow complet changement mot de passe + restore', async () => {
    test.skip(
      true,
      'Skip honnête : casser/restaurer le mot de passe du compte test fixe en CI mutualisé est risqué (race conditions parallel runs, limitation API supabase.auth.admin pour restore du hash). Le flow Supabase auth.updateUser identique est couvert par PageResetPassword + tests E2E reset-password graceful (inscription.spec.ts).',
    );
  });
});
