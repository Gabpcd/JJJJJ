// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { VILLES_SEO, PROFESSIONS_SEO } from './seo-data';
import { ETAPES_PUBLICATION, RENVOI_COMMUN, TYPES_ETABLISSEMENT_SEO } from './seo-contenu/etablissements';
import { GUIDES_SEO } from './seo-contenu/guides';
import { CODES_DEPARTEMENTS, DEPARTEMENTS } from './seo-departements';
import {
  BMO_2026,
  FINESS,
  NON_COMMUNIQUE,
  SEUIL_CLASSEMENT_BMO,
  SEUIL_PART_DIFFICILE,
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
  type TableBmo,
} from './seo-routes';
import { CATEGORIES, compter, normaliserCommune } from '../../scripts/seo/extraire-finess.mjs';
import { agreger, chainesPartagees, lignesFeuille, METIERS_BMO } from '../../scripts/seo/extraire-bmo.mjs';

const FAUX_FINESS: DonneesFiness = {
  source: 'test', sourceUrl: 'https://exemple.test', extractionDu: '2026-05-01', fichierPublieLe: '2026-07-02',
  colonnes: ['ehpad', 'ssiad', 'masfam', 'ime', 'centreSante'],
  national: [7399, 1737, 1928, 1538, 3395],
  departements: { '69': [10, 1, 0, 0, 3] },
  villes: { lyon: [44, 1, 0, 0, 1], 'le-havre': [1, 0, 0, 0, 0], vide: [0, 0, 0, 0, 0] },
};
const ville = (slug: string, nom: string) => ({ slug, nom, departement: '69' });
const nombre = (texte: string) => Number(texte.replace(/[^\d]/g, ''));

/** Tous les textes visibles d'une page, FAQ et libellés de liens de section compris. */
function textes(p: PageSEO): string[] {
  return [
    p.title, p.description, p.h1, ...p.intro,
    ...(p.sections ?? []).flatMap((s) => [
      s.titre, ...(s.paragraphes ?? []), ...(s.liste ?? []),
      ...(s.points ?? []).flatMap((pt) => [pt.titre, pt.texte]),
      ...(s.tableau ? [s.tableau.legende, ...s.tableau.entetes, ...s.tableau.lignes.flat()] : []),
      ...(s.liens ?? []).map((l) => l.label),
    ]),
    ...(p.faq ?? []).flatMap((f) => [f.q, f.r]),
  ];
}

