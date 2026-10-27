// Admission read-only d'une recette destructive, jamais un déploiement.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';

export const PROJECT = 'mejpriaetwgtcstbgfid';
const API = `https://api.supabase.com/v1/projects/${PROJECT}`;
const FIXTURE = 'tests/fixtures/staging-delete-account/';
const FILES = ['supabase/functions/_shared/admin-auth.ts', 'supabase/functions/_shared/cors.ts',
  'supabase/functions/_shared/rate-limit.ts', 'supabase/functions/delete-account/index.ts'];
const LIMIT = 2 * 1024 * 1024;
const digest = value => createHash('sha256').update(value).digest('hex');
const fail = code => { throw new Error(`DELETE_ACCOUNT_SAFETY_${code}`); };
const validSha = value => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value);

export function sourceFromGit(env = process.env, cwd = process.cwd()) {
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8', timeout: 15_000,
    maxBuffer: LIMIT, stdio: ['ignore', 'pipe', 'pipe'], env: { PATH: process.env.PATH,
      LC_ALL: 'C', GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', GIT_TERMINAL_PROMPT: '0' } });
  try {
    const sha = git(['rev-parse', 'HEAD']).trim();
    if (!validSha(env.JOLENE_E2E_EXPECTED_SHA) || sha !== env.JOLENE_E2E_EXPECTED_SHA) fail('SHA');
    const read = path => git(['show', `${sha}:${path}`]);
    return { sha, manifest: JSON.parse(read(`${FIXTURE}safe-v55.json`)), query: read(`${FIXTURE}catalogue.sql`),
      files: new Map(FILES.map(path => [path, read(path)])) };
  } catch { fail('COMMITTED_SOURCE'); }
}

export function checkSource(source) {
  const m = source.manifest;
  if (!validSha(source.sha) || m?.schemaVersion !== 1 || m.projectRef !== PROJECT
    || m.edge?.slug !== 'delete-account' || m.edge.version !== 55 || m.edge.status !== 'ACTIVE'
    || m.edge.verify_jwt !== false || m.edge.import_map !== false || m.edge.import_map_path !== null
    || !isDeepStrictEqual(Object.keys(m.files ?? {}).sort(), FILES.slice().sort())
    || !(source.files instanceof Map) || source.files.size !== FILES.length
    || FILES.some(path => typeof source.files.get(path) !== 'string' || digest(source.files.get(path)) !== m.files[path])
    || typeof source.query !== 'string' || digest(source.query) !== m.catalogueQuerySha256
    || m.catalogue?.routines?.length !== 7 || m.catalogue?.psc_routines?.length !== 1) fail('SOURCE');
}

function checkMetadata(rows, expected) {
  if (!Array.isArray(rows)) fail('METADATA');
  const matching = rows.filter(row => row?.slug === 'delete-account');
  if (matching.length !== 1) fail('METADATA');
  const row = matching[0];
  const projection = Object.fromEntries(Object.keys(expected).map(key => [key, row[key] ?? null]));
  if (!isDeepStrictEqual(projection, expected)) fail('DEPLOYMENT_DRIFT');
}

async function readResponse(response, files = false) {
  const reader = response.body?.getReader();
  if (!reader) fail('BODY');
  const chunks = []; let size = 0;
  while (true) {
    const { done, value } = await reader.read(); if (done) break;
    size += value.byteLength;
    if (size > LIMIT) { await reader.cancel(); fail('SIZE'); }
    chunks.push(Buffer.from(value));
  }
  const bytes = Buffer.concat(chunks, size), type = response.headers.get('content-type') ?? '';
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    if (files && /^multipart\/form-data\s*;/i.test(type)) {
      const form = await new Response(bytes, { headers: { 'content-type': type } }).formData();
      const rows = []; let parts = 0, metadata = false;
      for (const [name, part] of form) {
        if (++parts > 8) fail('MULTIPART');
        // Métadonnées non exécutées : seule la source et le catalogue lu
        // via l'API Management authentifiée déterminent l'admission.
        if (name === 'metadata') {
          if (metadata || typeof part !== 'string' || part.length > 4096) fail('MULTIPART');
          metadata = true; continue;
        }
        if (typeof part === 'string' || part.size > LIMIT) fail('MULTIPART');
        rows.push({ name: part.name, content: new TextDecoder('utf-8', { fatal: true }).decode(await part.arrayBuffer()) });
      }
      return { files: rows };
    }
    return JSON.parse(bytes.toString('utf8'));
  } catch { fail('BODY_FORMAT'); }
}

export function checkBody(value, source) {
  const rows = Array.isArray(value) ? value : value?.files;
  if (!Array.isArray(rows) || rows.length !== FILES.length) fail('BODY_FILES');
  const found = new Set();
  for (const row of rows) {
    if (typeof row?.name !== 'string' || typeof row.content !== 'string'
      || /[\0\r\n?#\\]/.test(row.name) || row.name.split('/').includes('..')) fail('BODY_PATH');
    const suffix = /(?:^|\/)(?:supabase\/)?functions\/(.+)$/.exec(row.name)?.[1];
    const path = suffix ? `supabase/functions/${suffix}` : '';
    if (!source.files.has(path) || found.has(path) || row.content !== source.files.get(path)) fail('BODY_SOURCE');
    found.add(path);
  }
}

// Le job et les déploiements respectent jolene-supabase-staging-writes.
// Deux lectures de métadonnées détectent une dérive observée ; elles ne sont
// pas un verrou atomique contre un opérateur externe ignorant ce protocole.
export function createDeletionSafetyGate({ env = process.env, source = sourceFromGit(env), fetchImpl = fetch } = {}) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_REPOSITORY !== 'Gabpcd/JJJJJ'
    || env.GITHUB_JOB !== 'comptes' || !['pull_request', 'workflow_dispatch'].includes(env.GITHUB_EVENT_NAME)
    || env.STAGING_SUPABASE_PROJECT_REF !== PROJECT || env.STAGING_SUPABASE_URL !== `https://${PROJECT}.supabase.co`
    || !env.STAGING_SUPABASE_ACCESS_TOKEN?.trim() || source.sha !== env.JOLENE_E2E_EXPECTED_SHA) fail('CONTEXT');
  checkSource(source);
  async function request(path, body, files = false) {
    try {
      const response = await fetchImpl(`${API}${path}`, { method: body === undefined ? 'GET' : 'POST',
        redirect: 'error', signal: AbortSignal.timeout(15_000), headers: {
          Authorization: `Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json',
          Accept: files ? 'multipart/form-data, application/json' : 'application/json' },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
      if (!response.ok) fail('HTTP');
      return await readResponse(response, files);
    } catch { fail('READ_REFUSED'); }
  }
  return async function verify() {
    checkMetadata(await request('/functions'), source.manifest.edge);
    checkBody(await request('/functions/delete-account/body', undefined, true), source);
    const rows = await request('/database/query', { query: source.query, read_only: true });
    if (!Array.isArray(rows) || rows.length !== 1 || !isDeepStrictEqual(rows[0]?.catalogue, source.manifest.catalogue)) fail('RPC_DRIFT');
    checkMetadata(await request('/functions'), source.manifest.edge);
  };
}
