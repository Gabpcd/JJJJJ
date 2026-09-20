import { readFileSync, appendFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const repo = process.env.GITHUB_REPOSITORY;
let sha = process.env.MOBILE_DELIVERY_SHA;
if (repo !== 'Gabpcd/JJJJJ' || !/^[a-f0-9]{40}$/.test(sha || '')) throw new Error('Unexpected repository or commit');
async function api(path) {
  const response = await fetch(`https://api.github.com/repos/${repo}/${path}`, {
    headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json' },
  });
  if (!response.ok) throw new Error(`GitHub ${response.status}: ${path}`);
  return response.json();
}
const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim();
const output = (mode, reason) => {
  appendFileSync(process.env.GITHUB_OUTPUT, `mode=${mode}\nsha=${sha}\n`);
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, `Delivery: **${mode}** — ${reason}\n`);
};
// Never execute an untrusted PR head with release credentials, or release an old main.
if ((await api('git/ref/heads/main')).object.sha !== sha) {
  output('none', 'A newer main commit exists.');
  process.exit(0);
}
const release = JSON.parse(readFileSync('config/mobile-release.json', 'utf8'));
let submitted;
try { submitted = git('rev-parse', '--verify', `refs/tags/mobile-native-${release.buildNumber}`); } catch { /* First delivery. */ }
if (!submitted) {
  let reserved;
  try { reserved = git('rev-parse', '--verify', `refs/tags/mobile-native-source-${release.buildNumber}`); } catch { /* First attempt. */ }
  if (reserved) {
    execFileSync('git', ['merge-base', '--is-ancestor', reserved, sha]);
    sha = reserved; // Check and resume exactly the previously reserved commit.
  }
}
for (const workflow of ['validate-pr.yml', 'playwright-e2e.yml', 'lighthouse.yml']) {
  const { workflow_runs: runs } = await api(`actions/workflows/${workflow}/runs?head_sha=${sha}&event=push&per_page=100`);
  const latest = runs.filter(run => run.head_branch === 'main').sort((a, b) => b.id - a.id)[0];
  if (latest?.conclusion !== 'success') {
    output('none', `Waiting for ${workflow} on this exact commit.`);
    process.exit(0);
  }
}
const deployment = await api(`commits/${sha}/status`);
if (!deployment.statuses.some(status => status.context === 'Vercel' && status.state === 'success')) {
  output('none', 'Waiting for the Vercel deployment of this exact commit.');
  process.exit(0);
}
const requested = process.env.MOBILE_DELIVERY_MODE || 'auto';
if (submitted === sha) {
  output('none', 'This native runtime has already been submitted.');
  process.exit(0);
}
if (requested === 'native' || !submitted) {
  if (submitted) throw new Error('Build number already submitted from another commit');
  const previousBuilds = git('tag', '--list', 'mobile-native-*').split('\n').map(tag => Number(tag.replace('mobile-native-', ''))).filter(Number.isFinite);
  if (release.buildNumber <= Math.max(19, ...previousBuilds)) throw new Error('Native build number must increase');
  output('native', `Store submission ${release.marketingVersion} (${release.buildNumber}).`);
} else {
  const prs = await api(`commits/${sha}/pulls`);
  const reviewed = prs.some(pr => pr.merged_at && pr.merge_commit_sha === sha && pr.labels.some(label => label.name === 'mobile:ota'));
  if (!reviewed) {
    output('none', 'No reviewed mobile:ota PR and no native version increment.');
    process.exit(0);
  }
  const baseline = `mobile-native-${release.buildNumber}`;
  // Must have a submitted native runtime with identical plugins, signing key and build configuration.
  git('rev-parse', '--verify', `${baseline}^{commit}`);
  const nativeChanges = git('diff', '--name-only', baseline, sha, '--', 'ios', 'android', 'package.json', 'package-lock.json', 'capacitor.config.ts', 'config', 'vite.config.ts', 'scripts/mobile');
  if (nativeChanges) throw new Error(`Native changes require a store build: ${nativeChanges}`);
  const changes = git('diff', '--name-only', baseline, sha).split('\n');
  const forbidden = /(?:auth|inscription|connexion|consent|cgu|legal|payment|paiement|escrow|stripe|sepa|mobileUpdates|NativeUpdateReady)/i;
  if (changes.some(file => !/^(src\/|public\/|tests\/|e2e\/|docs\/)/.test(file) || forbidden.test(file))) {
    throw new Error('This change requires native store review, not an OTA correction');
  }
  for (const commit of git('rev-list', '--first-parent', `${baseline}..${sha}`).split('\n')) {
    const files = git('diff', '--name-only', `${commit}^`, commit).split('\n');
    if (!files.some(file => /^(src\/|public\/)/.test(file))) continue;
    const commitsPRs = await api(`commits/${commit}/pulls`);
    if (!commitsPRs.some(pr => pr.merged_at && pr.merge_commit_sha === commit && pr.labels.some(label => label.name === 'mobile:ota'))) {
      throw new Error(`Unreviewed OTA changes in ${commit}; create a new store build`);
    }
  }
  output('ota', 'Reviewed compatible correction, unchanged native runtime.');
}
