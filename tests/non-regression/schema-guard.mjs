#!/usr/bin/env node
/**
 * Garde-fou schéma — non-régression structurelle de la base Supabase.
 *
 * Vérifie que la base pointée par SUPABASE_DB_URL expose bien les tables,
 * colonnes, fonctions et RLS listées dans schema-expectations.json.
 * Toute dérive (colonne renommée, fonction supprimée, RLS désactivée) fait
 * sortir le process en code 1 avec le détail exact de chaque manquement —
 * c'est la classe de bugs Sprint 17 (« contrainte désynchronisée du code »)
 * qu'on attrape ici avant le déploiement.
 *
 * Usage :
 *   SUPABASE_DB_URL=postgresql://... npm run test:schema
 *   (ou SUPABASE_DB_URL=... dans .env / .env.local à la racine du repo)
 */
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const ICI = dirname(fileURLToPath(import.meta.url));

function lireDbUrl() {
  if (process.env.SUPABASE_DB_URL) return process.env.SUPABASE_DB_URL;
  for (const nom of ['.env', '.env.local']) {
    const chemin = join(process.cwd(), nom);
    if (!existsSync(chemin)) continue;
    for (const ligne of readFileSync(chemin, 'utf8').split(/\r?\n/)) {
      const m = ligne.match(/^\s*(?:export\s+)?SUPABASE_DB_URL\s*=\s*(.+?)\s*$/);
      if (m) return m[1].replace(/^["']|["']$/g, '');
    }
  }
  return null;
}

const dbUrl = lireDbUrl();
if (!dbUrl) {
  console.error("✗ schema-guard : SUPABASE_DB_URL introuvable (ni env, ni .env, ni .env.local).");
  process.exit(1);
}

const attentes = JSON.parse(
  readFileSync(join(ICI, 'schema-expectations.json'), 'utf8'),
);

const echecs = [];
const client = new pg.Client({
  connectionString: dbUrl,
  application_name: 'schema-guard',
  connectionTimeoutMillis: 15_000,
});

try {
  await client.connect();

  // 1. Tables + colonnes — information_schema.columns
  for (const [table, colonnes] of Object.entries(attentes.tables)) {
    const { rows } = await client.query(
      `SELECT column_name FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = $1`,
      [table],
    );
    if (rows.length === 0) {
      echecs.push(`table absente : public.${table}`);
      continue;
    }
    const presentes = new Set(rows.map((r) => r.column_name));
    for (const col of colonnes) {
      if (!presentes.has(col)) echecs.push(`colonne absente : ${table}.${col}`);
    }
  }

  // 2. Fonctions — pg_proc (le nom suffit : une suppression ou un rename casse
  //    les 74 call sites du wrapper audit, cf. incident fn_ecrire_audit_safe)
  const { rows: fns } = await client.query(
    `SELECT p.proname FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = ANY($1)`,
    [attentes.functions],
  );
  const fnPresentes = new Set(fns.map((r) => r.proname));
  for (const fn of attentes.functions) {
    if (!fnPresentes.has(fn)) echecs.push(`fonction absente : public.${fn}()`);
  }

  // 3. RLS activée — pg_class.relrowsecurity
  const { rows: rls } = await client.query(
    `SELECT c.relname, c.relrowsecurity FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname = ANY($1)`,
    [attentes.rls],
  );
  const rlsParTable = new Map(rls.map((r) => [r.relname, r.relrowsecurity]));
  for (const table of attentes.rls) {
    if (!rlsParTable.has(table)) {
      echecs.push(`RLS invérifiable (table absente) : ${table}`);
    } else if (!rlsParTable.get(table)) {
      echecs.push(`RLS DÉSACTIVÉE sur table sensible : ${table}`);
    }
  }
} catch (err) {
  echecs.push(`connexion/requête impossible : ${err.message}`);
} finally {
  await client.end().catch(() => {});
}

if (echecs.length > 0) {
  console.error(`✗ schema-guard : ${echecs.length} manquement(s) détecté(s)\n`);
  for (const e of echecs) console.error(`  - ${e}`);
  process.exit(1);
}

console.log(
  `✓ schema-guard : ${Object.keys(attentes.tables).length} tables, ` +
    `${attentes.functions.length} fonctions, ${attentes.rls.length} RLS — conformes.`,
);
