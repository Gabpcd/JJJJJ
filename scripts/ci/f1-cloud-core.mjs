import { createHash } from 'node:crypto';
import { mkdir, open, readFile, lstat } from 'node:fs/promises';
import { resolve, relative, isAbsolute, join } from 'node:path';
import { performance } from 'node:perf_hooks';

export const STAGING = 'mejpriaetwgtcstbgfid';
export const ORIGIN = `https://${STAGING}.supabase.co`;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA = /^[0-9a-f]{40}$/;
const EFFECTS = new Set(['prepare_fixture', 'generate_original', 'prepare_correction', 'generate_replacement', 'finalize_auth']);
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export function refuse(code) { throw new Error(code); }

export function contextF1(env) {
  if (env.GITHUB_REPOSITORY !== 'Gabpcd/JJJJJ' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch'
    || env.GITHUB_REF !== 'refs/heads/main' || !SHA.test(env.GITHUB_SHA ?? '')
    || env.F1_APPROVED_SHA !== env.GITHUB_SHA) refuse('F1_TRUSTED_MAIN_REQUIRED');
  if (env.STAGING_SUPABASE_PROJECT_REF !== STAGING || env.STAGING_SUPABASE_URL !== ORIGIN) refuse('F1_STAGING_REQUIRED');
  if (!/^[1-9][0-9]{0,14}$/.test(env.GITHUB_RUN_ID ?? '')
    || !/^[1-9][0-9]{0,2}$/.test(env.GITHUB_RUN_ATTEMPT ?? '')) refuse('F1_RUN_REQUIRED');
  if (!isAbsolute(env.RUNNER_TEMP ?? '')) refuse('F1_PRIVATE_DIRECTORY_REQUIRED');
  return Object.freeze({ sha: env.GITHUB_SHA, ref: STAGING,
    run: `f1-ci-${env.GITHUB_RUN_ID}-${env.GITHUB_RUN_ATTEMPT}`, privateRoot: resolve(env.RUNNER_TEMP),
    jobStartedUnix: env.F1_JOB_STARTED_UNIX });
}

// Refuse before the first Auth effect if setup consumed the closure reserve.
// No timer races an in-flight operation or starts finalization concurrently.
export function requireTimeReserveF1(ctx, now = Date.now()) {
  if (!/^[1-9][0-9]{9}$/.test(ctx.jobStartedUnix ?? '')) refuse('F1_TIME_RESERVE_REQUIRED');
  const elapsed = now - Number(ctx.jobStartedUnix) * 1000;
  if (!Number.isFinite(elapsed) || elapsed < 0 || elapsed > (35 - 19) * 60000) refuse('F1_TIME_RESERVE_REQUIRED');
}

// These are independent prerequisites, not assertions supplied by the CLI operator.
// A future reviewed adapter must derive them from its fixed source/catalogue contract.
export function requireReady(preflight, ctx) {
  if (preflight?.ready !== true || preflight.sourceSha !== ctx.sha) refuse('F1_CONTRACT_PENDING');
  for (const field of ['catalogueExact', 'generatorSourceExact', 'outgoingClosed', 'noActiveCron',
    'authCreationReviewed', 'replacementCanonicalWithoutPayment', 'retentionReviewed', 'uiDocumentsAccessible',
    'uiNetworkContractReviewed']) {
    if (preflight[field] !== true) refuse('F1_CONTRACT_PENDING');
  }
}

async function writePrivate(path, value) {
  const fd = await open(path, 'wx', 0o600);
  try { await fd.writeFile(JSON.stringify(value)); await fd.sync(); }
  finally { await fd.close(); }
}

/** Persist intent before any effect. Reopening the same run never permits a replay.
 * A timeout, lost response, or failure after response remains ambiguous; reconciling
 * may explain the outcome, but must not reset this ledger or retry generation. */
