import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { attendreDeploiement, CLE_INDEXNOW, corpsIndexNow, empreintesAuCommit, FICHIER_EMPREINTES, HOTE, lireReponse, POINT_INDEXNOW, soumettre, URL_CLE, URL_SITEMAP, urlsChangees, urlsDuSitemap } from '../../scripts/seo/indexnow.mjs';

const reponse = (status, corps = '') => ({ ok: status >= 200 && status < 300, status, text: async () => corps, json: async () => JSON.parse(corps) });
const SITEMAP = `<?xml version="1.0"?><urlset>
  <url><loc>https://jolene.app/</loc></url>
  <url><loc>https://jolene.app/guides</loc><lastmod>2026-11-20</lastmod></url>
  <url><loc>https://jolene.app/guides</loc></url>
  <url><loc>https://exemple.test/ailleurs</loc></url>
  <url><loc>http://jolene.app/non-securise</loc></url>
</urlset>`;

test('la clé est servie par le site, sous le nom que le protocole attend', () => {
  assert.match(CLE_INDEXNOW, /^[a-zA-Z0-9-]{8,128}$/);
  assert.equal(readFileSync(new URL(`../../public/${CLE_INDEXNOW}.txt`, import.meta.url), 'utf8'), CLE_INDEXNOW);
  assert.equal(URL_CLE, `https://${HOTE}/${CLE_INDEXNOW}.txt`);
});

test('seules les URL https de l\'hôte, sans doublon, sont retenues', () => {
  assert.deepEqual(urlsDuSitemap(SITEMAP), ['https://jolene.app/', 'https://jolene.app/guides']);
  assert.deepEqual(corpsIndexNow(['https://jolene.app/']), { host: HOTE, key: CLE_INDEXNOW, keyLocation: URL_CLE, urlList: ['https://jolene.app/'] });
  assert.throws(() => corpsIndexNow([]), /aucune URL/);
});

test('un refus se distingue d\'une panne du service', () => {
  assert.equal(lireReponse(200), 'accepte');
  assert.equal(lireReponse(202), 'accepte');
  assert.equal(lireReponse(403), 'refus');
  assert.equal(lireReponse(422), 'refus');
  assert.equal(lireReponse(429), 'indisponible');
  assert.equal(lireReponse(503), 'indisponible');
});

test('seules les pages ajoutées, modifiées ou supprimées sont signalées', () => {
  const avant = { '/': 'aaa', '/guides': 'bbb', '/ancienne-page': 'ccc' };
  const apres = { '/': 'aaa', '/guides': 'bbb2', '/guides/nouveau': 'ddd' };
  assert.deepEqual(urlsChangees(avant, apres), ['https://jolene.app/ancienne-page', 'https://jolene.app/guides', 'https://jolene.app/guides/nouveau']);
  assert.deepEqual(urlsChangees(apres, apres), [], 'rien ne part quand rien ne change');
  assert.deepEqual(urlsChangees(null, { '/': 'aaa', '/guides': 'bbb' }), ['https://jolene.app/', 'https://jolene.app/guides'], 'premier signalement : toutes les pages');
});

test('le point de comparaison est le commit indiqué ; seul un fichier absent vaut premier signalement', () => {
  const appels = [];
  const lu = empreintesAuCommit('0123abc', (commande, args) => { appels.push([commande, ...args]); return '{"/":"aaa"}'; });
  assert.deepEqual(lu, { '/': 'aaa' });
  assert.deepEqual(appels, [['git', 'show', `0123abc:${FICHIER_EMPREINTES}`]]);
  const erreurGit = (stderr) => () => { throw Object.assign(new Error('Command failed'), { stderr }); };
  assert.equal(empreintesAuCommit('HEAD~1', erreurGit(`fatal: path '${FICHIER_EMPREINTES}' does not exist in 'HEAD~1'`)), null);
  assert.equal(empreintesAuCommit('HEAD~1', erreurGit(`fatal: path '${FICHIER_EMPREINTES}' exists on disk, but not in 'HEAD~1'`)), null);
  // Un commit introuvable n'est pas un premier signalement : sinon les 228 pages partiraient.
  assert.throws(() => empreintesAuCommit('0123abc', erreurGit('fatal: invalid object name 0123abc')), /impossible/);
  assert.throws(() => empreintesAuCommit('main; rm -rf /'), /invalide/);
  assert.throws(() => empreintesAuCommit('0000000000000000000000000000000000000000', erreurGit('fatal: bad object 0000000')), /impossible/);
});

