import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';

export const PROJECT = 'mejpriaetwgtcstbgfid';
export const FUNCTION = 'generate-invoice';
export const EXPECTED = Object.freeze({ version: 15, verify_jwt: false,
  ezbr_sha256: '1be7e9620e5f61af304b4bafc029c0a0f4a80c99dd50e22a9ba9b17d23a46c1d' });
const API = `https://api.supabase.com/v1/projects/${PROJECT}`;
const MAIN = 'https://api.github.com/repos/Gabpcd/JJJJJ/git/ref/heads/main';
const URL_FUNCTION = `https://${PROJECT}.supabase.co/functions/v1/${FUNCTION}`;
const sha = x => typeof x === 'string' && /^[a-f0-9]{40}$/.test(x) && !/^0+$/.test(x);
const digest = x => typeof x === 'string' && /^[a-f0-9]{64}$/.test(x) && !/^0+$/.test(x);
const integer = x => Number.isSafeInteger(x) && x >= 0;
const canonical = x => Array.isArray(x) ? x.map(canonical) : x && typeof x === 'object' ? Object.fromEntries(Object.keys(x).sort().map(k => [k, canonical(x[k])])) : x;
class Refusal extends Error { constructor(code) { super(code); this.code = code; } }
const fail = code => { throw new Refusal(code); };
export const QUIESCENCE_SQL = `SELECT
  (SELECT count(*)::int FROM cron.job WHERE active) AS active_crons,
  (SELECT count(*)::int FROM cron.job_run_details WHERE end_time IS NULL AND status IN ('starting','running','connecting','sending')) AS running_crons,
  (SELECT count(*)::int FROM public.escrow_release_queue WHERE statut IN ('EN_ATTENTE','EN_COURS')) AS releases,
  (SELECT count(*)::int FROM public.stripe_refunds_queue WHERE statut IN ('EN_ATTENTE','EN_COURS')) AS refunds;`;

