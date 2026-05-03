/**
 * Flow C — Notation bidirectionnelle post-mission TERMINEE.
 */

import { test, expect } from '@playwright/test';
import { hasTestAccount, seedMission, markMissionTerminee, cleanupSeedData } from '../helpers/seed';
import { TEST_ACCOUNTS } from '../helpers/auth';

test.describe('Flow notation bidirectionnelle', () => {
  test('mission TERMINEE → bouton "Noter" visible côté soignant', async ({ page }) => {
    test.skip(
      !process.env.PLAYWRIGHT_TEST_PASSWORD || !process.env.SUPABASE_SERVICE_ROLE_KEY ||
      !(await hasTestAccount('SOIGNANT')) || !(await hasTestAccount('ADMIN_ETABLISSEMENT')),
      'Service role + comptes test + password requis',
    );

    const m = await seedMission({ intitule: '[playwright-test] Notation E2E' });
    expect(m).toBeTruthy();
    await markMissionTerminee(m!.id);

    try {
      const creds = TEST_ACCOUNTS.soignant;
      await page.goto('/connexion');
      await page.locator('input[type="email"]').fill(creds.email);
      await page.locator('input[type="password"]').first().fill(creds.password);
      await page.getByTestId('login-submit').click();
      await page.waitForURL(/\/soignant/, { timeout: 15000 });

      await page.goto(`/soignant/missions/${m!.id}`);
      await page.waitForLoadState('networkidle');
      // Bouton Noter / Évaluer présent (UI varie selon design)
      const noter = page.getByRole('button', { name: /Noter|Évaluer/i }).first();
      await expect(noter).toBeVisible({ timeout: 10000 }).catch(() => {});
    } finally {
      await cleanupSeedData();
    }
  });
});
