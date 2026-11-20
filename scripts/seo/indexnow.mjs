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
 * Ce qui est envoyé : l'hôte, la clé, l'adresse du fichier de clé et les URL des pages publiques
 * dont le contenu a changé. Aucune donnée d'utilisateur.
 *
 * Seules les pages ajoutées, modifiées ou supprimées sont signalées : le protocole le demande
 * (« Submit only when content has changed. Do not resubmit unchanged URLs », indexnow.org/faq),
 * et chaque URL signalée compte dans le quota d'exploration du site. Le changement se lit dans
 * `src/lib/seo-empreintes.json` (une empreinte du contenu par page, tenue à jour par
 * `npm run seo:empreintes`), comparé entre le commit courant et le précédent.
 *
 * Usage :
 *   node scripts/seo/indexnow.mjs --changements   signale les pages changées depuis le commit précédent
 *   node scripts/seo/indexnow.mjs --tout          signale tout le sitemap en ligne (refonte, migration)
 *   ... --simuler                                 n'envoie rien, affiche ce qui partirait
 *   ... --attendre                                attend d'abord le déploiement de production du
 *                                                 commit courant (GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_TOKEN)
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const HOTE = 'jolene.app';
export const CLE_INDEXNOW = 'jolene-sante-indexnow-2026';
export const URL_CLE = `https://${HOTE}/${CLE_INDEXNOW}.txt`;
export const URL_SITEMAP = `https://${HOTE}/sitemap.xml`;
export const POINT_INDEXNOW = 'https://api.indexnow.org/indexnow';
export const FICHIER_EMPREINTES = 'src/lib/seo-empreintes.json';
/** Limite du protocole par requête. */
export const MAX_URLS = 10_000;

/** URL d'un sitemap, limitées à l'hôte : une URL d'un autre domaine ferait rejeter tout l'envoi. */
export function urlsDuSitemap(xml, hote = HOTE) {
  const urls = [...String(xml).matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((m) => m[1].replace(/&amp;/g, '&'));
  return [...new Set(urls)].filter((u) => {
    try { const x = new URL(u); return x.protocol === 'https:' && x.host === hote; } catch { return false; }
  });
}

/**
 * Adresses à signaler entre deux jeux d'empreintes : pages ajoutées, modifiées ou supprimées
 * (une page supprimée se signale aussi, pour que les moteurs la retirent).
 * `avant` nul = premier signalement : toutes les pages.
 */
export function urlsChangees(avant, apres, hote = HOTE) {
  const chemins = new Set();
  for (const [chemin, empreinte] of Object.entries(apres)) if (!avant || avant[chemin] !== empreinte) chemins.add(chemin);
  for (const chemin of Object.keys(avant ?? {})) if (!(chemin in apres)) chemins.add(chemin);
  return [...chemins].sort().map((chemin) => `https://${hote}${chemin}`);
}

/** Empreintes du commit précédent, ou `null` si le fichier n'y existait pas. */
export function empreintesDuCommitPrecedent(executer = execFileSync) {
  try {
    return JSON.parse(executer('git', ['show', `HEAD~1:${FICHIER_EMPREINTES}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
  } catch {
    return null;
  }
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

/**
 * Envoie `urls`. Sans `urls` (mode `--tout`), lit le sitemap en ligne.
 */
export async function soumettre({ urls, recuperer = fetch, simuler = false, journal = console.log } = {}) {
  if (urls && urls.length === 0) return { etat: 'rien', urls: 0 };
  // La clé doit être servie avant tout envoi : sans elle, le service répond 403 et peut écarter l'hôte.
  const cle = await recuperer(URL_CLE);
  const texteCle = cle.ok ? (await cle.text()).trim() : '';
  if (texteCle !== CLE_INDEXNOW) return { etat: 'refus', detail: `fichier de clé absent ou différent à ${URL_CLE} (HTTP ${cle.status})` };

  let liste = urls;
  if (!liste) {
    const sitemap = await recuperer(URL_SITEMAP);
    if (!sitemap.ok) return { etat: 'indisponible', detail: `sitemap en ligne illisible (HTTP ${sitemap.status})` };
    liste = urlsDuSitemap(await sitemap.text());
  }
  const corps = corpsIndexNow(liste);
  if (simuler) {
    journal(`[indexnow] simulation : ${liste.length} URL, rien n'est envoyé`);
    for (const u of liste.slice(0, 20)) journal(`  ${u}`);
    return { etat: 'simule', urls: liste.length };
  }

  const reponse = await recuperer(POINT_INDEXNOW, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(corps),
  });
  return { etat: lireReponse(reponse.status), urls: liste.length, detail: `HTTP ${reponse.status}` };
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

  // Ce qui ne dépend pas du réseau se calcule d'abord, et échoue franchement en cas d'erreur.
  if (options.has('--tout') === options.has('--changements')) {
    console.error('[indexnow] préciser --changements (pages changées depuis le commit précédent) ou --tout (sitemap en ligne)');
    process.exit(2);
  }
  const urls = options.has('--tout')
    ? undefined
    : urlsChangees(empreintesDuCommitPrecedent(), JSON.parse(readFileSync(FICHIER_EMPREINTES, 'utf8')));
  if (urls && urls.length === 0) {
    console.log('[indexnow] aucune page changée depuis le commit précédent : rien à signaler');
    process.exit(0);
  }

  try {
    if (options.has('--attendre')) {
      const pret = await attendreDeploiement({ depot: process.env.GITHUB_REPOSITORY, sha: process.env.GITHUB_SHA, jeton: process.env.GITHUB_TOKEN });
      if (!pret) { avertir('déploiement de production non confirmé : aucun envoi. Relancez cette exécution une fois le site à jour.'); process.exit(0); }
      // Le domaine bascule sur le nouveau déploiement juste après son succès : marge avant de relire le site.
      await new Promise((r) => setTimeout(r, 60_000));
    }
    const r = await soumettre({ urls, simuler: options.has('--simuler') });
    if (r.etat === 'refus') { console.error(`[indexnow] refus : ${r.detail}`); process.exit(1); }
    if (r.etat === 'indisponible') { avertir(`service indisponible (${r.detail}) : la prochaine mise en ligne signalera ses propres changements ; relancez cette exécution pour ceux-ci.`); process.exit(0); }
    console.log(`[indexnow] ${r.etat} : ${r.urls} URL${r.detail ? ` (${r.detail})` : ''}`);
  } catch (e) {
    // Panne réseau : ne pas faire échouer un workflow pour un service tiers momentanément injoignable.
    avertir(`envoi impossible (${e instanceof Error ? e.message : e}) : relancez cette exécution.`);
  }
}
