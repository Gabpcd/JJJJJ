#!/usr/bin/env node
/**
 * Compte les établissements du répertoire FINESS par catégorie, pour les villes de
 * `src/lib/seo-data.ts`, par département et pour la France entière, puis écrit
 * `src/lib/seo-finess.json`. Ces chiffres rendent chaque page locale différente des
 * autres (pages ville, ville × métier, baromètre) sans rien inventer.
 *
 * Source : réexposition officielle FINESS sur data.gouv.fr (Licence Ouverte), le même
 * fichier que `supabase/functions/import-finess`. Le fichier est lu en flux ; rien
 * n'est enregistré sur le disque à part le JSON de sortie (des comptes, aucune donnée
 * nominative).
 *
 * Date affichée au public : celle de l'extraction FINESS elle-même (colonne
 * `datemaj_geoloc`, identique sur la quasi-totalité des lignes), et non la date de
 * publication du fichier ni celle du jour. Au 20/11/2026 : fichier publié le
 * 02/07/2026, extraction du 04/05/2026 (la plus récente du jeu officiel « FINESS
 * Extraction du Fichier des établissements »). La réexposition est archivée sur
 * data.gouv.fr : au prochain rafraîchissement, lire l'extraction officielle.
 *
 * Une catégorie est choisie par son CODE FINESS et son libellé est contrôlé : si le
 * ministère renumérote une catégorie, le script échoue au lieu de compter autre chose.
 *
 * Usage : node scripts/seo/extraire-finess.mjs            (écrit le JSON)
 *         node scripts/seo/extraire-finess.mjs --verifier (compare au JSON versionné, n'écrit rien)
 */
import { build } from 'esbuild';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const FICHIER_FINESS = 'https://data-pipeline-open.s3.sbg.io.cloud.ovh.net/finess/finess_etablissements.csv';
export const PAGE_SOURCE = 'https://www.data.gouv.fr/datasets/reexposition-des-donnees-finess';
const SORTIE = path.join(RACINE, 'src', 'lib', 'seo-finess.json');

/** Ordre des colonnes du JSON. `codes` : catégories FINESS (categetab) ; `libelle` : contrôle du libellé officiel. */
export const CATEGORIES = [
  { cle: 'ehpad', codes: { 500: /hébergement pour personnes âgées dépendantes/i } },
  { cle: 'hopital', codes: { 355: /^Centre Hospitalier \(C\.H\.\)$/, 101: /^Centre Hospitalier Régional/, 106: /ex Hôpital local/i } },
  { cle: 'ssiad', codes: { 354: /Soins Infirmiers A Domicile/i } },
  { cle: 'had', codes: { 127: /^Hospitalisation à Domicile$/i } },
  { cle: 'masfam', codes: { 255: /Maison d'Accueil Spécialisée/i, 437: /Foyer d'Accueil Médicalisé/i, 448: /Médicalisé en tout ou partie/i } },
  { cle: 'ime', codes: { 183: /Institut Médico-Educatif/i } },
  { cle: 'centreSante', codes: { 124: /^Centre de Santé$/i } },
];

/** Départements d'outre-mer : code FINESS → code INSEE (celui de `seo-bmo-2026.json`). */
const DOM = { '9A': '971', '9B': '972', '9C': '973', '9D': '974', '9F': '976' };

