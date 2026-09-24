import { defineConfig, devices } from '@playwright/test';
import path from 'node:path';

const resultats = process.env.FLUIDITE_RESULTS_DIR || path.resolve('test-results/fluidite');

// Suite entièrement simulée : aucun setup/teardown ni compte de production.
export default defineConfig({
  testDir: '.', testMatch: 'fluidite-navigation.spec.ts',
  outputDir: resultats,
  timeout: 45_000, expect: { timeout: 12_000 }, workers: 1, retries: 0,
  reporter: [['list'], ['json', { outputFile: path.join(resultats, 'results.json') }]],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8780',
    locale: 'fr-FR', timezoneId: 'Europe/Paris', serviceWorkers: 'block',
    reducedMotion: 'no-preference', screenshot: 'only-on-failure', trace: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 }, launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH } } },
    { name: 'android-pixel', use: { ...devices['Pixel 7'], launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH } } },
    { name: 'webkit-iphone', use: { ...devices['iPhone 13'], launchOptions: { executablePath: process.env.PLAYWRIGHT_WEBKIT_EXECUTABLE_PATH } } },
  ],
});
