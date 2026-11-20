// @vitest-environment node
import { describe, expect, it, beforeAll, afterAll } from 'vitest';
import { readFileSync } from 'node:fs';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { VILLES_SEO, PROFESSIONS_SEO } from './seo-data';
import {
  toutesLesRoutesSeo,
  jsonLdPage,
  metaAccueil,
  metaDevenirSoignant,
  metaInstitutionnelle,
  titreMetier,
  CLES_INSTITUTIONNELLES,
  LONGUEUR_TITRE_MAX,
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
import { genererPagesStatiques, genererHtml, entreesSitemapConservees, scriptJsonLd, squeletteApplication } from '../../scripts/seo/generer-pages-statiques.mjs';

const RACINE_DEPOT = path.resolve(__dirname, '../..');

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

  it('génère le bon nombre de routes (accueil + institutionnelles + 2 piliers + villes + métiers + 30 villes × 6 métiers)', () => {
    const vm = pages.filter((p) => p.type === 'ville-metier');
    expect(NB_VILLES_VILLE_METIER).toBe(30);
    expect(PROFESSIONS_SEO_VILLE_METIER).toHaveLength(PROFESSIONS_VILLE_METIER.length);
    expect(vm).toHaveLength(30 * 6);
    expect(pages.filter((p) => p.type === 'ville')).toHaveLength(VILLES_SEO.length);
    expect(pages.filter((p) => p.type === 'metier')).toHaveLength(PROFESSIONS_SEO.length);
    expect(pages.filter((p) => p.type === 'accueil')).toHaveLength(1);
    expect(pages.filter((p) => p.type === 'institutionnel')).toHaveLength(CLES_INSTITUTIONNELLES.length);
    expect(pages).toHaveLength(1 + CLES_INSTITUTIONNELLES.length + 2 + VILLES_SEO.length + PROFESSIONS_SEO.length + 180);
  });

  it('garde les titres des pages métier sous la longueur que Google affiche', () => {
    for (const p of pages.filter((x) => x.type === 'metier')) {
      expect(p.title.length, p.title).toBeLessThanOrEqual(LONGUEUR_TITRE_MAX);
      expect(p.title, p.path).toMatch(/\| Jolene/);
    }
    expect(titreMetier('IDE', 'Infirmier(ère) Diplômé(e) d\'État (IDE)')).toBe('Infirmier (IDE) : missions et remplacements | Jolene Santé');
    // Métier inconnu de la table des noms courts : le libellé complet sert de repli.
    expect(titreMetier('INCONNU', 'Métier')).toBe('Métier : missions et remplacements | Jolene Santé');
  });

  it('ne promet aucun volume de missions sur les piliers', () => {
    const textes = [metaAccueil(), metaDevenirSoignant()].flatMap((p) => [p.description, p.h1, ...p.intro]).join(' ');
    expect(textes).not.toMatch(/centaines|milliers/i);
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
      const sections = (p.sections ?? []).flatMap((x) => [x.titre, ...(x.paragraphes ?? []), ...(x.liste ?? [])]);
      expect([p.title, p.description, p.h1, ...p.intro, ...sections].join(' '), p.path).not.toMatch(/intérim/i);
      // Seule mention admise : la question « Jolene est-elle une agence d'intérim ? », dont la réponse commence par « Non ».
      for (const f of p.faq ?? []) {
        if (/intérim/i.test(`${f.q} ${f.r}`)) expect(f.r, `${p.path} : ${f.q}`).toMatch(/^Non\./);
      }
    }
  });
});

