#!/usr/bin/env node
/**
 * Prérendu léger des pages SEO (sans navigateur headless), exécuté après `vite build`.
 *
 *  - lit dist/index.html (shell SPA produit par Vite) ;
 *  - relit dist/app.html : le shell SANS canonical ni og:url que le build Vite écrit
 *    (plugin `scripts/seo/vite-pages-statiques.mjs`) et que vercel.json sert pour toute
 *    route sans fichier statique (espaces connectés, pages légales, /mission/:id, URL
 *    inconnues). Avant, ces routes recevaient le shell de l'accueil et déclaraient donc
 *    `canonical = https://jolene.app/` dans leur HTML brut. S'il manque (dist produit sans
 *    le plugin), il est dérivé de dist/index.html ;
 *  - écrit dist/<route>/index.html pour chaque route SEO (l'accueil remplace
 *    dist/index.html), avec <title>, meta description, canonical, og:/twitter: et
 *    données structurées dans le <head>, et un contenu HTML sémantique (H1, intro,
 *    sections, questions fréquentes, liens internes) dans <div id="root"> ;
 *    src/main.tsx utilise createRoot().render() : React REMPLACE ce contenu
 *    au montage (pas d'hydratation, donc aucun mismatch possible) ;
 *  - écrit dist/llms.txt (présentation du site pour les assistants IA) ;
 *  - régénère dist/sitemap.xml (sans lastmod pour les routes SEO : une date de build
 *    changerait à chaque déploiement sans que le contenu change) en conservant les URL
 *    de public/sitemap.xml qui ne sont pas des routes SEO. Les pages noindex (ville ×
 *    métier sans donnée BMO) sont générées mais absentes du sitemap.
 *
 * Source de vérité : src/lib/seo-routes.ts (même module que les composants React),
 * compilé à la volée avec esbuild.
 *
 * Le contenu statique suit le modèle `PageSEO` : H1, introduction, sections (paragraphes,
 * points titrés, liste, tableau, liens, sources), questions fréquentes, liens. Le composant
 * React `ContenuSEO` rend la même structure à partir du même objet.
 *
 * Usage : node scripts/seo/generer-pages-statiques.mjs [--dist dist]
 */
