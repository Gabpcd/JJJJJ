import { test, expect } from '@playwright/test';
import { loginAs } from './helpers/auth';
import { cleanupMissionCascade, seedMission } from './helpers/seed';

/**
 * Parcours frontend établissement. Les anciens tests attendaient deux variables
 * E2E_ETABLISSEMENT_* que la CI ne fournissait jamais et étaient donc toujours
 * ignorés, alors que le compte canonique est déjà géré par loginAs().
 */
test.describe('Missions (espace établissement)', () => {
  let missionId: string | null = null;

  test.beforeAll(async () => {
    if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return;
    missionId = (await seedMission({
      intitule: `[playwright-test] Parcours frontend ${Date.now()}`,
      typeContratRecherche: 'SALARIE',
    }))?.id ?? null;
  });

  test.afterAll(async () => {
    if (missionId) await cleanupMissionCascade(missionId);
  });

  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'etab');
  });

  test('la liste des missions rend ses actions principales', async ({ page }) => {
    await page.goto('/etablissement/missions', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: /Missions/i }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: /Publier une mission/i })).toBeVisible();
  });

  test('le détail d’une mission seedée est accessible', async ({ page }) => {
    test.skip(!missionId, 'Service role ou seed mission indisponible');
    await page.goto(`/etablissement/missions/${missionId}`, { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: /Parcours frontend/i })).toBeVisible();
    await expect(page.getByText(/Mission introuvable/i)).toHaveCount(0);
  });

  test('le formulaire de création expose les champs et l’explication de facturation', async ({ page }) => {
    await page.goto('/etablissement/missions/creer', { waitUntil: 'domcontentloaded' });

    await expect(page.getByRole('heading', { name: /Publier une mission/i })).toBeVisible();
    await expect(page.getByLabel('Intitulé *')).toBeVisible();
    await expect(page.locator('#mission-profession')).toBeVisible();
    await expect(page.getByText(/régime retenu détermine ensuite la paie employeur ou les deux factures distinctes/i)).toBeVisible();
  });
});
