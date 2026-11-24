// Planificateur de mobile-delivery.yml. Depuis le lot 6 (docs/mobile-swift/DECISIONS_LOT6.md), il ne
// sert qu'Android (coquille Capacitor) : livraison native Google Play et mise à jour OTA. iOS natif
// (Swift) a ses propres workflows et n'a pas d'OTA (règle Apple 2.5.2) ; la coquille Capacitor iOS
// n'est plus construite ni soumise.
import { appendFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { checkBackendDeployment } from './delivery-plan-backend.mjs';
import { chargerConfigLivraison, exigerOtaAndroidSeul, plateformeMobileDelivery, tagsLivraison } from './release-config.mjs';

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
// A merge, Vercel status or completed workflow can never authorize a release.
const requested = process.env.MOBILE_DELIVERY_MODE || 'check';
if (process.env.GITHUB_EVENT_NAME !== 'workflow_dispatch' || process.env.GITHUB_REF !== 'refs/heads/main') {
  output('none', 'Mobile releases require an explicit manual dispatch on main.');
  process.exit(0);
}
if (!['check', 'native', 'ota'].includes(requested)) throw new Error('Unknown manual delivery mode');
// Refuse iOS in every mode, and the pre-split configuration, before any gate or output.
const platform = plateformeMobileDelivery(process.env.MOBILE_DELIVERY_PLATFORM);
const config = chargerConfigLivraison();
const release = config[platform];
const tags = tagsLivraison(platform, release.buildNumber);
// Never execute an untrusted PR head with release credentials, or release an old main.
const currentMain = (await api('git/ref/heads/main')).object.sha;
if (currentMain !== sha) {
  output('none', 'A newer main commit exists.');
  process.exit(0);
}
// Split tags: the Android runtime is `mobile-native-android-N`. The former common tag
// `mobile-native-N` required both stores and is never created nor read as a runtime again.
let submitted;
try { submitted = git('rev-parse', '--verify', `refs/tags/${tags.soumis}`); } catch { /* First delivery. */ }
if (!submitted) {
  let reserved;
  try { reserved = git('rev-parse', '--verify', `refs/tags/${tags.source}`); } catch { /* First attempt. */ }
  if (reserved) {
    execFileSync('git', ['merge-base', '--is-ancestor', reserved, sha]);
    sha = reserved; // Check and resume exactly the previously reserved commit.
  }
}
for (const workflow of ['validate-pr.yml', 'playwright-e2e.yml', 'lighthouse.yml', 'android-native-recette.yml']) {
  const { workflow_runs: runs } = await api(`actions/workflows/${workflow}/runs?head_sha=${sha}&event=push&per_page=100`);
  const latest = runs.filter(run => run.head_branch === 'main' && run.head_sha === sha && run.event === 'push')
    .sort((a, b) => b.id - a.id)[0];
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
if (submitted === sha) {
  output('none', 'This native runtime has already been submitted.');
  process.exit(0);
}
const backend = await checkBackendDeployment({ sha, api, git });
if (!backend.ready) {
  output('none', backend.reason);
  process.exit(0);
}
if (requested === 'check') {
  output('none', 'Quality and backend gates passed. Verification only: no build, update or store submission.');
  process.exit(0);
}
if (requested === 'ota' && !submitted) {
  output('none', 'No submitted native runtime for this build. OTA cannot start a native store submission.');
  process.exit(0);
}
if (requested === 'native') {
  if (submitted) throw new Error('Build number already submitted from another commit');
  // Android versionCodes already delivered: split Android tags and the former common tags.
  // iOS tags (Capacitor shell or Swift builds) follow their own numbering and are ignored.
  const previousBuilds = git('tag', '--list', 'mobile-native-*').split('\n')
    .map(tag => tag.match(/^mobile-native-(?:android-)?(\d+)$/)?.[1]).filter(Boolean).map(Number);
  if (release.buildNumber <= Math.max(19, ...previousBuilds)) throw new Error('Native build number must increase');
  output('native', `Google Play submission, Android ${release.marketingVersion} (${release.buildNumber}).`);
} else {
  // Android only, and never on a runtime the iOS Capacitor shell also carried.
  exigerOtaAndroidSeul(config);
  const prs = await api(`commits/${sha}/pulls`);
  const reviewed = prs.some(pr => pr.merged_at && pr.merge_commit_sha === sha && pr.labels.some(label => label.name === 'mobile:ota'));
  if (!reviewed) {
    output('none', 'No reviewed mobile:ota PR and no native version increment.');
    process.exit(0);
  }
  const baseline = tags.soumis;
  // Must have a submitted native runtime with identical plugins, signing key and build configuration.
  git('rev-parse', '--verify', `${baseline}^{commit}`);
  // `ios-native` (plan, lot 6): a change to the Swift app is never an OTA; it needs a store build.
  const nativeChanges = git('diff', '--name-only', baseline, sha, '--', 'ios', 'ios-native', 'android', 'package.json', 'package-lock.json', 'capacitor.config.ts', 'config', 'vite.config.ts', 'scripts/mobile');
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
