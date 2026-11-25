#!/usr/bin/env node

import { pathToFileURL } from 'node:url';

const DEPLOY_WORKFLOW_FILE = 'deploy-supabase.yml';
const DEPLOY_WORKFLOW_NAME = 'Deploy Supabase (migrations + edge functions)';
const DEFAULT_MAX_WAIT_MS = 20 * 60 * 1000;
const DEFAULT_POLL_INTERVAL_MS = 15 * 1000;
const NULL_SHA = /^0+$/;
// API compare de GitHub : 100 fichiers au plus par page, 3 000 au plus en tout (au-delà, la liste est tronquée).
export const COMPARE_PAGE_SIZE = 100;
export const COMPARE_MAX_PAGES = 30;

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

/**
 * Liste complète des fichiers d'un push, page par page (`per_page=100&page=N`) jusqu'à une page incomplète.
 * Une erreur de la première page est levée (comportement inchangé) ; une erreur sur une page suivante, ou le plafond
 * de l'API atteint, rend la liste inconnaissable : `complete` vaut alors false et `cause` dit pourquoi.
 */
export async function listChangedFiles({ fetchImpl, apiUrl, repository, beforeSha, headSha, token }) {
  const files = [];
  for (let page = 1; page <= COMPARE_MAX_PAGES; page += 1) {
    let comparison;
    try {
      comparison = await githubJson(
        fetchImpl,
        `${apiUrl}/repos/${repository}/compare/${beforeSha}...${headSha}?per_page=${COMPARE_PAGE_SIZE}&page=${page}`,
        token,
      );
    } catch (error) {
      if (page === 1) throw error;
      const message = error instanceof Error ? error.message : String(error);
      return { files, complete: false, cause: `erreur de l'API compare en page ${page} (${message.slice(0, 200)})` };
    }
    const pageFiles = Array.isArray(comparison.files) ? comparison.files : [];
    files.push(...pageFiles);
    if (pageFiles.length < COMPARE_PAGE_SIZE) return { files, complete: true, cause: '' };
  }
  return {
    files,
    complete: false,
    cause: `plafond de l'API compare atteint (${COMPARE_MAX_PAGES} pages de ${COMPARE_PAGE_SIZE} fichiers)`,
  };
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
  // La liste des fichiers est lue en entier (pagination de l'API compare) ; on
  // n'attend par prudence que si elle reste inconnaissable (plafond, erreur).
  let requiresDeploy = NULL_SHA.test(beforeSha);
  let prudence = '';
  if (!requiresDeploy) {
    const { files, complete, cause } = await listChangedFiles({
      fetchImpl, apiUrl, repository, beforeSha, headSha, token,
    });
    if (!complete) {
      prudence = cause;
      log.log(`Liste des fichiers de ${headSha} inconnaissable : ${cause} ; attente par prudence du déploiement Supabase.`);
    }
    requiresDeploy = !complete || deployPathWasChanged(files);
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
        `Aucun déploiement Supabase réussi pour le SHA ${headSha} après ${Math.round(elapsed / 1000)} s (${status}).`
          + (prudence ? ` Attente par prudence seulement : liste des fichiers inconnaissable (${prudence}).` : ''),
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
