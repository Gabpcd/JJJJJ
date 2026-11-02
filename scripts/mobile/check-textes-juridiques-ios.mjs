#!/usr/bin/env node
/**
 * Garde des textes juridiques et de consentement de l'app iOS (lot 2, tranche TL,
 * `docs/mobile-swift/LOT2_PLAN.md` §3 « TL », critère P9, HARD STOP n°4 de CLAUDE.md).
 *
 * `ios-native/Packages/JoleneCore/Sources/JoleneCore/Legal/TextesWeb.swift` est le seul fichier
 * Swift qui porte un texte juridique ou de consentement. Chaque constante y est précédée de
 * `// source: <fichier>:<ligne>` (ou `<fichier>:<début>-<fin>`) ; le script parse ce fichier
 * web (TypeScript TSX) et vérifie que la constante ÉGALE, au caractère près, un texte affiché
 * qui commence et finit exactement à ces lignes :
 *   - texte JSX, avec le traitement des espaces de React/Babel (lignes coupées aux bords et
 *     jointes par une espace) et les entités HTML décodées ;
 *   - littéral de chaîne ou fragment de gabarit, décodé (`\'` → `'`).
 * Les bords sont coupés côté web (espaces de mise en page) ; jamais à l'intérieur du texte.
 *
 * Autres annotations :
 *   - `// source-objet: <fichier>:<ligne> <NOM>` avant un `[String: String]` : l'objet littéral
 *     `NOM` du web (même jeu de clés, chaque clé reliée à la constante du même texte) ;
 *   - `// source-ensemble: <fichier>:<début>-<fin>` avant un `Set<String>` : `new Set([...])`.
 * `catalogue` doit lister toutes les constantes (le test Swift le parcourt). Tout autre littéral
 * de chaîne du fichier Swift est refusé (sauf `" "` et `""`, séparateurs des assemblages).
 *
 * Enfin, aucun texte juridique ne doit être écrit en dur dans les dossiers Swift du lot 2
 * (`DOSSIERS_LOT2`) hors de `TextesWeb.swift`.
 *
 * Usage :
 *   node scripts/mobile/check-textes-juridiques-ios.mjs          # vérifie, code 1 si écart
 *   node scripts/mobile/check-textes-juridiques-ios.mjs --liste  # tableau Markdown des textes
 *
 * Aucune valeur secrète n'est lue : le script ne lit que des fichiers du dépôt.
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const TEXTES_SWIFT = 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Legal/TextesWeb.swift';

/** Dossiers Swift du lot 2 (LOT2_PLAN §2.1) où aucun texte juridique ne s'écrit en dur. */
export const DOSSIERS_LOT2 = [
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Pointage',
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Documents',
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Contrats',
  'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Pointage',
  'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Documents',
  'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Contrats',
  'ios-native/Jolene/Screens/Presences',
  'ios-native/Jolene/Screens/Documents',
  'ios-native/Jolene/Screens/Contrats',
  'ios-native/Jolene/Composition/ContratReaderView.swift',
];

/** Marques d'un texte juridique (citation de code, RGPD, attestation sur l'honneur). */
const MARQUES_JURIDIQUES = [
  /Code civil/i, /Code du travail/i, /Code pénal/i, /RGPD/, /eIDAS/i, /Base légale/i,
  /J['’]atteste/i, /sur l['’]honneur/i, /\bart(?:icle|\.)\s*L?\.?\s*\d/i,
];

// ---------------------------------------------------------------------------------------------
// Swift
// ---------------------------------------------------------------------------------------------

const LITTERAL_SWIFT = /"((?:[^"\\]|\\.)*)"/g;

/** Échappe une valeur pour un littéral Swift sur une ligne (caractères invisibles en `\u{…}`). */
export function echapperSwift(valeur) {
  return [...valeur].map(c => {
    if (c === '\\') return '\\\\';
    if (c === '"') return '\\"';
    const code = c.codePointAt(0);
    if (code < 0x20 || [0x00a0, 0x2007, 0x2009, 0x200a, 0x200b, 0x202f, 0xfe0f, 0xfeff].includes(code)) {
      return `\\u{${code.toString(16).toUpperCase().padStart(4, '0')}}`;
    }
    return c;
  }).join('');
}

