#!/usr/bin/env node
/**
 * Garde des littéraux juridiques du Swift livré (lot 5, tranche T0, `docs/mobile-swift/LOT5_PLAN.md`
 * §2.9 « Zéro règle juridique en dur », HARD STOP n°4 de CLAUDE.md).
 *
 * Échoue si un littéral de chaîne d'un fichier Swift livré (`ios-native/**\/*.swift` hors cibles de
 * test, commentaires exclus) contient une valeur juridique tirée du dépôt — jamais d'une liste figée :
 *   - égalité exacte, sensible à la casse, avec une valeur des CHECK de `matrice_modes_exercice`
 *     (`supabase/schema/public.sql` : catégories, niveaux, forces de source) — une sous-chaîne
 *     rougirait `est_secteur_public` ;
 *   - sous-chaîne d'une `source_url`, `source_url_complementaire` ou `source_libelle` de la matrice,
 *     lues dans toutes les migrations qui l'écrivent (`supabase/migrations/*.sql` contenant
 *     `matrice_modes_exercice`) et dans les `'source_libelle', '…'` du dump (la base n'est pas
 *     lisible depuis le job « Cœur ») ;
 *   - sous-chaîne `fn_mode_exercice`, `matrice_modes_exercice`, `notations_missions`,
 *     `evaluations_publiees` ;
 *   - `Légifrance`, `Code du travail` (casse ignorée), `art.` ou `article` suivi d'un numéro.
 * Exceptions exactes (`EXCEPTIONS`) : `Legal/TextesWeb.swift` (TL du lot 2, textes verbatim gardés
 * par `tests/node/textes-juridiques-ios.node.mjs`) et la constante `RPCResponse.marqueurCodeDuTravail`
 * (lot 1). Les cibles de test (dossiers `*Tests`) rejouent verbatim des refus serveur et des textes de
 * TextesWeb : elles ne sont pas livrées et ne sont pas lues (DECISIONS_LOT5.md).
 *
 * Usage : node scripts/mobile/check-litteraux-juridiques.mjs   # code 1 si un littéral est interdit
 * Test  : node --test scripts/mobile/check-litteraux-juridiques.test.mjs
 * Aucune valeur secrète n'est lue : le script ne lit que des fichiers du dépôt.
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const SCHEMA = 'supabase/schema/public.sql';
export const MIGRATIONS = 'supabase/migrations';
export const RACINE_SWIFT = 'ios-native';

/** Seules exceptions admises (LOT5_PLAN §2.9). */
export const EXCEPTIONS = Object.freeze([
  Object.freeze({
    fichier: 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Legal/TextesWeb.swift',
    motif: 'textes verbatim du web (TL du lot 2), gardés par tests/node/textes-juridiques-ios.node.mjs',
  }),
  Object.freeze({
    fichier: 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/RPC/RPCResponse.swift',
    constante: 'marqueurCodeDuTravail',
    valeur: '[CODE DU TRAVAIL]',
    motif: 'préfixe des refus serveur du Code du travail (lot 1)',
  }),
]);

const NOMS_INTERDITS = ['fn_mode_exercice', 'matrice_modes_exercice', 'notations_missions', 'evaluations_publiees'];
const MOTIFS_INTERDITS = [
  { nom: 'Légifrance', re: /l[ée]gifrance/i },
  { nom: 'Code du travail', re: /code du travail/i },
  { nom: 'un article numéroté', re: /\bart(?:icle|\.)\s*L?\.?\s*\d/i },
];

// ---------------------------------------------------------------------------------------------
// SQL (dump et migrations)
// ---------------------------------------------------------------------------------------------

const decoderSql = brut => brut.replaceAll("''", "'");
const litterauxSql = fragment => [...fragment.matchAll(/'((?:[^']|'')*)'/g)].map(m => decoderSql(m[1]));

/** Instructions SQL d'un fichier (découpe sur `;` hors chaînes, commentaires et corps `$tag$`). */
function instructionsSql(texte) {
  const instructions = [];
  let courant = '';
  for (let i = 0; i < texte.length; i++) {
    const c = texte[i];
    if (c === '-' && texte[i + 1] === '-') { const fin = texte.indexOf('\n', i); i = fin < 0 ? texte.length : fin; courant += '\n'; continue; }
    if (c === '/' && texte[i + 1] === '*') { const fin = texte.indexOf('*/', i + 2); i = fin < 0 ? texte.length : fin + 1; continue; }
    if (c === '$') {
      const tag = /^\$[A-Za-z_]*\$/.exec(texte.slice(i, i + 64));
      if (tag) {
        const fin = texte.indexOf(tag[0], i + tag[0].length);
        const bout = fin < 0 ? texte.length : fin + tag[0].length;
        courant += texte.slice(i, bout);
        i = bout - 1;
        continue;
      }
    }
    if (c === "'") {
      let j = i + 1;
      while (j < texte.length && !(texte[j] === "'" && texte[j + 1] !== "'")) j += texte[j] === "'" ? 2 : 1;
      courant += texte.slice(i, j + 1);
      i = j;
      continue;
    }
    if (c === ';') { instructions.push(courant.trim()); courant = ''; continue; }
    courant += c;
  }
  if (courant.trim()) instructions.push(courant.trim());
  return instructions;
}

