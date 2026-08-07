#!/usr/bin/env node

import { pathToFileURL } from 'node:url';

const DEFAULT_MAX_WAIT_MS = 45 * 60 * 1000;
const DEFAULT_POLL_INTERVAL_MS = 15 * 1000;
const DEFAULT_STALE_QUEUED_AFTER_MS = 3 * 60 * 60 * 1000;
const ACTIVE_RUN_STATUSES = ['in_progress', 'queued', 'requested'];
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

async function githubJson(fetchImpl, url, token) {
  const response = await fetchImpl(url, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'User-Agent': 'jolene-playwright-fifo',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!response.ok) {
    const body = (await response.text()).slice(0, 500);
    throw new Error(`GitHub Actions API ${response.status} sur ${url}: ${body}`);
  }
  return response.json();
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

export function olderActiveRuns(runs, currentRun, options = {}) {
  return runs
    .filter((run) => isOlderActiveRun(run, currentRun))
    .filter((run) => !isStaleQueuedRun(run, options))
    .sort((left, right) => (
      Number(left.run_number) - Number(right.run_number)
      || Number(left.id) - Number(right.id)
    ));
}

async function listActiveWorkflowRuns(fetchImpl, apiUrl, repository, workflowId, token) {
  const runs = [];
  for (const status of ACTIVE_RUN_STATUSES) {
    let page = 1;
    while (true) {
      const listing = await githubJson(
        fetchImpl,
        `${apiUrl}/repos/${repository}/actions/workflows/${workflowId}/runs?status=${status}&per_page=100&page=${page}`,
        token,
      );
      const pageRuns = Array.isArray(listing.workflow_runs) ? listing.workflow_runs : [];
      runs.push(...pageRuns);
      if (pageRuns.length < 100) break;
      page += 1;
    }
  }
  return [...new Map(runs.map((run) => [String(run.id), run])).values()];
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

  const currentRun = await githubJson(
    fetchImpl,
    `${apiUrl}/repos/${repository}/actions/runs/${runId}`,
    token,
  );
  if (!currentRun.workflow_id || !currentRun.run_number) {
    throw new Error('La réponse GitHub du run courant ne contient pas workflow_id/run_number.');
  }

  const startedAt = now();
  let lastBlockerSignature = '';
  let lastIgnoredSignature = '';
  while (true) {
    // Interroger séparément tous les états actifs évite qu'un run ancien mais
    // bloqué soit masqué derrière plus de 100 runs déjà terminés. Chaque état
    // est paginé : la FIFO reste correcte même lors d'une rafale inhabituelle.
    const activeRuns = await listActiveWorkflowRuns(
      fetchImpl,
      apiUrl,
      repository,
      currentRun.workflow_id,
      token,
    );
    const pollNowMs = now();
    const staleOptions = { nowMs: pollNowMs, staleQueuedAfterMs };
    const ignoredStaleRuns = activeRuns
      .filter((run) => isOlderActiveRun(run, currentRun))
      .filter((run) => isStaleQueuedRun(run, staleOptions));
    const ignoredSignature = ignoredStaleRuns
      .map((run) => `${run.run_number}:${run.id}:${run.status}`)
      .join(',');
    if (ignoredSignature && ignoredSignature !== lastIgnoredSignature) {
      log.log(
        `Runs Playwright queued/requested fantômes ignorés après ${Math.round(staleQueuedAfterMs / 1000)} s: ${ignoredSignature}`,
      );
      lastIgnoredSignature = ignoredSignature;
    }

    const blockers = olderActiveRuns(activeRuns, currentRun, staleOptions);
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

    const elapsed = pollNowMs - startedAt;
    if (elapsed >= maxWaitMs) {
      throw new Error(
        `Timeout FIFO après ${Math.round(elapsed / 1000)} s; runs plus anciens toujours actifs: ${signature}`,
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
