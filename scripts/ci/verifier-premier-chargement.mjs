#!/usr/bin/env node
/**
 * Garde du premier chargement : ce que le navigateur télécharge avant d'afficher une page.
 *
 * Lancé à la fin de `npm run build`. Il part du script d'entrée de `dist/index.html`, suit les
 * imports statiques de fichier en fichier et échoue si :
 *  - une bibliothèque lourde réservée à quelques écrans (PDF, graphiques) est dans la chaîne ;
 *  - le poids total compressé dépasse le budget.
 *
 * Pourquoi : jusqu'au 20/11/2026, toutes les pages, accueil compris, chargeaient jsPDF et
 * recharts (255 Ko compressés sur 460). Un groupe de découpage capture aussi les dépendances de
 * ses modules : `clsx` était parti avec recharts, et l'assistant de préchargement de Vite avec
 * jsPDF. Le groupe `vendor-commun` de `vite.config.ts` corrige cela ; ce script empêche le retour
 * du défaut, qui ne casse rien de visible et ne se voit donc pas en recette.
 *
 * Usage : node scripts/ci/verifier-premier-chargement.mjs [dossier dist]
 */
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

/** Bibliothèques qui ne doivent être chargées que par les écrans qui s'en servent. */
export const BLOCS_INTERDITS = ['vendor-pdf', 'vendor-charts'];
/** Budget du premier chargement, en octets compressés (gzip). Mesuré à 204 518 le 20/11/2026. */
export const BUDGET_GZIP = 250_000;
/** Bloc que toute page charge : s'il manque à la chaîne, c'est la lecture des imports qui est cassée. */
const TEMOIN = 'vendor-react';

/** Imports statiques d'un fichier produit par le build (`import … from"./x.js"`, `import"./x.js"`, `export … from"./x.js"`). */
export function importsStatiques(code) {
  const trouves = new Set();
  for (const m of code.matchAll(/(?:^|[;\n}])\s*(?:import|export)\s*(?:[^"'`();]*?\bfrom\s*)?["'](\.\/[^"']+\.js)["']/g)) trouves.add(m[1].slice(2));
  return [...trouves];
}

/** Scripts de module et préchargements déclarés par une page HTML. */
export function scriptsHtml(html) {
  const entrees = [...html.matchAll(/<script[^>]*type="module"[^>]*src="\/assets\/([^"]+\.js)"/g)].map((m) => m[1]);
  const precharges = [...html.matchAll(/<link[^>]*rel="modulepreload"[^>]*href="\/assets\/([^"]+\.js)"/g)].map((m) => m[1]);
  return { entrees, precharges };
}

/** Chaîne des fichiers chargés statiquement à partir des entrées. `lire(nom)` rend le code d'un fichier. */
export function chaineStatique(entrees, lire) {
  const vus = new Set();
  const file = [...entrees];
  while (file.length) {
    const nom = file.pop();
    if (vus.has(nom)) continue;
    vus.add(nom);
    for (const suivant of importsStatiques(lire(nom))) if (!vus.has(suivant)) file.push(suivant);
  }
  return [...vus].sort();
}

export function verifier(dist) {
  const page = ['index.html', 'app.html'].map((f) => path.join(dist, f)).find(existsSync);
  if (!page) throw new Error(`Premier chargement : aucune page d'entrée dans ${dist}`);
  const { entrees, precharges } = scriptsHtml(readFileSync(page, 'utf8'));
  if (!entrees.length) throw new Error(`Premier chargement : aucun script de module dans ${path.basename(page)}`);

  const lire = (nom) => readFileSync(path.join(dist, 'assets', nom), 'utf8');
  const chaine = chaineStatique(entrees, lire);
  const erreurs = [];

  // Contrôle de la lecture elle-même : sans lui, un changement de format du build rendrait la garde muette.
  if (!chaine.some((f) => f.startsWith(`${TEMOIN}-`))) erreurs.push(`le bloc ${TEMOIN} est absent de la chaîne : la lecture des imports statiques ne fonctionne plus`);
  const oublies = precharges.filter((f) => !chaine.includes(f));
  if (oublies.length) erreurs.push(`préchargés par la page mais absents de la chaîne lue : ${oublies.join(', ')}`);

  const interdits = [...new Set([...chaine, ...precharges])].filter((f) => BLOCS_INTERDITS.some((b) => f.startsWith(`${b}-`)));
  if (interdits.length) {
    erreurs.push(`${interdits.join(', ')} chargé(s) par toutes les pages. Un petit module partagé a été rangé avec cette bibliothèque : cherchez dans dist/assets le fichier de la chaîne qui l'importe, et ajoutez le module au groupe vendor-commun de vite.config.ts`);
  }

  const poids = chaine.reduce((somme, f) => somme + gzipSync(readFileSync(path.join(dist, 'assets', f))).length, 0);
  if (poids > BUDGET_GZIP) erreurs.push(`${poids} octets compressés, budget ${BUDGET_GZIP}. Chargez à la demande (import dynamique) ce qui ne sert pas à toutes les pages`);

  return { page: path.basename(page), chaine, poids, erreurs };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const dist = path.resolve(process.argv[2] ?? 'dist');
  const { page, chaine, poids, erreurs } = verifier(dist);
  if (erreurs.length) {
    console.error(`[premier chargement] ÉCHEC (${page})`);
    for (const e of erreurs) console.error(`  - ${e}`);
    process.exit(1);
  }
  console.log(`[premier chargement] ${chaine.length} fichiers, ${poids} octets compressés (budget ${BUDGET_GZIP}), sans ${BLOCS_INTERDITS.join(' ni ')}`);
}
