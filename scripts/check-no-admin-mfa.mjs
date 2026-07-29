#!/usr/bin/env node

import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} from 'node:fs';
import { extname, join, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = resolve(import.meta.dirname, '..');
const MFA_REMOVAL_MIGRATION =
  '20260729121419_requalifier_donnees_prelaunch_et_supprimer_mfa_admin.sql';

function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    // Exiger début de ligne ou espace évite de prendre `https://...` pour un
    // commentaire et de masquer une URL vers une ancienne Edge Function.
    .replace(/(^|\s)\/\/.*$/gm, '$1')
    .replace(/(^|\s)--.*$/gm, '$1');
}

function walk(directory) {
  if (!existsSync(directory)) return [];
  const files = [];
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) files.push(...walk(path));
    else files.push(path);
  }
  return files;
}

export function findRuntimeMfaViolations(source) {
  const code = stripComments(source);
  const patterns = [
    ['API Supabase MFA', /\bauth\.mfa\.(?:enroll|challenge|verify|listFactors)\s*\(/i],
    ['lecture de claims MFA', /\bgetClaims\s*\(/i],
    ['niveau AAL2', /['"]aal2['"]/i],
    ['ancienne fonction admin-2fa', /\badmin-2fa\b/i],
  ];
  return patterns
    .filter(([, pattern]) => pattern.test(code))
    .map(([label]) => label);
}

export function findMigrationMfaViolations(source) {
  const sql = stripComments(source);
  const violations = [];

  // Exigence réelle du niveau AAL2, dans les deux ordres usuels. Une assertion
  // d'absence du type ILIKE '%auth.jwt()%aal%aal2%' ne contient ni extraction
  // ->> 'aal' ni opérateur de comparaison et reste donc autorisée.
  const aalAfterJwt =
    /auth\.jwt\s*\(\s*\)\s*(?:->>|#>>?)\s*['"]aal['"][\s\S]{0,180}?(?:=|!=|<>|IS\s+(?:NOT\s+)?DISTINCT\s+FROM)\s*['"]aal2['"]/i;
  const jwtAfterAal =
    /['"]aal2['"]\s*(?:=|!=|<>)\s*[\s\S]{0,180}?auth\.jwt\s*\(\s*\)\s*(?:->>|#>>?)\s*['"]aal['"]/i;
  if (aalAfterJwt.test(sql) || jwtAfterAal.test(sql)) {
    violations.push('exigence auth.jwt/AAL2');
  }

  if (/\bgetClaims\s*\([^)]*\)[\s\S]{0,400}\baal2\b/i.test(sql)) {
    violations.push('exigence getClaims/AAL2');
  }

  // DROP/DELETE et assertions d'absence sont permis. Seules les opérations qui
  // recréent, appellent ou republient l'ancienne fonction sont interdites.
  if (
    /(?:CREATE|REPLACE|ALTER|INSERT|UPDATE|GRANT|http_post|functions\.invoke)[\s\S]{0,220}\badmin-2fa\b/i
      .test(sql)
  ) {
    violations.push('réintroduction admin-2fa');
  }

  if (/\bauth\.mfa\.(?:enroll|challenge|verify|listFactors)\s*\(/i.test(sql)) {
    violations.push('appel API auth.mfa');
  }

  // Une future purge DELETE est autorisée ; créer ou modifier des facteurs ne
  // l'est pas. Les SELECT d'assertion qui vérifient leur absence sont permis.
  if (
    /(?:INSERT\s+INTO|UPDATE|MERGE\s+INTO)\s+auth\.mfa_(?:factors|challenges|amr_claims)\b/i
      .test(sql)
  ) {
    violations.push('écriture dans les tables MFA Auth');
  }

  return violations;
}

function main() {
  const violations = [];
  const runtimeFiles = [
    ...walk(join(root, 'src')),
    ...walk(join(root, 'supabase', 'functions')),
  ].filter((path) => ['.ts', '.tsx'].includes(extname(path)));

  for (const path of runtimeFiles) {
    for (const violation of findRuntimeMfaViolations(readFileSync(path, 'utf8'))) {
      violations.push(`${relative(root, path)}: ${violation}`);
    }
  }

  for (const retiredPath of [
    'src/components/admin/AdminMfaGate.tsx',
    'supabase/functions/admin-2fa/index.ts',
  ]) {
    if (existsSync(join(root, retiredPath))) {
      violations.push(`${retiredPath}: ancien artefact MFA présent`);
    }
  }

  const config = readFileSync(join(root, 'supabase', 'config.toml'), 'utf8');
  if (config.includes('[functions.admin-2fa]')) {
    violations.push('supabase/config.toml: admin-2fa encore déclaré');
  }

  const migrationsDirectory = join(root, 'supabase', 'migrations');
  const futureMigrations = readdirSync(migrationsDirectory)
    .filter(
      (name) =>
        name.endsWith('.sql')
        && name.localeCompare(MFA_REMOVAL_MIGRATION, 'en') > 0,
    )
    .sort();

  for (const name of futureMigrations) {
    const source = readFileSync(join(migrationsDirectory, name), 'utf8');
    for (const violation of findMigrationMfaViolations(source)) {
      violations.push(`supabase/migrations/${name}: ${violation}`);
    }
  }

  if (violations.length > 0) {
    console.error('MFA administrateur réintroduit :');
    for (const violation of violations) console.error(`- ${violation}`);
    process.exit(1);
  }

  console.log(
    `✓ aucun MFA admin ; ${futureMigrations.length} migration(s) post-retrait vérifiée(s)`,
  );
}

const invokedPath = process.argv[1]
  ? pathToFileURL(resolve(process.argv[1])).href
  : '';
if (invokedPath === import.meta.url) main();
