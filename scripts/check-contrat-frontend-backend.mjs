#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// Vérification de contrat front ↔ back (raccords).
//
// Objectif : empêcher qu'une fonctionnalité meure SILENCIEUSEMENT parce que le
// frontend référence un RPC / une edge function / un bucket de storage qui
// n'existe NI en prod NI dans le repo. C'est exactement la classe de bugs qui a
// motivé cette couche fiabilité (fn_ma_streak, fn_soignant_score_breakdown,
// buckets factures-honoraires/avoirs introuvables, etc.).
//
// Méthode :
//   1. Extrait de src/ tous les .rpc('x'), .functions.invoke('x'),
//      .storage.from('x') (multi-ligne).
//   2. Construit l'ensemble « existant » = état PROD ∪ objets définis dans le repo
//      (migrations + supabase/functions). L'union évite les faux positifs quand
//      une PR ajoute le backend ET le frontend dans le même commit.
//   3. Échoue (exit 1) si une référence n'existe nulle part.
//
// Introspection PROD :
//   - via Management API (SUPABASE_ACCESS_TOKEN + SUPABASE_PROJECT_REF) en CI ;
//   - via fichier JSON {functions:[],buckets:[],edgeFunctions:[]} si
//     CONTRAT_INTROSPECTION_FILE est défini (tests locaux) ;
//   - sinon prod vide → « existant » = repo seul (utile en local pour auditer).
// ─────────────────────────────────────────────────────────────────────────────

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, extname } from 'node:path';

const ROOT = process.cwd();
const SRC_DIR = join(ROOT, 'src');
const MIGRATIONS_DIR = join(ROOT, 'supabase', 'migrations');
const FUNCTIONS_DIR = join(ROOT, 'supabase', 'functions');

// Références dynamiques connues (nom calculé à l'exécution) ou objets gérés
// hors de ce périmètre. À garder court et justifié.
const ALLOWLIST = new Set([
  'fn_xxx', // placeholder de doc (JSDoc useApiCall + docs/*), pas un vrai appel
]);

// ── 1. Extraction des références frontend ────────────────────────────────────
function walk(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (entry === 'node_modules' || entry === 'dist') continue;
      walk(full, acc);
    } else if (['.ts', '.tsx', '.js', '.jsx'].includes(extname(entry))) {
      acc.push(full);
    }
  }
  return acc;
}

