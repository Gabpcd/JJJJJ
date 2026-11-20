// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { VILLES_SEO, PROFESSIONS_SEO } from './seo-data';
import { TYPES_ETABLISSEMENT_SEO } from './seo-contenu/etablissements';
import { GUIDES_SEO } from './seo-contenu/guides';
import { CODES_DEPARTEMENTS, DEPARTEMENTS } from './seo-departements';
import {
  BMO_2026,
  FINESS,
  SEUIL_CLASSEMENT_BMO,
  aVille,
  comptesFiness,
  dateLongue,
  enumerer,
  jsonLdPage,
  metaBarometre,
  metaEtablissement,
  metaGuide,
  metaGuides,
  metaVille,
  phraseFiness,
  phraseFinessNationale,
  resoudreEtablissement,
  resoudreGuide,
  totalBmo,
  toutesLesRoutesSeo,
  type DonneesFiness,
  type PageSEO,
} from './seo-routes';
import { CATEGORIES, compter, normaliserCommune } from '../../scripts/seo/extraire-finess.mjs';

const FAUX_FINESS: DonneesFiness = {
  source: 'test', sourceUrl: 'https://exemple.test', extractionDu: '2026-05-01', fichierPublieLe: '2026-07-02',
  colonnes: ['ehpad', 'hopital', 'ssiad', 'had', 'masfam', 'ime', 'centreSante'],
  national: [7399, 1954, 1737, 137, 1928, 1538, 3395],
  departements: { '69': [10, 2, 1, 0, 0, 0, 3] },
  villes: { lyon: [44, 1, 0, 0, 0, 0, 1], 'le-havre': [1, 0, 0, 0, 0, 0, 0], vide: [0, 0, 0, 0, 0, 0, 0] },
};
const ville = (slug: string, nom: string) => ({ slug, nom, departement: '69' });

/** Tous les textes visibles d'une page, FAQ comprise. */
function textes(p: PageSEO): string[] {
  return [
    p.title, p.description, p.h1, ...p.intro,
    ...(p.sections ?? []).flatMap((s) => [
      s.titre, ...(s.paragraphes ?? []), ...(s.liste ?? []),
      ...(s.points ?? []).flatMap((pt) => [pt.titre, pt.texte]),
      ...(s.tableau ? [s.tableau.legende, ...s.tableau.entetes, ...s.tableau.lignes.flat()] : []),
    ]),
    ...(p.faq ?? []).flatMap((f) => [f.q, f.r]),
  ];
}

