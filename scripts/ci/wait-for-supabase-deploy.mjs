#!/usr/bin/env node

import { pathToFileURL } from 'node:url';

const DEPLOY_WORKFLOW_FILE = 'deploy-supabase.yml';
const DEPLOY_WORKFLOW_NAME = 'Deploy Supabase (migrations + edge functions)';
const DEFAULT_MAX_WAIT_MS = 20 * 60 * 1000;
const DEFAULT_POLL_INTERVAL_MS = 15 * 1000;
const NULL_SHA = /^0+$/;

function requiredEnv(env, name) {
  const value = env[name]?.trim();
  if (!value) throw new Error(`${name} est requis pour attendre le déploiement Supabase.`);
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
      'User-Agent': 'jolene-supabase-deploy-gate',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!response.ok) {
    const body = (await response.text()).slice(0, 500);
    throw new Error(`GitHub Actions API ${response.status} sur ${url}: ${body}`);
  }
  return response.json();
}

export function deployPathWasChanged(files) {
  return files.some(({ filename = '' }) => (
    filename.startsWith('supabase/migrations/')
    || filename.startsWith('supabase/functions/')
    || filename === 'supabase/config.toml'
    || filename === `.github/workflows/${DEPLOY_WORKFLOW_FILE}`
  ));
}

export async function waitForSupabaseDeploy({
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
  const headSha = requiredEnv(env, 'GITHUB_SHA');
  const beforeSha = requiredEnv(env, 'GITHUB_EVENT_BEFORE');
  const apiUrl = (env.GITHUB_API_URL || 'https://api.github.com').replace(/\/$/, '');
  const maxWaitMs = positiveInteger(
    env.SUPABASE_DEPLOY_MAX_WAIT_MS,
    DEFAULT_MAX_WAIT_MS,
    'SUPABASE_DEPLOY_MAX_WAIT_MS',
  );
  const pollIntervalMs = positiveInteger(
    env.SUPABASE_DEPLOY_POLL_INTERVAL_MS,
    DEFAULT_POLL_INTERVAL_MS,
    'SUPABASE_DEPLOY_POLL_INTERVAL_MS',
  );

  // deploy-supabase.yml est déclenché par paths. Un push purement frontend ne
  // crée donc volontairement aucun run du même SHA et n'a rien à attendre.
  // Si GitHub tronque la liste à 300 fichiers, on attend par prudence.
  let requiresDeploy = NULL_SHA.test(beforeSha);
  if (!requiresDeploy) {
    const comparison = await githubJson(
      fetchImpl,
      `${apiUrl}/repos/${repository}/compare/${beforeSha}...${headSha}`,
      token,
    );
    const files = Array.isArray(comparison.files) ? comparison.files : [];
    requiresDeploy = files.length >= 300 || deployPathWasChanged(files);
  }

  if (!requiresDeploy) {
    log.log(`Aucun chemin Supabase modifié dans ${headSha}; aucun déploiement à attendre.`);
    return;
  }

  const workflow = await githubJson(
    fetchImpl,
    `${apiUrl}/repos/${repository}/actions/workflows/${DEPLOY_WORKFLOW_FILE}`,
    token,
  );
  if (workflow.name !== DEPLOY_WORKFLOW_NAME) {
    throw new Error(
      `Workflow Supabase inattendu: « ${workflow.name || 'sans nom'} » au lieu de « ${DEPLOY_WORKFLOW_NAME} » (${DEPLOY_WORKFLOW_FILE}).`,
    );
  }

  const startedAt = now();
  let lastStatus = '';
  while (true) {
    const listing = await githubJson(
      fetchImpl,
      `${apiUrl}/repos/${repository}/actions/workflows/${workflow.id}/runs?branch=main&event=push&per_page=100`,
      token,
    );
    const matchingRuns = (listing.workflow_runs || [])
      .filter((run) => run.head_sha === headSha)
      .sort((left, right) => Number(right.id) - Number(left.id));
    const deployRun = matchingRuns[0];

    if (deployRun?.status === 'completed') {
      if (deployRun.conclusion !== 'success') {
        throw new Error(
          `Le déploiement Supabase du SHA ${headSha} a terminé en ${deployRun.conclusion || 'état inconnu'}: ${deployRun.html_url || deployRun.id}`,
        );
      }
      log.log(`Déploiement Supabase du SHA ${headSha} réussi: ${deployRun.html_url || deployRun.id}`);
      return;
    }

    const status = deployRun
      ? `${deployRun.status}:${deployRun.id}`
      : 'run pas encore enregistré';
    if (status !== lastStatus) {
      log.log(`Attente du workflow « ${DEPLOY_WORKFLOW_NAME} » pour ${headSha}: ${status}.`);
      lastStatus = status;
    }

    const elapsed = now() - startedAt;
    if (elapsed >= maxWaitMs) {
      throw new Error(
        `Aucun déploiement Supabase réussi pour le SHA ${headSha} après ${Math.round(elapsed / 1000)} s (${status}).`,
      );
    }
    await sleep(Math.min(pollIntervalMs, maxWaitMs - elapsed));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  waitForSupabaseDeploy().catch((error) => {
    console.error(`::error::${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  });
}
