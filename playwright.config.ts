import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration — Jolene healthcare staffing
 *
 * Tests E2E qui simulent un VRAI utilisateur naviguant dans l'app via browser.
 *
 * Lancer en local :
 *   npm run test:e2e              # tous les tests, headless
 *   npm run test:e2e:ui           # mode interactif
 *   npx playwright test e2e/auth  # un fichier précis
 *   npx playwright test --project=mobile-iphone
 *
 * Voir docs/tests-playwright.md pour les détails (debug, helpers, comptes test).
 */

const BASE_URL = process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:5173';
const IS_CI = !!process.env.CI;

export default defineConfig({
  testDir: './e2e',
  testMatch: ['**/*.spec.ts'],
  // visual.spec.ts est exclu de la suite par défaut : il nécessite des
  // baselines committées. Lancer via le workflow `playwright-visual-update.yml`
  // (workflow_dispatch) qui génère les baselines puis crée une PR auto.
  // Pour run en local manuellement : `npx playwright test e2e/visual --project=chromium`.
  testIgnore: process.env.PLAYWRIGHT_INCLUDE_VISUAL === 'true' ? [] : ['**/visual.spec.ts'],
  timeout: 30_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  forbidOnly: IS_CI,
  retries: IS_CI ? 2 : 0,
  workers: IS_CI ? 2 : undefined,
  reporter: IS_CI
    ? [['html', { open: 'never' }], ['github'], ['list']]
    : [['html', { open: 'on-failure' }], ['list']],

  use: {
    baseURL: BASE_URL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 10_000,
    navigationTimeout: 15_000,
    locale: 'fr-FR',
    timezoneId: 'Europe/Paris',
    // Bloquer le service worker en E2E pour éviter le banner "Nouvelle version
    // disponible" qui intercepte les clics + viole les contrastes a11y.
    serviceWorkers: 'block',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], viewport: { width: 1920, height: 1080 } },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'], viewport: { width: 1920, height: 1080 } },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'], viewport: { width: 1440, height: 900 } },
    },
    {
      name: 'mobile-iphone',
      use: { ...devices['iPhone 14'] },
    },
    {
      name: 'mobile-pixel',
      use: { ...devices['Pixel 7'] },
    },
    {
      name: 'tablet-ipad',
      use: { ...devices['iPad (gen 7)'] },
    },
  ],

  // En CI on attend que le serveur soit démarré séparément (preview Vercel par
  // ex.) — pas de webServer ici. En local, Vite dev server est démarré
  // automatiquement.
  webServer: IS_CI
    ? undefined
    : {
        command: 'npm run dev',
        url: BASE_URL,
        reuseExistingServer: true,
        timeout: 120_000,
      },
});
