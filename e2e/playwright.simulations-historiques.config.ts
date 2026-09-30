import { defineConfig, devices } from '@playwright/test';
import path from 'node:path';

const sortie = process.env.RECETTE_RESULTS_DIR || path.resolve('test-results/simulations-historiques');
const chromium = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
const webkit = process.env.PLAYWRIGHT_WEBKIT_EXECUTABLE_PATH;

// Configuration de simulation uniquement : aucun globalSetup/globalTeardown de
// la suite backend, aucun compte distant, mêmes cinq formats et retries=0.
export default defineConfig({
  testDir: '.',
  testMatch: [
    'inscription-navigation.spec.ts',
    'etablissement-exploration.spec.ts',
    'soignant-public-exploration.spec.ts',
    'detail-mission-lisibilite.spec.ts',
    'fluidite-navigation.spec.ts',
    'isolation-websocket-simule.spec.ts',
  ],
  outputDir: sortie,
  timeout: 90_000,
  expect: { timeout: 12_000 },
  workers: 1,
  retries: 0,
  forbidOnly: !!process.env.CI,
  reporter: [['list'], ['json', { outputFile: path.join(sortie, 'results.json') }]],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8890',
    locale: 'fr-FR', timezoneId: 'Europe/Paris', serviceWorkers: 'block',
    contextOptions: { reducedMotion: 'no-preference' },
    screenshot: 'only-on-failure', trace: 'retain-on-failure',
  },
  projects: [
    { name: 'ipad-portrait', use: { ...devices['iPad Pro 11'], viewport: { width: 820, height: 1180 }, contextOptions: { screen: { width: 820, height: 1180 } }, launchOptions: { executablePath: webkit } } },
    { name: 'ipad-paysage', use: { ...devices['iPad Pro 11'], viewport: { width: 1180, height: 820 }, contextOptions: { screen: { width: 1180, height: 820 } }, launchOptions: { executablePath: webkit } } },
    { name: 'iphone', use: { ...devices['iPhone 13'], viewport: { width: 390, height: 844 }, launchOptions: { executablePath: webkit } } },
    { name: 'android', use: { ...devices['Pixel 7'], launchOptions: { executablePath: chromium } } },
    { name: 'ordinateur', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 }, launchOptions: { executablePath: chromium } } },
  ],
});
