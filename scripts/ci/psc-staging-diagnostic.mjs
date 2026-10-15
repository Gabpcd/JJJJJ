// Read-only staging inventory. Never calls authorize/callback/logout or creates a session.
// References: Supabase Management API get-project-api-keys, list-all-secrets,
// list-all-functions and get-a-function-body (checked 2026-10-14).
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { posix, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const PROJECT = 'mejpriaetwgtcstbgfid';
export const FUNCTIONS = Object.freeze(['psc-authorize', 'psc-callback', 'psc-logout', 'psc-test-connexion']);
export const SECRET_NAMES = Object.freeze(['PSC_ENVIRONMENT', 'PSC_CLIENT_ID', 'PSC_CLIENT_SECRET', 'PSC_REDIRECT_URI', 'PSC_FRONTEND_URL']);
const API = `https://api.supabase.com/v1/projects/${PROJECT}`;
const DIAGNOSTIC = `https://${PROJECT}.supabase.co/functions/v1/psc-test-connexion`;
const ENDPOINT_NAMES = ['issuer', 'authorization_endpoint', 'token_endpoint', 'userinfo_endpoint', 'end_session_endpoint'];
const MAX_BYTES = 2 * 1024 * 1024;
const sha = value => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value) && !/^0+$/.test(value);
const hash = value => createHash('sha256').update(value).digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const canonical = value => Array.isArray(value) ? value.map(canonical) : object(value)
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
class Refusal extends Error { constructor(code) { super(code); this.code = code; } }
const fail = code => { throw new Refusal(code); };

export function checkContext(env, local) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch'
    || env.GITHUB_REPOSITORY !== 'Gabpcd/JJJJJ'
    || !['refs/heads/main', 'refs/heads/test/recette-complete-20261014'].includes(env.GITHUB_REF)
    || !sha(env.GITHUB_SHA) || env.PSC_DIAGNOSTIC_EXPECTED_SHA !== env.GITHUB_SHA
    || local.sha !== env.GITHUB_SHA || local.clean !== true
    || typeof env.STAGING_SUPABASE_ACCESS_TOKEN !== 'string' || !env.STAGING_SUPABASE_ACCESS_TOKEN.trim()) fail('CONTEXT_REFUSED');
  checkCanonicalConfig(local.config);
}

