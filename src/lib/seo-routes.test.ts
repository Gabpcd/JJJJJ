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
  cheminGuide,
  CHEMIN_GUIDES,
  NB_VILLES_VILLE_METIER,
  PROFESSIONS_VILLE_METIER,
  PROFESSIONS_SEO_VILLE_METIER,
  VILLES_VILLE_METIER,
  type TableBmo,
} from './seo-routes';
import { TYPES_ETABLISSEMENT_SEO } from './seo-contenu/etablissements';
import { GUIDES_CITANT_INTERIM, GUIDES_SEO, RAPPEL_PAS_INTERIM } from './seo-contenu/guides';
import { genererPagesStatiques, genererHtml, entreesSitemapConservees, scriptJsonLd, squeletteApplication } from '../../scripts/seo/generer-pages-statiques.mjs';
import { cibleStatique, ecrireSquelette, estRequeteDePage, pagesStatiquesJolene } from '../../scripts/seo/vite-pages-statiques.mjs';
import { TITRE_ACCUEIL } from './seo-contenu/accueil';

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

  it('génère le bon nombre de routes (accueil, institutionnelles, piliers, villes, métiers, ville × métier, types d\'établissement, baromètre, guides)', () => {
    const vm = pages.filter((p) => p.type === 'ville-metier');
    expect(NB_VILLES_VILLE_METIER).toBe(30);
    expect(PROFESSIONS_SEO_VILLE_METIER).toHaveLength(PROFESSIONS_VILLE_METIER.length);
    expect(vm).toHaveLength(30 * 6);
    expect(pages.filter((p) => p.type === 'ville')).toHaveLength(VILLES_SEO.length);
    expect(pages.filter((p) => p.type === 'metier')).toHaveLength(PROFESSIONS_SEO.length);
    expect(pages.filter((p) => p.type === 'accueil')).toHaveLength(1);
    expect(pages.filter((p) => p.type === 'institutionnel')).toHaveLength(CLES_INSTITUTIONNELLES.length);
    expect(pages.filter((p) => p.type === 'etablissement')).toHaveLength(TYPES_ETABLISSEMENT_SEO.length);
    expect(pages.filter((p) => p.type === 'guide')).toHaveLength(GUIDES_SEO.length);
    expect(pages.filter((p) => p.type === 'barometre' || p.type === 'guides')).toHaveLength(2);
    expect(pages).toHaveLength(1 + CLES_INSTITUTIONNELLES.length + 2 + VILLES_SEO.length + PROFESSIONS_SEO.length + 180
      + TYPES_ETABLISSEMENT_SEO.length + 2 + GUIDES_SEO.length);
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

  it('n’injecte du BMO que sur les pages aide-soignant, médecin et infirmier, avec la donnée réelle', () => {
    for (const p of toutesLesRoutesSeo().filter((x) => x.type === 'ville-metier')) {
      const texte = p.intro.join(' ');
      // Kinésithérapeute et AES : agrégats trop larges. Sage-femme : l'agrégat « Infirmiers et sages-femmes » serait trompeur.
      if (p.path.endsWith('/kinesitherapeute') || p.path.endsWith('/sage-femme') || p.path.endsWith('/accompagnant-educatif-social')) {
        expect(texte, p.path).not.toContain('BMO');
      }
    }
    const paris = resoudreVilleMetier('paris', 'aide-soignant')!;
    expect(metaVilleMetier(paris.ville, paris.profession).intro.join(' ')).toContain('Enquête BMO 2026, France Travail');
  });

  it('page infirmier : l\'agrégat de l\'enquête est nommé tel qu\'il est publié', () => {
    const paris = resoudreVilleMetier('paris', 'infirmier-ide')!;
    const texte = metaVilleMetier(paris.ville, paris.profession).intro.join(' ');
    expect(texte).toMatch(/1\s680 projets de recrutement d’infirmiers et de sages-femmes en 2026, dont 38 % jugés difficiles \(Enquête BMO 2026, France Travail\)/);
    expect(phraseBmo('75', 'SAGE_FEMME')).toBeNull();
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

  it('n\'indexe que des pages aide-soignant, médecin ou infirmier', () => {
    const indexees = villeMetier.filter((p) => p.indexable);
    expect(indexees.length).toBeGreaterThan(60);
    for (const p of indexees) expect(p.path).toMatch(/\/(aide-soignant|medecin|infirmier-ide)$/);
  });

  it('les comptes FINESS seuls ne rendent pas une page indexable', () => {
    const lyon = resoudreVilleMetier('lyon', 'kinesitherapeute')!;
    const meta = metaVilleMetier(lyon.ville, lyon.profession);
    expect(meta.intro.join(' ')).toContain('le répertoire FINESS recense');
    expect(meta.indexable).toBe(false);
  });

  it('aucun texte SEO ne présente Jolene ou un métier sous l\'angle de l\'intérim', () => {
    // Seuls les guides qui comparent les solutions de remplacement citent l'intérim, et chacun
    // rappelle que Jolene n'en est pas une agence. La page /guides reprend leurs descriptions.
    const admis = new Set([CHEMIN_GUIDES, ...GUIDES_CITANT_INTERIM.map(cheminGuide)]);
    for (const slug of GUIDES_CITANT_INTERIM) {
      expect(textesDePage(toutesLesRoutesSeo().find((x) => x.path === cheminGuide(slug))!).join(' '), slug).toContain(RAPPEL_PAS_INTERIM);
    }
    for (const p of toutesLesRoutesSeo()) {
      if (admis.has(p.path)) continue;
      const sections = textesDePage(p).slice(4 + p.intro.length);
      expect([p.title, p.description, p.h1, ...p.intro, ...sections].join(' '), p.path).not.toMatch(/intérim/i);
      // Seule mention admise : la question « Jolene est-elle une agence d'intérim ? », dont la réponse commence par « Non ».
      for (const f of p.faq ?? []) {
        if (/intérim/i.test(`${f.q} ${f.r}`)) expect(f.r, `${p.path} : ${f.q}`).toMatch(/^Non\./);
      }
    }
  });
});

/** Tous les textes d'une page : title, description, H1, introduction, puis sections (titres, paragraphes, points, listes, tableaux). FAQ exclue. */
function textesDePage(p: ReturnType<typeof toutesLesRoutesSeo>[number]): string[] {
  const sections = (p.sections ?? []).flatMap((x) => [
    x.titre, ...(x.paragraphes ?? []), ...(x.liste ?? []),
    ...(x.points ?? []).flatMap((pt) => [pt.titre, pt.texte]),
    ...(x.tableau ? [x.tableau.legende, ...x.tableau.entetes, ...x.tableau.lignes.flat()] : []),
  ]);
  return [p.title, p.description, p.h1, '', ...p.intro, ...sections];
}

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
    const composants = ['PageAccueil', 'Tarifs', 'APropos', 'InfirmiereLiberal', 'Telecharger', 'PageContact', 'DevenirSoignant', 'RecruterSoignants', 'VilleLanding', 'ProfessionLanding', 'VilleProfessionLanding', 'RecruterTypeLanding', 'GuidesIndex', 'GuideArticle', 'BarometreRecrutement'];
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
    // Infirmier : donnée BMO départementale (agrégat « Infirmiers et sages-femmes ») → page indexée.
    expect(html).toContain('<meta name="robots" content="index, follow" />');
    expect(html).toContain('/assets/index-abc.js');
    // Kinésithérapeute : aucune donnée BMO propre → en ligne, non indexée.
    const kine = await readFile(path.join(dist, 'emploi-soignant', 'lyon', 'kinesitherapeute', 'index.html'), 'utf8');
    expect(kine).toContain('<meta name="robots" content="noindex, nofollow" />');
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
    const vercel = JSON.parse(readFileSync(path.join(RACINE_DEPOT, 'vercel.json'), 'utf8')) as { rewrites: { source: string; destination: string }[]; buildCommand?: string };
    expect(vercel.rewrites).toHaveLength(1);
    expect(vercel.rewrites[0].destination).toBe('/app.html');
    // Aucune commande de build propre à Vercel : c'est le script `build` du dépôt qui tourne.
    expect(vercel.buildCommand).toBeUndefined();
  });

  it('le shell est écrit par le build Vite lui-même, pas seulement par le générateur', () => {
    // Si app.html manquait, toutes les routes de l'application répondraient 404 sur Vercel.
    expect(readFileSync(path.join(RACINE_DEPOT, 'vite.config.ts'), 'utf8')).toMatch(/pagesStatiquesJolene\(\{ dist: path\.resolve\(__dirname, 'dist'\) \}\)/);
    const scripts = JSON.parse(readFileSync(path.join(RACINE_DEPOT, 'package.json'), 'utf8')).scripts as Record<string, string>;
    expect(scripts.build).toBe('vite build && node scripts/seo/generer-pages-statiques.mjs');
  });

  it('est rejouable : un second passage repart du shell, pas de l\'accueil déjà prérendu', async () => {
    const avant = await readFile(path.join(dist, 'tarifs', 'index.html'), 'utf8');
    const second = await genererPagesStatiques({ racine: RACINE_DEPOT, dist, date: '2026-11-09', sitemapSource: path.join(racine, 'sitemap-source.xml') });
    expect(second.pages).toBe(resultat.pages);
    const apres = await readFile(path.join(dist, 'tarifs', 'index.html'), 'utf8');
    expect(apres).toBe(avant);
    expect(apres.match(/data-prerender="seo"/g)).toHaveLength(1);
    expect(apres.match(/<h1>/g)).toHaveLength(1);
    expect(await readFile(path.join(dist, 'app.html'), 'utf8')).toContain('<div id="root"></div>');
  });

  it('/tarifs : le prix figure dans le corps statique, sous l\'intitulé affiché par la page', async () => {
    const html = await readFile(path.join(dist, 'tarifs', 'index.html'), 'utf8');
    expect(html).toContain('<h2>Commission Jolene</h2><p>15 % HT</p><p>soit 18 % TTC avec TVA à 20 %</p><ul>');
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
    expect(txt).not.toContain('/emploi-soignant/lyon/');
    expect(txt).toContain('](https://jolene.app/recruter-soignants/ehpad)');
    expect(txt).toContain('](https://jolene.app/guides/vacations-etablissement-de-sante)');
    expect(txt).toContain('https://jolene.app/sitemap.xml');
  });

  it('écrit une page par type d\'établissement : points titrés, liste numérotée, FAQ', async () => {
    const html = await readFile(path.join(dist, 'recruter-soignants', 'ehpad', 'index.html'), 'utf8');
    expect(html).toContain('<h1>Remplacer un soignant en EHPAD</h1>');
    expect(html).toContain('<link rel="canonical" href="https://jolene.app/recruter-soignants/ehpad" />');
    expect(html).toContain('<h3>L’absence imprévue</h3>');
    expect(html).toMatch(/<h2>Publier une mission en trois étapes<\/h2><ol><li>/);
    expect(html).toContain('<h3><a href="/metier/aide-soignant">Aide-soignant</a></h3>');
    expect(html).toContain('<h3>Combien coûte le service ?</h3>');
    expect(html).toContain('"@type":"FAQPage"');
  });

  it('écrit les guides : sources officielles en liens sortants, tableau comparatif, date de révision', async () => {
    const guide = await readFile(path.join(dist, 'guides', 'comparer-solutions-remplacement-soignants', 'index.html'), 'utf8');
    expect(guide).toContain('<p>Source : <a href="https://www.service-public.gouv.fr/particuliers/vosdroits/F11215" target="_blank" rel="noopener noreferrer">');
    expect(guide).toContain('<caption>Comparaison des trois solutions de remplacement d’un soignant</caption>');
    expect(guide).toContain('<th scope="row">Qui choisit le soignant</th><td>Vous</td>');
    expect(guide).toContain('<p>Guide mis à jour le 20 novembre 2026.</p>');
    expect(guide).toContain('"@type":"Article"');
    const sommaire = await readFile(path.join(dist, 'guides', 'index.html'), 'utf8');
    expect(sommaire).toContain('<h3><a href="/guides/cout-remplacement-soignant">');
  });

  it('écrit le baromètre : une ligne par département, deux sources', async () => {
    const html = await readFile(path.join(dist, 'barometre-recrutement-soignants-2026', 'index.html'), 'utf8');
    expect(html.match(/<tr><th scope="row">/g)).toHaveLength(101);
    expect(html).toContain('<th scope="row">Paris (75)</th>');
    expect(html).toContain('"@type":"Dataset"');
    expect(html).toMatch(/<p>Sources : <a href="https:\/\/www\.data\.gouv\.fr\/datasets\/enquete-besoins-en-main-doeuvre-bmo"[^>]*>[^<]+<\/a> ; <a href="https:\/\/www\.data\.gouv\.fr\/datasets\/finess-extraction-du-fichier-des-etablissements"/);
  });

  it('écrit les comptes FINESS de la ville dans la page ville', async () => {
    const html = await readFile(path.join(dist, 'emploi-soignant', 'lyon', 'index.html'), 'utf8');
    expect(html).toMatch(/<p>À Lyon, le répertoire FINESS recense 44 EHPAD, [^<]+\(extraction du 4 mai 2026\)\.<\/p>/);
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
    expect(xml).toContain('/emploi-soignant/lyon/infirmier-ide<');
    expect(xml).not.toContain('/emploi-soignant/lyon/kinesitherapeute<');
    // Guides et baromètre : lastmod = date de révision éditoriale, pas la date du build.
    expect(xml).toContain('<loc>https://jolene.app/guides/cout-remplacement-soignant</loc><lastmod>2026-11-20</lastmod>');
    expect(xml).toContain('<loc>https://jolene.app/recruter-soignants/ehpad</loc><changefreq>');
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

describe('plugin Vite des pages statiques (scripts/seo/vite-pages-statiques.mjs)', () => {
  let dist: string;
  beforeAll(async () => {
    dist = await mkdtemp(path.join(tmpdir(), 'jolene-vite-seo-'));
    await writeFile(path.join(dist, 'index.html'), SHELL);
    await mkdir(path.join(dist, 'tarifs'), { recursive: true });
    await writeFile(path.join(dist, 'tarifs', 'index.html'), '<html></html>');
    await mkdir(path.join(dist, 'assets'), { recursive: true });
    await writeFile(path.join(dist, 'assets', 'index-abc.js'), '');
    await mkdir(path.join(dist, 'metier'), { recursive: true }); // dossier sans index.html
  });
  afterAll(async () => { await rm(dist, { recursive: true, force: true }); });

  const plugin = (options: { natif?: boolean } = {}) => pagesStatiquesJolene({ dist, ...options }) as unknown as {
    configResolved: (c: { command: string }) => void; closeBundle: () => void;
    configurePreviewServer: (s: { middlewares: { use: (f: (req: { method: string; url: string; headers: Record<string, string> }, res: unknown, next: () => void) => void) => void } }) => void;
  };

  it('n\'écrit app.html qu\'après un build web', async () => {
    const lire = () => readFile(path.join(dist, 'app.html'), 'utf8');
    const dev = plugin(); dev.configResolved({ command: 'serve' }); dev.closeBundle();
    await expect(lire()).rejects.toThrow();
    const natif = plugin({ natif: true }); natif.configResolved({ command: 'build' }); natif.closeBundle();
    await expect(lire()).rejects.toThrow();
    const web = plugin(); web.configResolved({ command: 'build' }); web.closeBundle();
    expect(await lire()).toBe(squeletteApplication(SHELL));
    expect(await lire()).not.toMatch(/rel="canonical"/);
  });

  it('refuse d\'écrire le shell à partir d\'une page déjà prérendue', async () => {
    const autre = await mkdtemp(path.join(tmpdir(), 'jolene-vite-seo-'));
    await writeFile(path.join(autre, 'index.html'), SHELL.replace('<div id="root"></div>', '<div id="root"><main>accueil</main></div>'));
    expect(() => ecrireSquelette(autre)).toThrow(/root/);
    await rm(autre, { recursive: true, force: true });
  });

  it('sert, comme Vercel, le fichier, la page statique de la route ou le shell', () => {
    expect(cibleStatique(dist, '/assets/index-abc.js')).toBeNull();
    expect(cibleStatique(dist, '/')).toBe('/index.html');
    expect(cibleStatique(dist, '/tarifs')).toBe('/tarifs/index.html');
    expect(cibleStatique(dist, '/tarifs/?utm_source=x')).toBe('/tarifs/index.html');
    expect(cibleStatique(dist, '/connexion')).toBe('/app.html');
    expect(cibleStatique(dist, '/metier')).toBe('/app.html');
    expect(cibleStatique(dist, '/assets/absent.js')).toBe('/app.html');
    // Jamais hors de dist, jamais d'exception sur une URL mal formée.
    expect(cibleStatique(dist, '/../../etc/passwd')).toBe('/app.html');
    expect(cibleStatique(dist, '/..%2f..%2fetc/passwd')).toBe('/app.html');
    expect(cibleStatique(dist, '/%E0%A4%A')).toBe('/app.html');
    expect(cibleStatique(dist, '/a%00b')).toBe('/app.html');
    expect(cibleStatique(dist, undefined)).toBe('/index.html');
  });

  it('applique la condition du repli SPA de Vite (GET ou HEAD, type HTML, générique ou absent)', () => {
    expect(estRequeteDePage('GET', 'text/html,application/xhtml+xml')).toBe(true);
    expect(estRequeteDePage('HEAD', '*/*')).toBe(true);
    expect(estRequeteDePage('GET', undefined)).toBe(true);
    expect(estRequeteDePage('GET', '')).toBe(true);
    expect(estRequeteDePage('GET', 'application/json')).toBe(false);
    expect(estRequeteDePage('POST', 'text/html')).toBe(false);
  });

  it('en preview, réécrit l\'URL des navigations et laisse passer le reste', () => {
    const p = plugin();
    let intergiciel: Parameters<Parameters<ReturnType<typeof plugin>['configurePreviewServer']>[0]['middlewares']['use']>[0] | undefined;
    p.configurePreviewServer({ middlewares: { use: (f) => { intergiciel = f; } } });
    const passer = (method: string, url: string, accept?: string) => {
      const req = { method, url, headers: accept === undefined ? {} : { accept } };
      let suite = false;
      intergiciel!(req, {}, () => { suite = true; });
      expect(suite).toBe(true);
      return req.url;
    };
    expect(passer('GET', '/connexion', 'text/html')).toBe('/app.html');
    expect(passer('GET', '/connexion')).toBe('/app.html'); // curl sans en-tête : même réponse que Vercel
    expect(passer('GET', '/tarifs', 'text/html')).toBe('/tarifs/index.html');
    expect(passer('GET', '/assets/index-abc.js', '*/*')).toBe('/assets/index-abc.js');
    expect(passer('GET', '/rest/v1/missions', 'application/json')).toBe('/rest/v1/missions');
    expect(passer('POST', '/connexion', 'text/html')).toBe('/connexion');
  });
});

describe('titre de l\'accueil', () => {
  it('se coupe en deux à sa seule virgule (PageAccueil met la fin en dégradé)', () => {
    expect(TITRE_ACCUEIL.split(', ')).toEqual(['Le remplacement santé', 'enfin simple.']);
    expect(metaAccueil().h1).toBe(TITRE_ACCUEIL);
    expect(readFileSync(path.join(RACINE_DEPOT, 'src/pages/PageAccueil.tsx'), 'utf8')).toContain("const [TITRE_DEBUT, TITRE_FIN] = TITRE_ACCUEIL.split(', ');");
  });
});