describe('phrases locales FINESS', () => {
  it('accorde chaque catégorie, omet les comptes nuls et date par l\'extraction', () => {
    expect(phraseFiness(ville('lyon', 'Lyon'), undefined, FAUX_FINESS))
      .toBe('À Lyon, le répertoire FINESS recense 44 EHPAD, 1 service de soins infirmiers à domicile (SSIAD) et 1 centre de santé (extraction du 1er mai 2026).');
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
    // Sage-femme : centres de santé seulement. Le Havre n'a ici qu'un EHPAD.
    expect(phraseFiness(ville('le-havre', 'Le Havre'), 'SAGE_FEMME', FAUX_FINESS)).toBeNull();
    // Métier sans catégorie associée : rien.
    expect(phraseFiness(ville('lyon', 'Lyon'), 'PHARMACIEN', FAUX_FINESS)).toBeNull();
  });

  it('ne cite pour un métier que les catégories qui le concernent', () => {
    const texte = phraseFiness(ville('lyon', 'Lyon'), 'AES', FAUX_FINESS)!;
    expect(texte).toContain('44 EHPAD');
    expect(texte).not.toContain('SSIAD');
    expect(texte).not.toContain('centre de santé');
  });

  it('ne compte jamais d\'hôpitaux : la catégorie FINESS ne correspond pas à ce que le mot annonce', () => {
    expect(FINESS.colonnes).not.toContain('hopital');
    for (const p of toutesLesRoutesSeo().filter((x) => x.type === 'ville' || x.type === 'ville-metier')) {
      for (const t of p.intro.filter((x) => x.includes('répertoire FINESS'))) expect(t, p.path).not.toMatch(/hospitali|hôpit/i);
    }
  });

  it('énumère en français', () => {
    expect(enumerer([])).toBe('');
    expect(enumerer(['a'])).toBe('a');
    expect(enumerer(['a', 'b'])).toBe('a et b');
    expect(enumerer(['a', 'b', 'c'])).toBe('a, b et c');
    expect(dateLongue('2026-05-04')).toBe('4 mai 2026');
    expect(comptesFiness(undefined, ['ehpad'])).toEqual([]);
    expect(phraseFinessNationale([], FAUX_FINESS)).toBeNull();
    expect(phraseFinessNationale(['masfam', 'ime'], FAUX_FINESS)).toMatch(/^Le répertoire FINESS recense 1\s928 maisons d’accueil spécialisées et foyers d’accueil médicalisés et 1\s538 instituts médico-éducatifs \(IME\) en France \(extraction du 1er mai 2026\)\.$/);
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
  const ligne = (finess: string, dept: string, commune: string, acheminement: string, code: string, libelle: string, geoloc = '2026-05-04') => {
    const f = Array(35).fill('');
    f[0] = finess; f[11] = commune; f[12] = dept; f[14] = acheminement; f[17] = code; f[18] = libelle; f[34] = geoloc;
    return f.join(';');
  };
  async function* flux(lignes: string[]) { yield* lignes; }
  const villes = [
    { slug: 'angouleme', nom: 'Angoulême', departement: '16' },
    { slug: 'lille', nom: 'Lille', departement: '59' },
    { slug: 'paris', nom: 'Paris', departement: '75' },
  ];
  const EHPAD = 'Etablissement d\'hébergement pour personnes âgées dépendantes';
  const PHARMACIE = 'Pharmacie d\'Officine';

  it('rapproche les libellés malgré accents, tirets, CEDEX et abréviation de SAINT', () => {
    expect(normaliserCommune('Saint-Étienne')).toBe('ST ETIENNE');
    expect(normaliserCommune('ST ETIENNE CEDEX 2')).toBe('ST ETIENNE');
    expect(normaliserCommune('PARIS 15E ARRONDISSEMENT')).toBe('PARIS');
    expect(normaliserCommune("Villeneuve-d'Ascq")).toBe('VILLENEUVE D ASCQ');
  });

  it('reconnaît une ville par son code commune, pas par son libellé postal', async () => {
    const r = await compter(flux([
      'nofinesset;'.padEnd(40, ';'),
      // Angoulême = commune 015 (apprise sur des lignes non CEDEX, toutes catégories confondues).
      ligne('1', '16', '015', '16000 ANGOULEME', '620', PHARMACIE),
      ligne('2', '16', '015', '16000 ANGOULEME', '500', EHPAD),
      // CEDEX au nom d'Angoulême, mais établissement situé dans la commune voisine (341) : pas compté.
      ligne('3', '16', '341', '16959 ANGOULEME CEDEX 9', '500', EHPAD),
      // Lille = commune 350 ; Lomme, commune associée, porte le même code : compté.
      ligne('4', '59', '350', '59000 LILLE', '620', PHARMACIE),
      ligne('5', '59', '350', '59160 LOMME', '124', 'Centre de Santé'),
      // Paris : un code par arrondissement.
      ligne('6', '75', '114', '75014 PARIS', '500', EHPAD),
      ligne('7', '75', '120', '75020 PARIS', '354', 'Service de Soins Infirmiers A Domicile (S.S.I.A.D)'),
      // La Réunion : code département FINESS 9D → 974.
      ligne('8', '9D', '411', '97400 ST DENIS', '500', EHPAD),
    ]), villes);
    expect(r.lues).toBe(8);
    expect(r.extractionDu).toBe('2026-05-04');
    expect(r.villes.angouleme).toEqual([1, 0, 0, 0, 0]);
    expect(r.villes.lille).toEqual([0, 0, 0, 0, 1]);
    expect(r.villes.paris).toEqual([1, 1, 0, 0, 0]);
    expect(r.departements['16']).toEqual([2, 0, 0, 0, 0]);
    expect(r.departements['974']).toEqual([1, 0, 0, 0, 0]);
    expect(r.national).toEqual([4, 1, 0, 0, 1]);
    expect(r.ambigues).toEqual([]);
  });

  it('signale une ville dont deux codes commune sont fréquents', async () => {
    const r = await compter(flux([
      ligne('1', '16', '015', '16000 ANGOULEME', '620', PHARMACIE),
      ligne('2', '16', '015', '16000 ANGOULEME', '620', PHARMACIE),
      ligne('3', '16', '999', '16000 ANGOULEME', '620', PHARMACIE),
    ]), villes);
    expect(r.ambigues.join(' ')).toContain('angouleme');
  });

  it('échoue si un code de catégorie ne porte plus le libellé attendu', async () => {
    await expect(compter(flux([ligne('1', '16', '015', '16000 ANGOULEME', '500', 'Centre de Santé')]), villes)).rejects.toThrow(/libellé inattendu/);
  });

  it('échoue si l\'extraction ne peut pas être datée', async () => {
    await expect(compter(flux([ligne('1', '16', '015', '16000 ANGOULEME', '500', EHPAD, '')]), villes)).rejects.toThrow(/date d'extraction/);
  });
});

describe('extraction BMO (scripts/seo/extraire-bmo.mjs)', () => {
  const AS = { code: 'V0X60', libelle: 'Aides-soignants' };
  const bassin = (departement: string, projets: string | number, difficiles: string | number, m = AS) => ({ ...m, departement, projets, difficiles });

  it('ne calcule la part que si aucune valeur du département n\'est masquée', () => {
    const r = agreger([
      // 75 : deux bassins entièrement publiés → total exact et part exacte.
      bassin('75', 100, 30), bassin('75', 50, 20),
      // 69 : projets difficiles masqués dans un bassin → total exact, part inconnue.
      bassin('69', 100, 80), bassin('69', 40, '*'),
      // 03 : projets masqués dans un bassin → total minimal, part inconnue.
      bassin('03', 60, 30), bassin('03', '*', '*'),
      // 23 : tout est masqué → zéro publié, total minimal.
      bassin('23', '*', '*'),
      // 1 chiffre : le département est complété à deux chiffres.
      bassin('1', 10, 5),
    ]);
    expect(r['75'].AS).toEqual([150, 33.33, 0]);
    expect(r['69'].AS).toEqual([140, null, 0]);
    expect(r['03'].AS).toEqual([60, null, 1]);
    expect(r['23'].AS).toEqual([0, null, 1]);
    expect(r['01'].AS).toEqual([10, 50, 0]);
  });

  it('ne reproduit pas l\'ancienne méthode, qui sortait de l\'intervalle possible', () => {
    // Ancienne méthode (supabase/functions/_shared/bmo-acquisition.ts) : projets = tous les bassins,
    // part = difficiles / projets des seuls bassins où « difficiles » est publié.
    const lignes = [bassin('69', 100, 80), bassin('69', 40, '*')];
    const publies = lignes.filter((l) => typeof l.difficiles === 'number');
    const ancienne = (publies.reduce((s, l) => s + Number(l.difficiles), 0) / publies.reduce((s, l) => s + Number(l.projets), 0)) * 100;
    // Un astérisque cache une valeur de 0 à 4 : la part réelle du département est entre 80/140 et 84/140.
    const total = lignes.reduce((s, l) => s + Number(l.projets), 0);
    const [min, max] = [(80 / total) * 100, (84 / total) * 100];
    expect(ancienne).toBe(80);
    expect(ancienne).toBeGreaterThan(max);
    expect(Math.round(min)).toBe(57);
    expect(Math.round(max)).toBe(60);
    // Nouvelle méthode : total exact (aucun nombre de projets masqué), part non calculée.
    expect(agreger(lignes)['69'].AS).toEqual([140, null, 0]);
  });

  it('ignore les autres métiers et refuse un code dont le libellé a changé', () => {
    expect(agreger([{ code: 'A0X40', libelle: 'Agriculteurs', departement: '75', projets: 10, difficiles: 5 }])).toEqual({});
    expect(() => agreger([{ code: 'V1X80', libelle: 'Infirmiers', departement: '75', projets: 10, difficiles: 5 }])).toThrow(/libellé/);
    expect(Object.keys(METIERS_BMO).sort()).toEqual(['AS', 'IDE', 'MEDECIN']);
  });

  it('lit les cellules d\'une feuille (chaînes partagées, nombres, astérisque)', () => {
    const fichiers = new Map([['xl/sharedStrings.xml', () => '<sst><si><t>met</t></si><si><t xml:space="preserve">Infirmiers &amp; sages-femmes</t></si><si><t>*</t></si></sst>']]);
    const partagees = chainesPartagees(fichiers);
    expect(partagees).toEqual(['met', 'Infirmiers & sages-femmes', '*']);
    const xml = '<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row><row r="2"><c r="A2"><v>42</v></c><c r="B2" t="s"><v>2</v></c><c r="C2"/></row></sheetData>';
    expect([...lignesFeuille(xml, partagees)]).toEqual([{ A: 'met', B: 'Infirmiers & sages-femmes' }, { A: '42', B: '*' }]);
  });
});

describe('baromètre par département', () => {
  const page = metaBarometre();
  const tableau = page.sections!.find((s) => s.tableau)!.tableau!;
  const cles = page.sections![0].liste!;
  const COL = { asProjets: 1, asPart: 2, ideProjets: 3, idePart: 4, medProjets: 5, medPart: 6, ehpad: 7 };
  const partNumerique = (cellule: string) => (/^\d+ %$/.test(cellule) ? Number(cellule.replace(' %', '')) : null);

  it('a une ligne par département, huit colonnes et des en-têtes tous différents', () => {
    expect(tableau.lignes).toHaveLength(CODES_DEPARTEMENTS.length);
    for (const l of tableau.lignes) expect(l).toHaveLength(tableau.entetes.length);
    expect(tableau.entetes).toHaveLength(8);
    expect(new Set(tableau.entetes).size).toBe(8);
    expect(tableau.lignes[0][0]).toBe('Ain (01)');
    expect(tableau.lignes.find((l) => l[0] === 'Paris (75)')!.slice(1, 3)).toEqual([expect.stringMatching(/^1\s104$/), '28 %']);
  });

  it('note « ≥ » un total minimal et « n.c. » une part non calculable', () => {
    const rhone = tableau.lignes.find((l) => l[0] === 'Rhône (69)')!;
    expect(rhone[COL.asProjets]).toMatch(/^≥ 1\s471$/);
    expect(rhone[COL.asPart]).toBe(NON_COMMUNIQUE);
    // Allier, médecins : aucun projet publié et valeurs masquées → on ne sait pas, donc « n.c. », pas « 0 ».
    const allier = tableau.lignes.find((l) => l[0] === 'Allier (03)')!;
    expect(allier.slice(COL.medProjets, COL.medPart + 1)).toEqual([NON_COMMUNIQUE, NON_COMMUNIQUE]);
    // Jamais de part à côté d'un total minimal.
    for (const l of tableau.lignes) {
      for (const [projets, part] of [[COL.asProjets, COL.asPart], [COL.ideProjets, COL.idePart], [COL.medProjets, COL.medPart]]) {
        if (l[projets].startsWith('≥') || l[projets] === NON_COMMUNIQUE) expect(l[part], `${l[0]} col. ${part}`).toBe(NON_COMMUNIQUE);
      }
    }
  });

  it('chaque chiffre clé se recalcule depuis le tableau affiché', () => {
    const somme = (col: number) => tableau.lignes.reduce((s, l) => s + (l[col] === NON_COMMUNIQUE ? 0 : nombre(l[col])), 0);
    const minimal = (col: number) => tableau.lignes.some((l) => l[col].startsWith('≥') || l[col] === NON_COMMUNIQUE);
    // 1. Totaux : somme des cellules, « au moins » dès qu'une cellule est minimale.
    for (const [metier, col] of [['AS', COL.asProjets], ['IDE', COL.ideProjets], ['MEDECIN', COL.medProjets]] as const) {
      const t = totalBmo(metier);
      expect(t.projets, metier).toBe(somme(col));
      expect(t.partiel, metier).toBe(minimal(col));
      expect(cles[0].replace(/\s/g, ''), metier).toContain(`${t.partiel ? 'aumoins' : ''}${t.projets}projets`.replace('projets', metier === 'AS' ? 'projets' : ''));
    }
    expect(totalBmo('AS').projets).toBe(61987);
    expect(totalBmo('IDE').projets).toBe(36491);
    expect(totalBmo('MEDECIN').projets).toBe(8465);
    // 2. « Dans N des M départements… au moins 80 % » : parts telles qu'affichées.
    const parts = tableau.lignes.map((l) => partNumerique(l[COL.asPart])).filter((p): p is number => p !== null);
    expect(cles[1]).toContain(`Dans ${parts.filter((p) => p >= SEUIL_PART_DIFFICILE).length} des ${parts.length} départements`);
    // 3. Classement : les cinq plus fortes parts affichées parmi les lignes d'au moins SEUIL projets exacts.
    const eligibles = tableau.lignes
      .filter((l) => partNumerique(l[COL.asPart]) !== null && !l[COL.asProjets].startsWith('≥') && nombre(l[COL.asProjets]) >= SEUIL_CLASSEMENT_BMO)
      .sort((a, b) => partNumerique(b[COL.asPart])! - partNumerique(a[COL.asPart])! || nombre(b[COL.asProjets]) - nombre(a[COL.asProjets]))
      .slice(0, 5);
    expect(eligibles).toHaveLength(5);
    expect(cles[2].endsWith(`${enumerer(eligibles.map((l) => `${l[0]}, ${l[COL.asPart]}`))}.`)).toBe(true);
    // 4. EHPAD : somme de la colonne et trois premières lignes.
    expect(cles[3].replace(/\s/g, '')).toContain(`recense${somme(COL.ehpad)}EHPADdansces${tableau.lignes.length}départements`);
    const plus = [...tableau.lignes].sort((a, b) => nombre(b[COL.ehpad]) - nombre(a[COL.ehpad])).slice(0, 3);
    expect(cles[3].endsWith(`${enumerer(plus.map((l) => `${l[0]}, ${l[COL.ehpad]}`))}.`)).toBe(true);
  });

  it('dit ce que Jolene a calculé et ce que les astérisques du fichier impliquent', () => {
    const texte = textes(page).join(' ');
    expect(texte).not.toContain('n’a produit aucun');
    expect(texte).toContain('Jolene les a seulement additionnés par département');
    expect(texte).toContain('L’enquête est publiée par bassin d’emploi');
    expect(texte).toContain('le total du département est un minimum, noté « ≥ »');
    expect(texte).toContain('le total reste exact mais la part n’est pas calculée');
    expect(texte).toContain('un bassin qui n’a pas de ligne pour un métier est compté pour zéro');
    expect(page.description).toContain('d’infirmiers et sages-femmes');
  });

  it('se déclare comme jeu de données fondé sur les deux sources publiques', () => {
    const dataset = jsonLdPage(page).find((b) => b['@type'] === 'Dataset') as { isBasedOn: string[] };
    expect(dataset.isBasedOn).toEqual([
      'https://www.data.gouv.fr/datasets/enquete-besoins-en-main-doeuvre-bmo',
      'https://www.data.gouv.fr/datasets/finess-extraction-du-fichier-des-etablissements',
    ]);
    expect(page.sections!.some((s) => (s.sources ?? []).length === 2)).toBe(true);
  });

  it('se construit sur une table d\'essai sans part calculable', () => {
    const table: TableBmo = Object.fromEntries(CODES_DEPARTEMENTS.map((c) => [c, { AS: [300, null, 1] as [number, null, 1] }]));
    const p = metaBarometre(table);
    expect(p.sections![0].liste![1]).toContain('Dans 0 des 0 départements');
    expect(p.sections![1].tableau!.lignes[0].slice(1, 5)).toEqual([expect.stringMatching(/^≥ 300$/), NON_COMMUNIQUE, NON_COMMUNIQUE, NON_COMMUNIQUE]);
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

  it('ne cite que des professions qui ont une page métier, et y renvoie', () => {
    for (const t of TYPES_ETABLISSEMENT_SEO) {
      for (const valeur of t.professions) expect(PROFESSIONS_SEO.some((p) => p.valeur === valeur), `${t.slug} ${valeur}`).toBe(true);
      const liens = metaEtablissement(t).sections!.find((s) => s.titre === 'Les professions recherchées')!.liens!;
      expect(liens).toHaveLength(t.professions.length);
      for (const l of liens) expect(l.href).toMatch(/^\/metier\//);
    }
  });

  it('cite le nombre national FINESS seulement quand le type a une catégorie retenue', () => {
    expect(pages[0].intro.at(-1)).toMatch(/Le répertoire FINESS recense 7\s399 EHPAD en France/);
    // Clinique et hôpital public : aucune catégorie FINESS ne les compte honnêtement.
    expect(pages[1].intro.join(' ')).not.toContain('FINESS');
    expect(pages[2].intro.join(' ')).not.toContain('FINESS');
  });

  it('ne publie aucun pourcentage hors commission (15 % HT, 18 % TTC) et TVA (20 %)', () => {
    for (const p of pages) {
      for (const t of textes(p)) {
        for (const m of t.matchAll(/(\d+(?:[.,]\d+)?)\s?%/g)) expect(['15', '18', '20'], `${p.path} : ${t.slice(0, 80)}`).toContain(m[1]);
      }
    }
  });

  it('ne partage entre deux pages que les étapes et le renvoi communs (pas de pages satellites)', () => {
    const communs = new Set([...ETAPES_PUBLICATION, RENVOI_COMMUN, 'Les situations couvertes', 'Les professions recherchées', 'Publier une mission en trois étapes', 'Vérification, contrat, facturation et tarif', 'Quelles professions peut-on rechercher ?']);
    const vus = new Map<string, string>();
    for (const p of pages) {
      const propres = [p.title, p.description, p.h1, ...p.intro, ...p.sections!.flatMap((s) => [...(s.paragraphes ?? []), ...(s.liste ?? []), ...(s.points ?? []).flatMap((pt) => [pt.texte])]), ...p.faq!.flatMap((f) => [f.q, f.r])]
        .filter((t) => !communs.has(t));
      for (const t of propres) {
        expect(vus.get(t), `« ${t.slice(0, 60)} » sur ${p.path} et ${vus.get(t)}`).toBeUndefined();
        vus.set(t, p.path);
      }
      // Plus de 60 % du texte d'une page lui est propre.
      const longueur = (liste: string[]) => liste.join(' ').length;
      const tout = textes(p).filter((t) => !PROFESSIONS_SEO.some((m) => t === m.label));
      expect(longueur(propres) / longueur(tout), p.path).toBeGreaterThan(0.6);
    }
  });

  it('ne suggère pas d\'enchaîner des missions sur un poste permanent', () => {
    for (const p of pages) expect(textes(p).join(' '), p.path).not.toMatch(/poste vacant|succession de missions|en attendant l’arrivée d’un titulaire/i);
  });
});

describe('guides', () => {
  const pages = GUIDES_SEO.map(metaGuide);

  it('ont au moins quatre sections, trois questions et des dates de publication et de révision', () => {
    expect(GUIDES_SEO).toHaveLength(4);
    for (const g of GUIDES_SEO) {
      expect(g.sections.length, g.slug).toBeGreaterThanOrEqual(4);
      expect(g.faq.length, g.slug).toBeGreaterThanOrEqual(3);
      expect(g.publie, g.slug).toMatch(/^\d{4}-\d\d-\d\d$/);
      expect(g.maj >= g.publie, g.slug).toBe(true);
      expect(metaGuide(g).lastmod).toBe(g.maj);
      expect(metaGuide(g).intro.at(-1)).toBe(`Guide mis à jour le ${dateLongue(g.maj)}.`);
    }
    expect(resoudreGuide('absence-derniere-minute-remplacer-soignant')?.public).toBe('etablissement');
    expect(resoudreGuide('inconnu')).toBeNull();
  });

  it('ne citent que des sources officielles en https', () => {
    const sources = pages.flatMap((p) => p.sections!.flatMap((x) => x.sources ?? []));
    expect(sources.length).toBeGreaterThanOrEqual(4);
    for (const s of sources) expect(s.href).toMatch(/^https:\/\/([a-z-]+\.)?(service-public\.gouv\.fr|data\.gouv\.fr)\//);
  });

  it('insèrent les chiffres demandés avec leur source, après la première section', () => {
    const page = metaGuide(resoudreGuide('remplacement-aide-soignant-ehpad')!);
    expect(page.sections![1].titre).toBe('En chiffres');
    expect(page.sections![1].paragraphes!.join(' ')).toMatch(/déclarent (au moins )?61\s987 projets de recrutement d’aides-soignants pour 2026, en additionnant les valeurs publiées par bassin d’emploi/);
    expect(page.sections![1].paragraphes!.join(' ').includes('au moins')).toBe(totalBmo('AS').partiel);
    expect(page.sections![1].paragraphes!.join(' ')).toMatch(/7\s399 EHPAD en France/);
    expect(page.sections![1].sources).toHaveLength(2);
    expect(metaGuide(resoudreGuide('premiere-mission-de-remplacement')!).sections!.some((s) => s.titre === 'En chiffres')).toBe(false);
  });

  it('n\'écrivent aucun chiffre hors tarif publié : les seuls chiffres viennent des données sourcées', () => {
    for (const g of GUIDES_SEO) {
      const texte = [g.titre, g.description, ...g.resume, ...g.sections.flatMap((s) => [s.titre, ...(s.paragraphes ?? []), ...(s.liste ?? [])]), ...g.faq.flatMap((f) => [f.q, f.r])].join(' ')
        .replace(/15 % HT/g, '').replace(/18 % TTC/g, '').replace(/TVA de 20 %/g, '').replace(/chiffres publics de 2026/g, '');
      expect(texte.match(/\d[\d\s.,]*\s?(%|€)?/g) ?? [], g.slug).toEqual([]);
    }
  });

  it('ne parlent ni d\'intérim ni de prix d\'exemple, et ne comparent Jolene à aucun autre prestataire', () => {
    for (const p of [...pages, metaGuides()]) {
      const texte = textes(p).join(' ');
      expect(texte, p.path).not.toMatch(/intérim|agence|travail temporaire|€|compar/i);
    }
  });

  it('vouvoient, ne promettent ni volume ni délai, et n\'énoncent pas de généralité chiffrable', () => {
    for (const p of [...pages, ...TYPES_ETABLISSEMENT_SEO.map(metaEtablissement), metaBarometre(), metaGuides()]) {
      // « La mission est visible immédiatement » est un fait du produit, déjà publié sur /recruter-soignants : retiré avant contrôle.
      const texte = textes(p).join(' ').replace(/visible immédiatement/g, '');
      // Limites de mot Unicode : en JavaScript, \b coupe « été » ou « qualité » après le « t ».
      expect(texte, p.path).not.toMatch(/(?<!\p{L})(tu|ton|ta|tes|toi)(?!\p{L})/iu);
      expect(texte, p.path).not.toMatch(/centaines|milliers|immédiat|aussitôt|en quelques (secondes|minutes|heures)|en moins de|garanti[es]? |dès aujourd/i);
      expect(texte, p.path).not.toMatch(/\b(fréquents?|fréquemment|souvent|nombreux|nombreuses|la plupart des (établissements|soignants)|toujours|jamais)\b/i);
    }
  });

  it('se déclarent comme Article daté, avec fil d\'Ariane et FAQ', () => {
    const page = metaGuide(GUIDES_SEO[0]);
    expect(jsonLdPage(page).map((b) => b['@type'])).toEqual(['Article', 'BreadcrumbList', 'FAQPage']);
    const article = jsonLdPage(page)[0] as { datePublished: string; dateModified: string; mainEntityOfPage: string };
    expect(article.datePublished).toBe(GUIDES_SEO[0].publie);
    expect(article.dateModified).toBe(GUIDES_SEO[0].maj);
    expect(article.mainEntityOfPage).toBe(`https://jolene.app${page.path}`);
  });

  it('le sommaire liste chaque guide une fois, par public', () => {
    const hrefs = metaGuides().sections!.flatMap((s) => (s.points ?? []).map((p) => p.href));
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
      const liens = [
        ...p.liens.map((l) => l.href), ...(p.filAriane ?? []).map((l) => l.href),
        ...(p.sections ?? []).flatMap((s) => [...(s.points ?? []).flatMap((pt) => (pt.href ? [pt.href] : [])), ...(s.liens ?? []).map((l) => l.href)]),
      ];
      for (const href of liens) expect(chemins.has(href) || application.has(href), `${p.path} → ${href}`).toBe(true);
    }
  });

  it('chaque nouvelle page est liée depuis l\'accueil ou un pilier', () => {
    const depuis = new Set(toutes.filter((p) => ['accueil', 'recruter', 'devenir', 'guides'].includes(p.type)).flatMap((p) => [...p.liens.map((l) => l.href), ...(p.sections ?? []).flatMap((s) => (s.points ?? []).map((pt) => pt.href))]));
    for (const p of nouvelles) expect(depuis.has(p.path), p.path).toBe(true);
  });
});
