// @vitest-environment node
import { describe, expect, it, beforeAll, afterAll } from 'vitest';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { VILLES_SEO, PROFESSIONS_SEO } from './seo-data';
import {
  toutesLesRoutesSeo,
  metaVilleMetier,
  phraseBmo,
  resoudreVilleMetier,
  villesVoisines,
  regionDeDepartement,
  NB_VILLES_VILLE_METIER,
  PROFESSIONS_VILLE_METIER,
  PROFESSIONS_SEO_VILLE_METIER,
  VILLES_VILLE_METIER,
  type TableBmo,
} from './seo-routes';
import { genererPagesStatiques, genererHtml, entreesSitemapConservees } from '../../scripts/seo/generer-pages-statiques.mjs';

const SHELL = `<!doctype html>
<html lang="fr">
  <head>
    <meta charset="UTF-8" />
    <title>Jolene Santé — Missions soignants & remplacements vérifiés</title>
    <meta name="description" content="ancienne description" />
    <link rel="canonical" href="https://jolene.app/" />
    <meta property="og:title" content="ancien titre" />
    <meta property="og:description" content="ancienne description og" />
    <meta property="og:image" content="https://jolene.app/og-default.png" />
    <meta property="og:url" content="https://jolene.app" />
    <meta name="twitter:title" content="ancien titre" />
    <meta name="twitter:description" content="ancienne description tw" />
    <script type="module" src="/assets/index-abc.js"></script>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>`;

const SITEMAP_SOURCE = `<?xml version="1.0" encoding="UTF-8"?>
<urlset>
  <url><loc>https://jolene.app/</loc><lastmod>2026-06-15</lastmod></url>
  <url><loc>https://jolene.app/devenir-soignant</loc><lastmod>2026-06-15</lastmod></url>
  <url><loc>https://jolene.app/emploi-soignant/paris</loc><lastmod>2026-06-15</lastmod></url>
  <url><loc>https://jolene.app/metier/medecin</loc><lastmod>2026-06-15</lastmod></url>
  <url><loc>https://jolene.app/cgu</loc><lastmod>2026-06-15</lastmod></url>
</urlset>`;

describe('routes SEO', () => {
  const pages = toutesLesRoutesSeo();

  it('génère le bon nombre de routes (2 + villes + métiers + 30 villes × 6 métiers)', () => {
    const vm = pages.filter((p) => p.type === 'ville-metier');
    expect(NB_VILLES_VILLE_METIER).toBe(30);
    expect(PROFESSIONS_SEO_VILLE_METIER).toHaveLength(PROFESSIONS_VILLE_METIER.length);
    expect(vm).toHaveLength(30 * 6);
    expect(pages.filter((p) => p.type === 'ville')).toHaveLength(VILLES_SEO.length);
    expect(pages.filter((p) => p.type === 'metier')).toHaveLength(PROFESSIONS_SEO.length);
    expect(pages).toHaveLength(2 + VILLES_SEO.length + PROFESSIONS_SEO.length + 180);
  });

  it('a des chemins uniques, des titres uniques et des H1 uniques', () => {
    expect(new Set(pages.map((p) => p.path)).size).toBe(pages.length);
    expect(new Set(pages.map((p) => p.title)).size).toBe(pages.length);
    expect(new Set(pages.map((p) => p.h1)).size).toBe(pages.length);
  });

  it('couvre chaque département des villes dans la table des régions', () => {
    for (const v of VILLES_SEO) expect(regionDeDepartement(v.departement), v.nom).toBeTruthy();
  });

  it('propose jusqu’à 5 villes voisines du même département ou de la même région (au moins 1)', () => {
    for (const v of VILLES_VILLE_METIER) {
      const voisines = villesVoisines(v, 5);
      expect(voisines.length, v.nom).toBeGreaterThanOrEqual(1);
      expect(voisines.length).toBeLessThanOrEqual(5);
      for (const n of voisines) expect(regionDeDepartement(n.departement)).toBe(regionDeDepartement(v.departement));
    }
    const lyon = VILLES_SEO.find((v) => v.slug === 'lyon')!;
    expect(villesVoisines(lyon)[0].departement).toBe('69');
  });

  it('lie chaque page ville × métier à sa ville, à son métier et à des voisines', () => {
    const lyon = resoudreVilleMetier('lyon', 'infirmier-ide')!;
    const meta = metaVilleMetier(lyon.ville, lyon.profession);
    const hrefs = meta.liens.map((l) => l.href);
    expect(hrefs).toContain('/emploi-soignant/lyon');
    expect(hrefs).toContain('/metier/infirmier-ide');
    expect(hrefs.filter((h) => h !== '/emploi-soignant/lyon' && h !== '/metier/infirmier-ide').length).toBeGreaterThanOrEqual(3);
    expect(meta.h1).toBe('Infirmier (IDE) : missions à Lyon');
  });

  it('sigles professionnels jamais mis en minuscules (titres, H1, intros, liens)', () => {
    const fautifs: string[] = [];
    for (const p of toutesLesRoutesSeo()) {
      for (const t of [p.title, p.description, p.h1, ...p.intro, ...p.liens.map((l) => l.label)]) {
        if (/\((ide|aes|as|ibode|iade|rpps)\)/.test(t)) fautifs.push(`${p.path} : ${t.slice(0, 80)}`);
      }
    }
    expect(fautifs).toEqual([]);
    const lyon = toutesLesRoutesSeo().find((p) => p.path === '/emploi-soignant/lyon/infirmier-ide')!;
    expect(lyon.intro[0]).toMatch(/^Vous êtes infirmier \(IDE\) et cherchez une mission à Lyon/);
  });

  it('slug inconnu ou hors périmètre : aucune page ville × métier résolue', () => {
    expect(resoudreVilleMetier('inconnue', 'infirmier-ide')).toBeNull();
    expect(resoudreVilleMetier('paris', 'pharmacien')).toBeNull();
    expect(resoudreVilleMetier('bourges', 'infirmier-ide')).toBeNull(); // ville hors top 30
    expect(resoudreVilleMetier('paris', 'infirmier-ide')).not.toBeNull();
  });
});

