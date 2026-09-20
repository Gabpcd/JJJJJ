import { appendFileSync, readFileSync } from 'node:fs';
const sha = process.env.RELEASE_SHA;
const repo = process.env.GITHUB_REPOSITORY;
const build = JSON.parse(readFileSync('config/mobile-release.json', 'utf8')).buildNumber;
if (repo !== 'Gabpcd/JJJJJ' || !/^[a-f0-9]{40}$/.test(sha || '')) throw new Error('Invalid release identity');
async function api(path, method = 'GET', body) {
  const response = await fetch(`https://api.github.com/repos/${repo}/${path}`, {
    method, headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json' },
    body: body && JSON.stringify(body),
  });
  if (response.status === 404 && method === 'GET') return null;
  if (!response.ok) throw new Error(`GitHub release state HTTP ${response.status}`);
  return response.json();
}
const read = async tag => (await api(`git/ref/tags/${tag}`))?.object.sha;
async function record(tag) {
  const existing = await read(tag);
  if (existing && existing !== sha) throw new Error(`${tag} already belongs to another commit`);
  if (!existing) await api('git/refs', 'POST', { ref: `refs/tags/${tag}`, sha });
}
const [action, platform] = process.argv.slice(2);
if (platform && !['ios', 'android'].includes(platform)) throw new Error('Invalid platform');
if (action === 'reserve') await record(`mobile-native-source-${build}`);
else if (action === 'check') {
  const existing = await read(`mobile-native-${platform}-${build}`);
  if (existing && existing !== sha) throw new Error('Platform submitted from another commit');
  appendFileSync(process.env.GITHUB_OUTPUT, `submitted=${existing === sha}\n`);
} else if (action === 'record') await record(`mobile-native-${platform}-${build}`);
else if (action === 'complete') {
  for (const target of ['ios', 'android']) {
    if (await read(`mobile-native-${target}-${build}`) !== sha) throw new Error(`Submission missing for ${target}`);
  }
  await record(`mobile-native-${build}`);
} else throw new Error('Unknown release-state action');