function decoderSwift(brut) {
  if (/\\\(/.test(brut)) return { erreur: 'interpolation Swift interdite' };
  let sortie = '';
  for (let i = 0; i < brut.length; i += 1) {
    const c = brut[i];
    if (c !== '\\') { sortie += c; continue; }
    const suivant = brut[i + 1];
    i += 1;
    if (suivant === 'u' && brut[i + 1] === '{') {
      const fin = brut.indexOf('}', i);
      sortie += String.fromCodePoint(parseInt(brut.slice(i + 2, fin), 16));
      i = fin;
    } else {
      sortie += { n: '\n', t: '\t', r: '\r', 0: '\0', '"': '"', "'": "'", '\\': '\\' }[suivant] ?? `\\${suivant}`;
    }
  }
  return { valeur: sortie };
}

/** Littéraux de chaîne d'une ligne Swift situés avant un éventuel commentaire `//`. */
function litterauxHorsCommentaire(ligne) {
  const masque = ligne.replace(LITTERAL_SWIFT, t => `"${'x'.repeat(t.length - 2)}"`);
  const commentaire = masque.indexOf('//');
  return [...ligne.matchAll(LITTERAL_SWIFT)].filter(m => commentaire < 0 || m.index < commentaire);
}

/** Retire littéraux puis commentaire de fin de ligne (pour compter les accolades). */
function sansLitteraux(ligne) {
  return ligne.replace(LITTERAL_SWIFT, '""').replace(/\/\/.*$/, '');
}

function lireSource(texte) {
  const m = /^(\S+?):(\d+)(?:-(\d+))?$/.exec(texte.trim());
  if (!m) return null;
  return { fichier: m[1], debut: Number(m[2]), fin: Number(m[3] ?? m[2]) };
}

/**
 * Parse `TextesWeb.swift`. Rend les constantes (nom qualifié depuis `TextesWeb`), les
 * dictionnaires, les ensembles, le catalogue et les erreurs de forme.
 */
export function lireTextesSwift(source) {
  const lignes = source.split('\n');
  const pile = [];
  const constantes = [];
  const objets = [];
  const ensembles = [];
  const erreurs = [];
  let catalogue = null;
  let annotation = null;
  let bloc = null;
  const chemin = () => pile.filter(Boolean).slice(1).join('.');
  const qualifier = nom => (chemin() ? `${chemin()}.${nom}` : nom);

  lignes.forEach((ligne, index) => {
    const numero = index + 1;
    const nette = ligne.trim();

    if (bloc) {
      if (/^\]\s*$/.test(nette)) { bloc = null; return; }
      if (bloc.genre === 'objet') {
        const m = /^"([A-Z0-9_]+)"\s*:\s*([\w.]+)\s*,?$/.exec(nette);
        if (m) bloc.cible.entrees.push({ cle: m[1], ref: m[2], ligneSwift: numero });
        else erreurs.push(`${TEXTES_SWIFT}:${numero} : entrée de dictionnaire illisible « ${nette} »`);
      } else if (bloc.genre === 'ensemble') {
        const valeurs = [...nette.matchAll(LITTERAL_SWIFT)].map(m => m[1]);
        if (!valeurs.length || nette.replace(LITTERAL_SWIFT, '').replace(/[\s,]/g, '')) {
          erreurs.push(`${TEXTES_SWIFT}:${numero} : élément d'ensemble illisible « ${nette} »`);
        }
        bloc.cible.elements.push(...valeurs);
      } else if (bloc.genre === 'catalogue') {
        const m = /^\.init\(cle:\s*"([\w.]+)",\s*texte:\s*([\w.]+)\),?$/.exec(nette);
        if (m) bloc.cible.push({ cle: m[1], ref: m[2], ligneSwift: numero });
        else erreurs.push(`${TEXTES_SWIFT}:${numero} : entrée de catalogue illisible « ${nette} »`);
      }
      return;
    }

    if (nette.startsWith('//')) {
      let m = /^\/\/ source: (.+)$/.exec(nette);
      if (m) {
        const src = lireSource(m[1]);
        if (!src) erreurs.push(`${TEXTES_SWIFT}:${numero} : annotation illisible « ${nette} »`);
        else annotation = { genre: 'texte', source: src, ligne: numero };
        return;
      }
      m = /^\/\/ source-objet: (\S+) (\w+)$/.exec(nette);
      if (m) {
        const src = lireSource(m[1]);
        if (!src) erreurs.push(`${TEXTES_SWIFT}:${numero} : annotation illisible « ${nette} »`);
        else annotation = { genre: 'objet', source: { ...src, variable: m[2] }, ligne: numero };
        return;
      }
      m = /^\/\/ source-ensemble: (\S+)$/.exec(nette);
      if (m) {
        const src = lireSource(m[1]);
        if (!src) erreurs.push(`${TEXTES_SWIFT}:${numero} : annotation illisible « ${nette} »`);
        else annotation = { genre: 'ensemble', source: src, ligne: numero };
        return;
      }
      if (/^\/\/\s*source/.test(nette)) erreurs.push(`${TEXTES_SWIFT}:${numero} : annotation illisible « ${nette} »`);
      return;
    }

    const constante = /^(?:public\s+)?static\s+let\s+(\w+)(?:\s*:\s*String)?\s*=\s*"((?:[^"\\]|\\.)*)"\s*$/.exec(nette);
    const objet = /^(?:public\s+)?static\s+let\s+(\w+)\s*:\s*\[String\s*:\s*String\]\s*=\s*\[\s*$/.exec(nette);
    const ensemble = /^(?:public\s+)?static\s+let\s+(\w+)\s*:\s*Set<String>\s*=\s*\[\s*$/.exec(nette);
    const cat = /^(?:public\s+)?static\s+let\s+catalogue\s*:\s*\[EntreeTexteWeb\]\s*=\s*\[\s*$/.exec(nette);

    if (constante) {
      const nom = qualifier(constante[1]);
      const decode = decoderSwift(constante[2]);
      if (decode.erreur) erreurs.push(`${nom} (${TEXTES_SWIFT}:${numero}) : ${decode.erreur}`);
      else if (!annotation || annotation.genre !== 'texte') {
        erreurs.push(`${nom} (${TEXTES_SWIFT}:${numero}) : constante sans annotation « // source: <fichier>:<ligne> »`);
      } else {
        constantes.push({ nom, valeur: decode.valeur, source: annotation.source, ligneSwift: numero });
      }
      annotation = null;
      return;
    }
    if (objet || ensemble) {
      const genre = objet ? 'objet' : 'ensemble';
      const nom = qualifier((objet ?? ensemble)[1]);
      if (!annotation || annotation.genre !== genre) {
        erreurs.push(`${nom} (${TEXTES_SWIFT}:${numero}) : ${genre} sans annotation « // source-${genre}: … »`);
      }
      const cible = genre === 'objet'
        ? { nom, chemin: chemin(), source: annotation?.source, entrees: [], ligneSwift: numero }
        : { nom, source: annotation?.source, elements: [], ligneSwift: numero };
      (genre === 'objet' ? objets : ensembles).push(cible);
      bloc = { genre, cible };
      annotation = null;
      return;
    }
    if (cat) {
      catalogue = [];
      bloc = { genre: 'catalogue', cible: catalogue };
      annotation = null;
      return;
    }

    // Tout autre littéral : seuls les séparateurs des assemblages sont admis.
    for (const m of litterauxHorsCommentaire(ligne)) {
      if (m[1] !== ' ' && m[1] !== '') {
        erreurs.push(`${TEXTES_SWIFT}:${numero} : littéral non gardé « ${m[1]} » (texte hors constante annotée)`);
      }
    }
    // Une annotation ne vaut que pour la déclaration qui la suit immédiatement.
    if (nette && annotation) {
      erreurs.push(`${TEXTES_SWIFT}:${annotation.ligne} : annotation qui ne précède aucune constante gardée`);
      annotation = null;
    }

    // Pile des accolades : la première accolade d'une ligne `enum X` ouvre l'espace de noms X.
    const sans = sansLitteraux(ligne);
    let nomEnum = /\benum\s+(\w+)/.exec(sans)?.[1] ?? null;
    for (const c of sans) {
      if (c === '{') { pile.push(nomEnum); nomEnum = null; }
      if (c === '}') pile.pop();
    }
  });

  return { constantes, objets, ensembles, catalogue, erreurs };
}

