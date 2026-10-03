#!/usr/bin/env node

import { pathToFileURL } from 'node:url';

const DEFAULT_MAX_WAIT_MS = 45 * 60 * 1000;
const DEFAULT_POLL_INTERVAL_MS = 60 * 1000;
const DEFAULT_STALE_QUEUED_AFTER_MS = 3 * 60 * 60 * 1000;
const ACTIVE_RUN_STATUSES = ['in_progress', 'queued', 'requested', 'waiting', 'pending'];
const ISOLATED_JOB = /^Simulation interfaces \((?:ipad-portrait|ipad-paysage|iphone|android|ordinateur)(?:, lot (?:[12]\/2|[123]\/3))?\)$/;
const SHARED_JOB = /^Playwright E2E \((?:PR — Chromium|chromium|firefox|webkit|mobile-iphone|mobile-pixel|\$\{\{ matrix\.project \}\})\)$/;
const KNOWN_JOB_STATUSES = new Set(['queued', 'requested', 'waiting', 'pending', 'in_progress', 'completed']);
const COMPLETED_CONCLUSIONS = new Set(['success', 'failure', 'cancelled', 'timed_out', 'action_required', 'neutral', 'skipped', 'startup_failure', 'stale']);
const STALE_ELIGIBLE_RUN_STATUSES = new Set(['queued', 'requested']);

function requiredEnv(env, name) {
  const value = env[name]?.trim();
  if (!value) throw new Error(`${name} est requis pour sérialiser les runs Playwright.`);
  return value;
}

