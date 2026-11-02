import { readdirSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Coupe-circuits par écran de l'app iOS native (décision 9 du lot 0,
// docs/mobile-swift/DECISIONS_LOT0.md) : lignes `ios_natif_<ecran>_actif` de
// public.parametres_systeme, lues par l'app via fn_param_bool après ouverture de
// session (défaut fail-open côté Swift).
// - B0 (lot 1) : 20261102150000_drapeaux_ios_natif.sql, 5 onglets du socle.
// - D-FLAGS (lots 2, 4, 5) : <version>_drapeaux_ios_natif_lots_2_4_5.sql.
// Toutes les insertions suivent le gabarit B0 : mêmes colonnes, valeur 1, bornes
// 0/1, catégorie OPERATIONS (seule visible dans AdminConfig), cablee true,
// ON CONFLICT (cle) DO NOTHING — jamais DO UPDATE, sinon un rejeu réarmerait un
// écran coupé en urgence par l'administrateur.

const DOSSIER = 'supabase/migrations';
const FICHIER_B0 = '20261102150000_drapeaux_ios_natif.sql';
const SUFFIXE_LOTS_2_4_5 = '_drapeaux_ios_natif_lots_2_4_5.sql';

const ECRANS_LOT1 = ['accueil', 'explorer', 'missions', 'revenus', 'profil'];
const ECRANS_LOT2 = ['presences', 'documents', 'contrats'];
const ECRANS_LOT4 = [
  'swipe',
  'recherches',
  'disponibilites',
  'parrainage',
  'litiges',
  'reclamations',
  'messagerie',
  'bulletins',
  'evaluations',
  'score',
  'pool_urgence',
  'exclusions',
  'serie',
];
const ECRANS_LOT5 = [
  'accueil',
  'missions',
  'publier',
  'presences',
  'pointage',
  'messages',
  'compte',
].map((ecran) => `etab_${ecran}`);

const cle = (ecran: string) => `ios_natif_${ecran}_actif`;

const COLONNES = [
  'cle',
  'valeur',
  'label',
  'description',
  'unite',
  'val_min',
  'val_max',
  'categorie',
  'avertissement',
  'cablee',
];

const AVERTISSEMENT =
  "Coupe-circuit : passez à 0 uniquement si l'écran natif est cassé. Lu par l'app à l'ouverture de session et au retour au premier plan.";

type Insertion = {
  fichier: string;
  colonnes: string[];
  champs: string[];
};

const lire = (fichier: string) => readFileSync(`${DOSSIER}/${fichier}`, 'utf8');

// Retire les commentaires SQL `-- …` (en début comme en fin de ligne) et
// `/* … */` (imbriqués, comme Postgres), sans toucher aux littéraux '…' ni aux
// identifiants "…" : une clé commentée n'est jamais comptée comme posée.
// Appelée sur toutes les migrations (détection des fichiers de drapeaux) : elle
// ne lève jamais ; un littéral non fermé est rendu tel quel jusqu'à la fin, et la
// garde « rien d'autre que les INSERT du gabarit » le rejette dans un fichier de
// drapeaux.
function sansCommentaires(sql: string): string {
  let sortie = '';
  let i = 0;
  while (i < sql.length) {
    const c = sql[i];
    if (c === "'" || c === '"') {
      let fin = i + 1;
      while (fin < sql.length) {
        if (sql[fin] === c && sql[fin + 1] === c) fin += 2;
        else if (sql[fin] === c) break;
        else fin += 1;
      }
      sortie += sql.slice(i, fin + 1);
      i = fin + 1;
    } else if (c === '-' && sql[i + 1] === '-') {
      while (i < sql.length && sql[i] !== '\n') i += 1;
    } else if (c === '/' && sql[i + 1] === '*') {
      let profondeur = 1;
      i += 2;
      while (i < sql.length && profondeur > 0) {
        if (sql[i] === '/' && sql[i + 1] === '*') {
          profondeur += 1;
          i += 2;
        } else if (sql[i] === '*' && sql[i + 1] === '/') {
          profondeur -= 1;
          i += 2;
        } else {
          i += 1;
        }
      }
      sortie += ' ';
    } else {
      sortie += c;
      i += 1;
    }
  }
  return sortie;
}

// Découpe la liste VALUES(...) en champs, en respectant les littéraux SQL
// ('' = apostrophe échappée). Les littéraux sont rendus décodés, sans guillemets.
// Chaque champ est soit un littéral seul, soit un jeton nu (nombre, true, false) :
// aucune expression, aucun appel ni aucun `;` ne peut se glisser dans VALUES(...).
function decouperValeurs(valeurs: string): string[] {
  const champs: string[] = [];
  let litteral = '';
  let nu = '';
  let nbLitteraux = 0;
  let dansLitteral = false;
  const clore = () => {
    const forme = nbLitteraux === 0 ? /^\s*(\d+|true|false)\s*$/ : /^\s*$/;
    expect(nbLitteraux <= 1 && forme.test(nu), `champ hors gabarit dans VALUES : ${nu}`).toBe(true);
    champs.push(nbLitteraux === 0 ? nu.trim() : litteral);
    litteral = '';
    nu = '';
    nbLitteraux = 0;
  };
  for (let i = 0; i < valeurs.length; i += 1) {
    const c = valeurs[i];
    if (dansLitteral) {
      if (c === "'" && valeurs[i + 1] === "'") {
        litteral += "'";
        i += 1;
      } else if (c === "'") {
        dansLitteral = false;
      } else {
        litteral += c;
      }
    } else if (c === "'") {
      dansLitteral = true;
      nbLitteraux += 1;
    } else if (c === ',') {
      clore();
    } else {
      nu += c;
    }
  }
  expect(dansLitteral, `littéral non fermé dans ${valeurs}`).toBe(false);
  clore();
  return champs;
}

const INSERTION =
  /INSERT INTO public\.parametres_systeme\s*\(([^)]*)\)\s*VALUES\s*\(([\s\S]*?)\)\s*ON CONFLICT\s*\(cle\)\s*DO NOTHING\s*;/g;