export function checkCanonicalConfig(config) {
  if (typeof config !== 'string') fail('LOCAL_CONFIG_REFUSED');
  for (const slug of FUNCTIONS) {
    const sections = [...config.matchAll(new RegExp(`^\\[functions\\.${slug}\\][ \\t]*(?:#.*)?\\r?\\n([\\s\\S]*?)(?=^\\[|$(?![\\s\\S]))`, 'gm'))];
    if (sections.length !== 1) fail('LOCAL_CONFIG_REFUSED');
    const lines = sections[0][1].split('\n').map(line => line.replace(/#.*$/, '').trim()).filter(Boolean);
    // Canonical defaults: functions/<slug>/index.ts, no import map.
    if (lines.length !== 1 || !/^verify_jwt\s*=\s*false$/.test(lines[0])) fail('LOCAL_CONFIG_REFUSED');
  }
}

// Only the committed source is read. Include every local transitive import,
// including shared authentication/CORS helpers, rather than just index.ts.
export function sourceClosure(slug, readBlob) {
  if (!FUNCTIONS.includes(slug)) fail('SOURCE_REFUSED');
  const files = new Map();
  function visit(path) {
    if (files.has(path)) return;
    if (!/^supabase\/functions\/[a-zA-Z0-9_./-]+\.ts$/.test(path) || path.includes('/../') || files.size >= 100) fail('SOURCE_REFUSED');
    const content = readBlob(path);
    if (typeof content !== 'string' || Buffer.byteLength(content) > MAX_BYTES) fail('SOURCE_REFUSED');
    files.set(path, content);
    const imports = [...content.matchAll(/(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s*)["']([^"']+)["']/g)].map(match => match[1]);
    for (const specifier of imports) {
      if (specifier.startsWith('.')) visit(posix.normalize(posix.join(posix.dirname(path), specifier)));
      else if (!/^(npm:|https:\/\/|jsr:)/.test(specifier)) fail('SOURCE_IMPORT_UNSUPPORTED');
    }
  }
  visit(`supabase/functions/${slug}/index.ts`);
  return files;
}

function normalizedPath(name, slug) {
  if (typeof name !== 'string' || name.length > 1024 || /[\0\r\n?#\\]/.test(name) || name.split('/').includes('..')) fail('BODY_FORMAT_UNSUPPORTED');
  const match = name.match(/(?:^|\/)(?:supabase\/)?functions\/(.+)$/);
  const suffix = match?.[1] ?? (name === 'index.ts' ? `${slug}/index.ts` : name);
  if (!(suffix.startsWith(`${slug}/`) || suffix.startsWith('_shared/')) || !/^[a-zA-Z0-9_./-]+\.ts$/.test(suffix)) fail('BODY_FORMAT_UNSUPPORTED');
  return `supabase/functions/${suffix}`;
}

// The Management API body format is not specified beyond an object in its docs.
// Support explicit JSON file collections; unsupported ZIP/ESZIP stays UNKNOWN.
export function compareBody(slug, value, expected) {
  const rows = Array.isArray(value) ? value : object(value) ? value.files : null;
  if (!Array.isArray(rows) || rows.length < 1 || rows.length > 100) fail('BODY_FORMAT_UNSUPPORTED');
  const found = new Map();
  for (const row of rows) {
    if (!object(row) || typeof row.content !== 'string' || Buffer.byteLength(row.content) > MAX_BYTES) fail('BODY_FORMAT_UNSUPPORTED');
    const path = normalizedPath(row.name, slug);
    if (found.has(path)) fail('BODY_FORMAT_UNSUPPORTED');
    found.set(path, row.content);
  }
  const files = [...expected.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([path, content]) => ({
    path, localSha256: hash(content), deployedSha256: found.has(path) ? hash(found.get(path)) : null,
    matches: found.has(path) ? found.get(path) === content : null,
  }));
  return { status: files.some(file => file.matches === false) ? 'DIFFERENT'
    : files.some(file => file.matches === null) ? 'INCOMPLETE' : 'MATCH', files,
  dependencyScope: 'committed local transitive imports; external dependency contents not compared' };
}

export function projectDiagnostic(value) {
  if (!object(value) || !['sandbox', 'production'].includes(value.env)
    || !['secrets_ok', 'discovery_ok', 'endpoints_match'].every(key => typeof value[key] === 'boolean')
    || !Array.isArray(value.missing_secrets) || value.missing_secrets.some(name => !SECRET_NAMES.includes(name))
    || new Set(value.missing_secrets).size !== value.missing_secrets.length
    || value.secrets_ok !== (value.missing_secrets.length === 0)
    || !(value.discovery_status === null || (Number.isInteger(value.discovery_status) && value.discovery_status >= 100 && value.discovery_status <= 599))
    || !Array.isArray(value.endpoints_diff) || value.endpoints_diff.length > ENDPOINT_NAMES.length
    || !Number.isFinite(value.duration_ms) || value.duration_ms < 0 || value.duration_ms > 120000) fail('DIAGNOSTIC_SCHEMA_REFUSED');
  const fields = value.endpoints_diff.map(diff => {
    if (typeof diff !== 'string' || diff.length > 4096) fail('DIAGNOSTIC_SCHEMA_REFUSED');
    const name = diff.slice(0, diff.indexOf(':'));
    if (!ENDPOINT_NAMES.includes(name)) fail('DIAGNOSTIC_SCHEMA_REFUSED');
    return name;
  });
  if ((value.endpoints_match && (!value.discovery_ok || fields.length !== 0))
    || (value.discovery_ok && value.discovery_status !== 200)) fail('DIAGNOSTIC_SCHEMA_REFUSED');
  // No discovery_url, raw endpoint diffs, response extensions or error strings.
  return { environment: value.env, secretsOk: value.secrets_ok, missingSecrets: value.missing_secrets.slice(),
    discoveryOk: value.discovery_ok, discoveryStatus: value.discovery_status,
    endpointsMatch: value.endpoints_match, endpointDifferenceFields: fields, durationMs: value.duration_ms };
}

async function boundedJson(response) {
  const reader = response.body?.getReader();
  if (!reader) fail('RESPONSE_INVALID');
  const chunks = []; let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_BYTES) { await reader.cancel(); fail('RESPONSE_TOO_LARGE'); }
    chunks.push(value);
  }
  try { return JSON.parse(Buffer.concat(chunks, total).toString('utf8')); } catch { fail('RESPONSE_INVALID'); }
}

function entrypointMatches(value, slug) {
  if (typeof value !== 'string' || value.length > 1024 || /[\0\r\n?#\\%]/.test(value) || value.split('/').includes('..')) return false;
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value) && !value.startsWith('file://')) return false;
  if (value.startsWith('file://')) {
    try { const url = new URL(value); if (url.hostname !== '' || url.protocol !== 'file:') return false; value = url.pathname; }
    catch { return false; }
  }
  return value.endsWith(`/functions/${slug}/index.ts`) || value === `functions/${slug}/index.ts`;
}

function metadata(rows) {
  if (!Array.isArray(rows) || rows.length > 1000
    || rows.some(row => !object(row) || typeof row.slug !== 'string')
    || new Set(rows.map(row => row.slug)).size !== rows.length) fail('FUNCTION_METADATA_REFUSED');
  const functions = FUNCTIONS.map(slug => {
    const matches = rows.filter(row => row?.slug === slug);
    if (matches.length !== 1) fail('FUNCTION_METADATA_REFUSED');
    const row = matches[0];
    if (!Number.isSafeInteger(row.version) || row.version < 1 || typeof row.verify_jwt !== 'boolean'
      || !['ACTIVE', 'REMOVED', 'THROTTLED'].includes(row.status)) fail('FUNCTION_METADATA_REFUSED');
    return { slug, version: row.version, verifyJwt: row.verify_jwt, status: row.status,
      entrypointMatches: entrypointMatches(row.entrypoint_path, slug),
      importMapDisabled: row.import_map === false && (row.import_map_path == null || row.import_map_path === ''),
      metadataSha256: hash(JSON.stringify(canonical(row))),
      bundleSha256: typeof row.ezbr_sha256 === 'string' && /^[a-f0-9]{64}$/.test(row.ezbr_sha256)
        && !/^0+$/.test(row.ezbr_sha256) ? row.ezbr_sha256 : null };
  });
  // Bind the complete observed inventory, including unknown metadata fields.
  return { functions, inventorySha256: hash(JSON.stringify(canonical(rows.slice().sort((a, b) => a.slug.localeCompare(b.slug))))) };
}

export async function collectPscDiagnostic({ env, local, sources, fetchImpl = fetch }) {
  const report = { schemaVersion: 1, status: 'NON_PRET', projectRef: PROJECT, sourceSha: null,
    readOnly: true, authenticationVerified: false, frontendVerified: false, deploymentPerformed: false,
    secretPresence: null, functions: null, preKeyMetadataStable: false, metadataStable: false,
    metadataFingerprints: { before: null, beforeKeys: null, after: null },
    privilegedInvocationAllowed: false, diagnosticInvocationAttempted: false, diagnosticAttributionConfirmed: false,
    diagnostic: null, diagnosticHttpStatus: null, legacyServiceRoleAvailable: false, issues: [],
    limits: ['No PSC authentication, code/token exchange or application session created.',
      'Presence of secret names does not prove usable values or correct sandbox redirect configuration.',
      'Only decoded source files and their local imports are compared; unsupported body formats remain unknown.',
      'Privileged invocation requires matching diagnostic sources, canonical configuration and stable full metadata first.',
      'Provider discovery may be requested by the existing diagnostic function; no login endpoint is invoked.',
      'Sequential metadata snapshots detect observed drift; they cannot lock deployments atomically.'] };
  const issue = code => { if (!report.issues.includes(code)) report.issues.push(code); };
  async function request(url, token, diagnostic = false) {
    let response;
    try { response = await fetchImpl(url, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(15000),
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', ...(diagnostic ? { apikey: token } : {}) } }); }
    catch { fail('TRANSPORT_REFUSED'); }
    if (!Number.isInteger(response.status) || response.status < 100 || response.status > 599) fail('RESPONSE_INVALID');
    if (diagnostic) report.diagnosticHttpStatus = response.status;
    if (!response.ok) fail(diagnostic ? 'DIAGNOSTIC_HTTP_REFUSED' : 'MANAGEMENT_HTTP_REFUSED');
    return boundedJson(response);
  }
  async function attempt(code, action) {
    try { return await action(); } catch (error) { issue(error instanceof Refusal ? error.code : code); return null; }
  }
  try {
    checkContext(env, local);
    if (!(sources instanceof Map) || FUNCTIONS.some(slug => !(sources.get(slug) instanceof Map) || !sources.get(slug).size)) fail('SOURCE_REFUSED');
    report.sourceSha = local.sha;
    report.secretPresence = await attempt('SECRET_METADATA_UNREADABLE', async () => {
      const rows = await request(`${API}/secrets`, env.STAGING_SUPABASE_ACCESS_TOKEN);
      if (!Array.isArray(rows) || rows.length > 10000 || rows.some(row => !object(row) || typeof row.name !== 'string')) fail('SECRET_METADATA_REFUSED');
      return Object.fromEntries(SECRET_NAMES.map(name => [name, rows.some(row => row.name === name)]));
    });
    const before = await attempt('FUNCTION_METADATA_UNREADABLE', async () => metadata(await request(`${API}/functions`, env.STAGING_SUPABASE_ACCESS_TOKEN)));
    report.metadataFingerprints.before = before?.inventorySha256 ?? null;
    if (before) {
      report.functions = [];
      for (const row of before.functions) {
        const comparison = await attempt('BODY_UNREADABLE', async () => compareBody(row.slug,
          await request(`${API}/functions/${row.slug}/body`, env.STAGING_SUPABASE_ACCESS_TOKEN), sources.get(row.slug)));
        report.functions.push({ ...row, comparison: comparison ?? { status: 'UNKNOWN', files: [] } });
      }
    }
    const beforeKeys = await attempt('FUNCTION_METADATA_UNREADABLE', async () => metadata(await request(`${API}/functions`, env.STAGING_SUPABASE_ACCESS_TOKEN)));
    report.metadataFingerprints.beforeKeys = beforeKeys?.inventorySha256 ?? null;
    report.preKeyMetadataStable = before !== null && beforeKeys !== null && before.inventorySha256 === beforeKeys.inventorySha256;
    const canonicalMetadata = report.functions !== null && report.functions.every(row => row.status === 'ACTIVE'
      && row.verifyJwt === false && row.entrypointMatches && row.importMapDisabled && row.bundleSha256 !== null);
    const allSourcesMatch = report.functions !== null && report.functions.every(row => row.comparison.status === 'MATCH');
    // Do not even retrieve a privileged API key if deployed code or configuration
    // is unknown, stale, redirected through an import map, or changed during reads.
    report.privilegedInvocationAllowed = report.preKeyMetadataStable && canonicalMetadata && allSourcesMatch;
    if (report.privilegedInvocationAllowed) {
      await attempt('API_KEYS_UNREADABLE', async () => {
        const keys = await request(`${API}/api-keys?reveal=true`, env.STAGING_SUPABASE_ACCESS_TOKEN);
        if (!Array.isArray(keys)) fail('API_KEYS_REFUSED');
        const matches = keys.filter(key => key?.name === 'service_role');
        if (matches.length !== 1 || typeof matches[0].api_key !== 'string'
          || !/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(matches[0].api_key)) fail('LEGACY_SERVICE_ROLE_UNAVAILABLE');
        report.legacyServiceRoleAvailable = true;
        report.diagnosticInvocationAttempted = true;
        report.diagnostic = projectDiagnostic(await request(DIAGNOSTIC, matches[0].api_key, true));
      });
    } else issue('PRIVILEGED_DIAGNOSTIC_BLOCKED');
    const after = await attempt('FUNCTION_METADATA_UNREADABLE', async () => metadata(await request(`${API}/functions`, env.STAGING_SUPABASE_ACCESS_TOKEN)));
    report.metadataFingerprints.after = after?.inventorySha256 ?? null;
    report.metadataStable = report.preKeyMetadataStable && after !== null && before.inventorySha256 === after.inventorySha256;
    report.diagnosticAttributionConfirmed = report.diagnostic !== null && report.privilegedInvocationAllowed && report.metadataStable;
    if (!report.metadataStable) issue('FUNCTION_METADATA_CHANGED_OR_UNKNOWN');
    if (!report.secretPresence || Object.values(report.secretPresence).some(value => !value)) issue('PSC_SECRET_NAMES_MISSING_OR_UNKNOWN');
    if (!canonicalMetadata) issue('PSC_DEPLOYED_CONFIG_NOT_CANONICAL');
    if (!allSourcesMatch) issue('PSC_SOURCE_NOT_FULLY_MATCHED');
    const d = report.diagnostic;
    if (!d || d.environment !== 'sandbox' || !d.secretsOk || !d.discoveryOk || !d.endpointsMatch) issue('PSC_SANDBOX_DIAGNOSTIC_NOT_HEALTHY');
    if (report.issues.length === 0) report.status = 'CONFIGURATION_OBSERVED';
  } catch (error) { issue(error instanceof Refusal ? error.code : 'COLLECTION_REFUSED'); }
  return report;
}

export function sourceFromGit(expectedSha, cwd = process.cwd()) {
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 15000,
    maxBuffer: MAX_BYTES, env: { PATH: process.env.PATH, LC_ALL: 'C', GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', GIT_TERMINAL_PROMPT: '0' } });
  const actualSha = git(['rev-parse', 'HEAD']).trim();
  if (!sha(expectedSha) || actualSha !== expectedSha) fail('SOURCE_SHA_REFUSED');
  return { local: { sha: actualSha, clean: git(['status', '--porcelain', '--untracked-files=no']).trim() === '', config: git(['show', `${actualSha}:supabase/config.toml`]) },
    sources: new Map(FUNCTIONS.map(slug => [slug, sourceClosure(slug, path => git(['show', `${actualSha}:${path}`]))])) };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let report;
  try {
    if (process.argv.length !== 2) fail('ARGUMENTS_REFUSED');
    const source = sourceFromGit(process.env.PSC_DIAGNOSTIC_EXPECTED_SHA);
    report = await collectPscDiagnostic({ env: process.env, ...source });
  } catch { report = { schemaVersion: 1, status: 'NON_PRET', projectRef: PROJECT, readOnly: true,
    authenticationVerified: false, frontendVerified: false, deploymentPerformed: false, issues: ['SOURCE_OR_CONTEXT_REFUSED'] }; }
  try {
    writeFileSync('psc-staging-diagnostic.json', `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
    console.log(`PSC_STAGING_${report.status}: rapport expurgé enregistré ; authentification non vérifiée.`);
  } catch { console.error('PSC_REPORT_WRITE_REFUSED'); process.exitCode = 1; }
  if (!process.exitCode) process.exitCode = report.status === 'CONFIGURATION_OBSERVED' ? 0 : 2;
}