describe('données structurées', () => {
  const types = (p: Parameters<typeof jsonLdPage>[0]) => jsonLdPage(p).map((b) => b['@type']);

  it('accueil : WebSite, WebApplication et FAQPage, sans fil d\'Ariane', () => {
    expect(types(metaAccueil())).toEqual(['WebSite', 'WebApplication', 'FAQPage']);
  });

  it('page ville × métier : fil d\'Ariane Accueil → pilier soignants → ville → page', () => {
    const lyon = resoudreVilleMetier('lyon', 'aide-soignant')!;
    const [fil] = jsonLdPage(metaVilleMetier(lyon.ville, lyon.profession)) as { '@type': string; itemListElement: { position: number; name: string; item: string }[] }[];
    expect(fil['@type']).toBe('BreadcrumbList');
    expect(fil.itemListElement.map((e) => e.item)).toEqual([
      'https://jolene.app/',
      'https://jolene.app/devenir-soignant',
      'https://jolene.app/emploi-soignant/lyon',
      'https://jolene.app/emploi-soignant/lyon/aide-soignant',
    ]);
    expect(fil.itemListElement.map((e) => e.position)).toEqual([1, 2, 3, 4]);
  });

  it('une FAQ déclarée reprend mot pour mot les questions de la page', () => {
    const page = metaDevenirSoignant();
    const faq = jsonLdPage(page).find((b) => b['@type'] === 'FAQPage') as { mainEntity: { name: string; acceptedAnswer: { text: string } }[] };
    expect(faq.mainEntity.map((q) => q.name)).toEqual(page.faq!.map((f) => f.q));
    expect(faq.mainEntity.map((q) => q.acceptedAnswer.text)).toEqual(page.faq!.map((f) => f.r));
  });

  it('une page sans FAQ ne déclare pas de FAQPage', () => {
    expect(types(metaInstitutionnelle('telecharger'))).toEqual(['BreadcrumbList']);
  });

  it('le script JSON-LD ne peut pas fermer sa balise', () => {
    const script = scriptJsonLd([{ '@type': 'FAQPage', texte: '</script><b>x</b>' }])!;
    expect(script.match(/<\/script>/g)).toHaveLength(1);
    expect(script).toContain('\\u003c/script>');
    expect(scriptJsonLd([])).toBeNull();
  });

  it('chaque composant d\'une page à HTML statique lit ses données structurées dans seo-routes', () => {
    // Sans cela, le script du HTML statique serait retiré au montage (SEOHead sans jsonLd).
    const composants = ['PageAccueil', 'Tarifs', 'APropos', 'InfirmiereLiberal', 'Telecharger', 'PageContact', 'DevenirSoignant', 'RecruterSoignants', 'VilleLanding', 'ProfessionLanding', 'VilleProfessionLanding'];
    for (const c of composants) {
      expect(readFileSync(path.join(RACINE_DEPOT, 'src/pages', `${c}.tsx`), 'utf8'), c).toContain('jsonLd={jsonLdPage(meta)}');
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
    resultat = await genererPagesStatiques({ racine: RACINE_DEPOT, dist, date: '2026-11-09', sitemapSource });
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

  it('écrit le shell des routes de l\'application sans canonical ni og:url', async () => {
    const html = await readFile(path.join(dist, 'app.html'), 'utf8');
    expect(html).not.toMatch(/rel="canonical"/);
    expect(html).not.toMatch(/property="og:url"/);
    expect(html).toContain('<div id="root"></div>');
    expect(html).toContain('/assets/index-abc.js');
    expect(html).toContain('<title>Jolene Santé — Missions soignants & remplacements vérifiés</title>');
    expect(() => squeletteApplication('<html><head></head><body></body></html>')).toThrow(/root/);
  });

  it('vercel.json sert ce shell, et non l\'accueil, aux routes sans fichier statique', () => {
    const vercel = JSON.parse(readFileSync(path.join(RACINE_DEPOT, 'vercel.json'), 'utf8')) as { rewrites: { source: string; destination: string }[] };
    expect(vercel.rewrites).toHaveLength(1);
    expect(vercel.rewrites[0].destination).toBe('/app.html');
  });

  it('remplace dist/index.html par l\'accueil : H1, canonical, FAQ et données structurées', async () => {
    const html = await readFile(path.join(dist, 'index.html'), 'utf8');
    const accueil = metaAccueil();
    expect(html).toContain(`<h1>${accueil.h1}</h1>`);
    expect(html.match(/rel="canonical"/g)).toHaveLength(1);
    expect(html).toContain('<link rel="canonical" href="https://jolene.app/" />');
    expect(html).toContain('<meta name="robots" content="index, follow" />');
    expect(html).toContain('<h2>Questions fréquentes</h2>');
    expect(html).toContain('<h3>Comment fonctionne la commission ?</h3>');
    expect(html).toContain('<h2>Pour les établissements</h2>');
    expect(html.match(/data-jolene-ld="true"/g)).toHaveLength(1);
    const ld = JSON.parse(/<script type="application\/ld\+json" data-jolene-ld="true">([\s\S]*?)<\/script>/.exec(html)![1]);
    expect(ld).toEqual(JSON.parse(JSON.stringify(jsonLdPage(accueil))));
    expect(html).toContain('href="/recruter-soignants"');
    expect(html).toContain('/assets/index-abc.js');
  });

  it('écrit les pages institutionnelles avec leur propre canonical', async () => {
    for (const cle of CLES_INSTITUTIONNELLES) {
      const meta = metaInstitutionnelle(cle);
      const html = await readFile(path.join(dist, ...meta.path.split('/').filter(Boolean), 'index.html'), 'utf8');
      expect(html, cle).toContain(`<link rel="canonical" href="https://jolene.app${meta.path}" />`);
      expect(html, cle).toContain('<h1>');
      expect(html.match(/<title>/g), cle).toHaveLength(1);
    }
    const tarifs = await readFile(path.join(dist, 'tarifs', 'index.html'), 'utf8');
    expect(tarifs).toContain('<h1>Nos tarifs — Transparence totale</h1>');
    expect(tarifs).toContain('<li>Aucun abonnement, aucun frais caché</li>');
  });

  it('écrit les questions fréquentes de /recruter-soignants dans le HTML statique', async () => {
    const html = await readFile(path.join(dist, 'recruter-soignants', 'index.html'), 'utf8');
    expect(html).toContain('<h3>Combien coûte le service ?</h3>');
    expect(html).toContain('"@type":"FAQPage"');
  });

  it('écrit llms.txt avec les seules pages indexables', async () => {
    const txt = await readFile(path.join(dist, 'llms.txt'), 'utf8');
    expect(txt.startsWith('# Jolene Santé\n')).toBe(true);
    expect(txt).toContain(`> ${metaAccueil().description}`);
    expect(txt).toContain('](https://jolene.app/tarifs)');
    expect(txt).toContain('](https://jolene.app/emploi-soignant/paris)');
    expect(txt).not.toContain('/emploi-soignant/lyon/infirmier-ide');
    expect(txt).toContain('https://jolene.app/sitemap.xml');
  });

  it('génère aussi les pages ville, métier et /devenir-soignant', async () => {
    for (const p of ['emploi-soignant/paris', 'metier/medecin', 'devenir-soignant', 'recruter-soignants']) {
      const html = await readFile(path.join(dist, ...p.split('/'), 'index.html'), 'utf8');
      expect(html).toContain('<h1>');
    }
  });

  it('régénère le sitemap sans lastmod figé au build et conserve les URL non SEO', async () => {
    const xml = await readFile(path.join(dist, 'sitemap.xml'), 'utf8');
    // L'accueil est désormais une route générée : plus de lastmod figé, une seule entrée.
    expect(xml).toContain('<loc>https://jolene.app/</loc><changefreq>weekly</changefreq><priority>1.0</priority>');
    expect(xml.match(/<loc>https:\/\/jolene\.app\/<\/loc>/g)).toHaveLength(1);
    expect(xml).toContain('<loc>https://jolene.app/tarifs</loc><changefreq>');
    expect(xml).toContain('<loc>https://jolene.app/cgu</loc><lastmod>2026-06-15</lastmod>');
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