import { build } from 'esbuild';
import { mkdtemp, readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { FICHIER_SQUELETTE, squeletteApplication } from './vite-pages-statiques.mjs';

export { squeletteApplication };

const RACINE_DEFAUT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

export function echapper(texte) {
  return String(texte)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** Compile src/lib/seo-routes.ts (TS + JSON + imports relatifs) en ESM Node et l'importe. */
export async function chargerRoutesSeo(racine = RACINE_DEFAUT) {
  const tmp = await mkdtemp(path.join(tmpdir(), 'jolene-seo-'));
  try {
    const sortie = path.join(tmp, 'seo-routes.mjs');
    await build({
      entryPoints: [path.join(racine, 'src/lib/seo-routes.ts')],
      outfile: sortie,
      bundle: true,
      format: 'esm',
      platform: 'node',
      target: 'node20',
      logLevel: 'silent',
      alias: { '@': path.join(racine, 'src') },
    });
    return await import(pathToFileURL(sortie).href);
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
}

/** Retire du <head> les balises que l'on va réécrire (évite les doublons avec le shell). */
function nettoyerHead(html) {
  return html
    .replace(/<title>[\s\S]*?<\/title>\s*/i, '')
    .replace(/<link\s+rel="canonical"[^>]*>\s*/gi, '')
    .replace(/<meta\s+name="description"[^>]*>\s*/gi, '')
    .replace(/<meta\s+name="robots"[^>]*>\s*/gi, '')
    .replace(/<meta\s+property="og:(?:title|description|url)"[^>]*>\s*/gi, '')
    .replace(/<meta\s+name="twitter:(?:title|description)"[^>]*>\s*/gi, '');
}

export const STYLE_PRERENDU = '<style>main[data-prerender]{max-width:48rem;margin:0 auto;padding:24px 16px;font-family:system-ui,-apple-system,sans-serif;line-height:1.5;color:#1f1a2e}main[data-prerender] h1{font-size:1.75rem;line-height:1.2;font-weight:700;margin:0 0 16px}main[data-prerender] h2{font-size:1.25rem;line-height:1.3;font-weight:700;margin:24px 0 8px}main[data-prerender] h3{font-size:1rem;font-weight:600;margin:16px 0 4px}main[data-prerender] p{margin:0 0 12px}main[data-prerender] ul,main[data-prerender] ol{padding-left:20px}main[data-prerender] a{color:inherit;text-decoration:underline}main[data-prerender] .tableau{overflow-x:auto}main[data-prerender] table{border-collapse:collapse;font-size:.875rem}main[data-prerender] th,main[data-prerender] td{border:1px solid #d9d4e3;padding:4px 8px;text-align:left}</style>';

/** Script JSON-LD de la page. `<` est échappé : aucun texte ne peut fermer la balise script. */
export function scriptJsonLd(blocs) {
  if (!blocs?.length) return null;
  return `<script type="application/ld+json" data-jolene-ld="true">${JSON.stringify(blocs).replace(/</g, '\\u003c')}</script>`;
}

export function blocHead(page, siteUrl, jsonLd = []) {
  const url = `${siteUrl}${page.path}`;
  return [
    `<title>${echapper(page.title)}</title>`,
    `<meta name="description" content="${echapper(page.description)}" />`,
    `<meta name="robots" content="${page.indexable ? 'index, follow' : 'noindex, nofollow'}" />`,
    `<link rel="canonical" href="${echapper(url)}" />`,
    `<meta property="og:title" content="${echapper(page.title)}" />`,
    `<meta property="og:description" content="${echapper(page.description)}" />`,
    `<meta property="og:url" content="${echapper(url)}" />`,
    `<meta name="twitter:title" content="${echapper(page.title)}" />`,
    `<meta name="twitter:description" content="${echapper(page.description)}" />`,
    // Même attribut que SEOHead : au montage, React reprend ce script au lieu d'en ajouter un second.
    scriptJsonLd(jsonLd),
    // Lisible avant le chargement du JS (réseau lent) ; React remplace ce bloc au montage.
    STYLE_PRERENDU,
  ].filter(Boolean).map((l) => `    ${l}`).join('\n') + '\n';
}

const paragraphesHtml = (liste = []) => liste.map((p) => `<p>${echapper(p)}</p>`).join('');
const listeHtml = (liste = [], ordonnee = false) => {
  const balise = ordonnee ? 'ol' : 'ul';
  return liste.length ? `<${balise}>${liste.map((e) => `<li>${echapper(e)}</li>`).join('')}</${balise}>` : '';
};
const pointsHtml = (points = []) => points.map((p) => {
  const titre = p.href ? `<a href="${echapper(p.href)}">${echapper(p.titre)}</a>` : echapper(p.titre);
  return `<h3>${titre}</h3><p>${echapper(p.texte)}</p>`;
}).join('');
const tableauHtml = (t) => {
  if (!t) return '';
  const entetes = t.entetes.map((e) => `<th scope="col">${echapper(e)}</th>`).join('');
  const lignes = t.lignes.map((l) => `<tr>${l.map((c, i) => (i === 0 ? `<th scope="row">${echapper(c)}</th>` : `<td>${echapper(c)}</td>`)).join('')}</tr>`).join('');
  return `<div class="tableau"><table><caption>${echapper(t.legende)}</caption><thead><tr>${entetes}</tr></thead><tbody>${lignes}</tbody></table></div>`;
};
// Liens sortants vers les sources officielles : mêmes attributs que le composant React (`Sources`).
const sourcesHtml = (sources = []) => (sources.length
  ? `<p>${sources.length > 1 ? 'Sources' : 'Source'} : ${sources.map((x) => `<a href="${echapper(x.href)}" target="_blank" rel="noopener noreferrer">${echapper(x.label)}</a>`).join(' ; ')}.</p>`
  : '');

const liensHtml = (liens = []) => (liens.length ? `<ul>${liens.map((l) => `<li><a href="${echapper(l.href)}">${echapper(l.label)}</a></li>`).join('')}</ul>` : '');

/** Une section : titre, puis paragraphes, points, liste, tableau, liens, sources — le même ordre que `ContenuSEO`. */
export function sectionHtml(s) {
  return `<section><h2>${echapper(s.titre)}</h2>${paragraphesHtml(s.paragraphes)}${pointsHtml(s.points)}${listeHtml(s.liste, s.ordonnee)}${tableauHtml(s.tableau)}${liensHtml(s.liens)}${sourcesHtml(s.sources)}</section>`;
}

export function contenuRacine(page) {
  const sections = (page.sections ?? []).map(sectionHtml).join('');
  const faq = page.faq?.length
    ? `<section><h2>Questions fréquentes</h2>${page.faq.map((f) => `<h3>${echapper(f.q)}</h3><p>${echapper(f.r)}</p>`).join('')}</section>`
    : '';
  const liens = page.liens.map((l) => `<li><a href="${echapper(l.href)}">${echapper(l.label)}</a></li>`).join('');
  return `<main data-prerender="seo"><h1>${echapper(page.h1)}</h1>${paragraphesHtml(page.intro)}${sections}${faq}${liens ? `<nav aria-label="Pages liées"><ul>${liens}</ul></nav>` : ''}</main>`;
}

export function genererHtml(shell, page, siteUrl, jsonLd = []) {
  if (!/<div id="root"><\/div>/.test(shell)) {
    throw new Error('dist/index.html : <div id="root"></div> introuvable (shell modifié ?)');
  }
  const sansBalises = nettoyerHead(shell);
  if (!/<\/head>/i.test(sansBalises)) throw new Error('dist/index.html : </head> introuvable');
  return sansBalises
    .replace(/<\/head>/i, () => `${blocHead(page, siteUrl, jsonLd)}  </head>`)
    .replace('<div id="root"></div>', () => `<div id="root">${contenuRacine(page)}</div>`);
}

/** Entrées <url> de public/sitemap.xml qui ne sont pas des routes SEO régénérées. */
export function entreesSitemapConservees(sitemapSource, cheminsGeneres, siteUrl) {
  const gardees = [];
  for (const m of sitemapSource.matchAll(/<url>[\s\S]*?<\/url>/g)) {
    const loc = /<loc>([^<]+)<\/loc>/.exec(m[0])?.[1];
    if (!loc || !loc.startsWith(siteUrl)) continue;
    const chemin = loc.slice(siteUrl.length) || '/';
    if (cheminsGeneres.has(chemin) || chemin.startsWith('/emploi-soignant/') || chemin.startsWith('/metier/')) continue;
    gardees.push(m[0]);
  }
  return gardees;
}

export function genererSitemap({ pages: toutes, conservees, siteUrl }) {
  const pages = toutes.filter((p) => p.indexable); // une page noindex n'a rien à faire dans le sitemap
  // lastmod seulement pour les pages qui portent une date de révision éditoriale (guides, baromètre).
  const url = (p) => `  <url><loc>${echapper(siteUrl + p.path)}</loc>${p.lastmod ? `<lastmod>${p.lastmod}</lastmod>` : ''}<changefreq>${p.frequence}</changefreq><priority>${p.priorite}</priority></url>`;
  const section = (titre, liste) => liste.length ? [`  <!-- ${titre} -->`, ...liste.map(url), ''] : [];
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    '  <!-- Généré par scripts/seo/generer-pages-statiques.mjs (ne pas éditer dist/sitemap.xml) -->',
    '  <!-- Pages conservées de public/sitemap.xml -->',
    ...conservees.map((e) => `  ${e}`),
    '',
    ...section('Pages principales', pages.filter((p) => p.type === 'accueil' || p.type === 'institutionnel')),
    ...section('Pages SEO soignants / établissements', pages.filter((p) => p.type === 'devenir' || p.type === 'recruter')),
    ...section('Recruter par type d\'établissement', pages.filter((p) => p.type === 'etablissement')),
    ...section('Baromètre et guides', pages.filter((p) => p.type === 'barometre' || p.type === 'guides' || p.type === 'guide')),
    ...section('Landing pages par ville', pages.filter((p) => p.type === 'ville')),
    ...section('Landing pages par profession', pages.filter((p) => p.type === 'metier')),
    ...section('Landing pages ville × métier', pages.filter((p) => p.type === 'ville-metier')),
    '</urlset>',
    '',
  ].join('\n');
}

/**
 * llms.txt : présentation du site en Markdown pour les assistants IA (https://llmstxt.org).
 * Uniquement des textes déjà publiés : descriptions des pages et questions fréquentes de l'accueil.
 */
export function genererLlmsTxt({ pages, siteUrl }) {
  const indexables = pages.filter((p) => p.indexable);
  const accueil = indexables.find((p) => p.type === 'accueil');
  const ligne = (p) => `- [${p.h1}](${siteUrl}${p.path}) : ${p.description}`;
  const bloc = (titre, liste) => (liste.length ? [`## ${titre}`, '', ...liste.map(ligne), ''] : []);
  return [
    '# Jolene Santé',
    '',
    `> ${accueil?.description ?? ''}`,
    '',
    ...(accueil?.faq?.length ? ['## Questions fréquentes', '', ...accueil.faq.flatMap((f) => [`### ${f.q}`, '', f.r, '']) ] : []),
    ...bloc('Pages principales', indexables.filter((p) => ['institutionnel', 'devenir', 'recruter'].includes(p.type))),
    ...bloc('Recruter par type d\'établissement', indexables.filter((p) => p.type === 'etablissement')),
    ...bloc('Guides et données', indexables.filter((p) => ['guides', 'guide', 'barometre'].includes(p.type))),
    ...bloc('Missions par métier', indexables.filter((p) => p.type === 'metier')),
    ...bloc('Missions par ville', indexables.filter((p) => p.type === 'ville')),
    '## Plan du site',
    '',
    `- [sitemap.xml](${siteUrl}/sitemap.xml)`,
    '',
  ].join('\n');
}

export async function genererPagesStatiques({ racine = RACINE_DEFAUT, dist = path.join(racine, 'dist'), date = new Date().toISOString().slice(0, 10), sitemapSource: cheminSitemapSource = path.join(racine, 'public', 'sitemap.xml') } = {}) {
  const routes = await chargerRoutesSeo(racine);
  const siteUrl = routes.SITE_URL;
  const pages = routes.toutesLesRoutesSeo();

  // Shell = dist/app.html (écrit par le build Vite). La page d'accueil remplace dist/index.html :
  // partir d'app.html rend le générateur rejouable sur un dist déjà traité.
  const cheminSquelette = path.join(dist, FICHIER_SQUELETTE);
  let shell;
  try {
    shell = await readFile(cheminSquelette, 'utf8');
  } catch {
    shell = squeletteApplication(await readFile(path.join(dist, 'index.html'), 'utf8'));
    await writeFile(cheminSquelette, shell);
  }
  const canonicals = new Set();
  for (const page of pages) {
    const canonical = `${siteUrl}${page.path}`;
    if (canonicals.has(canonical)) throw new Error(`Canonical en double : ${canonical}`);
    canonicals.add(canonical);
    const dossier = path.join(dist, ...page.path.split('/').filter(Boolean));
    await mkdir(dossier, { recursive: true });
    await writeFile(path.join(dossier, 'index.html'), genererHtml(shell, page, siteUrl, routes.jsonLdPage(page)));
  }
  await writeFile(path.join(dist, 'llms.txt'), genererLlmsTxt({ pages, siteUrl }));

  let sourceSitemap = '';
  try {
    sourceSitemap = await readFile(cheminSitemapSource, 'utf8');
  } catch {
    /* pas de sitemap source : seules les routes SEO sont listées */
  }
  const conservees = entreesSitemapConservees(sourceSitemap, new Set(pages.map((p) => p.path)), siteUrl);
  const sitemap = genererSitemap({ pages, conservees, siteUrl });
  await writeFile(path.join(dist, 'sitemap.xml'), sitemap);

  return { pages: pages.length, urlSitemap: conservees.length + pages.filter((p) => p.indexable).length, conservees: conservees.length, date };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.env.VITE_NATIVE_BUILD === 'true') {
    // Le bundle Capacitor n'est pas indexé : inutile d'embarquer ~300 pages statiques dans l'app.
    // dist/index.html y reste le shell de Vite (pas de app.html : aucune réécriture Vercel en natif,
    // le plugin `pagesStatiquesJolene` ne l'écrit pas non plus pour ce build).
    console.log('[seo] build natif (VITE_NATIVE_BUILD=true) : pages statiques ignorées');
    process.exit(0);
  }
  const i = process.argv.indexOf('--dist');
  const dist = i > -1 ? path.resolve(process.argv[i + 1]) : undefined;
  genererPagesStatiques({ dist })
    .then((r) => console.log(`[seo] ${r.pages} pages statiques générées, sitemap : ${r.urlSitemap} URL (${r.conservees} conservées)`))
    .catch((e) => { console.error('[seo] échec :', e); process.exit(1); });
}
