/**
 * Flow E — Workflow mission complète bout-en-bout (Sprint 2 PR 6).
 *
 * Le scénario nominal le plus critique pour la prod :
 *   1. Inscription étab privé (clinique)
 *   2. Inscription soignant libéral médecin avec RPPS valide
 *   3. Étab crée mission (médecin libéral en clinique)
 *   4. Soignant candidate
 *   5. Étab accepte → contrat généré
 *   6. Soignant reçoit email + push CONTRAT_A_SIGNER
 *   7. Soignant signe avec OTP (mock SMS)
 *   8. Étab signe avec OTP (mock SMS)
 *   9. Mission passe ACTIVE
 *  10. Soignant et étab voient contrat signé + certificat
 *
 * Le test global est skip par défaut car nécessite seed full +
 * mock SMS + RPPS sandbox. À activer en local via
 * PLAYWRIGHT_FULL_WORKFLOW=1 pour la recette globale fin de Sprint 2.
 *
 * Le test sert aussi de documentation du happy path attendu pour la
 * recette manuelle.
 */
import { test, expect } from '@playwright/test';
import { TEST_ACCOUNTS } from '../helpers/auth';

const FULL_WORKFLOW = process.env.PLAYWRIGHT_FULL_WORKFLOW === '1';

test.describe('Workflow mission complète E2E', () => {
  test.beforeEach(() => {
    test.skip(!FULL_WORKFLOW, 'Activer via PLAYWRIGHT_FULL_WORKFLOW=1 — nécessite seed full + mock SMS + RPPS sandbox');
  });

  test('happy path : étab crée → soignant candidate → 2 signatures → mission active', async ({ page, browser }) => {
    // === Étape 1 : étab crée la mission ===
    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(TEST_ACCOUNTS.etab.email);
    await page.locator('input[type="password"]').first().fill(TEST_ACCOUNTS.etab.password);
    await page.getByTestId('login-submit').click();
    await page.waitForURL(/\/(etablissement|admin)/, { timeout: 15000 });

    await page.goto('/etablissement/missions/nouvelle');
    await page.locator('input[name="intitule"]').fill(`[playwright-test] Workflow E2E ${Date.now()}`);
    await page.locator('select[name="profession"]').selectOption('MEDECIN');
    await page.locator('select[name="type_contrat"]').selectOption('REMPLACEMENT_LIBERAL');
    await page.locator('input[name="taux_horaire_base"]').fill('80');
    await page.getByRole('button', { name: /Cr[eé]er|Publier/i }).first().click();
    await page.waitForURL(/\/etablissement\/missions/, { timeout: 15000 });

    const missionUrl = page.url();
    const missionIdMatch = missionUrl.match(/missions\/([a-f0-9-]+)/);
    const missionId = missionIdMatch?.[1];
    expect(missionId, 'mission_id captured').toBeTruthy();

    // === Étape 2 : soignant candidate (nouveau contexte) ===
    const soignantContext = await browser.newContext();
    const soignantPage = await soignantContext.newPage();
    await soignantPage.goto('/connexion');
    await soignantPage.locator('input[type="email"]').fill(TEST_ACCOUNTS.soignant.email);
    await soignantPage.locator('input[type="password"]').first().fill(TEST_ACCOUNTS.soignant.password);
    await soignantPage.getByTestId('login-submit').click();
    await soignantPage.waitForURL(/\/soignant/, { timeout: 15000 });

    await soignantPage.goto(`/soignant/missions/${missionId}`);
    await soignantPage.getByRole('button', { name: /Postuler|Candidater/i }).first().click();
    await expect(soignantPage.locator('text=/candidature.*envoyée|reçue/i')).toBeVisible({ timeout: 10000 });

    // === Étape 3 : étab valide la candidature ===
    await page.goto(`/etablissement/missions/${missionId}`);
    await page.getByRole('button', { name: /Accepter|Valider/i }).first().click();
    await expect(page.locator('text=/Contrat|signé|attente signature/i')).toBeVisible({ timeout: 10000 });

    // === Étape 4 : soignant signe OTP ===
    // ... (signature OTP nécessite mock SMS — détail en helpers/sms-mock.ts à créer Sprint 3)

    // === Étape 5 : étab signe OTP ===
    // ... (idem)

    // === Étape 6 : vérifier mission ACTIVE + certificat disponible ===
    // À compléter quand le mock SMS sera en place.

    await soignantContext.close();
  });
});