export async function ledgerF1(ctx) {
  const directory = join(ctx.privateRoot, ctx.run);
  const rel = relative(ctx.privateRoot, directory);
  if (!rel || rel.startsWith('..') || isAbsolute(rel)) refuse('F1_PRIVATE_DIRECTORY_REQUIRED');
  try { await mkdir(directory, { mode: 0o700 }); }
  catch (error) { if (error.code !== 'EEXIST') refuse('F1_LEDGER_IO'); }
  const stat = await lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || (stat.mode & 0o077)) refuse('F1_LEDGER_PERMISSIONS');
  const effects = [];
  return {
    directory,
    async once(effect, operation) {
      if (!EFFECTS.has(effect) || typeof operation !== 'function') refuse('F1_EFFECT_REFUSED');
      const started = performance.now();
      try { await writePrivate(join(directory, `${effect}.intent.json`), { version: 1, run: ctx.run, sha: ctx.sha, effect }); }
      catch (error) { refuse(error.code === 'EEXIST' ? 'F1_EFFECT_ALREADY_ATTEMPTED' : 'F1_LEDGER_IO'); }
      const observation = { effect, state: 'ambiguous', duration_ms: 0 };
      effects.push(observation);
      try {
        const result = await operation();
        observation.duration_ms = Math.max(0, Math.round(performance.now() - started));
        // Do not persist provider responses, tokens, URLs or exception text.
        await writePrivate(join(directory, `${effect}.result.json`), { state: 'response_received', duration_ms: observation.duration_ms });
        observation.state = 'response_received';
        return result;
      } catch {
        observation.duration_ms = Math.max(0, Math.round(performance.now() - started));
        refuse('F1_EFFECT_AMBIGUOUS');
      }
    },
    projection() { return effects.map(e => ({ ...e })); },
  };
}

const sameKeys = (body, keys) => body && typeof body === 'object' && !Array.isArray(body)
  && JSON.stringify(Object.keys(body).sort()) === JSON.stringify([...keys].sort());

export function originalBody(m) {
  const p = m?.period;
  if (!UUID.test(m?.missionId ?? '') || !p || !/^\d{4}-\d{2}-\d{2}$/.test(p.start ?? '')
    || !/^\d{4}-\d{2}-\d{2}$/.test(p.end ?? '') || p.start > p.end
    || !Number.isInteger(p.week) || p.week < 1 || p.week > 53 || !Number.isInteger(p.year)
    || p.year < 2026 || p.year > 2030) refuse('F1_PERIOD_INVALID');
  for (const day of [p.start, p.end]) {
    const date = new Date(`${day}T00:00:00Z`);
    if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== day) refuse('F1_PERIOD_INVALID');
  }
  return { mission_id: m.missionId, periode_debut: p.start, periode_fin: p.end,
    numero_semaine_iso: p.week, annee_iso: p.year, est_facture_finale_mission: false };
}

/** Single actual HTTP request, never retried, to the fixed staging Edge endpoint.
 * Authenticated actor/token ownership is the adapter's preflight responsibility.
 * The JSON result is kept in memory; reconcile must independently verify ownership. */
export async function generateOnce({ ctx, ledger, manifest, token, kind, correction, preflight, fetcher = fetch }) {
  requireReady(preflight, ctx);
  if (ctx.ref !== STAGING || typeof token !== 'string' || !token.length) refuse('F1_AUTH_REQUIRED');
  let body;
  if (kind === 'original') body = originalBody(manifest);
  else if (kind === 'replacement' && UUID.test(correction?.id ?? '') && correction?.initiation?.type === 'runner'
    && sameKeys(correction.initiation, ['type'])) body = { facture_id: correction.id };
  else refuse('F1_CORRECTION_INITIATOR_REFUSED');
  return ledger.once(`generate_${kind}`, async () => {
    const response = await fetcher(`${ORIGIN}/functions/v1/generate-invoice`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(90000),
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    });
    if (!response.ok) refuse('F1_EDGE_REFUSED');
    const data = await response.json();
    if (data?.success !== true || !UUID.test(data.facture_id ?? '')
      || (kind === 'replacement' && (data.facture_id !== correction.id || data.type_document !== 'FACTURE'))
      || typeof data.pdf_path !== 'string' || typeof data.xml_path !== 'string') refuse('F1_EDGE_RESPONSE_INVALID');
    return data;
  });
}

/** Only reconciled document bytes may enter the future public proof directory. */
export function documentBytes(bytes, expected) {
  if (!Buffer.isBuffer(bytes) || bytes.length === 0 || bytes.length > 25 * 1024 * 1024
    || !expected || bytes.length !== expected.size || sha256(bytes) !== expected.sha256
    || !['pdf', 'xml'].includes(expected.format)) refuse('F1_DOCUMENT_MISMATCH');
  if (expected.format === 'pdf' && !bytes.subarray(0, 5).equals(Buffer.from('%PDF-'))) refuse('F1_DOCUMENT_FORMAT');
  if (expected.format === 'xml' && !bytes.toString('utf8').trimStart().startsWith('<?xml')) refuse('F1_DOCUMENT_FORMAT');
  return { format: expected.format, size: bytes.length, sha256: expected.sha256 };
}

/** Offline gate: absence of a reviewed SQL/network adapter never means success. */
export async function checkContract(path, ctx) {
  let contract;
  try { contract = JSON.parse(await readFile(path, 'utf8')); } catch { refuse('F1_CONTRACT_PENDING'); }
  requireReady(contract, ctx);
  return contract;
}