export function context(env, local) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch'
    || env.GITHUB_REPOSITORY !== 'Gabpcd/JJJJJ' || env.GITHUB_REF !== 'refs/heads/main') fail('TRUSTED_MAIN_REQUIRED');
  if (!sha(env.GITHUB_SHA) || env.GITHUB_SHA !== env.INVOICE_EXPECTED_SHA || local?.sha !== env.GITHUB_SHA || local.clean !== true) fail('EXACT_CLEAN_SHA_REQUIRED');
  if (!/^[1-9][0-9]{0,19}$/.test(env.GITHUB_RUN_ID ?? '') || !/^[1-9][0-9]{0,5}$/.test(env.GITHUB_RUN_ATTEMPT ?? '')) fail('RUN_ID_REQUIRED');
  const sections = typeof local.config === 'string' ? [...local.config.matchAll(/^\[functions\.generate-invoice\][ \t]*(?:#[^\n]*)?\r?\n([^]*?)(?=^\[|$(?![^]))/gm)] : [];
  if (sections.length !== 1 || !/^verify_jwt\s*=\s*false$/.test(sections[0][1].replace(/#[^\n]*/g, '').trim())) fail('LOCAL_JWT_MODE_REFUSED');
  return { sha: env.GITHUB_SHA, run_id: env.GITHUB_RUN_ID, run_attempt: env.GITHUB_RUN_ATTEMPT };
}

export function functionsMetadata(rows) {
  if (!Array.isArray(rows) || !rows.length || rows.length > 1000) fail('FUNCTION_METADATA_INVALID');
  const seen = new Set(), ids = new Set();
  return rows.map(x => {
    if (!x || !/^[a-z0-9][a-z0-9_-]{0,63}$/.test(x.slug ?? '') || seen.has(x.slug)
      || typeof x.id !== 'string' || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(x.id) || ids.has(x.id)
      || !integer(x.version) || typeof x.verify_jwt !== 'boolean'
      || !['ACTIVE','REMOVED','THROTTLED'].includes(x.status)
      || (x.ezbr_sha256 != null && !digest(x.ezbr_sha256))) fail('FUNCTION_METADATA_INVALID');
    seen.add(x.slug); ids.add(x.id);
    // Full catalogue fingerprint is comparison-only, never emitted or persisted.
    // Even changes to fields outside the projected tuple must stop the run.
    return { id: x.id, slug: x.slug, version: x.version, verify_jwt: x.verify_jwt,
      status: x.status, ezbr_sha256: x.ezbr_sha256 ?? null,
      metadata_digest: createHash('sha256').update(JSON.stringify(canonical(x))).digest('hex') };
  }).sort((a, b) => a.slug.localeCompare(b.slug));
}
export function compareAfter(before, after) {
  const targetBefore = before.find(x => x.slug === FUNCTION), targetAfter = after.find(x => x.slug === FUNCTION);
  if (JSON.stringify(before.filter(x => x.slug !== FUNCTION)) !== JSON.stringify(after.filter(x => x.slug !== FUNCTION))) fail('OTHER_FUNCTIONS_CHANGED');
  if (!targetAfter || targetAfter.id !== targetBefore.id || targetAfter.status !== 'ACTIVE'
    || targetAfter.version !== targetBefore.version + 1 || targetAfter.verify_jwt !== false
    || !digest(targetAfter.ezbr_sha256) || targetAfter.ezbr_sha256 === targetBefore.ezbr_sha256) fail('DEPLOYMENT_NOT_CONFIRMED');
  return { version: targetAfter.version, verify_jwt: false, ezbr_sha256: targetAfter.ezbr_sha256,
    other_functions_count: after.length - 1, other_functions_metadata_unchanged: true };
}

export function deployCommand(env, cwd, execute = execFileSync) {
  // No inherited proxies, database credentials, service-role key or CLI profile.
  const childEnv = { PATH: env.PATH, HOME: env.HOME, CI: 'true', NO_COLOR: '1', DO_NOT_TRACK: '1',
    SUPABASE_ACCESS_TOKEN: env.STAGING_SUPABASE_ACCESS_TOKEN };
  const options = { cwd, env: childEnv, encoding: 'utf8', stdio: ['ignore','pipe','pipe'], timeout: 180_000, maxBuffer: 8 * 1024 * 1024 };
  if (execute('supabase', ['--version'], options).trim() !== '2.98.0') fail('CLI_VERSION_REFUSED');
  execute('supabase', ['functions','deploy',FUNCTION,'--project-ref',PROJECT,'--use-api','--no-verify-jwt'], options);
}

export async function refreshInvoice({ env, local, fetchImpl = fetch, deploy = () => deployCommand(env, process.cwd()), checkpoint = () => {} }) {
  const report = { schema_version: 1, status: 'failed', phase: 'context', code: null, project_ref: PROJECT,
    function: FUNCTION, source_sha: null, run_id: null, run_attempt: null,
    deployment_attempted: false, deployment_confirmed: false, before: null, after: null,
    quiescence: null, probes: null, business_flow_verified: false, cloud_font_rendering_verified: false };
  const save = () => { try { checkpoint(structuredClone(report)); } catch { fail('REPORT_WRITE_FAILED'); } };
  async function request(url, { method = 'GET', body, management = false } = {}) {
    const headers = management ? { Authorization: `Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' }
      : { Accept: 'application/json', 'User-Agent': 'Jolene-staging-invoice-check', 'Cache-Control': 'no-cache' };
    try { return await fetchImpl(url, { method, headers, redirect: 'error', signal: AbortSignal.timeout(15_000), ...(body ? { body: JSON.stringify(body) } : {}) }); }
    catch { fail('REQUEST_FAILED'); }
  }
  async function json(url, options) {
    const response = await request(url, options);
    if (!response.ok) fail('HTTP_REFUSED');
    try { return await response.json(); } catch { fail('JSON_REFUSED'); }
  }
  const mainMatches = async () => { const ref = await json(MAIN); if (ref?.ref !== 'refs/heads/main' || ref.object?.type !== 'commit' || ref.object.sha !== local.sha) fail('MAIN_MOVED'); };
  try {
    const identity = context(env, local); report.source_sha = identity.sha; report.run_id = identity.run_id; report.run_attempt = identity.run_attempt;
    if (typeof env.STAGING_SUPABASE_ACCESS_TOKEN !== 'string' || !env.STAGING_SUPABASE_ACCESS_TOKEN.trim()) fail('MANAGEMENT_TOKEN_REQUIRED');
    report.phase = 'main_before'; await mainMatches();
    report.phase = 'metadata_before';
    const before = functionsMetadata(await json(`${API}/functions`, { management: true }));
    const target = before.find(x => x.slug === FUNCTION);
    if (!target || target.status !== 'ACTIVE' || target.version !== EXPECTED.version || target.verify_jwt !== EXPECTED.verify_jwt || target.ezbr_sha256 !== EXPECTED.ezbr_sha256) fail('STAGING_VERSION_OR_JWT_DRIFT');
    report.before = { ...EXPECTED };
    report.phase = 'quiescence';
    const quiet = await json(`${API}/database/query`, { method: 'POST', management: true, body: { query: QUIESCENCE_SQL, read_only: true } });
    if (!Array.isArray(quiet) || quiet.length !== 1 || !quiet[0] || Object.keys(quiet[0]).sort().join(',') !== 'active_crons,refunds,releases,running_crons'
      || Object.values(quiet[0]).some(n => n !== 0)) fail('STAGING_NOT_QUIESCENT');
    report.quiescence = { active_crons: 0, running_crons: 0, releases: 0, refunds: 0 };
    report.phase = 'main_before_deploy'; await mainMatches();
    report.phase = 'deploy'; report.deployment_attempted = true; save();
    // One command only. On a lost response, stop: no second deployment or rollback.
    try { await deploy(); } catch (error) {
      if (error instanceof Refusal && error.code === 'CLI_VERSION_REFUSED') { report.deployment_attempted = false; throw error; }
      fail('DEPLOY_RESULT_UNCERTAIN');
    }
    report.phase = 'metadata_after';
    report.after = compareAfter(before, functionsMetadata(await json(`${API}/functions`, { management: true })));
    report.deployment_confirmed = true; save();
    report.phase = 'probe_options';
    const options = await request(URL_FUNCTION, { method: 'OPTIONS' });
    if (options.status !== 200 || (await options.text()) !== '') fail('OPTIONS_PROBE_REFUSED');
    report.phase = 'probe_unauthenticated';
    const denied = await request(URL_FUNCTION);
    let body; try { body = await denied.json(); } catch { fail('UNAUTHENTICATED_PROBE_REFUSED'); }
    if (denied.status !== 401 || !body || Object.keys(body).join(',') !== 'error' || body.error !== 'Non autorisé') fail('UNAUTHENTICATED_PROBE_REFUSED');
    report.probes = { options_status: 200, unauthenticated_status: 401, handler_contract_matches: true, exact_deployed_version_attributed: false };
    report.phase = 'complete'; report.status = 'success'; save();
  } catch (error) {
    report.status = 'failed'; report.code = error instanceof Refusal ? error.code : 'UNEXPECTED_FAILURE';
    try { save(); } catch { report.code = 'REPORT_WRITE_FAILED'; }
  }
  return report;
}

function localSource() {
  const git = args => execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore','pipe','pipe'] }).trim();
  return { sha: git(['rev-parse','HEAD']), clean: git(['status','--porcelain','--untracked-files=all']) === '', config: readFileSync('supabase/config.toml','utf8') };
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let report;
  try {
    if (process.argv.length !== 2) fail('ARGUMENTS_REFUSED');
    const dir = process.env.RUNNER_TEMP;
    if (!dir || !isAbsolute(dir)) fail('REPORT_DIRECTORY_REQUIRED');
    const out = resolve(dir, 'generate-invoice-staging-proof'); mkdirSync(out, { recursive: true, mode: 0o700 });
    const checkpoint = value => writeFileSync(resolve(out, 'result.json'), JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
    report = await refreshInvoice({ env: process.env, local: localSource(), checkpoint });
  } catch (error) { report = { status: 'failed', code: error instanceof Refusal ? error.code : 'LOCAL_FAILURE' }; }
  console.log(JSON.stringify(report)); if (report.status !== 'success') process.exitCode = 1;
}
