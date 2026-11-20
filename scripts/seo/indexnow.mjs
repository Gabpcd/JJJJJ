#!/usr/bin/env node
/**
 * Signale les pages publiques aux moteurs qui suivent le protocole IndexNow (Bing, Yandex, Seznam,
 * Naver). Google ne le suit pas : pour lui, le sitemap se soumet dans la Search Console.
 *
 * Pourquoi : un domaine récent est exploré rarement. Bing alimente aussi Copilot, DuckDuckGo et la
 * recherche de ChatGPT. Le protocole ne demande aucun compte : la preuve que l'on contrôle le
 * domaine est un fichier texte servi à sa racine, dont le nom et le contenu sont la clé.
 *
 * La clé n'est pas un secret : elle est publiée par construction (`public/<clé>.txt`). Elle est
 * volontairement lisible, pour ne pas ressembler à un identifiant aux yeux des détecteurs de secrets.
 *
 * Ce qui est envoyé : l'hôte, la clé, l'adresse du fichier de clé et la liste des URL du sitemap
 * EN LIGNE. Aucune donnée d'utilisateur, aucune URL hors sitemap.
 *
 * Usage :
 *   node scripts/seo/indexnow.mjs                 soumet le sitemap en ligne
 *   node scripts/seo/indexnow.mjs --simuler       n'envoie rien, affiche ce qui partirait
 *   node scripts/seo/indexnow.mjs --attendre      attend d'abord le déploiement de production du
 *                                                 commit courant (GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_TOKEN)
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const HOTE = 'jolene.app';
export const CLE_INDEXNOW = 'jolene-sante-indexnow-2026';
export const URL_CLE = `https://${HOTE}/${CLE_INDEXNOW}.txt`;
export const URL_SITEMAP = `https://${HOTE}/sitemap.xml`;
export const POINT_INDEXNOW = 'https://api.indexnow.org/indexnow';
/** Limite du protocole par requête. */
export const MAX_URLS = 10_000;

/** URL d'un sitemap, limitées à l'hôte : une URL d'un autre domaine ferait rejeter tout l'envoi. */
export function urlsDuSitemap(xml, hote = HOTE) {
  const urls = [...String(xml).matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((m) => m[1].replace(/&amp;/g, '&'));
  return [...new Set(urls)].filter((u) => {
    try { const x = new URL(u); return x.protocol === 'https:' && x.host === hote; } catch { return false; }
  });
}

export function corpsIndexNow(urls, { hote = HOTE, cle = CLE_INDEXNOW } = {}) {
  if (!urls.length) throw new Error('IndexNow : aucune URL à soumettre');
  if (urls.length > MAX_URLS) throw new Error(`IndexNow : ${urls.length} URL, limite ${MAX_URLS} par envoi`);
  return { host: hote, key: cle, keyLocation: `https://${hote}/${cle}.txt`, urlList: urls };
}

/**
 * Résultat d'un envoi. `refus` = erreur de notre fait (clé non servie, URL hors hôte) : à corriger.
 * `indisponible` = panne ou limitation du service : le prochain déploiement réessaiera.
 */
export function lireReponse(statut) {
  if (statut === 200 || statut === 202) return 'accepte';
  if (statut === 429 || statut >= 500) return 'indisponible';
  return 'refus';
}

export async function soumettre({ recuperer = fetch, simuler = false, journal = console.log } = {}) {
  // La clé doit être servie avant tout envoi : sans elle, le service répond 403 et peut écarter l'hôte.
  const cle = await recuperer(URL_CLE);
  const texteCle = cle.ok ? (await cle.text()).trim() : '';
  if (texteCle !== CLE_INDEXNOW) return { etat: 'refus', detail: `fichier de clé absent ou différent à ${URL_CLE} (HTTP ${cle.status})` };

  const sitemap = await recuperer(URL_SITEMAP);
  if (!sitemap.ok) return { etat: 'indisponible', detail: `sitemap en ligne illisible (HTTP ${sitemap.status})` };
  const urls = urlsDuSitemap(await sitemap.text());
  const corps = corpsIndexNow(urls);
  if (simuler) { journal(`[indexnow] simulation : ${urls.length} URL, rien n'est envoyé`); return { etat: 'simule', urls: urls.length }; }

  const reponse = await recuperer(POINT_INDEXNOW, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(corps),
  });
  return { etat: lireReponse(reponse.status), urls: urls.length, detail: `HTTP ${reponse.status}` };
}

/** Attend que le déploiement de production du commit soit en succès (API GitHub des déploiements). */
export async function attendreDeploiement({ depot, sha, jeton, recuperer = fetch, pause = (ms) => new Promise((r) => setTimeout(r, ms)), essais = 60, intervalle = 15_000 }) {
  const entetes = { Accept: 'application/vnd.github+json', ...(jeton ? { Authorization: `Bearer ${jeton}` } : {}) };
  for (let i = 0; i < essais; i += 1) {
    const liste = await recuperer(`https://api.github.com/repos/${depot}/deployments?sha=${sha}&environment=Production&per_page=5`, { headers: entetes });
    const deploiements = liste.ok ? await liste.json() : [];
    for (const d of deploiements) {
      const statuts = await recuperer(`https://api.github.com/repos/${depot}/deployments/${d.id}/statuses?per_page=10`, { headers: entetes });
      const etats = statuts.ok ? (await statuts.json()).map((s) => s.state) : [];
      if (etats.includes('success')) return true;
      if (etats.some((e) => e === 'failure' || e === 'error')) return false;
    }
    await pause(intervalle);
  }
  return false;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const options = new Set(process.argv.slice(2));
  const avertir = (m) => console.log(process.env.GITHUB_ACTIONS ? `::warning::${m}` : `[indexnow] ${m}`);
  try {
    if (options.has('--attendre')) {
      const pret = await attendreDeploiement({ depot: process.env.GITHUB_REPOSITORY, sha: process.env.GITHUB_SHA, jeton: process.env.GITHUB_TOKEN });
      if (!pret) { avertir('déploiement de production non confirmé : aucun envoi. Relancez le workflow à la main une fois le site à jour.'); process.exit(0); }
      // Le domaine bascule sur le nouveau déploiement juste après son succès : marge avant de lire le sitemap en ligne.
      await new Promise((r) => setTimeout(r, 60_000));
    }
    const r = await soumettre({ simuler: options.has('--simuler') });
    if (r.etat === 'refus') { console.error(`[indexnow] refus : ${r.detail}`); process.exit(1); }
    if (r.etat === 'indisponible') { avertir(`service indisponible (${r.detail}) : le prochain déploiement réessaiera.`); process.exit(0); }
    console.log(`[indexnow] ${r.etat} : ${r.urls} URL${r.detail ? ` (${r.detail})` : ''}`);
  } catch (e) {
    // Panne réseau : ne pas faire échouer un workflow pour un service tiers momentanément injoignable.
    avertir(`envoi impossible (${e instanceof Error ? e.message : e}) : le prochain déploiement réessaiera.`);
  }
}