const RE_RPC = /\.rpc\(\s*['"`]([a-zA-Z0-9_]+)['"`]/g;
const RE_INVOKE = /\.functions\s*\.invoke\(\s*['"`]([a-zA-Z0-9_-]+)['"`]/g;
const RE_BUCKET = /\.storage\s*\.from\(\s*['"`]([a-zA-Z0-9_-]+)['"`]/g;

function extractReferences(files) {
  const rpcs = new Map();    // name -> Set(file)
  const invokes = new Map();
  const buckets = new Map();
  const add = (map, name, file) => {
    if (!map.has(name)) map.set(name, new Set());
    map.get(name).add(file.replace(ROOT + '/', ''));
  };
  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    for (const m of text.matchAll(RE_RPC)) add(rpcs, m[1], file);
    for (const m of text.matchAll(RE_INVOKE)) add(invokes, m[1], file);
    for (const m of text.matchAll(RE_BUCKET)) add(buckets, m[1], file);
  }
  return { rpcs, invokes, buckets };
}

// ── 2. Objets définis dans le repo ───────────────────────────────────────────
function repoFunctions() {
  const names = new Set();
  if (!existsSync(MIGRATIONS_DIR)) return names;
  const re = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?["']?([a-zA-Z0-9_]+)/gi;
  for (const f of readdirSync(MIGRATIONS_DIR)) {
    if (!f.endsWith('.sql')) continue;
    const text = readFileSync(join(MIGRATIONS_DIR, f), 'utf8');
    for (const m of text.matchAll(re)) names.add(m[1]);
  }
  return names;
}

function repoBuckets() {
  const names = new Set();
  if (!existsSync(MIGRATIONS_DIR)) return names;
  // insert into storage.buckets (...) values ('id', ...)  /  storage.create_bucket('id'
  const reInsert = /storage\.buckets[\s\S]{0,200}?values\s*\(\s*['"]([a-zA-Z0-9_-]+)['"]/gi;
  const reCreate = /storage\.create_bucket\(\s*['"]([a-zA-Z0-9_-]+)['"]/gi;
  for (const f of readdirSync(MIGRATIONS_DIR)) {
    if (!f.endsWith('.sql')) continue;
    const text = readFileSync(join(MIGRATIONS_DIR, f), 'utf8');
    for (const m of text.matchAll(reInsert)) names.add(m[1]);
    for (const m of text.matchAll(reCreate)) names.add(m[1]);
  }
  return names;
}

function repoEdgeFunctions() {
  const names = new Set();
  if (!existsSync(FUNCTIONS_DIR)) return names;
  for (const entry of readdirSync(FUNCTIONS_DIR)) {
    if (entry.startsWith('_')) continue; // _shared, etc.
    if (statSync(join(FUNCTIONS_DIR, entry)).isDirectory()) names.add(entry);
  }
  return names;
}

// ── 3. Introspection PROD ────────────────────────────────────────────────────
async function prodIntrospection() {
  const file = process.env.CONTRAT_INTROSPECTION_FILE;
  if (file && existsSync(file)) {
    const j = JSON.parse(readFileSync(file, 'utf8'));
    return {
      functions: new Set(j.functions || []),
      buckets: new Set(j.buckets || []),
      edgeFunctions: new Set(j.edgeFunctions || []),
    };
  }
  const token = process.env.SUPABASE_ACCESS_TOKEN;
  const ref = process.env.SUPABASE_PROJECT_REF;
  if (!token || !ref) {
    console.warn('⚠️  Pas d\'introspection PROD (ni CONTRAT_INTROSPECTION_FILE ni SUPABASE_ACCESS_TOKEN/REF). Vérification repo-seul.');
    return { functions: new Set(), buckets: new Set(), edgeFunctions: new Set() };
  }
  const api = 'https://api.supabase.com';
  const sql = `SELECT json_build_object(
    'functions', (SELECT coalesce(json_agg(DISTINCT p.proname), '[]'::json)
                  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'),
    'buckets', (SELECT coalesce(json_agg(id), '[]'::json) FROM storage.buckets)
  ) AS r;`;
  const dbRes = await fetch(`${api}/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (!dbRes.ok) throw new Error(`Management API /database/query ${dbRes.status}: ${await dbRes.text()}`);
  const dbJson = await dbRes.json();
  const row = (Array.isArray(dbJson) ? dbJson[0] : dbJson?.result?.[0])?.r || {};
  const fnRes = await fetch(`${api}/v1/projects/${ref}/functions`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!fnRes.ok) throw new Error(`Management API /functions ${fnRes.status}: ${await fnRes.text()}`);
  const fnJson = await fnRes.json();
  return {
    functions: new Set(row.functions || []),
    buckets: new Set(row.buckets || []),
    edgeFunctions: new Set((fnJson || []).map((f) => f.slug)),
  };
}

// ── 4. Diff + rapport ────────────────────────────────────────────────────────
function check(label, refs, existing, lines) {
  const missing = [];
  for (const [name, where] of refs) {
    if (ALLOWLIST.has(name)) continue;
    if (!existing.has(name)) missing.push({ name, where: [...where] });
  }
  if (missing.length) {
    lines.push(`\n❌ ${label} introuvable(s) (${missing.length}) :`);
    for (const { name, where } of missing.sort((a, b) => a.name.localeCompare(b.name))) {
      lines.push(`   • ${name}`);
      for (const w of where) lines.push(`       ↳ ${w}`);
    }
  } else {
    lines.push(`✅ ${label} : ${refs.size} référence(s), toutes résolues.`);
  }
  return missing.length;
}

async function main() {
  const files = walk(SRC_DIR);
  const { rpcs, invokes, buckets } = extractReferences(files);

  const prod = await prodIntrospection();
  const fnExisting = new Set([...prod.functions, ...repoFunctions()]);
  const bucketExisting = new Set([...prod.buckets, ...repoBuckets()]);
  const edgeExisting = new Set([...prod.edgeFunctions, ...repoEdgeFunctions()]);

  const lines = [];
  lines.push(`Contrat front ↔ back — ${files.length} fichiers src/ analysés.`);
  let nbMissing = 0;
  nbMissing += check('RPC', rpcs, fnExisting, lines);
  nbMissing += check('Edge function (invoke)', invokes, edgeExisting, lines);
  nbMissing += check('Bucket storage', buckets, bucketExisting, lines);

  console.log(lines.join('\n'));
  if (nbMissing > 0) {
    console.error(`\n💥 ${nbMissing} raccord(s) cassé(s) — le frontend appelle du backend inexistant.`);
    process.exit(1);
  }
  console.log('\n🎉 Tous les raccords front ↔ back sont résolus.');
}

main().catch((e) => { console.error(e); process.exit(2); });
