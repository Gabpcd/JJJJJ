import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
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

test('le point de comparaison se lit dans un vrai dépôt git ; un commit inconnu échoue au lieu de tout signaler', () => {
  // Vrai git, pas de messages imités : c'est le comportement réel de git qui compte ici.
  const depot = mkdtempSync(path.join(tmpdir(), 'indexnow-git-'));
  const git = (...args) => execFileSync('git', args, { cwd: depot, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  try {
    git('init', '-q');
    git('config', 'user.email', 'test@jolene.test'); git('config', 'user.name', 'Test'); git('config', 'commit.gpgsign', 'false');
    writeFileSync(path.join(depot, 'LISEZMOI'), 'un');
    git('add', '-A'); git('commit', '-q', '-m', 'sans empreintes');
    const sans = git('rev-parse', 'HEAD');
    mkdirSync(path.join(depot, path.dirname(FICHIER_EMPREINTES)), { recursive: true });
    writeFileSync(path.join(depot, FICHIER_EMPREINTES), '{"/":"aaa","/guides":"bbb"}');
    git('add', '-A'); git('commit', '-q', '-m', 'avec empreintes');
    const avec = git('rev-parse', 'HEAD');

    assert.equal(empreintesAuCommit(sans, { cwd: depot }), null, 'fichier absent du commit : premier signalement');
    assert.deepEqual(empreintesAuCommit(avec, { cwd: depot }), { '/': 'aaa', '/guides': 'bbb' });
    assert.equal(empreintesAuCommit('HEAD~1', { cwd: depot }), null, 'par défaut : le commit précédent');
    // Commit inconnu du dépôt (valeur de github.event.before quand la branche vient d'être créée, ou fetch oublié).
    assert.throws(() => empreintesAuCommit('0000000000000000000000000000000000000000', { cwd: depot }), /introuvable/);
    assert.throws(() => empreintesAuCommit('0123456789abcdef0123456789abcdef01234567', { cwd: depot }), /introuvable/);
    assert.throws(() => empreintesAuCommit('main; rm -rf /', { cwd: depot }), /invalide/);
  } finally {
    rmSync(depot, { recursive: true, force: true });
  }
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
