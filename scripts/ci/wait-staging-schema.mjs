#!/usr/bin/env node
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const SQL_JOB_NAME = 'Migrations + sécurité SQL (transaction annulée)';
const API = 'https://api.github.com';
const WORKFLOW = 'validate-pr.yml';
const MAX_WAIT_MS = 15 * 60 * 1000;
const POLL_MS = 5000;

function configuration(env) {
  const repository = env.GITHUB_REPOSITORY?.trim();
  const sha = (env.STAGING_SCHEMA_SHA || env.GITHUB_SHA)?.trim();
  const branch = (env.STAGING_SCHEMA_BRANCH || env.GITHUB_HEAD_REF || env.GITHUB_REF_NAME)?.trim();
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository ?? '')) throw new Error('GITHUB_REPOSITORY invalide.');
  if (!/^[a-f0-9]{40}$/.test(sha ?? '')) throw new Error('SHA exact du schéma staging requis (40 caractères hexadécimaux).');
  if (!branch || /[\r\n\x00-\x1f]/.test(branch)) throw new Error('Branche du schéma staging requise.');
  if (!env.GITHUB_TOKEN) throw new Error('GITHUB_TOKEN avec permission actions:read requis.');
  // Le jeton ne doit jamais être envoyé à une URL issue d’une réponse API ou d’un environnement arbitraire.
  if (env.GITHUB_API_URL && env.GITHUB_API_URL.replace(/\/$/, '') !== API) throw new Error('Seule l’API GitHub officielle est autorisée.');
  return { repository, sha, branch, token: env.GITHUB_TOKEN };
}

/** Gate en lecture seule GitHub : aucun accès Supabase et aucun verrou d’écriture. */
export async function waitStagingSchema({ env = process.env, fetchImpl = fetch,
  now = () => Date.now(), sleep = ms => new Promise(done => setTimeout(done, ms)),
  log = console.log, maxWaitMs = MAX_WAIT_MS } = {}) {
  const { repository, sha, branch, token } = configuration(env);
  if (!Number.isInteger(maxWaitMs) || maxWaitMs <= 0 || maxWaitMs > MAX_WAIT_MS) throw new Error('Attente maximale bornée à 15 minutes.');
  const deadline = now() + maxWaitMs;
  const prefix = `${API}/repos/${repository}/actions`;
  let dernierEtat = '';
  let vu = false;
  const timeout = () => new Error(`Schéma staging non confirmé pour ${branch}@${sha} après ${Math.round(maxWaitMs / 1000)} s. ${vu
    ? `Le job « ${SQL_JOB_NAME} » n’a pas réussi.`
    : `Aucun run ${WORKFLOW} de cette branche et de ce SHA. Un lancement manuel ne remplace pas une validation SQL réussie.`} Aucun compte de recette ne doit être créé.`);
  async function lire(path) {
    const restant = deadline - now();
    if (restant <= 0) throw timeout();
    const response = await fetchImpl(`${prefix}${path}`, {
      method: 'GET', redirect: 'error', signal: AbortSignal.timeout(Math.min(30_000, restant)),
      headers: { Accept: 'application/vnd.github+json', Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'jolene-staging-schema-gate' },
    });
    if (!response.ok) throw new Error(`Lecture GitHub Actions impossible (HTTP ${response.status}). Aucun schéma staging confirmé.`);
    const body = await response.json();
    if (now() >= deadline) throw timeout();
    return body;
  }
  async function liste(path, key) {
    const elements = [];
    for (let page = 1; page <= 10; page++) {
      const data = await lire(`${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`);
      if (!Array.isArray(data?.[key])) throw new Error(`Réponse GitHub invalide (${key}).`);
      elements.push(...data[key]);
      if (data[key].length < 100) return elements;
    }
    throw new Error('Pagination GitHub trop importante : aucune validation implicite.');
  }
  while (now() < deadline) {
    // head_sha et head_branch sont aussi revérifiés localement : aucun succès de main,
    // d’un ancien commit, d’un fork ou d’un workflow au nom ressemblant n’est accepté.
    const recherche = new URLSearchParams({ head_sha: sha, branch, event: 'pull_request' });
    const runs = await liste(`/workflows/${WORKFLOW}/runs?${recherche}`, 'workflow_runs');
    const run = runs.filter(r => r.head_sha === sha && r.head_branch === branch && r.event === 'pull_request'
      && r.path === `.github/workflows/${WORKFLOW}`
      && r.head_repository?.full_name?.toLowerCase() === repository.toLowerCase())
      .sort((a, b) => Number(b.id) - Number(a.id))[0];
    let etat = 'validation SQL pas encore enregistrée';
    if (run) {
      vu = true;
      if (!Number.isSafeInteger(run.id) || !Number.isSafeInteger(run.run_attempt) || run.run_attempt < 1) throw new Error('Identité du run GitHub invalide.');
      // Endpoint par tentative : ne jamais accepter le succès d’une tentative antérieure.
      // https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run-attempt
      const jobs = await liste(`/runs/${run.id}/attempts/${run.run_attempt}/jobs`, 'jobs');
      const candidats = jobs.filter(j => j.name === SQL_JOB_NAME && j.head_sha === sha && j.run_id === run.id);
      if (candidats.length > 1) throw new Error('Plusieurs jobs SQL homonymes : validation ambiguë.');
      const job = candidats[0];
      etat = `run ${run.id}, tentative ${run.run_attempt}, SQL ${job?.status ?? 'absent'}`;
      if (job?.status === 'completed') {
        if (job.conclusion !== 'success') throw new Error(`Validation SQL du SHA ${sha} terminée en ${job.conclusion || 'état inconnu'} (run ${run.id}).`);
        const courant = await lire(`/runs/${run.id}`);
        if (courant.head_sha !== sha || courant.head_branch !== branch) throw new Error('Le run GitHub ne correspond plus au SHA/à la branche attendus.');
        if (courant.run_attempt === run.run_attempt) {
          log(`Schéma staging validé : ${branch}@${sha}, job SQL ${job.id}, run ${run.id}, tentative ${run.run_attempt}.`);
          return { sha, branch, runId: run.id, runAttempt: run.run_attempt, jobId: job.id };
        }
        etat = `run ${run.id} relancé : attente de sa nouvelle tentative`;
      } else if (run.status === 'completed') {
        throw new Error(`Validation ${WORKFLOW} terminée (${run.conclusion || 'état inconnu'}) sans succès du job SQL pour ${sha}.`);
      }
    }
    if (etat !== dernierEtat) { log(`Attente du schéma staging : ${etat}.`); dernierEtat = etat; }
    const restant = deadline - now();
    if (restant <= 0) break;
    await sleep(Math.min(POLL_MS, restant));
  }
  throw timeout();
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  waitStagingSchema().catch(error => {
    console.error(`::error::${error instanceof Error ? error.message : 'Gate SQL staging impossible.'}`);
    process.exitCode = 1;
  });
}
