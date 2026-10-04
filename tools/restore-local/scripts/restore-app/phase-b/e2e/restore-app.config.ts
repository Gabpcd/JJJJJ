import { defineConfig, devices } from '@playwright/test';
import { readBrowserInput } from '../browser-input.mjs';

// Only the runner-local file created by the owned synthetic source is accepted.
const fixture = readBrowserInput();

export default defineConfig({
  testDir: '.', testMatch: 'restore-app.spec.ts', workers: 1, retries: 0,
  failOnFlakyTests: true, forbidOnly: true, timeout: 90_000, expect: { timeout: 12_000 },
  outputDir: '/tmp/restore-results', reporter: [['json', { outputFile: '/restore-output/report.json' }]],
  // No globalSetup, storageState injection, interception fixtures or media of Auth.
  use: { baseURL: fixture.appUrl, locale: 'fr-FR', timezoneId: 'Europe/Paris',
    serviceWorkers: 'allow', screenshot: 'off', trace: 'off', video: 'off', acceptDownloads: true },
  projects: [
    { name: 'ipad-portrait', use: { ...devices['iPad Pro 11'], viewport: { width: 820, height: 1180 }, screen: { width: 820, height: 1180 } } },
    { name: 'ipad-paysage', use: { ...devices['iPad Pro 11'], viewport: { width: 1180, height: 820 }, screen: { width: 1180, height: 820 } } },
    { name: 'iphone', use: { ...devices['iPhone 13'], viewport: { width: 390, height: 844 } } },
    { name: 'android', use: { ...devices['Pixel 7'] } },
    { name: 'ordinateur', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
  ],
});
