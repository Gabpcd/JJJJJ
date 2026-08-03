/**
 * Sprint 16 PR 4 — Tests E2E réels litiges.
 *
 * Conversion des 2 stubs Sprint 3.5 en tests fonctionnels :
 * - soignant authentifié → page /soignant/litiges accessible
 * - RPC fn_basculer_litiges_revue_admin_timeout (cron 7j) existe en DB
 */

import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';
import { adminClient } from '../helpers/db';

test.describe('Flow litige', () => {
  test('soignant authentifié peut accéder à /soignant/litiges', async ({ page }) => {
    await loginAs(page, 'soignant');

    await page.goto('/soignant/litiges', { waitUntil: 'domcontentloaded' });

    await expect(page.locator('h1, h2').first()).toBeVisible({ timeout: 10_000 });
  });

  test('RPC fn_basculer_litiges_revue_admin_timeout existe et est appelable', async () => {
    // Appel direct via service_role. La fonction est SECURITY DEFINER cron,
    // elle doit répondre sans "function does not exist".
    const { error } = await adminClient().rpc(
      'fn_basculer_litiges_revue_admin_timeout' as any,
    );
    // Soit ok (cron exécuté, retour OK), soit erreur structurée — mais
    // pas "function ... does not exist".
    if (error) {
      expect(error.message).not.toMatch(/function .* does not exist/i);
    }
  });
});
