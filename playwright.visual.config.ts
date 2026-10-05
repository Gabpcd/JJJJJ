import { defineConfig, devices } from '@playwright/test';

// These eight public-page captures do not log in or mutate technical accounts.
// Keep their setup separate from the authenticated E2E suite.
export default defineConfig({
  testDir: './e2e',
  testMatch: '**/visual.spec.ts',
  outputDir: 'test-results/visual',
  timeout: 30_000,
  expect: { timeout: 10_000 },
  workers: 1,
  retries: 0,
  forbidOnly: !!process.env.CI,
  failOnFlakyTests: true,
  reporter: [['list']],
  webServer: {
    command: 'npm run preview -- --host 127.0.0.1 --port 4173 --strictPort',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: false,
    timeout: 30_000,
  },
  use: {
    baseURL: 'http://127.0.0.1:4173',
    locale: 'fr-FR',
    timezoneId: 'Europe/Paris',
    reducedMotion: 'reduce',
    serviceWorkers: 'block',
    actionTimeout: 10_000,
    navigationTimeout: 15_000,
    trace: 'off',
    screenshot: 'off',
    video: 'off',
  },
  projects: [{
    name: 'chromium',
    use: { ...devices['Desktop Chrome'], viewport: { width: 1920, height: 1080 } },
  }],
});
