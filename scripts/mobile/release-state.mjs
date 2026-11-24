// État de livraison par plateforme, porté par des tags git (docs/mobile-swift/DECISIONS_LOT6.md, D4).
//
//   reserve android   fige le commit d'une livraison Android : mobile-native-source-android-N
//   check <plateforme>   la plateforme est-elle déjà soumise depuis ce commit ?
//   record <plateforme>  consigne la soumission : mobile-native-android-N ou mobile-native-ios-N
//
// Android lit son versionCode dans config/mobile-release.json. iOS (Swift) reçoit le numéro du build
// TestFlight soumis dans RELEASE_BUILD_NUMBER : il n'est pas figé dans le dépôt. Aucune action
// n'exige les deux plateformes ; l'ancien tag commun mobile-native-N n'est plus créé.
import { appendFileSync } from 'node:fs';
import { DOC, PLATEFORMES, buildIosSoumis, chargerConfigLivraison, tagsLivraison } from './release-config.mjs';

const sha = process.env.RELEASE_SHA;
const repo = process.env.GITHUB_REPOSITORY;
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
if (action === 'complete') {
  // Verrou : l'ancienne clôture exigeait les tags iOS et Android puis posait mobile-native-N.
  throw new Error(`Action « complete » retirée : les tags sont scindés par plateforme, « record <plateforme> » clôt la livraison (voir ${DOC})`);
}
if (!['reserve', 'check', 'record'].includes(action)) throw new Error('Unknown release-state action');
if (!PLATEFORMES.includes(platform)) throw new Error(`Invalid platform: « ${platform ?? ''} » (ios ou android exigé, voir ${DOC})`);
const config = chargerConfigLivraison();
const build = platform === 'android' ? config.android.buildNumber : buildIosSoumis(config, process.env.RELEASE_BUILD_NUMBER);
const tags = tagsLivraison(platform, build);

if (action === 'reserve') {
  if (!tags.source) throw new Error(`iOS natif ne réserve aucune source : le build soumis vient de TestFlight (voir ${DOC})`);
  await record(tags.source);
} else if (action === 'check') {
  const existing = await read(tags.soumis);
  if (existing && existing !== sha) throw new Error('Platform submitted from another commit');
  appendFileSync(process.env.GITHUB_OUTPUT, `submitted=${existing === sha}\n`);
} else await record(tags.soumis);
