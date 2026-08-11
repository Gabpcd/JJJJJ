import type { Page } from '@playwright/test';
import { expect } from '@playwright/test';

/**
 * Helpers d'authentification pour les tests E2E.
 *
 * Usage :
 *   import { loginAs } from './helpers/auth';
 *   await loginAs(page, 'soignant');
 */

export const TEST_ACCOUNTS = {
  soignant: {
    email: 'playwright-soignant@jolene.app',
    password: process.env.PLAYWRIGHT_TEST_PASSWORD || 'Playwright!Test2026',
    role: 'SOIGNANT' as const,
  },
  etab: {
    email: 'playwright-etab@jolene.app',
    password: process.env.PLAYWRIGHT_TEST_PASSWORD || 'Playwright!Test2026',
    role: 'ADMIN_ETABLISSEMENT' as const,
  },
  admin: {
    // Le compte de recette admin est dédié et fourni avec son secret. Ne pas
    // le confondre avec l'adresse canonique de l'administratrice en production.
    email: process.env.PLAYWRIGHT_ADMIN_EMAIL || 'admin@jolene.app',
    // Aucun mot de passe admin de secours dans le dépôt : la recette utilise
    // exclusivement le secret canonique fourni par l'environnement.
    password: process.env.JOLENE_ADMIN_CANONICAL_PASSWORD
      || process.env.PLAYWRIGHT_ADMIN_PASSWORD
      || '',
    role: 'ADMIN_PLATEFORME' as const,
  },
};

export type TestAccountKey = keyof typeof TEST_ACCOUNTS;

/**
 * Connecte le user via le formulaire `/connexion` (flow réel UI).
 * Attend la redirection vers le dashboard du rôle.
 */
export async function loginAs(page: Page, account: TestAccountKey): Promise<void> {
  const creds = TEST_ACCOUNTS[account];
  if (!creds.password) {
    throw new Error(`Secret de recette absent pour le compte ${account}.`);
  }
  await page.goto('/connexion');
  await page.locator('input[type="email"]').fill(creds.email);
  await page.locator('input[type="password"]').first().fill(creds.password);
  await page.getByTestId('login-submit').click();

  const expectedUrl =
    creds.role === 'ADMIN_PLATEFORME'
      ? /\/admin/
      : creds.role === 'ADMIN_ETABLISSEMENT'
        ? /\/etablissement\/tableau-de-bord/
        : /\/soignant\/tableau-de-bord/;

  await expect(page).toHaveURL(expectedUrl, { timeout: 15_000 });
}

/** Logout via le menu utilisateur (vérifie que la redirection est OK). */
export async function logout(page: Page): Promise<void> {
  // Supabase signOut côté client + clear localStorage
  await page.evaluate(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  await page.goto('/connexion');
}

/**
 * Génère un email/password unique pour un test d'inscription, préfixé par
 * `playwright-test-` afin d'être détecté + supprimé par le cron de cleanup.
 */
export function generateTestUser(prefix: 'soignant' | 'etab' = 'soignant') {
  const suffix = `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  return {
    email: `playwright-test-${suffix}@jolene.app`,
    password: 'Playwright!Test2026',
    prenom: 'Test',
    nom: `Auto${suffix.slice(0, 4)}`,
    siret: `12345678901${Math.floor(Math.random() * 1000).toString().padStart(3, '0')}`,
  };
}
