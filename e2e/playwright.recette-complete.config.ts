import { defineConfig, devices } from '@playwright/test';
import path from 'node:path';

const sortie = process.env.RECETTE_RESULTS_DIR || path.resolve('test-results/recette-complete');
const chromium = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
const webkit = process.env.PLAYWRIGHT_WEBKIT_EXECUTABLE_PATH;

// Environnement simulé : aucun globalSetup/teardown et aucun compte réel.
export default defineConfig({
  testDir: '.',
  testMatch: '**/recette-complete-*.spec.ts',
  outputDir: sortie,
  timeout: 90_000,
  expect: { timeout: 12_000 },
  workers: 1,
  retries: 0,
  forbidOnly: !!process.env.CI,
  webServer: process.env.RECETTE_START_SERVER === '1' ? {
    command: 'npm run preview -- --host 127.0.0.1 --port 8890 --strictPort',
    url: 'http://127.0.0.1:8890',
    reuseExistingServer: !process.env.CI,
  } : undefined,
  reporter: [['list'], ['json', { outputFile: path.join(sortie, 'results.json') }]],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8890',
    locale: 'fr-FR', timezoneId: 'Europe/Paris', serviceWorkers: 'block',
    reducedMotion: 'no-preference', screenshot: 'only-on-failure', trace: 'retain-on-failure',
  },
  projects: [
    { name: 'ipad-portrait', use: { ...devices['iPad Pro 11'], viewport: { width: 820, height: 1180 }, screen: { width: 820, height: 1180 }, launchOptions: { executablePath: webkit } } },
    { name: 'ipad-paysage', use: { ...devices['iPad Pro 11'], viewport: { width: 1180, height: 820 }, screen: { width: 1180, height: 820 }, launchOptions: { executablePath: webkit } } },
    { name: 'iphone', use: { ...devices['iPhone 13'], viewport: { width: 390, height: 844 }, launchOptions: { executablePath: webkit } } },
    { name: 'android', use: { ...devices['Pixel 7'], launchOptions: { executablePath: chromium } } },
    { name: 'ordinateur', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 }, launchOptions: { executablePath: chromium } } },
  ],
});
