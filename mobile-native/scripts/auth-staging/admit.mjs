import { execFileSync } from 'node:child_process';
import { guardRun, publicEnvironment } from './policy.mjs';

// This step precedes dependency installation and private input staging. It reads
// only public configuration and Git metadata; no cohort is available to it.
try {
  const environment = publicEnvironment(process.env, { key: process.env.AUTH_PUBLISHABLE_KEY });
  const checkoutSha = execFileSync('git', ['rev-parse', 'HEAD'], {
    env: environment, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 10_000,
  }).trim();
  guardRun({ actions: process.env.GITHUB_ACTIONS, event: process.env.GITHUB_EVENT_NAME, ref: process.env.GITHUB_REF,
    sha: process.env.AUTH_SHA, reviewedSha: process.env.AUTH_REVIEWED_SHA, checkoutSha,
    dispatchSha: process.env.GITHUB_SHA, workflowSha: process.env.GITHUB_WORKFLOW_SHA,
    format: process.env.AUTH_FORMAT, projectRef: process.env.AUTH_PROJECT_REF,
    url: process.env.AUTH_URL, key: process.env.AUTH_PUBLISHABLE_KEY });
  process.stdout.write('AUTH_REVIEWED_SOURCE_ADMITTED\n');
} catch { process.stderr.write('AUTH_REVIEWED_SOURCE_REFUSED\n'); process.exitCode = 1; }
