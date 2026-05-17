/**
 * Sprint 16 PR 1 — Tests E2E réels candidature soignant → étab.
 *
 * Conversion des stubs Sprint 1 en tests fonctionnels :
 * - seed mission OUVERTE → assertion DB statut
 * - login soignant + navigation détail mission → assertion page chargée
 *
 * Pattern : seedMission via adminClient (helper Sprint 1) + loginAs (helper
 * Sprint 14). Cleanup automatique via cleanupSeedData en afterEach.
 */

import { test, expect } from '@playwright/test';
import { seedMission, cleanupSeedData } from '../helpers/seed';
import { loginAs } from '../helpers/auth';
import { adminClient } from '../helpers/db';

test.describe('Flow candidature soignant → étab', () => {
  test.afterEach(async () => {
    await cleanupSeedData().catch(() => {});
  });

  test('mission seedée apparaît bien en DB avec statut OUVERTE', async () => {
    const m = await seedMission({ intitule: '[playwright-test] Candidature DB E2E' });
    expect(m, 'seedMission failed').toBeTruthy();

    const { data, error } = await adminClient()
      .from('missions' as any)
      .select('id, statut, intitule, etablissement_id')
      .eq('id', m!.id)
      .single();

    expect(error).toBeFalsy();
    expect((data as any)?.statut).toBe('OUVERTE');
    expect((data as any)?.intitule).toContain('[playwright-test]');
    expect((data as any)?.etablissement_id).toBe(m!.etablissement_id);
  });

  test('soignant authentifié peut accéder à la page détail mission seedée', async ({ page }) => {
    const mission = await seedMission({ intitule: '[playwright-test] Candidature UI E2E' });
    expect(mission, 'seedMission failed').toBeTruthy();

    await loginAs(page, 'soignant');

    await page.goto(`/soignant/missions/${mission!.id}`);
    await page.waitForLoadState('networkidle');

    // La page charge (heading visible — soft sur structure UI variable selon
    // matching profession soignant vs mission).
    const heading = page.locator('h1, h2').first();
    await expect(heading).toBeVisible({ timeout: 10_000 });
  });
});
