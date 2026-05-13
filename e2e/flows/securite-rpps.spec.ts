/**
 * Flow D — Sécurité RPPS inscription soignant (Sprint 2 PR 6).
 *
 * Tests le flow d'inscription et les contrôles RPPS :
 *  - RPPS inexistant → erreur UI "RPPS_NOT_FOUND"
 *  - RPPS valide + profession différente → erreur (mismatch profession)
 *  - RPPS valide + traits identité incorrects → erreur
 *
 * Ces tests utilisent les vrais endpoints verify-rpps. Pour éviter la
 * pollution des comptes test, on skip par défaut sauf si
 * PLAYWRIGHT_SEED_RPPS=1.
 *
 * NB : la vérification RPPS frappe une API externe (annuaire santé).
 * En CI on mock via PLAYWRIGHT_MOCK_RPPS=1.
 */
import { test, expect } from '@playwright/test';

const SEED_READY = process.env.PLAYWRIGHT_SEED_RPPS === '1';

test.describe('Sécurité RPPS — inscription', () => {
  test.beforeEach(() => {
    test.skip(!SEED_READY, 'Seed RPPS E2E à compléter — flow validé manuellement Sprint 1');
  });

  test('inscription avec RPPS inexistant → erreur claire', async ({ page }) => {
    await page.goto('/inscription/soignant');

    // Remplir le formulaire avec un RPPS bidon
    await page.locator('input[name="prenom"]').fill('Test');
    await page.locator('input[name="nom"]').fill('Inexistant');
    await page.locator('input[name="email"]').fill(`test-rpps-${Date.now()}@jolene.app`);
    await page.locator('input[name="rpps"]').fill('99999999999');

    // Le système doit afficher RPPS_NOT_FOUND ou un message équivalent
    await page.locator('button[type="submit"]').first().click();
    await expect(page.locator('text=/RPPS|non trouvé|introuvable|invalide/i')).toBeVisible({ timeout: 10000 });
  });

  test('inscription avec RPPS valide mais profession mismatch → erreur', async ({ page }) => {
    const rppsValide = process.env.PLAYWRIGHT_RPPS_MEDECIN;
    test.skip(!rppsValide, 'PLAYWRIGHT_RPPS_MEDECIN (RPPS médecin valide) non défini');

    await page.goto('/inscription/soignant');
    await page.locator('input[name="prenom"]').fill('Test');
    await page.locator('input[name="nom"]').fill('Mismatch');
    await page.locator('input[name="email"]').fill(`test-mismatch-${Date.now()}@jolene.app`);
    await page.locator('input[name="rpps"]').fill(rppsValide!);
    // Sélectionner profession=IDE (mismatch)
    await page.locator('select[name="profession"]').selectOption('IDE');

    await page.locator('button[type="submit"]').first().click();
    await expect(page.locator('text=/profession.*ne correspond|mismatch|incohér/i')).toBeVisible({ timeout: 10000 });
  });

  test('inscription avec RPPS valide + traits incorrects → erreur', async ({ page }) => {
    const rppsValide = process.env.PLAYWRIGHT_RPPS_MEDECIN;
    test.skip(!rppsValide, 'PLAYWRIGHT_RPPS_MEDECIN non défini');

    await page.goto('/inscription/soignant');
    // Volontairement faux nom pour déclencher mismatch traits
    await page.locator('input[name="prenom"]').fill('XXXX-FAUX');
    await page.locator('input[name="nom"]').fill('YYYY-FAUX');
    await page.locator('input[name="email"]').fill(`test-traits-${Date.now()}@jolene.app`);
    await page.locator('input[name="rpps"]').fill(rppsValide!);

    await page.locator('button[type="submit"]').first().click();
    await expect(page.locator('text=/identité|trait|nom.*prénom/i')).toBeVisible({ timeout: 10000 });
  });
});