test('le fichier d\'empreintes versionné ne liste que des chemins du site', () => {
  const empreintes = JSON.parse(readFileSync(new URL(`../../${FICHIER_EMPREINTES}`, import.meta.url), 'utf8'));
  assert.ok(Object.keys(empreintes).length > 200);
  for (const [chemin, e] of Object.entries(empreintes)) { assert.match(chemin, /^\/[a-z0-9/-]*$/); assert.match(e, /^[0-9a-f]{12}$/); }
  assert.equal(urlsChangees(null, empreintes).length, Object.keys(empreintes).length);
});

test('aucune liste vide ne part, et aucun appel réseau n\'est fait pour elle', async () => {
  const appels = [];
  assert.deepEqual(await soumettre({ urls: [], recuperer: async (u) => { appels.push(u); return reponse(200); } }), { etat: 'rien', urls: 0 });
  assert.deepEqual(appels, []);
});

test('rien n\'est envoyé tant que le fichier de clé n\'est pas servi', async () => {
  const appels = [];
  const r = await soumettre({ recuperer: async (url) => { appels.push(url); return reponse(404); } });
  assert.equal(r.etat, 'refus');
  assert.deepEqual(appels, [URL_CLE]);
});

test('l\'envoi porte les pages changées ; la simulation n\'envoie rien', async () => {
  const appels = [];
  const recuperer = async (url, init) => {
    appels.push({ url, init });
    if (url === URL_CLE) return reponse(200, `${CLE_INDEXNOW}\n`);
    if (url === URL_SITEMAP) return reponse(200, SITEMAP);
    return reponse(202);
  };
  const urls = ['https://jolene.app/guides/nouveau'];
  assert.deepEqual(await soumettre({ urls, recuperer, simuler: true, journal: () => {} }), { etat: 'simule', urls: 1 });
  assert.equal(appels.some((a) => a.url === POINT_INDEXNOW), false);

  const r = await soumettre({ urls, recuperer });
  assert.equal(r.etat, 'accepte');
  assert.equal(appels.some((a) => a.url === URL_SITEMAP), false, 'le sitemap n\'est pas lu quand la liste est fournie');
  const envoi = appels.find((a) => a.url === POINT_INDEXNOW);
  assert.equal(envoi.init.method, 'POST');
  assert.deepEqual(JSON.parse(envoi.init.body), { host: HOTE, key: CLE_INDEXNOW, keyLocation: URL_CLE, urlList: urls });
});

test('le mode « tout » lit le sitemap en ligne', async () => {
  const appels = [];
  const recuperer = async (url, init) => {
    appels.push({ url, init });
    if (url === URL_CLE) return reponse(200, CLE_INDEXNOW);
    if (url === URL_SITEMAP) return reponse(200, SITEMAP);
    return reponse(200);
  };
  assert.deepEqual(await soumettre({ recuperer }), { etat: 'accepte', urls: 2, detail: 'HTTP 200' });
  assert.deepEqual(JSON.parse(appels.find((a) => a.url === POINT_INDEXNOW).init.body).urlList, ['https://jolene.app/', 'https://jolene.app/guides']);
});

test('l\'attente du déploiement s\'arrête au succès, à l\'échec ou à l\'épuisement des essais', async () => {
  const api = (etats) => async (url) => (url.includes('/statuses') ? reponse(200, JSON.stringify(etats.map((state) => ({ state })))) : reponse(200, JSON.stringify([{ id: 7 }])));
  const base = { depot: 'o/r', sha: 'abc', pause: async () => {}, essais: 2 };
  assert.equal(await attendreDeploiement({ ...base, recuperer: api(['pending', 'success']) }), true);
  assert.equal(await attendreDeploiement({ ...base, recuperer: api(['failure']) }), false);
  assert.equal(await attendreDeploiement({ ...base, recuperer: api(['pending']) }), false);
  assert.equal(await attendreDeploiement({ ...base, recuperer: async () => reponse(200, '[]') }), false);
});

test('le workflow ne part que de main, sur le contenu SEO, sans secret', () => {
  const yml = readFileSync(new URL('../../.github/workflows/indexnow.yml', import.meta.url), 'utf8');
  assert.match(yml, /push:\n\s+branches: \[main\]\n\s+paths:\n\s+- 'src\/lib\/seo-empreintes\.json'\n/);
  assert.doesNotMatch(yml, /concurrency:|cancel-in-progress/);
  assert.match(yml, /AVANT: \$\{\{ github\.event\.before \}\}\n\s+run: git fetch --no-tags --depth=1 origin "\$AVANT"/);
  assert.match(yml, /indexnow\.mjs --changements --depuis "\$AVANT" --attendre/);
  assert.match(yml, /github\.event_name == 'workflow_dispatch'[\s\S]*?indexnow\.mjs --tout/);
  assert.doesNotMatch(yml, /pull_request|secrets\./);
  assert.match(yml, /permissions:\n\s+contents: read\n\s+deployments: read/);
});