// ---------------------------------------------------------------------------------------------
// Web (TSX)
// ---------------------------------------------------------------------------------------------

const ENTITES = {
  nbsp: String.fromCharCode(0xa0), amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", laquo: '«', raquo: '»',
  hellip: '…', mdash: '—', ndash: '–', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', euro: '€',
};

function decoderEntites(texte) {
  return texte.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (tout, corps) => {
    if (corps[0] === '#') {
      const code = corps[1].toLowerCase() === 'x' ? parseInt(corps.slice(2), 16) : parseInt(corps.slice(1), 10);
      return String.fromCodePoint(code);
    }
    return ENTITES[corps] ?? tout;
  });
}

/** Texte rendu par React pour un nœud JSX texte (algorithme de Babel `cleanJSXElementLiteralChild`). */
export function texteJsx(brut) {
  const lignes = brut.split(/\r\n|\n|\r/);
  let derniereNonVide = 0;
  lignes.forEach((l, i) => { if (/[^ \t]/.test(l)) derniereNonVide = i; });
  let sortie = '';
  lignes.forEach((ligne, i) => {
    let t = ligne.replace(/\t/g, ' ');
    if (i !== 0) t = t.replace(/^[ ]+/, '');
    if (i !== lignes.length - 1) t = t.replace(/[ ]+$/, '');
    if (t) {
      if (i !== derniereNonVide) t += ' ';
      sortie += t;
    }
  });
  return decoderEntites(sortie);
}