/** Nom de commune comparable : majuscules, sans accent, tirets et apostrophes en espaces, SAINT(E) abrégé, sans CEDEX ni arrondissement. */
export function normaliserCommune(nom) {
  return String(nom)
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toUpperCase()
    .replace(/[-'’]/g, ' ')
    .replace(/\s+CEDEX.*$/, '')
    .replace(/\s+\d+\s*(ER|E|EME)?(\s+ARRONDISSEMENT)?$/, '')
    .replace(/\bSAINTE\b/g, 'STE').replace(/\bSAINT\b/g, 'ST')
    .replace(/\s+/g, ' ').trim();
}

async function chargerVilles() {
  const tmp = await mkdtemp(path.join(tmpdir(), 'jolene-finess-'));
  try {
    const sortie = path.join(tmp, 'seo-data.mjs');
    await build({ entryPoints: [path.join(RACINE, 'src/lib/seo-data.ts')], outfile: sortie, bundle: true, format: 'esm', platform: 'node', logLevel: 'silent' });
    return (await import(pathToFileURL(sortie).href)).VILLES_SEO;
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
}

/** Agrège un flux de lignes CSV FINESS (35 colonnes séparées par « ; »). */
export async function compter(lignesAsync, villes) {
  const parCode = new Map();
  CATEGORIES.forEach((c, i) => { for (const [code, libelle] of Object.entries(c.codes)) parCode.set(code, { i, libelle }); });
  const vide = () => CATEGORIES.map(() => 0);
  const cleVille = new Map(villes.map((v) => [`${v.departement}|${normaliserCommune(v.nom)}`, v.slug]));
  const national = vide(); const departements = {}; const parVille = Object.fromEntries(villes.map((v) => [v.slug, vide()]));
  let lues = 0;
  const datesExtraction = new Map();
  for await (const ligne of lignesAsync) {
    const f = ligne.split(';');
    if (f.length < 35 || f[0] === 'nofinesset') continue;
    lues++;
    const date = (f[34] || '').trim();
    if (/^\d{4}-\d\d-\d\d$/.test(date)) datesExtraction.set(date, (datesExtraction.get(date) || 0) + 1);
    const cat = parCode.get(f[17]);
    if (!cat) continue;
    const libelle = f[18].replace(/"/g, '').trim();
    if (!cat.libelle.test(libelle)) throw new Error(`Catégorie FINESS ${f[17]} : libellé inattendu « ${libelle} » (renumérotation ?)`);
    const brut = (f[12] || '').trim().toUpperCase();
    const dept = DOM[brut] ?? brut;
    national[cat.i]++;
    (departements[dept] ??= vide())[cat.i]++;
    const slug = cleVille.get(`${brut}|${normaliserCommune((f[14] || '').replace(/"/g, '').trim().slice(6))}`);
    if (slug) parVille[slug][cat.i]++;
  }
  // Date de l'extraction : celle que porte la quasi-totalité des lignes (sinon, on ne sait pas dater).
  const [extractionDu, nb] = [...datesExtraction].sort((a, b) => b[1] - a[1])[0] ?? [null, 0];
  if (!extractionDu || nb < lues * 0.9) throw new Error('FINESS : date d\'extraction introuvable (colonne datemaj_geoloc hétérogène)');
  return { lues, extractionDu, national, departements, villes: parVille };
}

async function* lignesDuFichier(reponse) {
  const decodeur = new TextDecoder('utf-8');
  let reste = '';
  for await (const morceau of reponse.body) {
    const lignes = (reste + decodeur.decode(morceau, { stream: true })).split('\n');
    reste = lignes.pop();
    yield* lignes;
  }
  if (reste) yield reste;
}

export async function extraire() {
  const villes = await chargerVilles();
  const reponse = await fetch(FICHIER_FINESS);
  if (!reponse.ok) throw new Error(`FINESS : HTTP ${reponse.status}`);
  const maj = new Date(reponse.headers.get('last-modified') ?? '');
  if (Number.isNaN(maj.getTime())) throw new Error('FINESS : en-tête Last-Modified absent, date du fichier inconnue');
  const { lues, extractionDu, national, departements, villes: parVille } = await compter(lignesDuFichier(reponse), villes);
  if (lues < 90_000) throw new Error(`FINESS : ${lues} lignes lues seulement, fichier tronqué ?`);
  const tri = (o) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => a.localeCompare(b)));
  return {
    source: 'Répertoire FINESS (ministère chargé de la santé), réexposition data.gouv.fr, Licence Ouverte',
    sourceUrl: PAGE_SOURCE,
    extractionDu,
    fichierPublieLe: maj.toISOString().slice(0, 10),
    colonnes: CATEGORIES.map((c) => c.cle),
    national,
    departements: tri(departements),
    villes: tri(parVille),
  };
}

const serialiser = (d) => `${JSON.stringify(d).replace(/("(?:departements|villes)":\{)/g, '\n$1').replace(/\],"/g, '],\n"')}\n`;

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const verifier = process.argv.includes('--verifier');
  extraire().then(async (donnees) => {
    const sansDonnee = Object.entries(donnees.villes).filter(([, c]) => c.every((n) => n === 0)).map(([s]) => s);
    console.log(`[finess] extraction du ${donnees.extractionDu} (fichier publié le ${donnees.fichierPublieLe}) : ${donnees.colonnes.map((c, i) => `${c}=${donnees.national[i]}`).join(', ')}`);
    if (sansDonnee.length) console.log(`[finess] villes sans aucun établissement compté (nom de commune différent ?) : ${sansDonnee.join(', ')}`);
    const texte = serialiser(donnees);
    if (verifier) {
      const actuel = await readFile(SORTIE, 'utf8');
      if (actuel !== texte) { console.error('[finess] le JSON versionné diffère de la source : relancer sans --verifier'); process.exit(1); }
      console.log('[finess] JSON versionné identique à la source');
      return;
    }
    await writeFile(SORTIE, texte);
    console.log(`[finess] écrit ${path.relative(RACINE, SORTIE)}`);
  }).catch((e) => { console.error('[finess] échec :', e.message); process.exit(1); });
}
