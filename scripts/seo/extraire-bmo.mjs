#!/usr/bin/env node
/**
 * Agrège par département l'enquête Besoins en main-d'œuvre (BMO) de France Travail pour
 * les métiers affichés sur les pages publiques, et écrit `src/lib/seo-bmo-2026.json`.
 *
 * Source : classeur officiel « Base open data BMO 2026 » (data.gouv.fr, Licence Ouverte),
 * publié PAR BASSIN D'EMPLOI. Le département n'y figure pas : le total départemental est
 * donc une somme faite par Jolene, et il faut le dire (page baromètre, « Comment lire ces
 * chiffres »). Deux règles, pour ne rien publier que le fichier ne permette d'établir :
 *
 *  1. Projets de recrutement : somme des valeurs publiées des bassins du département. Si au
 *     moins un bassin a une valeur remplacée par « * » pour ce métier, le total est un
 *     minimum (`partiel` = 1 → affiché « au moins N »).
 *  2. Part jugée difficile : calculée seulement si AUCUNE valeur (projets ou projets
 *     difficiles) n'est masquée dans le département pour ce métier. Sinon `null` (« n.c. »).
 *     Un total peut donc être exact avec une part inconnue (seuls des projets difficiles masqués).
 *
 * Hypothèse, dite sur la page : un bassin qui n'a AUCUNE ligne pour un métier compte pour zéro.
 * Le classeur ne contient aucune ligne à zéro, garde les petites valeurs sous forme de lignes
 * « * », et les unités sans ligne sont de petites unités (revue B8 de #1170, seconde passe).
 * France Travail rattache le bassin de Monaco aux Alpes-Maritimes (06) : il est inclus dans ce
 * département, comme dans le classeur.
 *     L'ancienne méthode retirait du dénominateur les bassins masqués tout en gardant leurs
 *     projets dans le total : la part affichée pouvait dépasser toute valeur possible
 *     (revue B8 de #1170 : Reims infirmiers 83 % affichés pour 71 à 73 % possibles).
 *
 * Le classeur est lu en mémoire ; rien n'est enregistré à part le JSON (des comptes).
 * Lecture du .xlsx sans dépendance : un .xlsx est une archive ZIP de fichiers XML.
 *
 * Usage : node scripts/seo/extraire-bmo.mjs            (écrit le JSON)
 *         node scripts/seo/extraire-bmo.mjs --verifier (compare au JSON versionné, n'écrit rien)
 */
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { inflateRawSync } from 'node:zlib';

const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const ANNEE_BMO = 2026;
export const FICHIER_BMO = 'https://www.francetravail.org/files/live/sites/peorg/files/documents/Statistiques-et-analyses/Open-data/BMO/Base-open-data-BMO-2026.xlsx';
const SORTIE = path.join(RACINE, 'src', 'lib', 'seo-bmo-2026.json');

/** Métier affiché → code et libellé exact de la catégorie de l'enquête (contrôlé à la lecture). */
export const METIERS_BMO = {
  AS: { code: 'V0X60', libelle: /^Aides-soignants/i },
  IDE: { code: 'V1X80', libelle: /^Infirmiers et sages-femmes$/i },
  MEDECIN: { code: 'V2X90', libelle: /^Médecins$/i },
};