const PAIRE_SOURCE = /'source_(?:libelle|url|url_complementaire)'\s*,\s*'((?:[^']|'')*)'/g;
const estLibelleOuUrl = v => /^https?:\/\//.test(v) || (v.length >= 20 && /\s/.test(v));

/**
 * Sources de la matrice écrites par un fichier SQL : littéraux des `INSERT INTO`/`UPDATE` de
 * `matrice_modes_exercice` qui sont des URL ou des libellés (les codes courts d'un `WHERE` ou d'un
 * `unnest(ARRAY[...])` ne le sont pas), et valeurs des paires `'source_…', '…'` (repli de
 * `fn_mode_exercice`).
 */
export function sourcesMatrice(texte) {
  const valeurs = [];
  for (const instruction of instructionsSql(texte)) {
    if (!/^(?:INSERT\s+INTO|UPDATE)\s+(?:public\.)?matrice_modes_exercice\b/i.test(instruction)) continue;
    valeurs.push(...litterauxSql(instruction).filter(estLibelleOuUrl));
  }
  for (const m of texte.matchAll(PAIRE_SOURCE)) valeurs.push(decoderSql(m[1]));
  return valeurs;
}

/** Valeurs des CHECK de `matrice_modes_exercice` dans le dump. */
export function valeursCheckMatrice(schemaSource) {
  const debut = schemaSource.indexOf('CREATE TABLE IF NOT EXISTS "public"."matrice_modes_exercice" (');
  if (debut < 0) throw new Error('matrice_modes_exercice absente de public.sql.');
  const bloc = schemaSource.slice(debut, schemaSource.indexOf('\n);', debut));
  const valeurs = bloc.split('\n').filter(l => /CONSTRAINT "matrice_modes_exercice_\w+_check" CHECK/.test(l)).flatMap(litterauxSql);
  if (valeurs.length === 0) throw new Error('CHECK de matrice_modes_exercice illisibles dans public.sql.');
  return [...new Set(valeurs)];
}

/** Migrations qui écrivent ou lisent la matrice (`git grep -l matrice_modes_exercice`). */
export function migrationsMatrice(racine = ROOT) {
  const dossier = join(racine, MIGRATIONS);
  return readdirSync(dossier).filter(n => n.endsWith('.sql')).sort()
    .map(n => ({ chemin: `${MIGRATIONS}/${n}`, contenu: readFileSync(join(dossier, n), 'utf8') }))
    .filter(m => m.contenu.includes('matrice_modes_exercice'));
}

/** Valeurs interdites : `exactes` (CHECK), `sousChaines` (noms, sources), `motifs` (expressions). */
export function valeursInterdites({ schemaSource, migrations }) {
  const sources = [...migrations.flatMap(m => sourcesMatrice(m.contenu)), ...sourcesMatrice(schemaSource)];
  return {
    exactes: valeursCheckMatrice(schemaSource),
    sousChaines: [...new Set([...NOMS_INTERDITS, ...sources])],
    motifs: MOTIFS_INTERDITS,
  };
}

// ---------------------------------------------------------------------------------------------
// Swift
// ---------------------------------------------------------------------------------------------

const ECHAPPEMENTS = { n: '\n', t: '\t', r: '\r', 0: '\0', '"': '"', "'": "'", '\\': '\\' };

/** Fin (indice du `)` fermant) d'une interpolation `\(` commencée à `i` (indice après `(`). */
function finInterpolation(src, i) {
  let profondeur = 1;
  for (; i < src.length; i++) {
    const c = src[i];
    if (c === '"') { i++; while (i < src.length && src[i] !== '"') i += src[i] === '\\' ? 2 : 1; continue; }
    if (c === '(') profondeur++;
    if (c === ')' && --profondeur === 0) return i;
  }
  return src.length;
}

/**
 * Littéraux de chaîne d'un source Swift, commentaires exclus (`//`, `///`, blocs imbriqués) :
 * chaînes simples (échappements décodés, interpolations recopiées), multilignes `"""` et brutes
 * `#"…"#`. Chaque littéral porte la ligne de son guillemet ouvrant.
 */
