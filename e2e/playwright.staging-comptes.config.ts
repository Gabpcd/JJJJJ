import { defineConfig, devices } from '@playwright/test';
import path from 'node:path';

const sortie = path.resolve('test-results/staging-comptes');

export default defineConfig({
  testDir: './staging', testMatch: 'comptes.spec.ts',
  timeout: 90_000, expect: { timeout: 15_000 }, workers: 1, retries: 0,
  forbidOnly: true,
  outputDir: sortie,
  reporter: [['list'], ['json', { outputFile: path.join(sortie, 'results.json') }]],
  // Origine de développement explicitement autorisée par les services existants.
  // Ne pas contourner CORS dans le navigateur ni élargir la politique serveur.
  use: { baseURL: 'http://localhost:5173', locale: 'fr-FR', serviceWorkers: 'block', screenshot: 'only-on-failure', actionTimeout: 15_000, navigationTimeout: 20_000 },
  webServer: { command: 'npm run preview -- --host 0.0.0.0 --port 5173 --strictPort', url: 'http://localhost:5173' },
  projects: [{ name: 'staging-chromium', use: { ...devices['Desktop Chrome'] } }],
});
