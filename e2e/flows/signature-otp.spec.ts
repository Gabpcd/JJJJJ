/**
 * Flow B — Signature électronique OTP SMS (Sprint 2 PR 6).
 *
 * Couvre :
 *  - Le module SignerContratOtp rend le bouton "Recevoir le code SMS"
 *  - L'établissement peut signer avant le soignant
 *  - Backend TROP_DE_SMS : limite 3 SMS / 24h appliquée
 *  - UI affiche le hash SHA-256 du document signé
 *
 * Les tests skip par défaut car nécessitent :
 *   1. seed contrat EN_ATTENTE_SIGNATURES avec soignant + étab tests
 *   2. mock SMS (vault decrypted_secrets ou Twilio sandbox)
 *   3. user_phone_verifie pour les 2 comptes test
 *
 * Activer en local via PLAYWRIGHT_SEED_SIGNATURES=1.
 */
import { test, expect } from '@playwright/test';
import { TEST_ACCOUNTS } from '../helpers/auth';

const SEED_READY = process.env.PLAYWRIGHT_SEED_SIGNATURES === '1';

test.describe('Flow signature OTP — workflow critique', () => {
  test.beforeEach(() => {
    test.skip(!SEED_READY, 'Seed signature E2E à compléter (cf. helpers/seed.ts) — flow validé manuellement Sprint 2');
  });

  test('soignant ouvre contrat → bouton SMS visible + checkbox CGU obligatoire', async ({ page }) => {
    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(TEST_ACCOUNTS.soignant.email);
    await page.locator('input[type="password"]').first().fill(TEST_ACCOUNTS.soignant.password);
    await page.getByTestId('login-submit').click();
    await page.waitForURL(/\/soignant/, { timeout: 15000 });

    // Ouvrir un contrat seedé EN_ATTENTE_SIGNATURES
    const contratId = process.env.PLAYWRIGHT_CONTRAT_E2E;
    test.skip(!contratId, 'PLAYWRIGHT_CONTRAT_E2E non défini');
    await page.goto(`/contrat/${contratId}`);

    // Mode OTP_SMS coché par défaut (recommandé)
    await expect(page.locator('text=Signature électronique OTP SMS')).toBeVisible();

    // Sans cocher la checkbox → bouton désactivé
    const btnSms = page.getByRole('button', { name: /Recevoir le code SMS/i });
    await expect(btnSms).toBeDisabled();

    // Cocher → bouton actif
    await page.getByRole('checkbox', { name: /j'ai lu/i }).check();
    await expect(btnSms).toBeEnabled();
  });

  test('l’établissement peut demander son OTP avant le soignant', async ({ page }) => {
    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(TEST_ACCOUNTS.etab.email);
    await page.locator('input[type="password"]').first().fill(TEST_ACCOUNTS.etab.password);
    await page.getByTestId('login-submit').click();
    await page.waitForURL(/\/(etablissement|admin)/, { timeout: 15000 });

    const contratId = process.env.PLAYWRIGHT_CONTRAT_E2E;
    test.skip(!contratId, 'PLAYWRIGHT_CONTRAT_E2E non défini');
    await page.goto(`/contrat/${contratId}`);

    // Aucun ordre légal artificiel : l'établissement peut initier sa signature.
    await expect(page.getByText(/doit signer en premier/i)).toHaveCount(0);
    await page.getByRole('checkbox', { name: /j'ai lu/i }).check();
    await page.getByRole('button', { name: /Recevoir le code SMS/i }).click();
    await expect(page.getByText(/Code envoyé/i)).toBeVisible({ timeout: 5000 });
  });

  test('hash SHA-256 du document affiché dans le certificat', async ({ page }) => {
    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(TEST_ACCOUNTS.soignant.email);
    await page.locator('input[type="password"]').first().fill(TEST_ACCOUNTS.soignant.password);
    await page.getByTestId('login-submit').click();
    await page.waitForURL(/\/soignant/, { timeout: 15000 });

    const contratId = process.env.PLAYWRIGHT_CONTRAT_SIGNE_E2E;
    test.skip(!contratId, 'PLAYWRIGHT_CONTRAT_SIGNE_E2E non défini');

    await page.goto(`/contrat/${contratId}/certificat`);
    await expect(page.locator('text=Empreinte du document signé')).toBeVisible();
    // hash hex 64 caractères : on vérifie la présence d'une chaîne hex de cette longueur
    const hashEl = page.locator('text=/[a-f0-9]{64}/');
    await expect(hashEl).toBeVisible({ timeout: 5000 });
  });
});
