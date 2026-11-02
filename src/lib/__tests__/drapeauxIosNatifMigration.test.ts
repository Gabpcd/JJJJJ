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
];
const ECRANS_LOT5 = ['accueil', 'missions', 'publier', 'presences', 'messages', 'compte'].map(
  (ecran) => `etab_${ecran}`,
);

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

const sansCommentaires = (sql: string) =>
  sql
    .split('\n')
    .filter((ligne) => !ligne.trimStart().startsWith('--'))
    .join('\n');

// Découpe la liste VALUES(...) en champs, en respectant les littéraux SQL
// ('' = apostrophe échappée). Les littéraux sont rendus décodés, sans guillemets.
function decouperValeurs(valeurs: string): string[] {
  const champs: string[] = [];
  let courant = '';
  let dansLitteral = false;
  for (let i = 0; i < valeurs.length; i += 1) {
    const c = valeurs[i];
    if (dansLitteral) {
      if (c === "'" && valeurs[i + 1] === "'") {
        courant += "'";
        i += 1;
      } else if (c === "'") {
        dansLitteral = false;
      } else {
        courant += c;
      }
    } else if (c === "'") {
      dansLitteral = true;
    } else if (c === ',') {
      champs.push(courant.trim());
      courant = '';
    } else {
      courant += c;
    }
  }
  expect(dansLitteral, `littéral non fermé dans ${valeurs}`).toBe(false);
  champs.push(courant.trim());
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

  it('D-FLAGS pose 3 clés lot 2, 11 clés lot 4 et 6 clés lot 5 ios_natif_etab_*, dans cet ordre', () => {
    const cles = insertions(fichiersLots245[0]).map((i) => i.champs[0]);
    expect(cles).toEqual([...ECRANS_LOT2, ...ECRANS_LOT4, ...ECRANS_LOT5].map(cle));
    expect(cles).toHaveLength(20);
    expect(cles.filter((c) => c.startsWith('ios_natif_etab_'))).toHaveLength(6);
  });

  it('25 drapeaux distincts au total, libellés distincts', () => {
    const cles = toutesInsertions.map((i) => i.champs[0]);
    expect(cles).toHaveLength(25);
    expect(new Set(cles).size).toBe(25);
    expect(new Set(toutesInsertions.map((i) => i.champs[2])).size).toBe(25);
    expect(new Set(cles)).toEqual(
      new Set([...ECRANS_LOT1, ...ECRANS_LOT2, ...ECRANS_LOT4, ...ECRANS_LOT5].map(cle)),
    );
  });
});
