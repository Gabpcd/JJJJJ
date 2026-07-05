#!/usr/bin/env npx tsx
/**
 * populate-baseline-statements.ts — 9.0 (post-squash)
 *
 * PROBLÈME : le squash a enregistré la baseline dans le registre prod avec un
 * INSERT (version, name) SANS la colonne `statements`. Or le branching Supabase
 * (branche preview / rebuild from scratch) rejoue les migrations depuis
 * `supabase_migrations.schema_migrations.statements` — PAS depuis les fichiers
 * git. Résultat : une branche neuve rejouait « rien » pour la baseline → 0 table
 * (constaté sur recette-escrow-post-squash + recette-escrow-v2, 04-05/07/2026).
 *
 * CE SCRIPT (source unique = le fichier du repo, aucun SQL ad hoc) :
 *   1. Lit supabase/migrations/00000000000000_baseline_prod.sql (préambule
 *      CREATE EXTENSION inclus).
 *   2. Le découpe en statements individuels (machine à états : commentaires
 *      ligne/bloc, chaînes '…' / E'…' / "…", dollar-quoting $tag$…$tag$).
 *      Découpage PARTITIONNANT : concat(statements) == fichier, octet pour
 *      octet (vérifié, sinon abort) → le hash joint est comparable au fichier.
 *   3. Émet build/populate-baseline/batch_NNN.sql : le batch 001 fait
 *      `SET statements = ARRAY[…]`, les suivants `SET statements = statements
 *      || ARRAY[…]` (le fichier fait ~2 Mo, impossible en un seul appel).
 *      + verify.sql (compte + md5 du contenu joint) + manifest.json.
 *
 * EXÉCUTION : workflow `populate-baseline-registry` (Management API + secrets
 * repo, comme le step Heal de deploy-supabase). Métadonnées uniquement —
 * n'altère AUCUN objet du schéma prod. Backup du registre en artifact AVANT
 * écriture. Rollback : UPDATE supabase_migrations.schema_migrations
 * SET statements = NULL WHERE version = '00000000000000';
 *
 * Vérifications post-écriture (obligatoires, cf. protocole registre) :
 *   - statements IS NOT NULL, array_length == manifest.nbStatements
 *   - md5(array_to_string(statements,'')) == manifest.md5File
 *   - premier élément = la ligne pgcrypto du préambule
 */
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const BASELINE = join(ROOT, 'supabase/migrations/00000000000000_baseline_prod.sql');
const OUT_DIR = join(ROOT, 'build/populate-baseline');
const VERSION = '00000000000000';
const MAX_BATCH_BYTES = 70_000; // taille max du SQL d'un appel MCP
const TAG = 'SBQ7f'; // tag de dollar-quoting pour transporter les statements

// ── 1. Lecture ───────────────────────────────────────────────────────────────
const sql = readFileSync(BASELINE, 'utf8');
const md5File = createHash('md5').update(sql, 'utf8').digest('hex');
if (sql.includes(`$${TAG}$`)) {
  console.error(`ABORT : le tag $${TAG}$ apparaît dans le fichier — changer TAG.`);
  process.exit(1);
}

