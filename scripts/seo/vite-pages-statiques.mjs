/**
 * Shell de l'application (`dist/app.html`) et service des pages statiques par `vite preview`.
 *
 * `vercel.json` renvoie toute route sans fichier statique vers `/app.html`. Ce fichier doit
 * donc exister dans TOUT build web, y compris si le générateur de pages SEO ne tourne pas
 * (`vite build` seul, `npm run build:dev`) : sans lui, connexion, espaces et pages mission
 * répondraient 404. Il est écrit ici, par le build Vite lui-même (`closeBundle`), et non par
 * `scripts/seo/generer-pages-statiques.mjs`, qui ne fait que le relire.
 *
 * Module sans dépendance (Node seul) : importé par `vite.config.ts`, par le générateur et par les tests.
 */
import fs from 'node:fs';
import path from 'node:path';

export const FICHIER_SQUELETTE = 'app.html';

/**
 * Shell des routes sans page statique (application connectée, pages légales, /mission/:id,
 * URL inconnues) : celui de Vite, sans le canonical ni l'og:url de l'accueil. La page
 * rendue pose les siens (SEOHead, RouteMeta) ; mieux vaut aucun canonical qu'un canonical faux.
 */
export function squeletteApplication(shell) {
  if (!/<div id="root"><\/div>/.test(shell)) {
    throw new Error('dist/index.html : <div id="root"></div> introuvable (shell modifié, ou page déjà prérendue ?)');
  }
  return shell
    .replace(/[ \t]*<link\s+rel="canonical"[^>]*>\s*\n?/gi, '')
    .replace(/[ \t]*<meta\s+property="og:url"[^>]*>\s*\n?/gi, '');
}

/** Écrit dist/app.html à partir du dist/index.html que Vite vient de produire. */
export function ecrireSquelette(dist) {
  const shell = fs.readFileSync(path.join(dist, 'index.html'), 'utf8');
  fs.writeFileSync(path.join(dist, FICHIER_SQUELETTE), squeletteApplication(shell));
}

/** Même condition que le repli SPA de Vite : navigation ou requête sans type précis, en GET ou HEAD. */
export function estRequeteDePage(methode, accept) {
  if (methode !== 'GET' && methode !== 'HEAD') return false;
  return accept === undefined || accept === '' || accept.includes('text/html') || accept.includes('*/*');
}

/**
 * Ce que Vercel sert pour `url`, exprimé en chemin de fichier sous `dist` :
 *  - null si un fichier existe à ce chemin (servi tel quel) ;
 *  - `<route>/index.html` si la route a sa page statique ;
 *  - `/app.html` sinon (y compris URL mal encodée ou hors de `dist`).
 */
export function cibleStatique(dist, url) {
  let chemin = null;
  try { chemin = decodeURIComponent(String(url || '/').split('?')[0].split('#')[0]); } catch { /* URL mal encodée : shell */ }
  const cible = chemin === null || chemin.includes('\0') ? null : path.join(dist, chemin);
  const dansDist = cible !== null && (cible === dist || cible.startsWith(dist + path.sep));
  if (dansDist && fs.existsSync(cible) && fs.statSync(cible).isFile()) return null;
  if (dansDist && fs.existsSync(path.join(cible, 'index.html'))) return `${chemin.replace(/\/+$/, '')}/index.html`;
  return `/${FICHIER_SQUELETTE}`;
}

/**
 * Plugin Vite :
 *  - au build web, écrit dist/app.html (jamais pour le bundle natif, qui n'a pas de réécriture Vercel) ;
 *  - en `vite preview`, sert les pages statiques et le shell comme Vercel, pour que Lighthouse CI,
 *    les simulations Playwright et la recette locale reçoivent le même HTML qu'en production.
 */
export function pagesStatiquesJolene({ dist, natif = process.env.VITE_NATIVE_BUILD === 'true' } = {}) {
  let commande = 'serve';
  return {
    name: 'jolene-pages-statiques',
    configResolved(config) { commande = config.command; },
    closeBundle() {
      // `closeBundle` est aussi appelé à l'arrêt de `vite dev` : n'écrire qu'après un vrai build.
      if (commande !== 'build' || natif) return;
      if (fs.existsSync(path.join(dist, 'index.html'))) ecrireSquelette(dist);
    },
    configurePreviewServer(server) {
      if (!fs.existsSync(path.join(dist, FICHIER_SQUELETTE))) return; // bundle natif
      server.middlewares.use((req, _res, next) => {
        if (estRequeteDePage(req.method, req.headers?.accept)) {
          const cible = cibleStatique(dist, req.url);
          if (cible) req.url = cible;
        }
        next();
      });
    },
  };
}