function insertions(fichier: string): Insertion[] {
  const sql = sansCommentaires(lire(fichier));
  return [...sql.matchAll(INSERTION)].map((m) => ({
    fichier,
    colonnes: m[1].split(',').map((colonne) => colonne.trim()),
    champs: decouperValeurs(m[2]),
  }));
}

const fichiers = readdirSync(DOSSIER)
  .filter((fichier) => fichier.endsWith('.sql'))
  .sort();
const fichiersDrapeaux = fichiers.filter((fichier) =>
  sansCommentaires(lire(fichier)).includes("'ios_natif_"),
);
const toutesInsertions = fichiersDrapeaux.flatMap(insertions);
const fichiersLots245 = fichiers.filter((fichier) => fichier.endsWith(SUFFIXE_LOTS_2_4_5));

describe('drapeaux ios_natif_* de l’app iOS native', () => {
  it('la migration B0 et la migration D-FLAGS des lots 2, 4 et 5 sont les seules à poser des drapeaux', () => {
    expect(fichiersLots245).toHaveLength(1);
    expect(fichiersDrapeaux).toEqual([FICHIER_B0, fichiersLots245[0]]);
  });

  it('la migration D-FLAGS est au format 14 chiffres et postérieure à B0', () => {
    const [nom] = fichiersLots245;
    expect(nom).toMatch(/^\d{14}_drapeaux_ios_natif_lots_2_4_5\.sql$/);
    expect(nom.slice(0, 14) > FICHIER_B0.slice(0, 14)).toBe(true);
  });

  it('chaque drapeau est un INSERT idempotent ON CONFLICT (cle) DO NOTHING, sans autre instruction', () => {
    for (const fichier of fichiersDrapeaux) {
      const sql = sansCommentaires(lire(fichier));
      const nbCles = sql.match(/'ios_natif_/g)?.length ?? 0;
      expect(insertions(fichier), `${fichier} : toute clé passe par le gabarit`).toHaveLength(nbCles);
      expect(
        sql.replace(INSERTION, '').trim(),
        `${fichier} : hors commentaires, rien d'autre que les INSERT du gabarit`,
      ).toBe('');
      expect(sql, `${fichier} : pas de BEGIN/COMMIT`).not.toMatch(/^\s*(BEGIN|COMMIT)\s*;/im);
      expect(sql, `${fichier} : pas de dollar-quoting`).not.toMatch(/\$\$|\$[a-z_]+\$/i);
      expect(sql, `${fichier} : aucun GRANT`).not.toMatch(/\bGRANT\b/i);
      expect(sql, `${fichier} : jamais DO UPDATE`).not.toMatch(/DO\s+UPDATE/i);
      expect(sql, `${fichier} : données seulement, aucun DDL ni écrasement`).not.toMatch(
        /\b(DROP|TRUNCATE|DELETE|ALTER|CREATE|UPDATE)\b/i,
      );
    }
  });

  it('chaque ligne suit le gabarit B0 : colonnes, valeur 1, booléen 0/1, OPERATIONS, cablee true', () => {
    expect(toutesInsertions.length).toBeGreaterThan(0);
    for (const { fichier, colonnes, champs } of toutesInsertions) {
      const [cleLue, valeur, label, description, unite, valMin, valMax, categorie, avertissement, cablee] =
        champs;
      const contexte = `${fichier} : ${cleLue}`;
      expect(colonnes, contexte).toEqual(COLONNES);
      expect(champs, contexte).toHaveLength(COLONNES.length);
      expect(cleLue, contexte).toMatch(/^ios_natif_[a-z_]+_actif$/);
      expect([valeur, unite, valMin, valMax, categorie, cablee], contexte).toEqual([
        '1',
        'booléen',
        '0',
        '1',
        'OPERATIONS',
        'true',
      ]);
      expect(label, contexte).toMatch(/^App iOS — écran \S.* actif$/);
      expect(description, contexte).toMatch(
        /^Autorise l'écran natif \S.* de l'application iOS\. À 0, l'app affiche un renvoi vers la version web à la place de cet écran\.$/,
      );
      expect(avertissement, contexte).toBe(AVERTISSEMENT);
      for (const texte of [label, description, avertissement]) {
        expect(texte, `${contexte} : vouvoiement`).not.toMatch(
          /(?<!\p{L})(tu|toi|ton|ta|tes)(?!\p{L})/iu,
        );
      }
    }
  });

  it('B0 garde ses cinq onglets du socle, inchangés', () => {
    expect(insertions(FICHIER_B0).map((i) => i.champs[0])).toEqual(ECRANS_LOT1.map(cle));
  });

  // Blueprints v2 : LOT4_PLAN.md B0-bis et D18 (13 clés, dont exclusions et serie),
  // LOT5_PLAN.md B5a et D14 (7 clés ios_natif_etab_*, dont pointage : coupe-circuit
  // du polling 5 s du code rotatif côté établissement).
  it('D-FLAGS pose 3 clés lot 2, 13 clés lot 4 et 7 clés lot 5 ios_natif_etab_*, dans cet ordre', () => {
    const cles = insertions(fichiersLots245[0]).map((i) => i.champs[0]);
    expect(cles).toEqual([...ECRANS_LOT2, ...ECRANS_LOT4, ...ECRANS_LOT5].map(cle));
    expect(cles).toHaveLength(23);
    expect(cles.filter((c) => c.startsWith('ios_natif_etab_'))).toHaveLength(7);
    expect(cles).toEqual(expect.arrayContaining(['exclusions', 'serie', 'etab_pointage'].map(cle)));
  });

  it('28 drapeaux distincts au total, libellés et descriptions distincts', () => {
    const cles = toutesInsertions.map((i) => i.champs[0]);
    expect(cles).toHaveLength(28);
    expect(new Set(cles).size).toBe(28);
    expect(new Set(toutesInsertions.map((i) => i.champs[2])).size).toBe(28);
    expect(new Set(toutesInsertions.map((i) => i.champs[3])).size).toBe(28);
    expect(new Set(cles)).toEqual(
      new Set([...ECRANS_LOT1, ...ECRANS_LOT2, ...ECRANS_LOT4, ...ECRANS_LOT5].map(cle)),
    );
  });

  // Un écran natif = un drapeau : la description d'un drapeau ne revendique pas
  // la surface d'un autre (LOT5_PLAN.md v2 : etab-pointage-screen distinct des
  // présences ; LOT4_PLAN.md v2 T11 : /soignant/exclusions distinct du pool).
  it('une surface par drapeau : pointage hors Présences établissement, exclusions hors Pool urgence', () => {
    const description = (ecran: string) =>
      toutesInsertions.find((i) => i.champs[0] === cle(ecran))?.champs[3] ?? '';
    expect(description('etab_pointage')).toMatch(/code de pointage/);
    expect(description('etab_presences')).not.toMatch(/pointage/i);
    expect(description('exclusions')).toMatch(/exclu/i);
    expect(description('pool_urgence')).not.toMatch(/exclu/i);
  });

  it('les commentaires -- et /* */ ne comptent jamais comme instruction ni comme clé', () => {
    const sql = [
      "/* INSERT INTO public.parametres_systeme(cle) VALUES('ios_natif_x_actif') ON CONFLICT (cle) DO NOTHING; */",
      "SELECT 'a--b', '/* c */'; -- 'ios_natif_y_actif'",
      '/* externe /* imbriqué */ toujours commentaire */',
    ].join('\n');
    const nettoye = sansCommentaires(sql);
    expect(nettoye).not.toContain('ios_natif_');
    expect(nettoye.replace(/\s+/g, ' ').trim()).toBe("SELECT 'a--b', '/* c */';");
  });

  it('VALUES(...) n’admet que des littéraux et des jetons nus', () => {
    expect(decouperValeurs("'a''b', 1, true")).toEqual(["a'b", '1', 'true']);
    expect(() => decouperValeurs("'a', pg_sleep(1)")).toThrow();
    expect(() => decouperValeurs("'a' || 'b', 1")).toThrow();
    expect(() => decouperValeurs("1); DELETE FROM t; SELECT (1")).toThrow();
  });
});