/** Fichiers d'une archive ZIP (méthodes « stored » et « deflate »), sans dépendance. */
export function lireZip(tampon) {
  const fin = tampon.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  if (fin < 0) throw new Error('BMO : archive ZIP illisible (fin de répertoire introuvable)');
  const nombre = tampon.readUInt16LE(fin + 10);
  let position = tampon.readUInt32LE(fin + 16);
  const fichiers = new Map();
  for (let i = 0; i < nombre; i++) {
    if (tampon.readUInt32LE(position) !== 0x02014b50) throw new Error('BMO : répertoire ZIP corrompu');
    const methode = tampon.readUInt16LE(position + 10);
    const tailleCompressee = tampon.readUInt32LE(position + 20);
    const longueurNom = tampon.readUInt16LE(position + 28);
    const longueurExtra = tampon.readUInt16LE(position + 30);
    const longueurCommentaire = tampon.readUInt16LE(position + 32);
    const decalage = tampon.readUInt32LE(position + 42);
    const nom = tampon.toString('utf8', position + 46, position + 46 + longueurNom);
    const debut = decalage + 30 + tampon.readUInt16LE(decalage + 26) + tampon.readUInt16LE(decalage + 28);
    const brut = tampon.subarray(debut, debut + tailleCompressee);
    if (methode !== 0 && methode !== 8) throw new Error(`BMO : compression ZIP ${methode} non gérée (${nom})`);
    fichiers.set(nom, () => (methode === 8 ? inflateRawSync(brut) : brut).toString('utf8'));
    position += 46 + longueurNom + longueurExtra + longueurCommentaire;
  }
  return fichiers;
}

const texteXml = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');

