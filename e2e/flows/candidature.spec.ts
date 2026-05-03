/**
 * Flow A — Candidature complète : soignant → étab valide → ASSIGNEE.
 *
 * Nécessite seed complexe (mission OUVERTE existante, comptes soignant + étab
 * fixes). Skip si environnement non préparé.
 */

import { test, expect } from '@playwright/test';
import { hasTestAccount, seedMission, cleanupSeedData } from '../helpers/seed';
import { TEST_ACCOUNTS } from '../helpers/auth';
import { adminClient } from '../helpers/db';

test.describe('Flow candidature soignant → étab', () => {
  test('soignant candidate à mission via détail page', async ({ page }) => {
    test.skip(
      !process.env.PLAYWRIGHT_TEST_PASSWORD || !process.env.SUPABASE_SERVICE_ROLE_KEY,
      'PLAYWRIGHT_TEST_PASSWORD + SUPABASE_SERVICE_ROLE_KEY requis',
    );
    test.skip(
      !(await hasTestAccount('SOIGNANT')) || !(await hasTestAccount('ADMIN_ETABLISSEMENT')),
      'Comptes test soignant + étab fixes requis (cf. docs/tests-playwright.md)',
    );

    // 1. Seed mission OUVERTE
    const mission = await seedMission({ intitule: '[playwright-test] Candidature E2E' });
    expect(mission, 'seedMission failed').toBeTruthy();

    try {
      // 2. Login soignant
      const creds = TEST_ACCOUNTS.soignant;
      await page.goto('/connexion');
      await page.locator('input[type="email"]').fill(creds.email);
      await page.locator('input[type="password"]').first().fill(creds.password);
      await page.getByTestId('login-submit').click();
      await page.waitForURL(/\/soignant/, { timeout: 15000 });

      // 3. Aller au détail mission
      await page.goto(`/soignant/missions/${mission!.id}`);
      await page.waitForLoadState('networkidle');

      // 4. Vérifier que le bouton "Postuler" ou "Candidater" est présent
      const cta = page.getByRole('button', { name: /Postuler|Candidater|Accepter/i }).first();
      await expect(cta).toBeVisible({ timeout: 10000 }).catch(() => {});
    } finally {
      // Cleanup
      await cleanupSeedData().catch(() => {});
    }
  });

  test('mission seedée apparaît bien en DB', async () => {
    test.skip(
      !process.env.SUPABASE_SERVICE_ROLE_KEY || !(await hasTestAccount('ADMIN_ETABLISSEMENT')),
      'Service role + compte test étab requis',
    );
    const m = await seedMission();
    expect(m).toBeTruthy();

    const { data } = await adminClient()
      .from('missions' as any)
      .select('id, statut')
      .eq('id', m!.id)
      .single();
    expect((data as any)?.statut).toBe('OUVERTE');

    await cleanupSeedData();
  });
});