describe('phrases locales FINESS', () => {
  it('accorde chaque catégorie, omet les comptes nuls et date par l\'extraction', () => {
    expect(phraseFiness(ville('lyon', 'Lyon'), undefined, FAUX_FINESS))
      .toBe('À Lyon, le répertoire FINESS recense 44 EHPAD, 1 site hospitalier public et 1 centre de santé (extraction du 1er mai 2026).');
  });

  it('contracte la préposition avec l\'article du nom de ville', () => {
    expect(aVille({ nom: 'Le Havre' })).toBe('au Havre');
    expect(aVille({ nom: 'Le Mans' })).toBe('au Mans');
    expect(aVille({ nom: 'La Rochelle' })).toBe('à La Rochelle');
    expect(aVille({ nom: 'Les Sables-d’Olonne' })).toBe('aux Sables-d’Olonne');
    expect(phraseFiness(ville('le-havre', 'Le Havre'), undefined, FAUX_FINESS)).toMatch(/^Au Havre, le répertoire FINESS recense 1 EHPAD \(/);
    expect(metaVille(VILLES_SEO.find((v) => v.slug === 'le-havre')!).h1).toBe('Missions soignants au Havre');
  });

  it('ne dit rien quand aucun établissement n\'est compté ou que la ville est absente', () => {
    expect(phraseFiness(ville('vide', 'Vide'), undefined, FAUX_FINESS)).toBeNull();
    expect(phraseFiness(ville('absente', 'Absente'), undefined, FAUX_FINESS)).toBeNull();
    // Sage-femme : sites hospitaliers et centres de santé seulement. Le Havre n'a ici qu'un EHPAD.
    expect(phraseFiness(ville('le-havre', 'Le Havre'), 'SAGE_FEMME', FAUX_FINESS)).toBeNull();
    // Métier sans catégorie associée : rien.
    expect(phraseFiness(ville('lyon', 'Lyon'), 'PHARMACIEN', FAUX_FINESS)).toBeNull();
  });

  it('ne cite pour un métier que les catégories qui le concernent', () => {
    const texte = phraseFiness(ville('lyon', 'Lyon'), 'AES', FAUX_FINESS)!;
    expect(texte).toContain('44 EHPAD');
    expect(texte).not.toContain('hospitalier');
    expect(texte).not.toContain('centre de santé');
  });

  it('énumère en français', () => {
    expect(enumerer([])).toBe('');
    expect(enumerer(['a'])).toBe('a');
    expect(enumerer(['a', 'b'])).toBe('a et b');
    expect(enumerer(['a', 'b', 'c'])).toBe('a, b et c');
    expect(dateLongue('2026-05-04')).toBe('4 mai 2026');
    expect(comptesFiness(undefined, ['ehpad'])).toEqual([]);
    expect(phraseFinessNationale([], FAUX_FINESS)).toBeNull();
    expect(phraseFinessNationale(['ssiad', 'had'], FAUX_FINESS)).toMatch(/^Le répertoire FINESS recense 1\s737 services de soins infirmiers à domicile \(SSIAD\) et 137 structures d’hospitalisation à domicile \(HAD\) en France \(extraction du 1er mai 2026\)\.$/);
  });
});

describe('fichier seo-finess.json', () => {
  it('a les colonnes du script d\'extraction, dans le même ordre', () => {
    expect(FINESS.colonnes).toEqual(CATEGORIES.map((c: { cle: string }) => c.cle));
    expect(FINESS.extractionDu).toMatch(/^\d{4}-\d\d-\d\d$/);
    expect(FINESS.extractionDu <= FINESS.fichierPublieLe).toBe(true);
  });

  it('a un total national égal à la somme des départements', () => {
    FINESS.colonnes.forEach((_, i) => {
      const somme = Object.values(FINESS.departements).reduce((s, d) => s + d[i], 0);
      expect(somme, FINESS.colonnes[i]).toBe(FINESS.national[i]);
    });
  });

  it('couvre les 100 villes, sans dépasser le compte de leur département', () => {
    for (const v of VILLES_SEO) {
      const compte = FINESS.villes[v.slug];
      expect(compte, v.nom).toHaveLength(FINESS.colonnes.length);
      expect(phraseFiness(v), v.nom).not.toBeNull();
      compte.forEach((n, i) => expect(n, `${v.nom} ${FINESS.colonnes[i]}`).toBeLessThanOrEqual(FINESS.departements[v.departement][i]));
    }
  });

  it('couvre chaque département du baromètre', () => {
    for (const code of CODES_DEPARTEMENTS) {
      expect(BMO_2026[code], code).toBeDefined();
      expect(FINESS.departements[code], `${code} ${DEPARTEMENTS[code]}`).toBeDefined();
    }
    expect(CODES_DEPARTEMENTS).toHaveLength(Object.keys(BMO_2026).length);
    expect(CODES_DEPARTEMENTS.slice(0, 3)).toEqual(['01', '02', '03']);
    expect(CODES_DEPARTEMENTS.indexOf('2A')).toBe(CODES_DEPARTEMENTS.indexOf('19') + 1);
    expect(CODES_DEPARTEMENTS.at(-1)).toBe('976');
  });
});

describe('extraction FINESS (scripts/seo/extraire-finess.mjs)', () => {
  const ligne = (finess: string, dept: string, acheminement: string, code: string, libelle: string, geoloc = '2026-05-04') => {
    const f = Array(35).fill('');
    f[0] = finess; f[12] = dept; f[14] = acheminement; f[17] = code; f[18] = libelle; f[34] = geoloc;
    return f.join(';');
  };
  async function* flux(lignes: string[]) { yield* lignes; }
  const villes = [{ slug: 'saint-etienne', nom: 'Saint-Étienne', departement: '42' }, { slug: 'paris', nom: 'Paris', departement: '75' }];
  const EHPAD = 'Etablissement d\'hébergement pour personnes âgées dépendantes';

  it('rapproche les communes malgré accents, tirets, CEDEX et abréviation de SAINT', () => {
    expect(normaliserCommune('Saint-Étienne')).toBe('ST ETIENNE');
    expect(normaliserCommune('ST ETIENNE CEDEX 2')).toBe('ST ETIENNE');
    expect(normaliserCommune('PARIS 15E ARRONDISSEMENT')).toBe('PARIS');
    expect(normaliserCommune("Villeneuve-d'Ascq")).toBe('VILLENEUVE D ASCQ');
  });

  it('compte par catégorie, par ville, par département et au national, et date l\'extraction', async () => {
    const r = await compter(flux([
      'nofinesset;'.padEnd(40, ';'),
      ligne('1', '42', '42000 ST ETIENNE', '500', EHPAD),
      ligne('2', '42', '42100 SAINT ETIENNE CEDEX 1', '500', EHPAD),
      ligne('3', '42', '42300 ROANNE', '355', 'Centre Hospitalier (C.H.)'),
      ligne('4', '75', '75014 PARIS', '124', 'Centre de Santé'),
      ligne('5', '9D', '97400 ST DENIS', '500', EHPAD),
      ligne('6', '75', '75014 PARIS', '620', 'Pharmacie d\'Officine'),
    ]), villes);
    expect(r.lues).toBe(6);
    expect(r.extractionDu).toBe('2026-05-04');
    expect(r.national).toEqual([3, 1, 0, 0, 0, 0, 1]);
    expect(r.villes['saint-etienne']).toEqual([2, 0, 0, 0, 0, 0, 0]);
    expect(r.villes.paris).toEqual([0, 0, 0, 0, 0, 0, 1]);
    expect(r.departements['42']).toEqual([2, 1, 0, 0, 0, 0, 0]);
    expect(r.departements['974']).toEqual([1, 0, 0, 0, 0, 0, 0]); // 9D = La Réunion
  });

  it('échoue si un code de catégorie ne porte plus le libellé attendu', async () => {
    await expect(compter(flux([ligne('1', '42', '42000 ST ETIENNE', '500', 'Centre de Santé')]), villes)).rejects.toThrow(/libellé inattendu/);
  });

  it('échoue si l\'extraction ne peut pas être datée', async () => {
    await expect(compter(flux([ligne('1', '42', '42000 ST ETIENNE', '500', EHPAD, '')]), villes)).rejects.toThrow(/date d'extraction/);
  });
});

describe('baromètre par département', () => {
  const page = metaBarometre();
  const tableau = page.sections!.find((s) => s.tableau)!.tableau!;
  const cles = page.sections![0].liste!;

  it('a une ligne par département et huit colonnes', () => {
    expect(tableau.lignes).toHaveLength(CODES_DEPARTEMENTS.length);
    for (const l of tableau.lignes) expect(l).toHaveLength(tableau.entetes.length);
    expect(tableau.entetes).toHaveLength(8);
    expect(tableau.lignes[0][0]).toBe('Ain (01)');
    expect(tableau.lignes.find((l) => l[0] === 'Paris (75)')!.slice(1, 3)).toEqual([expect.stringMatching(/^1\s104$/), '28 %']);
  });

  it('énonce des chiffres clés que le tableau confirme', () => {
    // « Dans N départements… au moins 80 % » = nombre de lignes dont la part affichée est ≥ 80 %.
    const affiches = tableau.lignes.filter((l) => /^\d+ %$/.test(l[2]) && Number(l[2].replace(' %', '')) >= 80).length;
    expect(cles[1]).toContain(`Dans ${affiches} départements sur `);
    expect(cles[0]).toContain(String(totalBmo('AS')).replace(/\B(?=(\d{3})+(?!\d))/g, ' ').slice(0, 2));
    expect(totalBmo('AS')).toBe(61987);
    expect(totalBmo('IDE')).toBe(36491);
    expect(totalBmo('MEDECIN')).toBe(8465);
    // Le classement ne retient que des départements au-dessus du seuil de projets.
    for (const nom of cles[2].match(/[A-ZÀ-Ý][^,(]+ \((\d\w|\d{3})\)/g) ?? []) {
      const code = /\((\w+)\)$/.exec(nom)![1];
      expect(BMO_2026[code]!.AS![0], nom).toBeGreaterThanOrEqual(SEUIL_CLASSEMENT_BMO);
    }
  });

  it('marque « n.c. » une part non communiquée et ne publie aucune part pour zéro projet', () => {
    const allier = tableau.lignes.find((l) => l[0] === 'Allier (03)')!;
    expect(allier.slice(5, 7)).toEqual(['0', 'n.c.']);
  });

  it('se déclare comme jeu de données fondé sur les deux sources publiques', () => {
    const dataset = jsonLdPage(page).find((b) => b['@type'] === 'Dataset') as { isBasedOn: string[] };
    expect(dataset.isBasedOn).toEqual([
      'https://www.data.gouv.fr/datasets/enquete-besoins-en-main-doeuvre-bmo',
      'https://www.data.gouv.fr/datasets/finess-extraction-du-fichier-des-etablissements',
    ]);
    expect(page.sections!.some((s) => (s.sources ?? []).length === 2)).toBe(true);
  });
});

describe('pages par type d\'établissement', () => {
  const pages = TYPES_ETABLISSEMENT_SEO.map(metaEtablissement);

  it('couvre cinq types, résolus par leur slug', () => {
    expect(TYPES_ETABLISSEMENT_SEO.map((t) => t.slug)).toEqual(['ehpad', 'clinique', 'hopital', 'soins-a-domicile', 'handicap']);
    expect(resoudreEtablissement('ehpad')?.nom).toBe('EHPAD');
    expect(resoudreEtablissement('inconnu')).toBeNull();
    expect(resoudreEtablissement(undefined)).toBeNull();
  });

  it('ne cite que des professions qui ont une page métier', () => {
    for (const t of TYPES_ETABLISSEMENT_SEO) {
      for (const valeur of t.professions) expect(PROFESSIONS_SEO.some((p) => p.valeur === valeur), `${t.slug} ${valeur}`).toBe(true);
    }
  });

  it('cite le nombre national FINESS seulement quand le type a une catégorie', () => {
    expect(pages[0].intro.at(-1)).toMatch(/Le répertoire FINESS recense 7\s399 EHPAD en France/);
    expect(pages[1].intro.join(' ')).not.toContain('FINESS'); // clinique : pas de catégorie retenue
  });

  it('ne publie aucun pourcentage hors commission (15 % HT, 18 % TTC) et TVA (20 %)', () => {
    for (const p of pages) {
      for (const t of textes(p)) {
        for (const m of t.matchAll(/(\d+(?:[.,]\d+)?)\s?%/g)) expect(['15', '18', '20'], `${p.path} : ${t.slice(0, 80)}`).toContain(m[1]);
      }
    }
  });
});

describe('guides', () => {
  it('ont au moins quatre sections, trois questions et une date de révision', () => {
    for (const g of GUIDES_SEO) {
      expect(g.sections.length, g.slug).toBeGreaterThanOrEqual(4);
      expect(g.faq.length, g.slug).toBeGreaterThanOrEqual(3);
      expect(g.maj, g.slug).toMatch(/^\d{4}-\d\d-\d\d$/);
      expect(metaGuide(g).lastmod).toBe(g.maj);
      expect(metaGuide(g).intro.at(-1)).toBe(`Guide mis à jour le ${dateLongue(g.maj)}.`);
    }
    expect(resoudreGuide('cout-remplacement-soignant')?.public).toBe('etablissement');
    expect(resoudreGuide('inconnu')).toBeNull();
  });

  it('ne citent que des sources officielles en https', () => {
    for (const g of GUIDES_SEO) {
      for (const s of metaGuide(g).sections!.flatMap((x) => x.sources ?? [])) {
        expect(s.href, g.slug).toMatch(/^https:\/\/([a-z-]+\.)?(service-public\.gouv\.fr|data\.gouv\.fr)\//);
      }
    }
  });

  it('insèrent les chiffres demandés avec leur source, après la première section', () => {
    const page = metaGuide(resoudreGuide('remplacement-aide-soignant-ehpad')!);
    expect(page.sections![1].titre).toBe('En chiffres');
    expect(page.sections![1].paragraphes!.join(' ')).toMatch(/61\s987 projets de recrutement d’aides-soignants pour 2026/);
    expect(page.sections![1].paragraphes!.join(' ')).toMatch(/7\s399 EHPAD en France/);
    expect(page.sections![1].sources).toHaveLength(2);
    expect(metaGuide(resoudreGuide('premiere-mission-de-remplacement')!).sections!.some((s) => s.titre === 'En chiffres')).toBe(false);
  });

  it('vouvoient et ne promettent aucun volume', () => {
    for (const p of [...GUIDES_SEO.map(metaGuide), ...TYPES_ETABLISSEMENT_SEO.map(metaEtablissement), metaBarometre(), metaGuides()]) {
      const texte = textes(p).join(' ');
      // Limites de mot Unicode : en JavaScript, \b coupe « été » ou « qualité » après le « t ».
      expect(texte, p.path).not.toMatch(/(?<!\p{L})(tu|ton|ta|tes|toi)(?!\p{L})/iu);
      expect(texte, p.path).not.toMatch(/centaines|milliers|garanti[es]? en|en moins de \d+ ?(h|heures|minutes)/i);
    }
  });

  it('l\'exemple chiffré du coût applique la commission publiée', () => {
    const texte = textes(metaGuide(resoudreGuide('cout-remplacement-soignant')!)).join(' ');
    expect(texte).toContain('7 × 20 € = 140 €');
    expect(texte).toContain('15 % de 140 € = 21 € HT, soit 25,20 € TTC');
    expect((140 * 0.15).toFixed(2)).toBe('21.00');
    expect((21 * 1.2).toFixed(2)).toBe('25.20');
  });

  it('se déclarent comme Article daté, avec fil d\'Ariane et FAQ', () => {
    const page = metaGuide(GUIDES_SEO[0]);
    const types = jsonLdPage(page).map((b) => b['@type']);
    expect(types).toEqual(['Article', 'BreadcrumbList', 'FAQPage']);
    const article = jsonLdPage(page)[0] as { dateModified: string; mainEntityOfPage: string };
    expect(article.dateModified).toBe(GUIDES_SEO[0].maj);
    expect(article.mainEntityOfPage).toBe(`https://jolene.app${page.path}`);
  });

  it('le sommaire liste chaque guide une fois, par public', () => {
    const sommaire = metaGuides();
    const hrefs = sommaire.sections!.flatMap((s) => (s.points ?? []).map((p) => p.href));
    expect(hrefs).toEqual([...GUIDES_SEO.filter((g) => g.public === 'soignant'), ...GUIDES_SEO.filter((g) => g.public === 'etablissement')].map((g) => `/guides/${g.slug}`));
  });
});

describe('nouvelles pages : titres, descriptions et liens', () => {
  const toutes = toutesLesRoutesSeo();
  const nouvelles = toutes.filter((p) => ['etablissement', 'guide', 'guides', 'barometre'].includes(p.type));

  it('titre de 65 caractères au plus, description de 110 à 165', () => {
    for (const p of nouvelles) {
      expect(p.title.length, p.title).toBeLessThanOrEqual(65);
      expect(p.description.length, `${p.path} (${p.description.length})`).toBeGreaterThanOrEqual(110);
      expect(p.description.length, `${p.path} (${p.description.length})`).toBeLessThanOrEqual(165);
      expect(p.indexable, p.path).toBe(true);
    }
  });

  it('aucun lien interne ne mène à une page qui n\'existe pas', () => {
    const chemins = new Set(toutes.map((p) => p.path));
    // Routes de l'application sans page statique (src/App.tsx).
    const application = new Set(['/inscription/soignant', '/inscription/etablissement', '/aide']);
    for (const p of toutes) {
      const liens = [...p.liens.map((l) => l.href), ...(p.filAriane ?? []).map((l) => l.href), ...(p.sections ?? []).flatMap((s) => (s.points ?? []).flatMap((pt) => (pt.href ? [pt.href] : [])))];
      for (const href of liens) expect(chemins.has(href) || application.has(href), `${p.path} → ${href}`).toBe(true);
    }
  });

  it('chaque nouvelle page est liée depuis l\'accueil ou un pilier', () => {
    const depuis = new Set(toutes.filter((p) => ['accueil', 'recruter', 'devenir', 'guides'].includes(p.type)).flatMap((p) => [...p.liens.map((l) => l.href), ...(p.sections ?? []).flatMap((s) => (s.points ?? []).map((pt) => pt.href))]));
    for (const p of nouvelles) expect(depuis.has(p.path), p.path).toBe(true);
  });
});