export function litterauxSwift(src) {
  const sortie = [];
  let ligne = 1;
  const avancer = (de, a) => { for (let k = de; k < a; k++) if (src[k] === '\n') ligne++; };
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === '\n') { ligne++; continue; }
    if (c === '/' && src[i + 1] === '/') { while (i < src.length && src[i] !== '\n') i++; i--; continue; }
    if (c === '/' && src[i + 1] === '*') {
      let profondeur = 1;
      let j = i + 2;
      for (; j < src.length && profondeur > 0; j++) {
        if (src[j] === '/' && src[j + 1] === '*') { profondeur++; j++; } else if (src[j] === '*' && src[j + 1] === '/') { profondeur--; j++; }
      }
      avancer(i, j);
      i = j - 1;
      continue;
    }
    const brut = /^(#+)("""|")/.exec(src.slice(i, i + 16));
    if (brut || c === '"') {
      const dieses = brut ? brut[1] : '';
      const multi = (brut ? brut[2] : src.slice(i, i + 3) === '"""' ? '"""' : '"') === '"""';
      const ouverture = dieses + (multi ? '"""' : '"');
      const fermeture = (multi ? '"""' : '"') + dieses;
      const debutLigne = ligne;
      let j = i + ouverture.length;
      let valeur = '';
      while (j < src.length && src.slice(j, j + fermeture.length) !== fermeture) {
        const d = src[j];
        if (!multi && d === '\n') break;
        if (d === '\\' && !dieses) {
          const e = src[j + 1];
          if (e === '(') { const fin = finInterpolation(src, j + 2); valeur += src.slice(j, fin + 1); j = fin + 1; continue; }
          if (e === 'u' && src[j + 2] === '{') { const fin = src.indexOf('}', j); valeur += String.fromCodePoint(parseInt(src.slice(j + 3, fin), 16)); j = fin + 1; continue; }
          valeur += ECHAPPEMENTS[e] ?? e;
          j += 2;
          continue;
        }
        valeur += d;
        j++;
      }
      if (multi) valeur = valeur.replace(/^\n/, '');
      sortie.push({ valeur, ligne: debutLigne });
      avancer(i, j);
      i = j + fermeture.length - 1;
      continue;
    }
  }
  return sortie;
}

/** Fichier Swift livré : sous `ios-native/`, hors dossiers `*Tests`, `.build` et dossiers cachés. */
export function estLivre(chemin) {
  if (!chemin.startsWith(`${RACINE_SWIFT}/`) || !chemin.endsWith('.swift')) return false;
  const dossiers = chemin.split('/').slice(0, -1);
  return !dossiers.some(d => d.endsWith('Tests') || d.startsWith('.') || d === 'DerivedData');
}

/** Raison de l'interdiction d'un littéral, ou `null`. */
function raison(valeur, interdits) {
  if (interdits.exactes.includes(valeur)) return `la valeur CHECK « ${valeur} » de matrice_modes_exercice`;
  const sous = interdits.sousChaines.find(s => valeur.includes(s));
  if (sous) return `« ${sous.length > 60 ? `${sous.slice(0, 57)}…` : sous} » (matrice des modes d'exercice ou lecture interdite)`;
  const motif = interdits.motifs.find(m => m.re.test(valeur));
  return motif ? motif.nom : null;
}

/** Littéraux interdits des fichiers Swift livrés, une faute par littéral. */
export function fautesLitteraux({ fichiers, interdits }) {
  const fautes = [];
  for (const { chemin, contenu } of fichiers) {
    if (!estLivre(chemin)) continue;
    const exceptions = EXCEPTIONS.filter(e => e.fichier === chemin);
    if (exceptions.some(e => !e.constante)) continue;
    const lignes = contenu.split('\n');
    for (const { valeur, ligne } of litterauxSwift(contenu)) {
      const admis = exceptions.some(e => e.valeur === valeur && new RegExp(`\\b${e.constante}\\s*=`).test(lignes[ligne - 1] ?? ''));
      if (admis) continue;
      const pourquoi = raison(valeur, interdits);
      if (pourquoi) {
        fautes.push(`${chemin}:${ligne} : littéral « ${valeur.length > 80 ? `${valeur.slice(0, 77)}…` : valeur} » contient ${pourquoi} `
          + '(LOT5_PLAN §2.9 : texte juridique → Legal/TextesWeb.swift, règle juridique → serveur)');
      }
    }
  }
  return fautes;
}

function fichiersSwift(racine, relatif) {
  const plein = join(racine, relatif);
  if (!existsSync(plein)) return [];
  if (!statSync(plein).isDirectory()) return relatif.endsWith('.swift') ? [relatif] : [];
  return readdirSync(plein)
    .filter(n => !n.startsWith('.') && n !== 'DerivedData' && n !== 'node_modules')
    .flatMap(n => fichiersSwift(racine, `${relatif}/${n}`));
}

export function main(argv = process.argv.slice(2), racine = ROOT) {
  const interdits = valeursInterdites({
    schemaSource: readFileSync(join(racine, SCHEMA), 'utf8'),
    migrations: migrationsMatrice(racine),
  });
  const chemins = fichiersSwift(racine, RACINE_SWIFT).filter(estLivre);
  const fichiers = chemins.map(chemin => ({ chemin, contenu: readFileSync(join(racine, chemin), 'utf8') }));
  const fautes = fautesLitteraux({ fichiers, interdits });
  if (fautes.length) {
    for (const f of fautes) console.error(`✗ ${f}`);
    return 1;
  }
  if (!argv.includes('--silencieux')) {
    console.log(`✓ ${chemins.length} fichiers Swift livrés sans littéral juridique `
      + `(${interdits.exactes.length} valeurs CHECK, ${interdits.sousChaines.length} sources et noms, ${interdits.motifs.length} motifs).`);
  }
  return 0;
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  process.exit(main());
}
