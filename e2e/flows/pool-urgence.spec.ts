/**
 * Flow H — Pool urgence : opt-in soignant + déclenchement notif sur mission urgente.
 *
 * SMS réels non envoyés en test → vérifier seulement que les RPCs/UI répondent.
 */

import { test, expect } from '@playwright/test';
import { hasTestAccount } from '../helpers/seed';
import { TEST_ACCOUNTS } from '../helpers/auth';

test.describe('Flow pool urgence', () => {
  test('soignant authentifié peut accéder au pool urgence dans préférences', async ({ page }) => {
    test.skip(
      !process.env.PLAYWRIGHT_TEST_PASSWORD || !(await hasTestAccount('SOIGNANT')),
      'Compte test soignant requis',
    );
    const creds = TEST_ACCOUNTS.soignant;
    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(creds.email);
    await page.locator('input[type="password"]').first().fill(creds.password);
    await page.getByTestId('login-submit').click();
    await page.waitForURL(/\/soignant/, { timeout: 15000 });

    await page.goto('/soignant/parametres');
    await page.waitForLoadState('networkidle');
    // Onglet préférences ou pool urgence accessible
    await expect(page.locator('h1').first()).toBeVisible();
  });

  test('étab peut accéder au pool urgence', async ({ page }) => {
    test.skip(
      !process.env.PLAYWRIGHT_TEST_PASSWORD || !(await hasTestAccount('ADMIN_ETABLISSEMENT')),
      'Compte test étab requis',
    );
    const creds = TEST_ACCOUNTS.etab;
    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(creds.email);
    await page.locator('input[type="password"]').first().fill(creds.password);
    await page.getByTestId('login-submit').click();
    await page.waitForURL(/\/etablissement/, { timeout: 15000 });

    await page.goto('/etablissement/pool-urgence');
    await page.waitForLoadState('networkidle');
    // Page existe (peut être empty state)
    await expect(page.locator('h1, h2').first()).toBeVisible();
  });
});