describe('données BMO 2026', () => {
  const table: TableBmo = {
    '75': { AS: [1104, 28.08], MEDECIN: [425, 67.53] },
    '18': { AS: [283, 47.17], MEDECIN: [12, null] },
    '99': { AS: [0, 50], MEDECIN: [5, 10] },
  };

  it('affiche la phrase avec la source quand la donnée existe', () => {
    const phrase = phraseBmo('75', 'AS', table)!;
    expect(phrase).toContain('1 104 projets');
    expect(phrase).toContain('d’aides-soignants');
    expect(phrase).toContain('28 %');
    expect(phrase).toContain('Enquête BMO 2026, France Travail');
  });

  it('n’affiche rien quand le pourcentage est null', () => {
    expect(phraseBmo('18', 'MEDECIN', table)).toBeNull();
    expect(phraseBmo('18', 'AS', table)).not.toBeNull();
  });

  it('n’affiche rien quand les projets valent 0, quand le département est absent ou pour un autre métier', () => {
    expect(phraseBmo('99', 'AS', table)).toBeNull();
    expect(phraseBmo('00', 'AS', table)).toBeNull();
    expect(phraseBmo('75', 'IDE', table)).toBeNull();
    expect(phraseBmo('75', 'KINE', table)).toBeNull();
  });

  it('n’injecte du BMO que sur les pages AS et MEDECIN, avec la donnée réelle', () => {
    for (const p of toutesLesRoutesSeo().filter((x) => x.type === 'ville-metier')) {
      const texte = p.intro.join(' ');
      if (p.path.endsWith('/infirmier-ide') || p.path.endsWith('/kinesitherapeute') || p.path.endsWith('/sage-femme') || p.path.endsWith('/accompagnant-educatif-social')) {
        expect(texte, p.path).not.toContain('BMO');
      }
    }
    const paris = resoudreVilleMetier('paris', 'aide-soignant')!;
    expect(metaVilleMetier(paris.ville, paris.profession).intro.join(' ')).toContain('Enquête BMO 2026, France Travail');
  });
});

describe('indexation des pages ville × métier', () => {
  const villeMetier = toutesLesRoutesSeo().filter((p) => p.type === 'ville-metier');

  it('indexe une page si et seulement si elle porte une donnée BMO départementale', () => {
    for (const p of villeMetier) {
      const bmo = p.intro.some((t) => t.includes('Enquête BMO 2026'));
      expect({ path: p.path, indexable: p.indexable }).toEqual({ path: p.path, indexable: bmo });
    }
  });

  it('n\'indexe que des pages aide-soignant ou médecin', () => {
    const indexees = villeMetier.filter((p) => p.indexable);
    expect(indexees.length).toBeGreaterThan(0);
    for (const p of indexees) expect(p.path).toMatch(/\/(aide-soignant|medecin)$/);
  });

  it('aucun texte SEO ne présente Jolene ou un métier sous l\'angle de l\'intérim', () => {
    for (const p of toutesLesRoutesSeo()) {
      expect([p.title, p.description, p.h1, ...p.intro].join(' ')).not.toMatch(/intérim/i);
    }
  });
});