// ── 2. Découpage (machine à états, partitionnant) ────────────────────────────
type State = 'code' | 'lineComment' | 'blockComment' | 'single' | 'double' | 'dollar';
const statements: string[] = [];
let state: State = 'code';
let blockDepth = 0;
let dollarTag = '';
let start = 0;
let i = 0;
const n = sql.length;
while (i < n) {
  const c = sql[i];
  const c2 = sql.substr(i, 2);
  switch (state) {
    case 'code':
      if (c2 === '--') { state = 'lineComment'; i += 2; }
      else if (c2 === '/*') { state = 'blockComment'; blockDepth = 1; i += 2; }
      else if (c === "'") { state = 'single'; i++; }
      else if (c === '"') { state = 'double'; i++; }
      else if (c === '$') {
        // ouverture éventuelle d'un dollar-quote : $tag$ (tag = [A-Za-z0-9_]*)
        const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i));
        if (m) { state = 'dollar'; dollarTag = m[0]; i += m[0].length; }
        else i++;
      } else if (c === ';') {
        statements.push(sql.slice(start, i + 1));
        start = i + 1;
        i++;
      } else i++;
      break;
    case 'lineComment':
      if (c === '\n') state = 'code';
      i++;
      break;
    case 'blockComment':
      if (c2 === '/*') { blockDepth++; i += 2; }
      else if (c2 === '*/') { blockDepth--; i += 2; if (blockDepth === 0) state = 'code'; }
      else i++;
      break;
    case 'single':
      // standard_conforming_strings=on (posé en tête du dump) : le seul
      // échappement est le doublage ''. Vérifié : 0 backslash dans le fichier
      // (les 6 chaînes E'…' n'en contiennent pas non plus).
      if (c === "'" && sql[i + 1] === "'") i += 2; // '' échappé
      else if (c === "'") { state = 'code'; i++; }
      else i++;
      break;
    case 'double':
      if (c === '"' && sql[i + 1] === '"') i += 2;
      else if (c === '"') { state = 'code'; i++; }
      else i++;
      break;
    case 'dollar':
      if (sql.startsWith(dollarTag, i)) { state = 'code'; i += dollarTag.length; }
      else i++;
      break;
  }
}
if (start < n) {
  // reliquat après le dernier ';' (commentaires/blancs) → collé au dernier stmt
  if (statements.length) statements[statements.length - 1] += sql.slice(start);
  else statements.push(sql.slice(start));
}

// ── 3. Invariant : partition exacte ──────────────────────────────────────────
const joined = statements.join('');
if (joined !== sql) {
  console.error('ABORT : concat(statements) != fichier — bug de découpage.');
  process.exit(1);
}
const md5Joined = createHash('md5').update(joined, 'utf8').digest('hex');

// ── 4. Émission des batches ──────────────────────────────────────────────────
mkdirSync(OUT_DIR, { recursive: true });
const lit = (s: string) => `$${TAG}$${s}$${TAG}$`;
let batchIdx = 0;
let cursor = 0;
const batchFiles: string[] = [];
while (cursor < statements.length) {
  const parts: string[] = [];
  let size = 0;
  while (cursor < statements.length) {
    const piece = lit(statements[cursor]);
    if (parts.length && size + piece.length > MAX_BATCH_BYTES) break;
    parts.push(piece);
    size += piece.length + 2;
    cursor++;
  }
  batchIdx++;
  const arr = `ARRAY[${parts.join(',\n')}]::text[]`;
  const op = batchIdx === 1 ? `statements = ${arr}` : `statements = statements || ${arr}`;
  const body =
    `-- populate-baseline batch ${batchIdx} (statements ${cursor - parts.length + 1}..${cursor}/${statements.length})\n` +
    `UPDATE supabase_migrations.schema_migrations SET ${op} WHERE version = '${VERSION}';\n`;
  const fname = `batch_${String(batchIdx).padStart(3, '0')}.sql`;
  writeFileSync(join(OUT_DIR, fname), body);
  batchFiles.push(fname);
}

// ── 5. verify.sql + manifest ─────────────────────────────────────────────────
writeFileSync(
  join(OUT_DIR, 'verify.sql'),
  `SELECT
  array_length(statements,1)               AS nb_statements,   -- attendu : ${statements.length}
  md5(array_to_string(statements,''))      AS md5_joint,       -- attendu : ${md5File}
  left(statements[1], 80)                  AS premier_element  -- attendu : ligne pgcrypto
FROM supabase_migrations.schema_migrations WHERE version = '${VERSION}';\n`,
);
const manifest = {
  fichier: 'supabase/migrations/00000000000000_baseline_prod.sql',
  tailleOctets: Buffer.byteLength(sql, 'utf8'),
  md5File,
  md5Joined,
  nbStatements: statements.length,
  nbBatches: batchIdx,
  maxBatchBytes: MAX_BATCH_BYTES,
  tag: TAG,
};
writeFileSync(join(OUT_DIR, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify(manifest, null, 2));
console.log(`OK — ${batchIdx} batches dans build/populate-baseline/`);
