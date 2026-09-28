import { appendFileSync, realpathSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = 'Gabpcd/JJJJJ';
const workflowPath = '.github/workflows/deploy-supabase.yml';
// Keep these inputs aligned with the production deployment's push.paths.
export const backendPaths = ['supabase/migrations', 'supabase/functions', 'supabase/config.toml', workflowPath];
const validSha = value => /^[a-f0-9]{40}$/.test(value || '');
const gitCommand = (...args) => execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const wait = reason => ({ ready: false, reason: `Waiting for Supabase: ${reason}` });
const timestamp = value => {
  const result = Date.parse(value);
  if (!Number.isFinite(result)) throw new Error('Invalid Supabase deployment timestamp');
  return result;
};

async function pages(api, path, key) {
  const items = [];
  let total;
  // Do not silently accept a truncated history, including GitHub's search limits.
  for (let page = 1; page <= 100; page++) {
    const response = await api(`${path}?per_page=100&page=${page}`);
    if (!Number.isSafeInteger(response.total_count) || response.total_count < 0 || !Array.isArray(response[key])) {
      throw new Error('Malformed Supabase deployment history');
    }
    total ??= response.total_count;
    if (total !== response.total_count) throw new Error('Supabase deployment history changed during pagination');
    items.push(...response[key]);
    if (items.length === total && new Set(items.map(item => item.id)).size === total) return items;
    if (!response[key].length || items.length > total) break;
  }
  throw new Error('Incomplete Supabase deployment history');
}

export async function checkBackendDeployment({ sha, api, git = gitCommand }) {
  if (!validSha(sha)) throw new Error('Invalid mobile backend source');
  if (git('rev-parse', '--is-shallow-repository') !== 'false') throw new Error('Full git history is required for the Supabase delivery gate');
  // An empty repository fixture may have no backend at all. Deleted backend files
  // still count: inspecting history prevents their deletion becoming a bypass.
  if (!git('log', '-1', '--format=%H', sha, '--', ...backendPaths)) {
    return { ready: true, reason: 'No backend inputs in this source history.' };
  }
  const workflow = await api('actions/workflows/deploy-supabase.yml');
  if (!Number.isSafeInteger(workflow.id) || workflow.path !== workflowPath || workflow.state !== 'active') {
    throw new Error('Unexpected production Supabase workflow');
  }
  // Include failures, manual dispatches and other refs: they may have touched the
  // same production. Filtering only successful main pushes would hide them.
  const runs = await pages(api, `actions/workflows/${workflow.id}/runs`, 'workflow_runs');
  if (!runs.length) return wait('no deployment evidence.');
  for (const run of runs) {
    if (!Number.isSafeInteger(run.id) || !Number.isSafeInteger(run.run_attempt) || run.run_attempt < 1 ||
        run.workflow_id !== workflow.id || run.repository?.full_name !== repository ||
        !validSha(run.head_sha) || typeof run.status !== 'string') throw new Error('Invalid Supabase run identity');
    timestamp(run.updated_at);
  }
  if (runs.some(run => run.status !== 'completed')) return wait('a deployment is still pending or running.');
  // An old run can be rerun today: run.id/created_at alone are not chronological
  // evidence. Verify the newest update against the actual attempt's job times.
  runs.sort((a, b) => timestamp(b.updated_at) - timestamp(a.updated_at));
  const latest = runs[0];
  if (latest.conclusion !== 'success') return wait(`latest deployment ${latest.id} is not successful.`);
  if (latest.head_branch !== 'main' || !['push', 'workflow_dispatch'].includes(latest.event) ||
      latest.head_repository?.full_name !== repository || latest.path !== workflowPath) {
    return wait('latest deployment is not from the trusted production ref.');
  }
  const requiredJobs = ['Apply SQL migrations', 'Deploy edge functions'];
  const effectiveJobs = new Map();
  const jobIds = new Set();
  if (latest.run_attempt > 100) throw new Error('Supabase attempt history exceeds the verification limit');
  // A rerun of failed jobs omits successful parents from that attempt. Reuse
  // their latest state, but never an older green state over a newer failed job.
  for (let attempt = latest.run_attempt; attempt >= 1; attempt--) {
    const jobs = await pages(api, `actions/runs/${latest.id}/attempts/${attempt}/jobs`, 'jobs');
    const names = new Set();
    if (!jobs.length) return wait('deployment attempt has incomplete jobs.');
    for (const job of jobs) {
      if (!Number.isSafeInteger(job.id) || job.id < 1 || jobIds.has(job.id) ||
          typeof job.name !== 'string' || !job.name || names.has(job.name) ||
          job.run_id !== latest.id || job.head_sha !== latest.head_sha) {
        return wait('deployment attempt has ambiguous job identities.');
      }
      names.add(job.name);
      jobIds.add(job.id);
      if (!effectiveJobs.has(job.name)) effectiveJobs.set(job.name, job);
    }
    if (requiredJobs.every(name => effectiveJobs.has(name))) break;
  }
  const jobs = [...effectiveJobs.values()];
  if (!requiredJobs.every(name => effectiveJobs.has(name)) ||
      jobs.some(job => job.status !== 'completed' || job.conclusion !== 'success')) {
    return wait('effective deployment jobs are incomplete or unsuccessful.');
  }
  // Include the original migration job when only Edge was rerun: another
  // deployment after that migration invalidates the combined evidence.
  const startedAt = Math.min(...jobs.map(job => timestamp(job.started_at)));
  if (runs.slice(1).some(run => timestamp(run.updated_at) >= startedAt)) {
    return wait('deployment attempt order is ambiguous or overlapping.');
  }
  try { git('merge-base', '--is-ancestor', latest.head_sha, sha); }
  catch { return wait('deployed source is not an ancestor of the mobile source.'); }
  if (git('diff', '--name-only', latest.head_sha, sha, '--', ...backendPaths)) {
    return wait('the mobile source contains backend changes not covered by the latest successful deployment.');
  }
  // Detect an attempt restarted while its jobs were inspected. This is a fresh
  // check, not an atomic lock against subsequent production mutations.
  const confirmed = await api(`actions/runs/${latest.id}`);
  if (confirmed.run_attempt !== latest.run_attempt || confirmed.updated_at !== latest.updated_at ||
      confirmed.status !== 'completed' || confirmed.conclusion !== 'success' || confirmed.head_sha !== latest.head_sha) {
    return wait('deployment evidence changed during verification.');
  }
  return { ready: true, reason: `Supabase ${latest.head_sha} verified by run ${latest.id}, attempt ${latest.run_attempt}.` };
}

// Same guard immediately before an OTA publication or a store submission.
if (process.argv[1] && realpathSync(resolve(process.argv[1])) === realpathSync(fileURLToPath(import.meta.url))) {
  if (process.env.GITHUB_REPOSITORY !== repository) throw new Error('Unexpected repository');
  const result = await checkBackendDeployment({
    sha: process.env.MOBILE_DELIVERY_SHA,
    api: async path => {
      const response = await fetch(`https://api.github.com/repos/${repository}/${path}`, {
        headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json' },
      });
      if (!response.ok) throw new Error(`GitHub ${response.status}: ${path}`);
      return response.json();
    },
  });
  if (!result.ready) throw new Error(result.reason);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${result.reason}\n`);
}