describe('HTML statique et sitemap', () => {
  let racine: string;
  let dist: string;
  let resultat: { pages: number; urlSitemap: number; conservees: number };

  beforeAll(async () => {
    racine = await mkdtemp(path.join(tmpdir(), 'jolene-seo-test-'));
    dist = path.join(racine, 'dist');
    await mkdir(dist, { recursive: true });
    await writeFile(path.join(dist, 'index.html'), SHELL);
    const sitemapSource = path.join(racine, 'sitemap-source.xml');
    await writeFile(sitemapSource, SITEMAP_SOURCE);
    resultat = await genererPagesStatiques({ racine: path.resolve(__dirname, '../..'), dist, date: '2026-11-09', sitemapSource });
  }, 60_000);

  afterAll(async () => { await rm(racine, { recursive: true, force: true }); });

  it('écrit une page par route', () => {
    expect(resultat.pages).toBe(toutesLesRoutesSeo().length);
  });

  it('écrit dans une page ville × métier le title, le H1, le canonical et les liens', async () => {
    const html = await readFile(path.join(dist, 'emploi-soignant', 'lyon', 'infirmier-ide', 'index.html'), 'utf8');
    expect(html).toContain('<title>Infirmier (IDE) à Lyon : missions et remplacements | Jolene Santé</title>');
    expect(html).toContain('<h1>Infirmier (IDE) : missions à Lyon</h1>');
    expect(html).toContain('<link rel="canonical" href="https://jolene.app/emploi-soignant/lyon/infirmier-ide" />');
    expect(html).toContain('<meta property="og:url" content="https://jolene.app/emploi-soignant/lyon/infirmier-ide" />');
    expect(html).toContain('href="/emploi-soignant/lyon"');
    expect(html).toContain('href="/metier/infirmier-ide"');
    // IDE : aucune donnée BMO départementale → page en ligne mais non indexée.
    expect(html).toContain('<meta name="robots" content="noindex, nofollow" />');
    expect(html).toContain('/assets/index-abc.js');
  });

  it('ne duplique aucune balise du head et unifie les canonicals', async () => {
    const html = await readFile(path.join(dist, 'emploi-soignant', 'paris', 'aide-soignant', 'index.html'), 'utf8');
    expect(html.match(/<title>/g)).toHaveLength(1);
    expect(html.match(/rel="canonical"/g)).toHaveLength(1);
    expect(html.match(/name="description"/g)).toHaveLength(1);
    expect(html.match(/property="og:title"/g)).toHaveLength(1);
    expect(html).not.toContain('ancienne description');
    expect(html).toContain('Enquête BMO 2026, France Travail');
    expect(html).toContain('<meta name="robots" content="index, follow" />');
    const canonicals = toutesLesRoutesSeo().map((p) => `https://jolene.app${p.path}`);
    expect(new Set(canonicals).size).toBe(canonicals.length);
  });

  it('génère aussi les pages ville, métier et /devenir-soignant', async () => {
    for (const p of ['emploi-soignant/paris', 'metier/medecin', 'devenir-soignant', 'recruter-soignants']) {
      const html = await readFile(path.join(dist, ...p.split('/'), 'index.html'), 'utf8');
      expect(html).toContain('<h1>');
    }
  });

  it('régénère le sitemap sans lastmod figé au build et conserve les URL non SEO', async () => {
    const xml = await readFile(path.join(dist, 'sitemap.xml'), 'utf8');
    expect(xml).toContain('<loc>https://jolene.app/</loc><lastmod>2026-06-15</lastmod>');
    expect(xml).toContain('<loc>https://jolene.app/cgu</loc>');
    expect(xml).toContain('<loc>https://jolene.app/emploi-soignant/paris/aide-soignant</loc><changefreq>');
    expect(xml).not.toContain('/emploi-soignant/lyon/infirmier-ide<');
    const villeMetier = toutesLesRoutesSeo().filter((p) => p.type === 'ville-metier');
    for (const p of villeMetier) expect(xml.includes(`<loc>https://jolene.app${p.path}</loc>`)).toBe(p.indexable);
    expect(xml).toContain('<loc>https://jolene.app/devenir-soignant</loc><changefreq>');
    expect(xml).not.toContain('2026-11-09');
    expect(xml.match(/<loc>/g)).toHaveLength(resultat.urlSitemap);
    expect(xml.match(/devenir-soignant/g)).toHaveLength(1);
    expect(xml.match(/\/emploi-soignant\/paris<\/loc>/g)).toHaveLength(1);
  });

  it('rejette un shell sans <div id="root">', () => {
    expect(() => genererHtml('<html><head></head><body></body></html>', toutesLesRoutesSeo()[0], 'https://jolene.app')).toThrow(/root/);
  });

  it('entreesSitemapConservees ignore les routes générées', () => {
    const gardees = entreesSitemapConservees(SITEMAP_SOURCE, new Set(['/devenir-soignant']), 'https://jolene.app');
    expect(gardees).toHaveLength(2);
  });
});
