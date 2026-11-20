#!/usr/bin/env node
/**
 * Garde du premier chargement : ce que le navigateur télécharge avant d'afficher une page.
 *
 * Il part du script d'entrée de `dist/index.html`, suit les imports statiques de fichier en
 * fichier et contrôle deux choses.
 *
 * 1. Aucune bibliothèque lourde réservée à quelques écrans (PDF, graphiques) n'est dans la chaîne
 *    de l'entrée, ni dans celle du cadre des espaces connectés (`LayoutApp`). Contrôle lancé à la
 *    fin de `npm run build` : son verdict ne dépend pas de l'environnement du build.
 * 2. Avec `--budget <octets>`, le poids compressé de la chaîne de l'entrée ne dépasse pas le
 *    budget. Lancé par `validate-pr`, pas par `npm run build` : le poids dépend de l'environnement
 *    (le build Vercel embarque le suivi d'erreurs dans l'entrée), et un budget dans le chemin du
 *    déploiement pourrait bloquer une mise en production pour quelques kilo-octets.
 *
 * Pourquoi : jusqu'au 20/11/2026, toutes les pages, accueil compris, chargeaient jsPDF et
 * recharts (257 Ko compressés inutiles). Un groupe de découpage capture aussi les dépendances de
 * ses modules : `clsx` était parti avec recharts, l'assistant de préchargement de Vite avec
 * jsPDF. Le groupe `vendor-commun` de `vite.config.ts` corrige cela ; ce script empêche le retour
 * du défaut, qui ne casse rien de visible et ne se voit donc pas en recette.
 *
 * Mesures du 20/11/2026 après correctif, gzip niveau 6 : 204 224 octets pour un build sans DSN
 * Sentry (local, CI), 296 401 pour le build de prévisualisation Vercel ; la production ajoute
 * environ 8 600 octets d'identifiants de débogage.
 *
 * Usage : node scripts/ci/verifier-premier-chargement.mjs [dossier dist] [--budget <octets>]
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

/** Bibliothèques qui ne doivent être chargées que par les écrans qui s'en servent. */
export const BLOCS_INTERDITS = ['vendor-pdf', 'vendor-charts'];
/** Blocs propres à l'application dont la chaîne est surveillée en plus de l'entrée. */
export const CADRES_SURVEILLES = ['LayoutApp'];
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

const estInterdit = (fichier) => BLOCS_INTERDITS.some((b) => fichier.startsWith(`${b}-`));

export function verifier(dist, { budget } = {}) {
  const page = ['index.html', 'app.html'].map((f) => path.join(dist, f)).find(existsSync);
  if (!page) throw new Error(`Premier chargement : aucune page d'entrée dans ${dist}`);
  const { entrees, precharges } = scriptsHtml(readFileSync(page, 'utf8'));
  if (!entrees.length) throw new Error(`Premier chargement : aucun script de module dans ${path.basename(page)}`);

  const lire = (nom) => readFileSync(path.join(dist, 'assets', nom), 'utf8');
  const chaine = chaineStatique(entrees, lire);
  const erreurs = [];
  const remede = 'Un petit module partagé a été rangé avec cette bibliothèque : cherchez dans dist/assets le fichier de la chaîne qui l\'importe, et ajoutez le module au groupe vendor-commun de vite.config.ts';

  // Contrôle de la lecture elle-même : sans lui, un changement de format du build rendrait la garde muette.
  if (!chaine.some((f) => f.startsWith(`${TEMOIN}-`))) erreurs.push(`le bloc ${TEMOIN} est absent de la chaîne : la lecture des imports statiques ne fonctionne plus`);
  const oublies = precharges.filter((f) => !chaine.includes(f));
  if (oublies.length) erreurs.push(`préchargés par la page mais absents de la chaîne lue : ${oublies.join(', ')}`);

  const interdits = [...new Set([...chaine, ...precharges])].filter(estInterdit);
  if (interdits.length) erreurs.push(`${interdits.join(', ')} chargé(s) par toutes les pages. ${remede}`);

  const fichiers = readdirSync(path.join(dist, 'assets'));
  for (const cadre of CADRES_SURVEILLES) {
    const blocs = fichiers.filter((f) => f.startsWith(`${cadre}-`) && f.endsWith('.js'));
    if (!blocs.length) { erreurs.push(`aucun bloc ${cadre}-*.js dans dist/assets : le cadre surveillé a changé de nom, mettre CADRES_SURVEILLES à jour`); continue; }
    const fautifs = chaineStatique(blocs, lire).filter(estInterdit);
    if (fautifs.length) erreurs.push(`${fautifs.join(', ')} chargé(s) par ${cadre}, donc par tous les écrans qu'il encadre. ${remede}`);
  }

  const poids = chaine.reduce((somme, f) => somme + gzipSync(readFileSync(path.join(dist, 'assets', f))).length, 0);
  if (budget !== undefined && poids > budget) erreurs.push(`${poids} octets compressés, budget ${budget}. Chargez à la demande (import dynamique) ce qui ne sert pas à toutes les pages`);

  return { page: path.basename(page), chaine, poids, erreurs };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const iBudget = args.indexOf('--budget');
  let budget;
  if (iBudget !== -1) {
    budget = Number(args[iBudget + 1]);
    if (!Number.isInteger(budget) || budget <= 0) { console.error('[premier chargement] --budget attend un nombre entier d\'octets'); process.exit(2); }
    args.splice(iBudget, 2);
  }
  const dist = path.resolve(args[0] ?? 'dist');
  const { page, chaine, poids, erreurs } = verifier(dist, { budget });
  if (erreurs.length) {
    console.error(`[premier chargement] ÉCHEC (${page})`);
    for (const e of erreurs) console.error(`  - ${e}`);
    process.exit(1);
  }
  console.log(`[premier chargement] ${chaine.length} fichiers, ${poids} octets compressés${budget ? ` (budget ${budget})` : ''}, sans ${BLOCS_INTERDITS.join(' ni ')} dans l'entrée ni dans ${CADRES_SURVEILLES.join(', ')}`);
}
