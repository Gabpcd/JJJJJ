#!/usr/bin/env node

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = process.cwd();
const sourceRoots = ['scripts', 'e2e', 'supabase/functions'];
const passwordMutation =
  /updateUserById\s*\([\s\S]{0,800}?\bpassword(?:\s*:|\s*[,}])/;
const allowed = new Set([
  'scripts/seed-demo.ts',
  'e2e/helpers/garantir-etablissement-playwright.ts',
]);

function walk(path) {
  const files = [];
  for (const entry of readdirSync(path)) {
    const absolute = join(path, entry);
    if (statSync(absolute).isDirectory()) files.push(...walk(absolute));
    else if (/\.(?:[cm]?[jt]sx?)$/.test(entry)) files.push(absolute);
  }
  return files;
}

const mutators = sourceRoots
  .flatMap((path) => walk(join(root, path)))
  .filter((path) => passwordMutation.test(readFileSync(path, 'utf8')))
  .map((path) => relative(root, path))
  .sort();

const unexpected = mutators.filter((path) => !allowed.has(path));
const missing = [...allowed].filter((path) => !mutators.includes(path));
const errors = [];

if (unexpected.length) {
  errors.push(
    `Mutation de mot de passe Auth non autorisée : ${unexpected.join(', ')}`,
  );
}
if (missing.length) {
  errors.push(
    `Allowlist obsolète (mutation attendue introuvable) : ${missing.join(', ')}`,
  );
}

const seedDemo = readFileSync(join(root, 'scripts/seed-demo.ts'), 'utf8');
const seedUpdate = seedDemo.indexOf('updateUserById(existing.id');
for (const invariant of [
  'PROTECTED_ADMIN_EMAILS.has(DEMO_EMAIL)',
  ".from('equipe_admin')",
  ".eq('user_id', existing.id)",
  "existing.app_metadata?.role === 'ADMIN_PLATEFORME'",
  "existing.user_metadata?.role === 'ADMIN_PLATEFORME'",
  'Impossible de prouver que le compte cible',
]) {
  const index = seedDemo.indexOf(invariant);
  if (index < 0 || index > seedUpdate) {
    errors.push(`seed-demo : garde absente ou placée après le reset : ${invariant}`);
  }
}

const playwright = readFileSync(
  join(root, 'e2e/helpers/garantir-etablissement-playwright.ts'),
  'utf8',
);
for (const invariant of [
  "const EMAIL_ETABLISSEMENT_PLAYWRIGHT = 'playwright-etab@jolene.app'",
  'p_email: EMAIL_ETABLISSEMENT_PLAYWRIGHT',
  "role: 'ADMIN_ETABLISSEMENT'",
  'is_test_playwright: true',
  'updateUserById(userId',
]) {
  if (!playwright.includes(invariant)) {
    errors.push(`fixture Playwright établissement : invariant absent : ${invariant}`);
  }
}

if (errors.length) {
  for (const error of errors) console.error(`✗ ${error}`);
  process.exit(1);
}

console.log(
  `✓ resets Auth bornés à ${mutators.length} fixture(s), aucun compte plateforme ciblable`,
);
