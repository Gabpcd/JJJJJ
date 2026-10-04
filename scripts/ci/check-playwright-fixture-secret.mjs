#!/usr/bin/env node
import { requireFixturePassword } from '../lib/playwright-fixtures.mjs';
try {
  requireFixturePassword(process.env.E2E_TEST_PASSWORD || process.env.PLAYWRIGHT_TEST_PASSWORD);
  console.log('Secret privé des fixtures présent et au format attendu.');
} catch {
  console.error('PLAYWRIGHT_FIXTURE_PASSWORD requis : 32 octets aléatoires encodés en 64 caractères hexadécimaux.');
  process.exitCode = 1;
}
