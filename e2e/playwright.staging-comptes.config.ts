import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './staging', testMatch: 'comptes.spec.ts',
  timeout: 90_000, expect: { timeout: 15_000 }, workers: 1, retries: 0,
  forbidOnly: true,
  outputDir: 'test-results/staging-comptes',
  reporter: [['list'], ['json', { outputFile: 'test-results/staging-comptes/results.json' }]],
  use: { baseURL: 'http://127.0.0.1:8891', locale: 'fr-FR', serviceWorkers: 'block', screenshot: 'only-on-failure' },
  webServer: { command: 'npm run preview -- --host 127.0.0.1 --port 8891 --strictPort', url: 'http://127.0.0.1:8891' },
  projects: [{ name: 'staging-chromium', use: { ...devices['Desktop Chrome'] } }],
});