/** Chaînes partagées du classeur (les cellules de type « s » y renvoient par leur rang). */
export function chainesPartagees(fichiers) {
  const partagees = [];
  const xml = fichiers.get('xl/sharedStrings.xml')?.() ?? '';
  for (const si of xml.matchAll(/<si>([\s\S]*?)<\/si>/g)) {
    partagees.push(texteXml([...si[1].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join('')));
  }
  return partagees;
}

export const feuillesClasseur = (fichiers) => [...fichiers.keys()].filter((n) => /^xl\/worksheets\/sheet\d+\.xml$/.test(n)).sort();

/** Lignes d'une feuille : objets de cellules indexés par lettre de colonne. */
export function* lignesFeuille(xmlFeuille, partagees) {
  const feuille = xmlFeuille;
  for (const ligne of feuille.matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g)) {
    const cellules = {};
    for (const c of ligne[1].matchAll(/<c\s([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const colonne = /r="([A-Z]+)\d+"/.exec(c[1])?.[1];
      if (!colonne || c[2] === undefined) continue;
      const v = /<v>([\s\S]*?)<\/v>/.exec(c[2])?.[1];
      const enLigne = /<is>[\s\S]*?<t[^>]*>([\s\S]*?)<\/t>/.exec(c[2])?.[1];
      cellules[colonne] = v === undefined ? (enLigne === undefined ? null : texteXml(enLigne)) : (/t="s"/.test(c[1]) ? partagees[Number(v)] : texteXml(v));
    }
    yield cellules;
  }
}

const nombreOuNul = (v) => (v !== null && v !== undefined && /^\d+(\.\d+)?$/.test(String(v).trim()) ? Number(v) : null);
const codeDepartement = (v) => { const d = String(v ?? '').trim().toUpperCase(); return /^\d$/.test(d) ? `0${d}` : d; };

/**
 * Agrège des lignes { code, libelle, departement, projets, difficiles } (valeurs brutes du classeur).
 * Retourne { [département]: { [métier]: [projets, part | null, partiel 0|1] } }.
 */
export function agreger(lignes) {
  const parCode = new Map(Object.entries(METIERS_BMO).map(([metier, m]) => [m.code, { metier, ...m }]));
  const cumul = new Map();
  for (const l of lignes) {
    const cible = parCode.get(String(l.code ?? '').trim());
    if (!cible) continue;
    if (!cible.libelle.test(String(l.libelle ?? '').trim())) throw new Error(`BMO : le code ${cible.code} porte le libellé « ${l.libelle} » (nomenclature modifiée ?)`);
    const departement = codeDepartement(l.departement);
    if (!departement) throw new Error('BMO : ligne sans département');
    const cle = `${departement}\u0000${cible.metier}`;
    const c = cumul.get(cle) ?? { departement, metier: cible.metier, projets: 0, difficiles: 0, masque: false, difficilesMasques: false };
    const projets = nombreOuNul(l.projets);
    const difficiles = nombreOuNul(l.difficiles);
    if (projets === null) c.masque = true; else c.projets += projets;
    if (difficiles === null) c.difficilesMasques = true; else c.difficiles += difficiles;
    cumul.set(cle, c);
  }
  const resultat = {};
  for (const c of cumul.values()) {
    const exact = !c.masque && !c.difficilesMasques && c.projets > 0;
    (resultat[c.departement] ??= {})[c.metier] = [Math.round(c.projets), exact ? Math.round((c.difficiles / c.projets) * 10000) / 100 : null, c.masque ? 1 : 0];
  }
  return resultat;
}

export async function extraire() {
  const reponse = await fetch(FICHIER_BMO, { headers: { 'User-Agent': 'jolene-seo-extraction' } });
  if (!reponse.ok) throw new Error(`BMO : HTTP ${reponse.status}`);
  const fichiers = lireZip(Buffer.from(await reponse.arrayBuffer()));
  const partagees = chainesPartagees(fichiers);
  // La feuille de données est celle dont l'en-tête porte « met » et « xmet » (une feuille décrit les variables).
  let it; let entete;
  for (const nom of feuillesClasseur(fichiers)) {
    const essai = lignesFeuille(fichiers.get(nom)(), partagees);
    const premiere = essai.next().value ?? {};
    const titres = Object.values(premiere).map((v) => String(v ?? '').trim().toLowerCase());
    if (titres.includes('met') && titres.includes('xmet')) { it = essai; entete = premiere; break; }
  }
  if (!it) throw new Error('BMO : feuille de données introuvable (aucun en-tête avec « met » et « xmet »)');
  const colonne = (...noms) => {
    const trouve = Object.entries(entete).find(([, v]) => noms.includes(String(v ?? '').trim().toLowerCase()));
    if (!trouve) throw new Error(`BMO : colonne ${noms.join(' / ')} introuvable (en-tête : ${Object.values(entete).join(', ')})`);
    return trouve[0];
  };
  const c = { annee: colonne('annee', 'année'), code: colonne('code métier bmo'), libelle: colonne('nom métier bmo'), departement: colonne('dept'), projets: colonne('met'), difficiles: colonne('xmet') };
  const lignes = [];
  let lues = 0;
  for (const l of it) {
    lues++;
    if (Number(l[c.annee]) !== ANNEE_BMO) throw new Error(`BMO : ligne de l'année ${l[c.annee]} dans le classeur ${ANNEE_BMO}`);
    lignes.push({ code: l[c.code], libelle: l[c.libelle], departement: l[c.departement], projets: l[c.projets], difficiles: l[c.difficiles] });
  }
  if (lues < 40_000) throw new Error(`BMO : ${lues} lignes lues seulement, classeur tronqué ?`);
  const departements = agreger(lignes);
  return Object.fromEntries(Object.entries(departements).sort(([a], [b]) => a.localeCompare(b)));
}

const serialiser = (d) => `${JSON.stringify(d).replace(/\},"/g, '},\n"')}\n`;

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const verifier = process.argv.includes('--verifier');
  extraire().then(async (donnees) => {
    const codes = Object.keys(donnees);
    for (const metier of Object.keys(METIERS_BMO)) {
      const entrees = codes.map((d) => donnees[d][metier]).filter(Boolean);
      console.log(`[bmo] ${metier} : ${entrees.length} départements, ${entrees.reduce((s, e) => s + e[0], 0)} projets publiés, part calculable dans ${entrees.filter((e) => e[1] !== null).length}, total partiel dans ${entrees.filter((e) => e[2]).length}`);
    }
    const texte = serialiser(donnees);
    if (verifier) {
      if ((await readFile(SORTIE, 'utf8')) !== texte) { console.error('[bmo] le JSON versionné diffère de la source : relancer sans --verifier'); process.exit(1); }
      console.log('[bmo] JSON versionné identique à la source');
      return;
    }
    await writeFile(SORTIE, texte);
    console.log(`[bmo] écrit ${path.relative(RACINE, SORTIE)}`);
  }).catch((e) => { console.error('[bmo] échec :', e.message); process.exit(1); });
}