function positiveInteger(value, fallback, name) {
  if (value === undefined || value === '') return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} doit être un entier strictement positif.`);
  }
  return parsed;
}

export async function githubJson(fetchImpl, url, token, {
  sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds)),
  requestTimeoutMs = 15_000,
} = {}) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), requestTimeoutMs);
    let response;
    let retryError;
    let delay = 1000 * (attempt + 1);
    try {
      response = await fetchImpl(url, {
        method: 'GET', signal: controller.signal,
        headers: {
          Accept: 'application/vnd.github+json',
          Authorization: `Bearer ${token}`,
          'User-Agent': 'jolene-playwright-fifo',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      });
      if (response.ok) return await response.json();
      const error = new Error(`GitHub Actions API ${response.status} sur ${url}`);
      if (response.status === 429) {
        const value = response.headers?.get('retry-after');
        const seconds = value && /^\d+$/.test(value) ? Number(value) : NaN;
        const retryAfter = Number.isFinite(seconds) ? seconds * 1000 : Date.parse(value || '') - Date.now();
        // Unknown or excessive rate-limit delays stop the gate, never open it.
        if (!Number.isFinite(retryAfter) || retryAfter < 0 || retryAfter > 10_000) throw error;
        delay = retryAfter;
      } else if (response.status < 500 || response.status > 599) {
        throw error; // Auth/permission and other 4xx errors are not retried.
      }
      retryError = error;
    } catch (error) {
      // Malformed JSON and non-retryable HTTP errors remain immediately fatal.
      if (response && !controller.signal.aborted && !(error instanceof TypeError)) throw error;
      retryError = error;
    } finally {
      clearTimeout(timer);
    }
    if (attempt === 2) {
      throw new Error(`Lecture GitHub échouée après 3 essais ; FIFO fermée : ${retryError?.message || 'erreur réseau'}`, { cause: retryError });
    }
    await sleep(delay);
  }
}

/**
 * GitHub attribue `run_number` dans l'ordre de création d'un workflow. Chaque
 * run attend uniquement les runs actifs de numéro inférieur : aucune
 * annulation, et aucun interblocage entre deux runs démarrés simultanément.
 */
function isOlderActiveRun(run, currentRun) {
  return (
    Number(run.id) !== Number(currentRun.id)
    && Number(run.run_number) < Number(currentRun.run_number)
    && run.status !== 'completed'
  );
}

export function isStaleQueuedRun(run, {
  nowMs = Date.now(),
  staleQueuedAfterMs = DEFAULT_STALE_QUEUED_AFTER_MS,
} = {}) {
  if (!STALE_ELIGIBLE_RUN_STATUSES.has(run.status)) return false;

  const timestampMs = Date.parse(run.created_at || run.updated_at || '');
  if (!Number.isFinite(timestampMs)) return false;

  return nowMs - timestampMs >= staleQueuedAfterMs;
}

export function olderActiveRuns(runs, currentRun) {
  return runs
    .filter((run) => isOlderActiveRun(run, currentRun))
    .sort((left, right) => (
      Number(left.run_number) - Number(right.run_number)
      || Number(left.id) - Number(right.id)
    ));
}

async function listActiveWorkflowRuns(fetchImpl, apiUrl, repository, workflowId, token, readOptions) {
  const runs = [];
  for (const status of ACTIVE_RUN_STATUSES) {
    let page = 1;
    while (true) {
      const listing = await githubJson(
        fetchImpl,
        `${apiUrl}/repos/${repository}/actions/workflows/${workflowId}/runs?status=${status}&per_page=100&page=${page}`,
        token, readOptions,
      );
      if (!Array.isArray(listing.workflow_runs) || listing.workflow_runs.some(run => !Number.isSafeInteger(run.id) || !Number.isSafeInteger(run.run_number) || typeof run.status !== 'string')) {
        throw new Error('Liste de runs GitHub incomplète ou invalide : FIFO fermée.');
      }
      const pageRuns = listing.workflow_runs;
      runs.push(...pageRuns);
      if (pageRuns.length < 100) break;
      page += 1;
    }
  }
  return [...new Map(runs.map((run) => [String(run.id), run])).values()];
}

/** Completion of the job includes every step and its cleanup. A green test
 * step alone cannot release the shared database. Unknown/missing jobs fail closed. */
export function sharedDatabaseJobsFinished(jobs, event) {
  const expected = event === 'pull_request' ? 'Playwright E2E (PR — Chromium)'
    : ['push', 'workflow_dispatch'].includes(event) ? 'Playwright E2E (chromium)' : null;
  if (!expected || !Array.isArray(jobs) || !jobs.some(job => job.name === expected)) return false;
  return jobs.every(job => {
    if (!job || typeof job.name !== 'string' || !KNOWN_JOB_STATUSES.has(job.status)) return false;
    if (job.status === 'completed' && !COMPLETED_CONCLUSIONS.has(job.conclusion)) return false;
    if (ISOLATED_JOB.test(job.name)) return true;
    return SHARED_JOB.test(job.name) && job.status === 'completed';
  });
}

async function currentAttemptJobs(fetchImpl, apiUrl, repository, run, token, readOptions) {
  const jobs = new Map();
  let page = 1;
  let expectedCount;
  while (true) {
    const listing = await githubJson(fetchImpl,
      `${apiUrl}/repos/${repository}/actions/runs/${run.id}/attempts/${run.run_attempt}/jobs?per_page=100&page=${page}`, token, readOptions);
    if (!Array.isArray(listing.jobs) || !Number.isSafeInteger(listing.total_count) || listing.total_count < 0
      || listing.jobs.some(job => !Number.isSafeInteger(job.id) || job.run_id !== run.id)) {
      throw new Error('Liste de jobs GitHub incomplète ou invalide : FIFO fermée.');
    }
    if (expectedCount !== undefined && expectedCount !== listing.total_count) {
      throw new Error('Liste de jobs GitHub modifiée pendant la pagination : FIFO fermée.');
    }
    expectedCount = listing.total_count;
    for (const job of listing.jobs) jobs.set(job.id, job);
    if (listing.jobs.length < 100) break;
    page += 1;
  }
  if (jobs.size !== expectedCount) throw new Error('Pagination de jobs GitHub incomplète : FIFO fermée.');
  return [...jobs.values()];
}

async function olderRunStillUsesDatabase(fetchImpl, apiUrl, repository, run, token, readOptions) {
  const runUrl = `${apiUrl}/repos/${repository}/actions/runs/${run.id}`;
  const fresh = await githubJson(fetchImpl, runUrl, token, readOptions);
  if (fresh.id !== run.id || fresh.run_number !== run.run_number) {
    throw new Error('Identité du run GitHub incohérente : FIFO fermée.');
  }
  if (fresh.status === 'completed') return false;
  // Queued reruns may still expose successful jobs from their previous attempt.
  // Age alone never proves that a queued job cannot resume against the database.
  if (fresh.status !== 'in_progress' || !Number.isSafeInteger(fresh.run_attempt) || fresh.run_attempt < 1) return true;
  const jobs = await currentAttemptJobs(fetchImpl, apiUrl, repository, fresh, token, readOptions);
  if (!sharedDatabaseJobsFinished(jobs, fresh.event)) return true;
  // A rerun started during pagination must not inherit the old attempt's result.
  // This read guard is not an atomic database lock: a manual rerun started after
  // the final read cannot be excluded by the GitHub status API.
  const after = await githubJson(fetchImpl, runUrl, token, readOptions);
  return after.id !== fresh.id || after.run_number !== fresh.run_number
    || after.run_attempt !== fresh.run_attempt
    || !['in_progress', 'completed'].includes(after.status);
}

export async function waitForOlderPlaywrightRuns({
  env = process.env,
  fetchImpl = globalThis.fetch,
  sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
  now = () => Date.now(),
  log = console,
} = {}) {
  if (typeof fetchImpl !== 'function') {
    throw new Error('Cette gate CI requiert fetch (Node.js 18+).');
  }

  const token = requiredEnv(env, 'GITHUB_TOKEN');
  const repository = requiredEnv(env, 'GITHUB_REPOSITORY');
  const runId = positiveInteger(requiredEnv(env, 'GITHUB_RUN_ID'), 0, 'GITHUB_RUN_ID');
  const apiUrl = (env.GITHUB_API_URL || 'https://api.github.com').replace(/\/$/, '');
  const maxWaitMs = positiveInteger(
    env.PLAYWRIGHT_FIFO_MAX_WAIT_MS,
    DEFAULT_MAX_WAIT_MS,
    'PLAYWRIGHT_FIFO_MAX_WAIT_MS',
  );
  const pollIntervalMs = positiveInteger(
    env.PLAYWRIGHT_FIFO_POLL_INTERVAL_MS,
    DEFAULT_POLL_INTERVAL_MS,
    'PLAYWRIGHT_FIFO_POLL_INTERVAL_MS',
  );
  const staleQueuedAfterMs = positiveInteger(
    env.PLAYWRIGHT_FIFO_STALE_QUEUED_AFTER_MS,
    DEFAULT_STALE_QUEUED_AFTER_MS,
    'PLAYWRIGHT_FIFO_STALE_QUEUED_AFTER_MS',
  );

  const readOptions = { sleep };
  const currentRun = await githubJson(
    fetchImpl,
    `${apiUrl}/repos/${repository}/actions/runs/${runId}`,
    token, readOptions,
  );
  if (!currentRun.workflow_id || !currentRun.run_number) {
    throw new Error('La réponse GitHub du run courant ne contient pas workflow_id/run_number.');
  }

  const startedAt = now();
  let lastBlockerSignature = '';
  let lastOldQueuedSignature = '';
  while (true) {
    // Interroger séparément tous les états actifs évite qu'un run ancien mais
    // bloqué soit masqué derrière plus de 100 runs déjà terminés. Chaque état
    // est paginé : la FIFO reste correcte même lors d'une rafale inhabituelle.
    const activeRuns = await listActiveWorkflowRuns(
      fetchImpl,
      apiUrl,
      repository,
      currentRun.workflow_id,
      token, readOptions,
    );
    const pollNowMs = now();
    const staleOptions = { nowMs: pollNowMs, staleQueuedAfterMs };
    const oldQueuedRuns = activeRuns
      .filter((run) => isOlderActiveRun(run, currentRun))
      .filter((run) => isStaleQueuedRun(run, staleOptions));
    const oldQueuedSignature = oldQueuedRuns
      .map((run) => `${run.run_number}:${run.id}:${run.status}`)
      .join(',');
    if (oldQueuedSignature && oldQueuedSignature !== lastOldQueuedSignature) {
      log.log(
        `Runs Playwright queued/requested anciens toujours bloquants après ${Math.round(staleQueuedAfterMs / 1000)} s: ${oldQueuedSignature}`,
      );
      lastOldQueuedSignature = oldQueuedSignature;
    }

    const blockers = [];
    for (const run of olderActiveRuns(activeRuns, currentRun)) {
      if (await olderRunStillUsesDatabase(fetchImpl, apiUrl, repository, run, token, readOptions)) {
        blockers.push(run);
        break; // The oldest proven blocker suffices; spare the API until next poll.
      }
    }
    if (blockers.length === 0) {
      log.log(
        `File Playwright disponible pour le run #${currentRun.run_number} (${currentRun.id}).`,
      );
      return;
    }

    const signature = blockers.map((run) => `${run.run_number}:${run.id}:${run.status}`).join(',');
    if (signature !== lastBlockerSignature) {
      log.log(
        `Run Playwright #${currentRun.run_number} en attente de ${blockers.length} run(s) plus ancien(s): ${signature}`,
      );
      lastBlockerSignature = signature;
    }

    const elapsed = now() - startedAt;
    if (elapsed >= maxWaitMs) {
      throw new Error(
        `Timeout FIFO après ${Math.round(elapsed / 1000)} s; runs plus anciens susceptibles d’utiliser la base: ${signature}`,
      );
    }
    await sleep(Math.min(pollIntervalMs, maxWaitMs - elapsed));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  waitForOlderPlaywrightRuns().catch((error) => {
    console.error(`::error::${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  });
}
