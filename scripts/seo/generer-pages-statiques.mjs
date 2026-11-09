#!/usr/bin/env node
/**
 * Prérendu léger des pages SEO (sans navigateur headless), exécuté après `vite build`.
 *
 *  - lit dist/index.html (shell SPA) ;
 *  - écrit dist/<route>/index.html pour chaque route SEO, avec <title>, meta
 *    description, canonical, og:/twitter: dans le <head> et un contenu HTML
 *    sémantique minimal (H1, intro, liens internes) dans <div id="root"> ;
 *    src/main.tsx utilise createRoot().render() : React REMPLACE ce contenu
 *    au montage (pas d'hydratation, donc aucun mismatch possible) ;
 *  - régénère dist/sitemap.xml (sans lastmod pour les routes SEO : une date de build
 *    changerait à chaque déploiement sans que le contenu change) en conservant les URL
 *    de public/sitemap.xml qui ne sont pas des routes SEO. Les pages noindex (ville ×
 *    métier sans donnée BMO) sont générées mais absentes du sitemap.
 *
 * Source de vérité : src/lib/seo-routes.ts (même module que les composants React),
 * compilé à la volée avec esbuild.
 *
 * Usage : node scripts/seo/generer-pages-statiques.mjs [--dist dist]
 */
import { build } from 'esbuild';
import { mkdtemp, readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

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

export const STYLE_PRERENDU = '<style>main[data-prerender]{max-width:48rem;margin:0 auto;padding:24px 16px;font-family:system-ui,-apple-system,sans-serif;line-height:1.5;color:#1f1a2e}main[data-prerender] h1{font-size:1.75rem;line-height:1.2;font-weight:700;margin:0 0 16px}main[data-prerender] p{margin:0 0 12px}main[data-prerender] ul{padding-left:20px}main[data-prerender] a{color:inherit;text-decoration:underline}</style>';

export function blocHead(page, siteUrl) {
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
    // Lisible avant le chargement du JS (réseau lent) ; React remplace ce bloc au montage.
    STYLE_PRERENDU,
  ].map((l) => `    ${l}`).join('\n') + '\n';
}

export function contenuRacine(page) {
  const paragraphes = page.intro.map((p) => `<p>${echapper(p)}</p>`).join('');
  const liens = page.liens.map((l) => `<li><a href="${echapper(l.href)}">${echapper(l.label)}</a></li>`).join('');
  return `<main data-prerender="seo"><h1>${echapper(page.h1)}</h1>${paragraphes}${liens ? `<nav aria-label="Pages liées"><ul>${liens}</ul></nav>` : ''}</main>`;
}

export function genererHtml(shell, page, siteUrl) {
  if (!/<div id="root"><\/div>/.test(shell)) {
    throw new Error('dist/index.html : <div id="root"></div> introuvable (shell modifié ?)');
  }
  const sansBalises = nettoyerHead(shell);
  if (!/<\/head>/i.test(sansBalises)) throw new Error('dist/index.html : </head> introuvable');
  return sansBalises
    .replace(/<\/head>/i, () => `${blocHead(page, siteUrl)}  </head>`)
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
  const url = (p) => `  <url><loc>${echapper(siteUrl + p.path)}</loc><changefreq>${p.frequence}</changefreq><priority>${p.priorite}</priority></url>`;
  const section = (titre, liste) => liste.length ? [`  <!-- ${titre} -->`, ...liste.map(url), ''] : [];
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    '  <!-- Généré par scripts/seo/generer-pages-statiques.mjs (ne pas éditer dist/sitemap.xml) -->',
    '  <!-- Pages conservées de public/sitemap.xml -->',
    ...conservees.map((e) => `  ${e}`),
    '',
    ...section('Pages SEO soignants / établissements', pages.filter((p) => p.type === 'devenir' || p.type === 'recruter')),
    ...section('Landing pages par ville', pages.filter((p) => p.type === 'ville')),
    ...section('Landing pages par profession', pages.filter((p) => p.type === 'metier')),
    ...section('Landing pages ville × métier', pages.filter((p) => p.type === 'ville-metier')),
    '</urlset>',
    '',
  ].join('\n');
}

export async function genererPagesStatiques({ racine = RACINE_DEFAUT, dist = path.join(racine, 'dist'), date = new Date().toISOString().slice(0, 10), sitemapSource: cheminSitemapSource = path.join(racine, 'public', 'sitemap.xml') } = {}) {
  const routes = await chargerRoutesSeo(racine);
  const siteUrl = routes.SITE_URL;
  const pages = routes.toutesLesRoutesSeo();

  const shell = await readFile(path.join(dist, 'index.html'), 'utf8');
  const canonicals = new Set();
  for (const page of pages) {
    const canonical = `${siteUrl}${page.path}`;
    if (canonicals.has(canonical)) throw new Error(`Canonical en double : ${canonical}`);
    canonicals.add(canonical);
    const dossier = path.join(dist, ...page.path.split('/').filter(Boolean));
    await mkdir(dossier, { recursive: true });
    await writeFile(path.join(dossier, 'index.html'), genererHtml(shell, page, siteUrl));
  }

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
    console.log('[seo] build natif (VITE_NATIVE_BUILD=true) : pages statiques ignorées');
    process.exit(0);
  }
  const i = process.argv.indexOf('--dist');
  const dist = i > -1 ? path.resolve(process.argv[i + 1]) : undefined;
  genererPagesStatiques({ dist })
    .then((r) => console.log(`[seo] ${r.pages} pages statiques générées, sitemap : ${r.urlSitemap} URL (${r.conservees} conservées)`))
    .catch((e) => { console.error('[seo] échec :', e); process.exit(1); });
}
