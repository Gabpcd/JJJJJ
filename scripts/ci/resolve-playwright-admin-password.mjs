#!/usr/bin/env node

/**
 * Sélectionne, sans jamais l'afficher, le secret GitHub qui authentifie encore
 * le compte admin canonique utilisé par Playwright.
 *
 * Deux secrets historiques coexistent dans le dépôt. Les tester ici évite de
 * lancer douze minutes de recette avec un secret désynchronisé. Aucun mot de
 * passe Auth n'est modifié : la valeur valide est seulement transmise aux
 * étapes suivantes via GITHUB_ENV.
 */

import { appendFile } from 'node:fs/promises';

const url = process.env.E2E_SUPABASE_URL || process.env.SUPABASE_URL || '';
const publishableKey =
  process.env.E2E_PUBLISHABLE_KEY || process.env.SUPABASE_PUBLISHABLE_KEY || '';
const githubEnv = process.env.GITHUB_ENV || '';
const candidates = [
  {
    name: 'PLAYWRIGHT_ADMIN',
    email: process.env.PLAYWRIGHT_ADMIN_EMAIL_PRIMARY || 'admin@jolene.app',
    password: process.env.PLAYWRIGHT_ADMIN_PASSWORD_PRIMARY || '',
  },
  {
    name: 'ADMIN_TEST',
    email: 'admin@jolene.app',
    password: process.env.PLAYWRIGHT_ADMIN_PASSWORD_FALLBACK || '',
  },
].filter(({ email, password }) => email && password);

if (!url || !publishableKey || !githubEnv) {
  console.error(
    'E2E_SUPABASE_URL, E2E_PUBLISHABLE_KEY et GITHUB_ENV sont requis.',
  );
  process.exit(2);
}
if (candidates.length === 0) {
  console.error('Aucun secret administrateur E2E n’est configuré.');
  process.exit(2);
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function login(email, password) {
  let lastStatus = 0;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
        method: 'POST',
        headers: {
          apikey: publishableKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email, password }),
        signal: AbortSignal.timeout(45_000),
      });
      lastStatus = response.status;
      const payload = await response.json().catch(() => ({}));
      if (response.ok && payload?.access_token) {
        return { accessToken: payload.access_token, status: response.status };
      }
      if (response.status !== 429 && response.status < 500) break;
    } catch {
      lastStatus = 0;
    }
    await wait(attempt * 3_000);
  }
  return { accessToken: '', status: lastStatus };
}

for (const { name, email, password } of candidates) {
  console.log(`::add-mask::${password}`);
  const result = await login(email, password);
  if (!result.accessToken) {
    console.warn(`${name} refusé pour l’admin E2E (HTTP ${result.status || '000'}).`);
    continue;
  }

  await appendFile(
    githubEnv,
    `PLAYWRIGHT_ADMIN_EMAIL=${email}\n`
      + `PLAYWRIGHT_ADMIN_PASSWORD<<JOLENE_ADMIN_EOF\n${password}\nJOLENE_ADMIN_EOF\n`,
  );
  await fetch(`${url}/auth/v1/logout`, {
    method: 'POST',
    headers: {
      apikey: publishableKey,
      Authorization: `Bearer ${result.accessToken}`,
    },
    signal: AbortSignal.timeout(20_000),
  }).catch(() => {});
  console.log(`Compte admin E2E vérifié via ${name} ✓`);
  process.exit(0);
}

console.error('Aucune paire de secrets GitHub admin E2E n’est valide.');
process.exit(1);
