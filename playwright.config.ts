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

const BASE_URL = process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:8080';
const IS_CI = !!process.env.CI;
const LOCAL_CHROMIUM_EXECUTABLE = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;

export default defineConfig({
  testDir: './e2e',
  testMatch: ['**/*.spec.ts'],
  // visual.spec.ts est exclu de la suite par défaut : il nécessite des
  // baselines committées. Lancer via le workflow `playwright-visual-update.yml`
  // (workflow_dispatch) qui génère les baselines puis crée une PR auto.
  // Pour run en local manuellement : `npx playwright test e2e/visual --project=chromium`.
  testIgnore: [
    ...(process.env.PLAYWRIGHT_INCLUDE_VISUAL === 'true' ? [] : ['**/visual.spec.ts']),
    // e2e/non-regression/ appartient exclusivement au projet
    // mobile-non-regression ci-dessous — chromium & co l'ignorent.
    '**/non-regression/**',
  ],
  globalSetup: './e2e/global-setup.ts',
  globalTeardown: './e2e/global-teardown.ts',
  timeout: 30_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  forbidOnly: IS_CI,
  retries: IS_CI ? 2 : 0,
  // Un retry peut aider à diagnostiquer une panne transitoire, mais ne doit
  // jamais transformer un test instable en check GitHub vert. Le journal et
  // le statut CI racontent désormais la même chose.
  failOnFlakyTests: IS_CI,
  // 1 worker en CI : il n'existe qu'UN couple de comptes test
  // (playwright-soignant / playwright-etab) partagé par tous les fichiers —
  // avec 2 workers, les afterEach d'un fichier purgent l'état (quota
  // super-likes, swipes, missions) pendant qu'un autre fichier teste dessus
  // (flaky systémique : super_swipes_quota effacé entre l'upsert et la RPC,
  // missions matching supprimées en plein swipe). Sérialiser coûte ~2 min de
  // wall-time par navigateur et supprime toute la classe de courses.
  workers: IS_CI ? 1 : undefined,
  reporter: IS_CI
    ? [['html', { open: 'never' }], ['github'], ['list']]
    : [['html', { open: 'on-failure' }], ['list']],

  use: {
    baseURL: BASE_URL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    // L'exécution locale peut réutiliser Chrome système sans installer le
    // bundle Playwright/ffmpeg. La CI conserve les vidéos d'échec.
    video: LOCAL_CHROMIUM_EXECUTABLE ? 'off' : 'retain-on-failure',
    actionTimeout: 10_000,
    navigationTimeout: 15_000,
    locale: 'fr-FR',
    timezoneId: 'Europe/Paris',
    // prefers-reduced-motion : l'app désactive TOUTES ses transitions sous ce
    // réglage (media query globale index.css:850 — page-enter/exit, fade-in,
    // holographic…). Sans lui, axe-core scanne parfois EN PLEIN fondu
    // d'opacité PageTransition et calcule le contraste sur du texte
    // semi-transparent → color-contrast SERIOUS fantôme (observé sur
    // landing/chromium, /accessibilite/webkit, pages aléatoires selon le
    // timing). C'est aussi un réglage d'utilisateur réel : on teste le mode
    // accessibilité que l'app prétend supporter.
    reducedMotion: 'reduce',
    // Bloquer le service worker en E2E pour éviter le banner "Nouvelle version
    // disponible" qui intercepte les clics + viole les contrastes a11y.
    serviceWorkers: 'block',
  },

  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1920, height: 1080 },
        ...(LOCAL_CHROMIUM_EXECUTABLE
          ? { launchOptions: { executablePath: LOCAL_CHROMIUM_EXECUTABLE } }
          : {}),
      },
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
    {
      // Non-régression mobile : uniquement e2e/non-regression/ (viewport
      // 390×844 + tactile). Lancer : npm run test:e2e:regression.
      name: 'mobile-non-regression',
      testMatch: /non-regression\/.*\.spec\.ts/,
      // Override du testIgnore global (qui exclut non-regression pour tous
      // les autres projets) ; visual.spec.ts ne matche pas le testMatch.
      testIgnore: [],
      use: {
        browserName: 'chromium',
        viewport: { width: 390, height: 844 },
        hasTouch: true,
        isMobile: true,
        ...(LOCAL_CHROMIUM_EXECUTABLE
          ? { launchOptions: { executablePath: LOCAL_CHROMIUM_EXECUTABLE } }
          : {}),
      },
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