/**
 * Textes affichables d'un fichier TSX : nœuds JSX texte, littéraux de chaîne, fragments de
 * gabarit. Chaque unité porte sa valeur (bords coupés), ses lignes (premier et dernier
 * caractère non blanc) et ses positions dans le fichier.
 */
export function unitesWeb(fichier, texte) {
  return analyserWeb(fichier, texte).unites;
}

function analyserWeb(fichier, texte) {
  const sf = ts.createSourceFile(fichier, texte, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const unites = [];
  const ligne = pos => sf.getLineAndCharacterOfPosition(pos).line + 1;
  const ajouter = (noeud, valeur, genre) => {
    const debutNoeud = genre === 'jsx' ? noeud.pos : noeud.getStart(sf);
    const extrait = texte.slice(debutNoeud, noeud.end);
    const premier = extrait.search(/\S/);
    if (premier < 0) return;
    const dernier = extrait.length - 1 - [...extrait].reverse().join('').search(/\S/);
    const offset = debutNoeud + premier;
    const offsetFin = debutNoeud + dernier + 1;
    const cle = ts.isPropertyAssignment(noeud.parent) && noeud.parent.initializer === noeud
      ? noeud.parent.name.getText(sf).replace(/^['"]|['"]$/g, '') : null;
    unites.push({ valeur: valeur.trim(), genre, debut: ligne(offset), fin: ligne(offsetFin - 1), offset, offsetFin, cle });
  };
  const visiter = noeud => {
    if (ts.isJsxText(noeud)) {
      const valeur = texteJsx(noeud.text);
      if (valeur.trim()) ajouter(noeud, valeur, 'jsx');
    } else if (ts.isStringLiteral(noeud) || ts.isNoSubstitutionTemplateLiteral(noeud)) {
      if (!ts.isImportDeclaration(noeud.parent) && !ts.isExportDeclaration(noeud.parent) && noeud.text.trim()) {
        ajouter(noeud, noeud.text, 'chaine');
      }
    } else if (ts.isTemplateHead(noeud) || ts.isTemplateMiddle(noeud) || ts.isTemplateTail(noeud)) {
      if (noeud.text.trim()) ajouter(noeud, noeud.text, 'gabarit');
    }
    ts.forEachChild(noeud, visiter);
  };
  visiter(sf);
  return { unites, sf };
}

/** Objets littéraux `const NOM = { CLE: 'texte', … }` et `new Set([...])` d'un fichier TSX. */
function structuresWeb(sf) {
  const objets = [];
  const ensembles = [];
  const ligne = pos => sf.getLineAndCharacterOfPosition(pos).line + 1;
  const deballer = e => {
    let x = e;
    while (x && (ts.isAsExpression(x) || ts.isSatisfiesExpression?.(x) || ts.isParenthesizedExpression(x))) x = x.expression;
    return x;
  };
  const visiter = noeud => {
    if (ts.isVariableDeclaration(noeud) && ts.isIdentifier(noeud.name)) {
      const init = deballer(noeud.initializer);
      if (init && ts.isObjectLiteralExpression(init)) {
        const proprietes = new Map();
        for (const p of init.properties) {
          if (!ts.isPropertyAssignment(p)) continue;
          const valeur = deballer(p.initializer);
          if (valeur && (ts.isStringLiteral(valeur) || ts.isNoSubstitutionTemplateLiteral(valeur))) {
            proprietes.set(p.name.getText(sf).replace(/^['"]|['"]$/g, ''), { valeur: valeur.text, ligne: ligne(valeur.getStart(sf)) });
          }
        }
        objets.push({ nom: noeud.name.text, ligne: ligne(noeud.getStart(sf)), proprietes });
      }
    }
    if (ts.isNewExpression(noeud) && noeud.expression.getText(sf) === 'Set' && noeud.arguments?.length === 1
      && ts.isArrayLiteralExpression(noeud.arguments[0])) {
      const elements = noeud.arguments[0].elements
        .filter(e => ts.isStringLiteral(e) || ts.isNoSubstitutionTemplateLiteral(e)).map(e => e.text);
      ensembles.push({ debut: ligne(noeud.getStart(sf)), fin: ligne(noeud.end - 1), elements });
    }
    ts.forEachChild(noeud, visiter);
  };
  visiter(sf);
  return { objets, ensembles };
}

/** Lecteur de fichiers web avec cache des unités ; `lire(fichier)` rend le contenu ou lève. */
export function lecteurWeb(lire) {
  const cache = new Map();
  return fichier => {
    if (!cache.has(fichier)) {
      let contenu;
      try { contenu = lire(fichier); } catch { contenu = null; }
      if (contenu === null || contenu === undefined) cache.set(fichier, null);
      else {
        const { unites, sf } = analyserWeb(fichier, contenu);
        cache.set(fichier, { unites, ...structuresWeb(sf) });
      }
    }
    return cache.get(fichier);
  };
}

// ---------------------------------------------------------------------------------------------
// Vérification
// ---------------------------------------------------------------------------------------------

const lignesDe = s => (s.debut === s.fin ? `l.${s.debut}` : `l.${s.debut}-${s.fin}`);

/** Vérifie `TextesWeb.swift` contre le web. Rend `{ erreurs, constantes, objets, ensembles }`. */
export function verifierTextes({ swiftSource, lireWeb }) {
  const lu = lireTextesSwift(swiftSource);
  const erreurs = [...lu.erreurs];
  const parNom = new Map();

  for (const c of lu.constantes) {
    if (parNom.has(c.nom)) erreurs.push(`${c.nom} : constante déclarée deux fois`);
    parNom.set(c.nom, c);
    if (!c.valeur) { erreurs.push(`${c.nom} : constante vide`); continue; }
    if (c.valeur !== c.valeur.trim()) erreurs.push(`${c.nom} : espace au bord de la constante`);
    const web = lireWeb(c.source.fichier);
    if (!web) { erreurs.push(`${c.nom} : fichier source introuvable ${c.source.fichier}`); continue; }
    const exacte = web.unites.find(u => u.valeur === c.valeur && u.debut === c.source.debut && u.fin === c.source.fin);
    if (exacte) { c.unite = exacte; continue; }
    const ailleurs = web.unites.find(u => u.valeur === c.valeur);
    if (ailleurs) {
      erreurs.push(`${c.nom} : texte retrouvé ${lignesDe(ailleurs)} de ${c.source.fichier} et non ${lignesDe(c.source)} : `
        + 'mettre à jour l’annotation source après relecture du texte');
      continue;
    }
    const aLaLigne = web.unites.filter(u => u.debut === c.source.debut);
    erreurs.push(`${c.nom} : ${c.source.fichier} ${lignesDe(c.source)} n'affiche pas « ${c.valeur} »`
      + (aLaLigne.length ? ` (le web affiche : ${aLaLigne.map(u => `« ${u.valeur} »`).join(', ')})` : ' (aucun texte à cette ligne)'));
  }

  // Référence locale à l'espace de noms du dictionnaire d'abord, puis qualifiée depuis `TextesWeb`.
  const resoudre = (ref, cheminLocal) => (cheminLocal && parNom.get(`${cheminLocal}.${ref}`)) || parNom.get(ref);

  for (const o of lu.objets) {
    if (!o.source) continue;
    const web = lireWeb(o.source.fichier);
    const cible = web?.objets.find(x => x.nom === o.source.variable && x.ligne === o.source.debut);
    if (!cible) {
      erreurs.push(`${o.nom} : objet ${o.source.variable} introuvable ${lignesDe(o.source)} de ${o.source.fichier}`);
      continue;
    }
    const clesSwift = new Set();
    for (const e of o.entrees) {
      if (clesSwift.has(e.cle)) erreurs.push(`${o.nom} : clé ${e.cle} répétée`);
      clesSwift.add(e.cle);
      const attendu = cible.proprietes.get(e.cle);
      const constante = resoudre(e.ref, o.chemin);
      if (!attendu) erreurs.push(`${o.nom} : clé ${e.cle} absente de ${o.source.variable} (web)`);
      else if (!constante) erreurs.push(`${o.nom} : ${e.cle} → ${e.ref}, constante inconnue`);
      else if (constante.valeur !== attendu.valeur || constante.source.fichier !== o.source.fichier
        || constante.source.debut !== attendu.ligne) {
        erreurs.push(`${o.nom} : ${e.cle} → ${constante.nom} ne correspond pas à ${o.source.variable}.${e.cle} `
          + `(web l.${attendu.ligne} : « ${attendu.valeur} »)`);
      }
    }
    for (const cle of cible.proprietes.keys()) {
      if (!clesSwift.has(cle)) erreurs.push(`${o.nom} : clé ${cle} de ${o.source.variable} absente du dictionnaire Swift`);
    }
  }

  for (const e of lu.ensembles) {
    if (!e.source) continue;
    const web = lireWeb(e.source.fichier);
    const cible = web?.ensembles.find(x => x.debut === e.source.debut && x.fin === e.source.fin);
    if (!cible) {
      erreurs.push(`${e.nom} : new Set([...]) introuvable ${lignesDe(e.source)} de ${e.source.fichier}`);
      continue;
    }
    const swift = new Set(e.elements);
    const webSet = new Set(cible.elements);
    for (const x of webSet) if (!swift.has(x)) erreurs.push(`${e.nom} : ${x} présent sur le web, absent du Swift`);
    for (const x of swift) if (!webSet.has(x)) erreurs.push(`${e.nom} : ${x} absent du web`);
    if (swift.size !== e.elements.length) erreurs.push(`${e.nom} : élément répété`);
  }

  if (!lu.catalogue) erreurs.push('catalogue : `public static let catalogue: [EntreeTexteWeb] = [` absent');
  else {
    const vus = new Set();
    for (const entree of lu.catalogue) {
      if (entree.cle !== entree.ref) erreurs.push(`catalogue : ${entree.cle} pointe vers ${entree.ref}`);
      if (!parNom.has(entree.cle)) erreurs.push(`catalogue : ${entree.cle} n'est pas une constante gardée`);
      if (vus.has(entree.cle)) erreurs.push(`catalogue : ${entree.cle} répétée`);
      vus.add(entree.cle);
    }
    for (const nom of parNom.keys()) if (!vus.has(nom)) erreurs.push(`catalogue : ${nom} absente du catalogue`);
  }

  return { erreurs, constantes: lu.constantes, objets: lu.objets, ensembles: lu.ensembles };
}

/** Textes juridiques écrits en dur dans des fichiers Swift du lot 2 (hors `TextesWeb.swift`). */
export function textesJuridiquesHorsTL(fichiers) {
  const fautes = [];
  for (const { chemin, contenu } of fichiers) {
    if (chemin === TEXTES_SWIFT) continue;
    if (!DOSSIERS_LOT2.some(d => chemin === d || chemin.startsWith(`${d}/`))) continue;
    contenu.split('\n').forEach((ligne, i) => {
      for (const m of litterauxHorsCommentaire(ligne)) {
        if (MARQUES_JURIDIQUES.some(r => r.test(m[1]))) {
          fautes.push(`${chemin}:${i + 1} : texte juridique en dur « ${m[1]} » (le reprendre de TextesWeb.swift)`);
        }
      }
    });
  }
  return fautes;
}

function fichiersSwift(racine, relatif) {
  const plein = join(racine, relatif);
  if (!existsSync(plein)) return [];
  if (!statSync(plein).isDirectory()) return relatif.endsWith('.swift') ? [relatif] : [];
  return readdirSync(plein).filter(n => !n.startsWith('.')).flatMap(n => fichiersSwift(racine, `${relatif}/${n}`));
}

export function textesJuridiquesHorsTLSurDisque(racine = ROOT) {
  const fichiers = DOSSIERS_LOT2.flatMap(d => fichiersSwift(racine, d))
    .map(chemin => ({ chemin, contenu: readFileSync(join(racine, chemin), 'utf8') }));
  return textesJuridiquesHorsTL(fichiers);
}

export function main(argv = process.argv.slice(2)) {
  const swiftSource = readFileSync(join(ROOT, TEXTES_SWIFT), 'utf8');
  const lireWeb = lecteurWeb(fichier => readFileSync(join(ROOT, fichier), 'utf8'));
  const { erreurs, constantes } = verifierTextes({ swiftSource, lireWeb });
  const fautes = [...erreurs, ...textesJuridiquesHorsTLSurDisque(ROOT)];
  if (argv.includes('--liste')) {
    console.log('| Constante | Texte (verbatim) | Source |');
    console.log('|---|---|---|');
    for (const c of constantes) {
      console.log(`| \`${c.nom}\` | ${c.valeur.replace(/\|/g, '\\|')} | \`${c.source.fichier}:${c.source.debut === c.source.fin ? c.source.debut : `${c.source.debut}-${c.source.fin}`}\` |`);
    }
  }
  if (fautes.length) {
    for (const f of fautes) console.error(`✗ ${f}`);
    return 1;
  }
  if (!argv.includes('--liste')) console.log(`✓ ${constantes.length} textes juridiques iOS identiques au web`);
  return 0;
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  process.exit(main());
}
