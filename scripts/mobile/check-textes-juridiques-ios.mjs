#!/usr/bin/env node
/**
 * Garde des textes de l'app iOS (lot 2, tranche TL, `docs/mobile-swift/LOT2_PLAN.md` §3 « TL »,
 * critère P9, HARD STOP n°4 de CLAUDE.md).
 *
 * Deux fichiers Swift portent tous les textes que les écrans du lot 2 reprennent du web :
 *   - `Legal/TextesWeb.swift` (HARD STOP n°4) : textes juridiques et de consentement, chaque
 *     annotation suivie de sa nature (`[juridique]`, `[consentement]`, `[libellé]` pour un texte non
 *     juridique listé par le blueprint, `[fragment]` pour un morceau d'assemblage) ;
 *   - `Libelles/LibellesWeb.swift` (hors HARD STOP) : libellés non juridiques, sans nature ; une
 *     marque juridique y est refusée (le texte va dans TextesWeb).
 * Chaque constante est précédée de `// source: <fichier>:<ligne>` (ou `<début>-<fin>`) ; le script
 * parse ce fichier web (TypeScript TSX) et vérifie que la constante ÉGALE, au caractère près, un
 * texte affiché qui commence et finit à ces lignes :
 *   - texte JSX, avec le traitement des espaces de React/Babel (lignes coupées aux bords et jointes
 *     par une espace) et les entités HTML décodées ;
 *   - littéral de chaîne ou fragment de gabarit, décodé (`\'` → `'`).
 * Un texte INCHANGÉ retrouvé ailleurs dans le même fichier (décalage de lignes d'une PR web) est
 * toléré avec un avertissement : phrase longue retrouvée une seule fois, ou texte à la place que
 * donne le décalage de ses voisines gardées ; un texte modifié, disparu ou ambigu fait rougir la garde.
 *
 * Autres annotations :
 *   - `// source-objet: <fichier>:<ligne> <NOM>` avant un `[String: String]` : l'objet littéral
 *     `NOM` du web (même jeu de clés, chaque clé reliée à la constante du même texte) ;
 *     `<NOM>.<champ>` pour un objet d'objets (`STATUT_CONFIG.label` : le champ `label` de chaque clé) ;
 *   - `// source-ensemble: <fichier>:<début>-<fin>` avant un `Set<String>` : `new Set([...])`.
 * `catalogue` doit lister toutes les constantes du fichier (les tests Swift le parcourent). Tout
 * autre littéral de chaîne est refusé (sauf `" "` et `""`, séparateurs des assemblages), de même que
 * tout littéral multi-ligne (triple guillemet).
 *
 * Zones de rendu (`scripts/mobile/textes-web-ios-rendus.json`) : chaque fonction d'assemblage
 * (fonction, propriété calculée, liste de constantes) est ancrée sur le code web qui produit son
 * rendu (conditions, ordre, séparateurs), retrouvé par son contenu normalisé. Zone modifiée,
 * disparue ou ambiguë : erreur qui nomme la fonction Swift à relire ; zone décalée : avertissement.
 * Les `rendus` du même fichier (exemples assertés par les tests Swift) sont montrés à Gabrielle.
 *
 * Verrou Q9 (LOT2_PLAN §7 Q9, DECISIONS_LOT2, en attente de Gabrielle) : aucune constante ne reprend
 * un texte de délai de contestation du panneau (`ANCRES_Q9`, localisées par leur texte), ni ne
 * l'annonce dans leur bloc JSX, ni n'associe contestation ou litige et délai (`DELAI_CONTESTATION`).
 *
 * Enfin : aucun texte juridique en dur dans les fichiers Swift du lot 2 (`DOSSIERS_LOT2`) hors de
 * TextesWeb.swift, et aucune chaîne système nouvelle (`Info.plist`, `INFOPLIST_KEY_*`, fichiers
 * `.strings`/`.xcstrings`), que cette garde ne lit pas (LOT2_PLAN §7 Q5).
 *
 * Usage :
 *   node scripts/mobile/check-textes-juridiques-ios.mjs                   # vérifie, code 1 si erreur
 *   node scripts/mobile/check-textes-juridiques-ios.mjs --liste           # textes, natures et rendus (Markdown)
 *   node scripts/mobile/check-textes-juridiques-ios.mjs --corriger-lignes # réécrit les annotations
 *     des textes et les « source » des zones INCHANGÉS retrouvés à une autre ligne du même fichier
 *     (TextesWeb.swift, LibellesWeb.swift, textes-web-ios-rendus.json), puis revérifie ; un texte ou
 *     une zone modifiés ne sont jamais « corrigés ».
 *
 * Aucune valeur secrète n'est lue : le script ne lit que des fichiers du dépôt.
 */
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const SCRIPT = 'scripts/mobile/check-textes-juridiques-ios.mjs';
export const TEST_NODE = 'tests/node/textes-juridiques-ios.node.mjs';
export const TEXTES_SWIFT = 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Legal/TextesWeb.swift';
export const LIBELLES_SWIFT = 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Libelles/LibellesWeb.swift';
export const ZONES_RENDU_JSON = 'scripts/mobile/textes-web-ios-rendus.json';
export const INFO_PLIST = 'ios-native/Jolene/Info.plist';
const COMMANDE = `node ${SCRIPT}`;

/** Les deux fichiers de textes, leur espace de noms racine et leurs tests Swift. */
export const FICHIERS_SWIFT = [
  {
    chemin: TEXTES_SWIFT, racine: 'TextesWeb', hardStop: true,
    tests: 'ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/TextesWebTests.swift',
  },
  {
    chemin: LIBELLES_SWIFT, racine: 'LibellesWeb', hardStop: false,
    tests: 'ios-native/Packages/JoleneCore/Tests/JoleneCoreTests/LibellesWebTests.swift',
  },
];
const fichierDeRacine = racine => FICHIERS_SWIFT.find(f => f.racine === racine);
const decrireFichier = f => (f.hardStop
  ? `${f.chemin} (HARD STOP n°4 : PR validée par Gabrielle)`
  : `${f.chemin} (hors HARD STOP)`);

/** Natures d'un texte HARD STOP (annotation `// source: … [nature]` de TextesWeb.swift). */
export const NATURES = ['juridique', 'consentement', 'libellé', 'fragment'];

/**
 * Dossiers et fichiers Swift du lot 2 (LOT2_PLAN §2.1 et §3) où aucun texte juridique ne s'écrit
 * en dur. Les fichiers du lot 2 placés hors des dossiers d'écrans sont nommés un à un : aucun
 * fichier du lot 1 n'est concerné. La fondation de T1 en fait partie (journal et reçus, résultats,
 * ports, trousseau : messages `RecuScan.messageIllisible`, `KeychainTerminalIdentity.message*` ;
 * seconde revue fraîche de T1).
 */
export const DOSSIERS_LOT2 = [
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Pointage',
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Documents',
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Contrats',
  'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Pointage',
  'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Documents',
  'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Contrats',
  'ios-native/Packages/JoleneDesign/Sources/JoleneDesign/Components/CountdownLabel.swift',
  'ios-native/Packages/JoleneDesign/Sources/JoleneDesign/Components/NumericCodeField.swift',
  'ios-native/Packages/JoleneDesign/Sources/JoleneDesign/Components/StatusBadge.swift',
  'ios-native/Jolene/Screens/Presences',
  'ios-native/Jolene/Screens/Documents',
  'ios-native/Jolene/Screens/Contrats',
  'ios-native/Jolene/Screens/Profil/ConsentementGpsRow.swift',
  'ios-native/Jolene/Screens/Profil/EspaceSoignantSection.swift',
  'ios-native/Jolene/Composition/ContratReaderView.swift',
  'ios-native/Jolene/Composition/Device',
  'ios-native/Jolene/Composition/Media',
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Receipts',
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Models/Lot2Results.swift',
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Ports/Lot2Ports.swift',
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Ports/AppareilPorts.swift',
  'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Keychain/KeychainTerminalIdentity.swift',
  'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Keychain/KeychainReceiptStore.swift',
];

/**
 * Marques d'un texte juridique ou de consentement (citation de code, RGPD, attestation sur
 * l'honneur, consentement, signature électronique, délai de 72 h, preuve d'intégrité). Refusées
 * dans les fichiers Swift du lot 2 hors TextesWeb.swift et dans LibellesWeb.swift. Un identifiant
 * (`profil-gps-consentement`, `RGPD_CONSENTEMENT_DONNE`) n'est pas un texte : les littéraux sans
 * espace sont ignorés hors des fichiers de textes, et les marques de mot exigent qu'il ne soit pas
 * collé à un tiret.
 */
export const MARQUES_JURIDIQUES = [
  /Code civil/i, /Code du travail/i, /Code pénal/i, /RGPD/, /eIDAS/i, /Base légale/i,
  /J['’]atteste/i, /sur l['’]honneur/i, /\bart(?:icle|\.)\s*L?\.?\s*\d/i,
  /(?<![-\w])consentement(?![-\w])/i, /géolocalisation/i, /signature électronique/i,
  /pointage sans (?:GPS|localisation)/i, /\b72\s?h\b/i,
  /\bpreuve (?:juridique|que)\b/i, /horodatage/i, /SHA-?256/i,
];

/**
 * Verrou Q9 (LOT2_PLAN v2 §1.2, correction 14, §7 Q9 ; DECISIONS_LOT2 « En attente de
 * Gabrielle ») : les textes de délai du panneau de contestation contredisent le serveur
 * (`delai_contestation_pointage_h`, 48 h par défaut ; escalade vers `EN_MEDIATION`) et ne sont pas
 * affichés tant que Q9 n'est pas tranchée. Chaque ancre est retrouvée par son texte (où qu'il soit
 * dans le fichier) ; aucune constante ne pointe dans son bloc JSX ni n'en reprend un texte. Une ancre
 * disparue fait rougir la garde : le web a changé, Q9 est à relire.
 */
export const ANCRES_Q9 = [
  { fichier: 'src/components/PanneauContestation.tsx', motif: /72\s?h pour répondre/i },
  { fichier: 'src/components/PanneauContestation.tsx', motif: /admin plateforme tranchera/i },
  { fichier: 'src/components/PanneauContestation.tsx', motif: /après la validation pour contester/i },
];

/** Motifs des textes de délai de contestation, refusés quelle que soit la source annoncée. */
export const MOTIFS_Q9 = ANCRES_Q9.map(a => a.motif);

/** Toute constante qui associe contestation ou litige et délai est refusée, quel que soit son groupe. */
export const DELAI_CONTESTATION = {
  sujet: /contest|litige/i,
  delai: /\d+\s?(?:h|heures?|jours?)\b|délai/i,
};

const MESSAGE_Q9 = 'texte de délai de contestation interdit tant que Q9 n’est pas tranchée par Gabrielle '
  + '(LOT2_PLAN §7 Q9, DECISIONS_LOT2 « En attente de Gabrielle »)';

/**
 * Chaînes d'autorisation iOS d'`Info.plist`, verrouillées sur la liste et les textes actuels (lot 0) :
 * une nouvelle chaîne (par exemple `NSLocationTemporaryUsageDescriptionDictionary` pour
 * `requestTemporaryFullAccuracyAuthorization`, refusé par LOT2_PLAN §7 Q5) est un nouveau texte
 * exposé, que cette garde ne compare à aucun texte web.
 */
export const CHAINES_INFO_PLIST = {
  NSLocationWhenInUseUsageDescription: 'Jolene utilise votre position, à votre demande, pour valider un pointage ou localiser votre profil ou votre établissement.',
  NSLocationAlwaysAndWhenInUseUsageDescription: 'Jolene n’utilise votre position qu’au premier plan, lorsque vous demandez un pointage ou une localisation. Aucun suivi en arrière-plan n’est effectué.',
  NSCameraUsageDescription: 'Jolene utilise la caméra pour photographier vos documents professionnels et scanner les QR codes de pointage.',
  NSCalendarsUsageDescription: 'Jolene utilise le calendrier uniquement lorsque vous choisissez d’y ajouter une mission.',
  NSCalendarsWriteOnlyAccessUsageDescription: 'Jolene ajoute au calendrier les missions que vous sélectionnez.',
  NSPhotoLibraryUsageDescription: 'Jolene accède à vos photos pour téléverser vos documents professionnels.',
  NSPhotoLibraryAddUsageDescription: 'Jolene peut enregistrer une photo de document dans votre photothèque uniquement lorsque vous le demandez.',
  NSFaceIDUsageDescription: 'Jolene utilise Face ID ou Touch ID pour sécuriser la connexion à votre compte.',
};

/** Réglages de projet qui peuvent injecter des chaînes `Info.plist` (`INFOPLIST_KEY_*`). */
export const PROJETS_IOS = [
  'ios-native/project.yml',
  'ios-native/Jolene.xcodeproj/project.pbxproj',
  'ios-native/Config',
];

const TRIPLE_GUILLEMET = '"'.repeat(3);

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

/** Valeurs décodées des littéraux Swift d'un fichier (tests Swift : rendus assertés). */
export function litterauxSwift(source) {
  return [...source.matchAll(LITTERAL_SWIFT)].map(m => decoderSwift(m[1]).valeur).filter(v => v !== undefined);
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
 * Parse un fichier de textes (`TextesWeb.swift` par défaut). Rend les constantes (nom qualifié
 * depuis la racine, nom complet avec la racine), dictionnaires, ensembles, catalogue, assemblages
 * (fonctions, propriétés calculées, listes de constantes) et erreurs de forme.
 */
export function lireTextesSwift(source, fichier = FICHIERS_SWIFT[0]) {
  const { chemin: cheminSwift, racine, hardStop } = fichier;
  const lignes = source.split('\n');
  const pile = [];
  const constantes = [];
  const objets = [];
  const ensembles = [];
  const assemblages = [];
  const erreurs = [];
  let catalogue = null;
  let annotation = null;
  let bloc = null;
  let dansMultiLigne = false;
  const chemin = () => pile.filter(Boolean).slice(1).join('.');
  const qualifier = nom => (chemin() ? `${chemin()}.${nom}` : nom);
  const complet = nom => `${racine}.${nom}`;

  lignes.forEach((ligne, index) => {
    const numero = index + 1;
    const nette = ligne.trim();

    // Littéral multi-ligne : ses lignes intérieures n'ont pas de guillemets et échapperaient à
    // toutes les règles ci-dessous ; il est refusé en bloc (signalé à son ouverture).
    const triples = ligne.split(TRIPLE_GUILLEMET).length - 1;
    if (triples || dansMultiLigne) {
      if (triples && !dansMultiLigne) {
        erreurs.push(`${cheminSwift}:${numero} : littéral multi-ligne (triple guillemet) interdit : texte hors constante annotée`);
      }
      if (triples % 2) dansMultiLigne = !dansMultiLigne;
      return;
    }

    if (bloc) {
      if (/^\]\s*$/.test(nette)) { bloc = null; return; }
      if (bloc.genre === 'objet') {
        const m = /^"([A-Z0-9_]+)"\s*:\s*([\w.]+)\s*,?$/.exec(nette);
        if (m) bloc.cible.entrees.push({ cle: m[1], ref: m[2], ligneSwift: numero });
        else erreurs.push(`${cheminSwift}:${numero} : entrée de dictionnaire illisible « ${nette} »`);
      } else if (bloc.genre === 'ensemble') {
        const valeurs = [...nette.matchAll(LITTERAL_SWIFT)].map(m => m[1]);
        if (!valeurs.length || nette.replace(LITTERAL_SWIFT, '').replace(/[\s,]/g, '')) {
          erreurs.push(`${cheminSwift}:${numero} : élément d'ensemble illisible « ${nette} »`);
        }
        bloc.cible.elements.push(...valeurs);
      } else if (bloc.genre === 'catalogue') {
        const m = /^\.init\(cle:\s*"([\w.]+)",\s*texte:\s*([\w.]+)\),?$/.exec(nette);
        if (m) bloc.cible.push({ cle: m[1], ref: m[2], ligneSwift: numero });
        else erreurs.push(`${cheminSwift}:${numero} : entrée de catalogue illisible « ${nette} »`);
      }
      return;
    }

    if (nette.startsWith('//')) {
      let m = /^\/\/ source: (\S+)(?:\s+\[([^\]]*)\])?$/.exec(nette);
      if (m) {
        const src = lireSource(m[1]);
        const nature = m[2] ?? null;
        if (!src) erreurs.push(`${cheminSwift}:${numero} : annotation illisible « ${nette} »`);
        else {
          if (hardStop && !NATURES.includes(nature)) {
            erreurs.push(`${cheminSwift}:${numero} : nature manquante ou inconnue « ${nature ?? ''} » `
              + `(attendu : // source: <fichier>:<ligne> [${NATURES.join('|')}])`);
          }
          if (!hardStop && nature !== null) {
            erreurs.push(`${cheminSwift}:${numero} : nature « ${nature} » interdite : tout ${racine}.swift est libellé `
              + 'hors HARD STOP (un texte juridique va dans TextesWeb.swift)');
          }
          annotation = { genre: 'texte', source: src, nature, ligne: numero };
        }
        return;
      }
      m = /^\/\/ source-objet: (\S+) (\w+)(?:\.(\w+))?$/.exec(nette);
      if (m) {
        const src = lireSource(m[1]);
        if (!src) erreurs.push(`${cheminSwift}:${numero} : annotation illisible « ${nette} »`);
        else annotation = { genre: 'objet', source: { ...src, variable: m[2], champ: m[3] ?? null }, ligne: numero };
        return;
      }
      m = /^\/\/ source-ensemble: (\S+)$/.exec(nette);
      if (m) {
        const src = lireSource(m[1]);
        if (!src) erreurs.push(`${cheminSwift}:${numero} : annotation illisible « ${nette} »`);
        else annotation = { genre: 'ensemble', source: src, ligne: numero };
        return;
      }
      if (/^\/\/\s*source/.test(nette)) erreurs.push(`${cheminSwift}:${numero} : annotation illisible « ${nette} »`);
      return;
    }

    const constante = /^(?:public\s+)?static\s+let\s+(\w+)(?:\s*:\s*String)?\s*=\s*"((?:[^"\\]|\\.)*)"\s*$/.exec(nette);
    const objet = /^(?:public\s+)?static\s+let\s+(\w+)\s*:\s*\[String\s*:\s*String\]\s*=\s*\[\s*$/.exec(nette);
    const ensemble = /^(?:public\s+)?static\s+let\s+(\w+)\s*:\s*Set<String>\s*=\s*\[\s*$/.exec(nette);
    const cat = /^(?:public\s+)?static\s+let\s+catalogue\s*:\s*\[EntreeTexteWeb\]\s*=\s*\[\s*$/.exec(nette);

    if (constante || objet || ensemble) {
      if (pile.filter(Boolean)[0] !== racine) {
        erreurs.push(`${cheminSwift}:${numero} : déclaration hors de l'espace de noms ${racine}`);
      }
    }
    if (constante) {
      const nom = qualifier(constante[1]);
      const decode = decoderSwift(constante[2]);
      if (decode.erreur) erreurs.push(`${complet(nom)} (${cheminSwift}:${numero}) : ${decode.erreur}`);
      else if (!annotation || annotation.genre !== 'texte') {
        erreurs.push(`${complet(nom)} (${cheminSwift}:${numero}) : constante sans annotation « // source: <fichier>:<ligne> »`);
      } else {
        constantes.push({
          nom, nomComplet: complet(nom), racine, fichierSwift: cheminSwift, hardStop,
          valeur: decode.valeur, source: annotation.source, nature: annotation.nature,
          ligneSwift: numero, ligneAnnotation: annotation.ligne,
        });
      }
      annotation = null;
      return;
    }
    if (objet || ensemble) {
      const genre = objet ? 'objet' : 'ensemble';
      const nom = qualifier((objet ?? ensemble)[1]);
      if (!annotation || annotation.genre !== genre) {
        erreurs.push(`${complet(nom)} (${cheminSwift}:${numero}) : ${genre} sans annotation « // source-${genre}: … »`);
      }
      const ligneAnnotation = annotation?.ligne;
      const cible = genre === 'objet'
        ? { nom, nomComplet: complet(nom), fichierSwift: cheminSwift, chemin: chemin(), source: annotation?.source, entrees: [], ligneSwift: numero, ligneAnnotation }
        : { nom, nomComplet: complet(nom), fichierSwift: cheminSwift, source: annotation?.source, elements: [], ligneSwift: numero, ligneAnnotation };
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

    // Assemblages : fonctions, propriétés calculées, listes de constantes (ancrés par les zones).
    const fonction = /^(public\s+)?(?:static\s+)?func\s+(\w+)\s*\(/.exec(nette);
    const propriete = /^(public\s+)?(?:static\s+)?var\s+(\w+)\s*:\s*String\??\s*\{/.exec(nette);
    const liste = /^(public\s+)?static\s+let\s+(\w+)\s*=\s*\[[\w.,\s]+\]\s*$/.exec(nette);
    const assemblage = fonction ?? propriete ?? liste;
    if (assemblage) {
      const nom = qualifier(assemblage[2]);
      assemblages.push({
        nom, nomComplet: complet(nom), fichierSwift: cheminSwift, public: Boolean(assemblage[1]),
        genre: fonction ? 'fonction' : propriete ? 'propriété' : 'liste', ligneSwift: numero,
      });
    }

    // Tout autre littéral : seuls les séparateurs des assemblages sont admis.
    for (const m of litterauxHorsCommentaire(ligne)) {
      if (m[1] !== ' ' && m[1] !== '') {
        erreurs.push(`${cheminSwift}:${numero} : littéral non gardé « ${m[1]} » (texte hors constante annotée)`);
      }
    }
    // Une annotation ne vaut que pour la déclaration qui la suit immédiatement.
    if (nette && annotation) {
      erreurs.push(`${cheminSwift}:${annotation.ligne} : annotation qui ne précède aucune constante gardée`);
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

  return { constantes, objets, ensembles, catalogue, assemblages, erreurs };
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
 * gabarit. Chaque unité porte sa valeur (bords coupés), ses lignes (premier et dernier caractère
 * non blanc), ses positions dans le fichier et les lignes de l'élément JSX qui la contient.
 */
export function unitesWeb(fichier, texte) {
  return analyserWeb(fichier, texte).unites;
}

function analyserWeb(fichier, texte) {
  const sf = ts.createSourceFile(fichier, texte, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const unites = [];
  const ligne = pos => sf.getLineAndCharacterOfPosition(pos).line + 1;
  const blocDe = noeud => {
    let p = noeud.parent;
    while (p && !ts.isJsxElement(p) && !ts.isJsxSelfClosingElement(p) && !ts.isJsxFragment(p)) p = p.parent;
    return p ? { debut: ligne(p.getStart(sf)), fin: ligne(p.end - 1) } : null;
  };
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
    const debut = ligne(offset);
    const fin = ligne(offsetFin - 1);
    unites.push({ valeur: valeur.trim(), genre, debut, fin, offset, offsetFin, cle, bloc: blocDe(noeud) ?? { debut, fin } });
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
        const nomDe = p => p.name.getText(sf).replace(/^['"]|['"]$/g, '');
        const estTexte = v => v && (ts.isStringLiteral(v) || ts.isNoSubstitutionTemplateLiteral(v));
        const proprietes = new Map();
        // Objet d'objets (`{ OUVERT: { label: 'Ouvert', … } }`) : champ → (clé → texte).
        const champs = new Map();
        for (const p of init.properties) {
          if (!ts.isPropertyAssignment(p)) continue;
          const valeur = deballer(p.initializer);
          if (estTexte(valeur)) {
            proprietes.set(nomDe(p), { valeur: valeur.text, ligne: ligne(valeur.getStart(sf)) });
          } else if (valeur && ts.isObjectLiteralExpression(valeur)) {
            for (const q of valeur.properties) {
              if (!ts.isPropertyAssignment(q)) continue;
              const texte = deballer(q.initializer);
              if (!estTexte(texte)) continue;
              if (!champs.has(nomDe(q))) champs.set(nomDe(q), new Map());
              champs.get(nomDe(q)).set(nomDe(p), { valeur: texte.text, ligne: ligne(texte.getStart(sf)) });
            }
          }
        }
        objets.push({ nom: noeud.name.text, ligne: ligne(noeud.getStart(sf)), proprietes, champs });
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

/** Ligne de code normalisée : bords coupés, espaces internes réduites à une. */
export const normaliserLigne = l => l.trim().replace(/\s+/g, ' ');

/** Lignes non vides d'un fichier, normalisées, avec leur numéro. */
function lignesNormalisees(texte) {
  return texte.split('\n').map((l, i) => ({ ligne: i + 1, code: normaliserLigne(l) })).filter(x => x.code);
}

/** Lecteur de fichiers web avec cache des analyses ; `lire(fichier)` rend le contenu ou lève. */
export function lecteurWeb(lire) {
  const cache = new Map();
  return fichier => {
    if (!cache.has(fichier)) {
      let contenu;
      try { contenu = lire(fichier); } catch { contenu = null; }
      if (contenu === null || contenu === undefined) cache.set(fichier, null);
      else {
        const { unites, sf } = analyserWeb(fichier, contenu);
        cache.set(fichier, { unites, ...structuresWeb(sf), texte: contenu, normes: lignesNormalisees(contenu) });
      }
    }
    return cache.get(fichier);
  };
}

// ---------------------------------------------------------------------------------------------
// Localisation (texte exact, décalé, modifié, ambigu)
// ---------------------------------------------------------------------------------------------

const lignesDe = s => (s.debut === s.fin ? `l.${s.debut}` : `l.${s.debut}-${s.fin}`);
const formatSource = (debut, fin) => (debut === fin ? `${debut}` : `${debut}-${fin}`);

/** Longueur (caractères) à partir de laquelle un texte retrouvé une seule fois ailleurs est tenu pour déplacé. */
export const TEXTE_LONG = 40;

/**
 * Situe chaque constante dans son fichier web : `exact` (texte à la ligne annoncée), `decale`
 * (texte inchangé retrouvé ailleurs, à la place que donne le décalage de ses voisines), `modifie`
 * (texte absent, ou seule copie identique hors de cette place : le texte a pu changer à sa ligne
 * alors que le même texte existe ailleurs), `ambigu` (plusieurs copies possibles), `fichier`
 * (fichier introuvable). Chaque occurrence web ne sert qu'à une constante.
 *
 * Une PR web qui ajoute ou retire des lignes décale d'autant tous les textes qui suivent : le
 * décalage d'un texte déplacé est compris entre celui de la voisine gardée qui le précède et celui
 * de la voisine qui le suit (ou égal à celui de son unique voisine). Les voisines situées servent
 * d'appui de proche en proche, à partir des textes exacts et des phrases longues (TEXTE_LONG
 * caractères et plus) retrouvées une seule fois, tenues pour déplacées. Un texte court peut avoir
 * une copie fortuite (ex. `usePageTitle('Certificat de signature')` l.43 de
 * CertificatSignaturePage.tsx, copie du titre l.185) : il n'est déplacé que s'il suit ses voisines.
 */
function localiserConstantes(constantes, lireWeb) {
  const etats = new Map();
  const prises = new Set();
  for (const c of constantes) {
    const web = lireWeb(c.source.fichier);
    if (!web) { etats.set(c, { statut: 'fichier' }); continue; }
    const u = web.unites.find(x => !prises.has(x) && x.valeur === c.valeur && x.debut === c.source.debut && x.fin === c.source.fin);
    if (u) { prises.add(u); etats.set(c, { statut: 'exact', unite: u }); }
  }
  const libres = c => lireWeb(c.source.fichier).unites.filter(x => !prises.has(x) && x.valeur === c.valeur);
  const delta = c => etats.get(c).unite.debut - c.source.debut;
  const situer = (c, u) => { prises.add(u); etats.set(c, { statut: 'decale', unite: u }); };
  const enAttente = () => constantes.filter(c => !etats.has(c));
  // Phrases longues retrouvées une seule fois : déplacées.
  for (const c of enAttente()) {
    const occurrences = libres(c);
    if (occurrences.length === 1 && [...c.valeur].length >= TEXTE_LONG) situer(c, occurrences[0]);
  }
  // De proche en proche : un texte (ou les textes identiques d'une même ligne, « s » deux fois dans
  // un gabarit) prend les occurrences dont le décalage suit ses voisines déjà situées.
  const bornesDe = c => {
    const voisines = constantes.filter(x => x !== c && etats.get(x)?.unite && x.source.fichier === c.source.fichier);
    const avant = voisines.filter(x => x.source.debut <= c.source.debut).sort((a, b) => b.source.debut - a.source.debut)[0];
    const apres = voisines.filter(x => x.source.debut >= c.source.debut).sort((a, b) => a.source.debut - b.source.debut)[0];
    return [avant, apres].filter(Boolean).map(delta);
  };
  const suit = (bornes, d) => bornes.length > 0 && d >= Math.min(...bornes) && d <= Math.max(...bornes);
  let progres = true;
  while (progres) {
    progres = false;
    for (const c of enAttente()) {
      if (etats.has(c)) continue;
      const bornes = bornesDe(c);
      if (!bornes.length) continue;
      const soeurs = enAttente().filter(x => x.valeur === c.valeur && x.source.fichier === c.source.fichier
        && x.source.debut === c.source.debut && x.source.fin === c.source.fin);
      const places = libres(c).filter(u => suit(bornes, u.debut - c.source.debut) && u.fin - u.debut === c.source.fin - c.source.debut);
      if (places.length !== soeurs.length) continue;
      soeurs.forEach((s, i) => situer(s, places[i]));
      progres = true;
    }
  }
  // Fichier dont aucun texte n'a pu servir d'appui : un texte unique retrouvé une seule fois est déplacé.
  for (const c of enAttente()) {
    const autres = constantes.filter(x => x !== c && x.source.fichier === c.source.fichier && etats.get(x)?.unite);
    const occurrences = libres(c);
    if (!autres.length && occurrences.length === 1
      && !constantes.some(x => x !== c && x.source.fichier === c.source.fichier && x.valeur === c.valeur)) {
      situer(c, occurrences[0]);
    }
  }
  for (const c of enAttente()) {
    const occurrences = libres(c);
    if (!occurrences.length) etats.set(c, { statut: 'modifie' });
    else if (occurrences.length === 1) etats.set(c, { statut: 'modifie', copie: occurrences[0] });
    else etats.set(c, { statut: 'ambigu', occurrences });
  }
  return etats;
}

/** Positions (première et dernière ligne) où la suite de lignes normalisées `code` apparaît. */
function positionsZone(web, code) {
  const positions = [];
  const n = code.length;
  for (let i = 0; i + n <= web.normes.length; i += 1) {
    let egal = true;
    for (let k = 0; k < n && egal; k += 1) egal = web.normes[i + k].code === code[k];
    if (egal) positions.push({ debut: web.normes[i].ligne, fin: web.normes[i + n - 1].ligne });
  }
  return positions;
}

/**
 * Situe chaque zone de rendu : `exact`, `decale` (une seule fois ailleurs ; pour une zone d'une
 * ligne, à une place compatible avec le décalage des textes gardés voisins du même fichier, comme
 * pour les textes courts), `modifie` (absente, ou copie hors de cette place), `ambigu`, `fichier`.
 */
function localiserZones(zones, lireWeb, constantes) {
  const situees = constantes.filter(c => c.etat?.statut === 'exact' || c.etat?.statut === 'decale');
  const coherente = (source, delta) => {
    const voisines = situees.filter(c => c.source.fichier === source.fichier);
    const avant = voisines.filter(c => c.source.debut <= source.debut).sort((a, b) => b.source.debut - a.source.debut)[0];
    const apres = voisines.filter(c => c.source.debut >= source.debut).sort((a, b) => a.source.debut - b.source.debut)[0];
    const bornes = [avant, apres].filter(Boolean).map(c => c.position.debut - c.source.debut);
    return !bornes.length || (delta >= Math.min(...bornes) && delta <= Math.max(...bornes));
  };
  return zones.map(zone => {
    const source = lireSource(zone.source ?? '');
    if (!source) return { zone, source: null, statut: 'illisible' };
    const web = lireWeb(source.fichier);
    if (!web) return { zone, source, statut: 'fichier' };
    const positions = positionsZone(web, zone.code ?? []);
    if (positions.some(p => p.debut === source.debut && p.fin === source.fin)) return { zone, source, statut: 'exact', position: source };
    // Une zone de plusieurs lignes retrouvée une seule fois est déplacée ; une zone d'une ligne
    // doit en plus suivre le décalage des textes gardés voisins (copie fortuite possible).
    if (positions.length === 1 && (zone.code.length >= 2 || coherente(source, positions[0].debut - source.debut))) {
      return { zone, source, statut: 'decale', position: positions[0] };
    }
    return { zone, source, statut: positions.length > 1 ? 'ambigu' : 'modifie', positions, web };
  });
}

/** Lit `textes-web-ios-rendus.json` (zones et rendus). */
export function lireZonesRendu(racine = ROOT) {
  return JSON.parse(readFileSync(join(racine, ZONES_RENDU_JSON), 'utf8'));
}

// ---------------------------------------------------------------------------------------------
// Vérification
// ---------------------------------------------------------------------------------------------

const lireDepot = relatif => readFileSync(join(ROOT, relatif), 'utf8');

/**
 * Vérifie TextesWeb.swift et LibellesWeb.swift contre le web, et les zones de rendu. Rend
 * `{ erreurs, avertissements, constantes, objets, ensembles, assemblages, zones, rendus }`.
 */
export function verifierTextes({ swiftSource, libellesSource, zonesRendu, lireWeb }) {
  const sources = {
    [TEXTES_SWIFT]: swiftSource ?? lireDepot(TEXTES_SWIFT),
    [LIBELLES_SWIFT]: libellesSource ?? lireDepot(LIBELLES_SWIFT),
  };
  const { zones = [], rendus = [] } = zonesRendu ?? lireZonesRendu();
  const erreurs = [];
  const avertissements = [];
  const lus = FICHIERS_SWIFT.map(f => ({ fichier: f, ...lireTextesSwift(sources[f.chemin], f) }));
  const constantes = lus.flatMap(l => l.constantes);
  const objets = lus.flatMap(l => l.objets);
  const ensembles = lus.flatMap(l => l.ensembles);
  const assemblages = lus.flatMap(l => l.assemblages);
  for (const l of lus) erreurs.push(...l.erreurs);
  const parNom = new Map();
  for (const c of constantes) {
    if (parNom.has(c.nomComplet)) erreurs.push(`${c.nomComplet} : constante déclarée deux fois`);
    parNom.set(c.nomComplet, c);
  }

  // Textes : exacts, décalés (tolérés), modifiés, ambigus.
  const etats = localiserConstantes(constantes.filter(c => c.valeur), lireWeb);
  for (const c of constantes) {
    const f = fichierDeRacine(c.racine);
    if (!c.valeur) { erreurs.push(`${c.nomComplet} : constante vide`); continue; }
    if (c.valeur !== c.valeur.trim()) erreurs.push(`${c.nomComplet} : espace au bord de la constante`);
    const etat = etats.get(c);
    c.etat = etat;
    c.position = etat.unite ? { debut: etat.unite.debut, fin: etat.unite.fin } : c.source;
    if (etat.statut === 'fichier') erreurs.push(`${c.nomComplet} : fichier source introuvable ${c.source.fichier}`);
    else if (etat.statut === 'decale') {
      avertissements.push(`${c.nomComplet} : texte inchangé retrouvé ${lignesDe(etat.unite)} de ${c.source.fichier} `
        + `(annoncé ${lignesDe(c.source)}) : toléré ; réaligner l'annotation de ${f.chemin} avec `
        + `\`${COMMANDE} --corriger-lignes\``);
    } else if (etat.statut === 'ambigu') {
      erreurs.push(`${c.nomComplet} : « ${c.valeur} » n'est plus ${lignesDe(c.source)} de ${c.source.fichier} et y figure `
        + `plusieurs fois ailleurs (${etat.occurrences.map(lignesDe).join(', ')}) : choisir la ligne à la main dans `
        + `l'annotation de ${decrireFichier(f)}`);
    } else if (etat.statut === 'modifie') {
      const web = lireWeb(c.source.fichier);
      const aLaLigne = web.unites.filter(u => u.debut === c.source.debut);
      // Constantes du même texte à la même ligne (« s » deux fois dans un gabarit) : nommées aussi,
      // car l'occurrence restante est attribuée à l'une d'elles au hasard de l'ordre.
      const memes = constantes.filter(x => x !== c && x.valeur === c.valeur && x.source.fichier === c.source.fichier
        && x.source.debut === c.source.debut && x.source.fin === c.source.fin);
      erreurs.push(`${c.nomComplet}${memes.length ? ` (avec ${memes.map(x => x.nomComplet).join(', ')})` : ''} : `
        + `${c.source.fichier} ${lignesDe(c.source)} n'affiche plus (ou plus autant de fois) « ${c.valeur} »`
        + (aLaLigne.length ? ` (le web affiche : ${aLaLigne.map(u => `« ${u.valeur} »`).join(', ')})` : ' (aucun texte à cette ligne)')
        + (etat.copie ? ` ; un texte identique figure ${lignesDe(etat.copie)}, hors de la place de ses voisines : `
          + 'texte modifié à sa ligne, ou déplacé (alors corriger l\'annotation à la main)' : '')
        + ` : relire le texte web ; s'il a changé, mettre à jour la constante dans ${decrireFichier(f)} et ${f.tests}`);
    }
  }

  // LibellesWeb.swift (hors HARD STOP) : aucune marque juridique.
  for (const c of constantes.filter(x => !x.hardStop)) {
    const marque = MARQUES_JURIDIQUES.find(r => r.test(c.valeur));
    if (marque) {
      erreurs.push(`${c.nomComplet} : texte juridique (${marque}) dans ${LIBELLES_SWIFT}, hors HARD STOP : `
        + `le déplacer dans ${TEXTES_SWIFT} (HARD STOP n°4)`);
    }
  }

  // Verrou Q9 : ancres retrouvées par leur texte ; ni constante dans leur bloc JSX, ni valeur d'un
  // texte de ces blocs, ni motif de délai, ni contestation associée à un délai.
  const blocsQ9 = [];
  const valeursQ9 = new Set();
  for (const ancre of ANCRES_Q9) {
    const web = lireWeb(ancre.fichier);
    if (!web) { erreurs.push(`ANCRES_Q9 : ${ancre.fichier} introuvable`); continue; }
    const unites = web.unites.filter(u => ancre.motif.test(u.valeur));
    if (!unites.length) {
      erreurs.push(`ANCRES_Q9 : ${ancre.fichier} n'affiche plus de texte ${ancre.motif} : le web a changé, relire Q9 `
        + `(LOT2_PLAN §7 Q9) puis mettre à jour ANCRES_Q9 (${SCRIPT}) et ${TEST_NODE}`);
    }
    for (const u of unites) blocsQ9.push({ fichier: ancre.fichier, ...u.bloc });
  }
  for (const b of blocsQ9) {
    for (const u of lireWeb(b.fichier).unites) {
      if (u.debut <= b.fin && u.fin >= b.debut && /\p{L}.*\p{L}.*\p{L}/u.test(u.valeur)) valeursQ9.add(u.valeur);
    }
  }
  for (const c of constantes) {
    const touche = s => blocsQ9.some(b => b.fichier === c.source.fichier && s.debut <= b.fin && s.fin >= b.debut);
    const delai = DELAI_CONTESTATION.sujet.test(c.valeur) && DELAI_CONTESTATION.delai.test(c.valeur);
    if (touche(c.source) || touche(c.position ?? c.source) || valeursQ9.has(c.valeur) || MOTIFS_Q9.some(m => m.test(c.valeur)) || delai) {
      erreurs.push(`${c.nomComplet} (${c.source.fichier} ${lignesDe(c.source)}) : ${MESSAGE_Q9}`);
    }
  }

  // Dictionnaires : référence locale à l'espace de noms d'abord, puis qualifiée depuis la racine.
  const resoudre = (ref, o) => {
    const racine = o.nomComplet.split('.')[0];
    return (o.chemin && parNom.get(`${racine}.${o.chemin}.${ref}`)) || parNom.get(`${racine}.${ref}`) || parNom.get(ref);
  };
  for (const o of objets) {
    if (!o.source) continue;
    const web = lireWeb(o.source.fichier);
    const nomWeb = o.source.champ ? `${o.source.variable}.${o.source.champ}` : o.source.variable;
    let cible = web?.objets.find(x => x.nom === o.source.variable && x.ligne === o.source.debut);
    if (!cible && web) {
      const memes = web.objets.filter(x => x.nom === o.source.variable);
      if (memes.length === 1) {
        cible = memes[0];
        o.position = { debut: cible.ligne, fin: cible.ligne };
        avertissements.push(`${o.nomComplet} : objet ${o.source.variable} retrouvé l.${cible.ligne} de ${o.source.fichier} `
          + `(annoncé ${lignesDe(o.source)}) : toléré ; \`${COMMANDE} --corriger-lignes\``);
      } else if (memes.length > 1) {
        erreurs.push(`${o.nomComplet} : objet ${o.source.variable} présent plusieurs fois dans ${o.source.fichier}`);
        continue;
      }
    }
    if (!cible) {
      erreurs.push(`${o.nomComplet} : objet ${o.source.variable} introuvable dans ${o.source.fichier}`);
      continue;
    }
    const proprietes = o.source.champ ? (cible.champs.get(o.source.champ) ?? new Map()) : cible.proprietes;
    if (!proprietes.size) erreurs.push(`${o.nomComplet} : ${nomWeb} n'a aucun texte (web)`);
    const clesSwift = new Set();
    for (const e of o.entrees) {
      if (clesSwift.has(e.cle)) erreurs.push(`${o.nomComplet} : clé ${e.cle} répétée`);
      clesSwift.add(e.cle);
      const attendu = proprietes.get(e.cle);
      const constante = resoudre(e.ref, o);
      if (!attendu) erreurs.push(`${o.nomComplet} : clé ${e.cle} absente de ${nomWeb} (web)`);
      else if (!constante) erreurs.push(`${o.nomComplet} : ${e.cle} → ${e.ref}, constante inconnue`);
      else if (constante.valeur !== attendu.valeur || constante.source.fichier !== o.source.fichier
        || (constante.position ?? constante.source).debut !== attendu.ligne) {
        erreurs.push(`${o.nomComplet} : ${e.cle} → ${constante.nomComplet} ne correspond pas à ${nomWeb}[${e.cle}] `
          + `(web l.${attendu.ligne} : « ${attendu.valeur} »)`);
      }
    }
    for (const cle of proprietes.keys()) {
      if (!clesSwift.has(cle)) erreurs.push(`${o.nomComplet} : clé ${cle} de ${nomWeb} absente du dictionnaire Swift`);
    }
  }

  for (const e of ensembles) {
    if (!e.source) continue;
    const web = lireWeb(e.source.fichier);
    const swift = new Set(e.elements);
    const memeContenu = x => {
      const autre = new Set(x.elements);
      return autre.size === swift.size && [...swift].every(v => autre.has(v));
    };
    let cible = web?.ensembles.find(x => x.debut === e.source.debut && x.fin === e.source.fin);
    if (!cible && web) {
      const memes = web.ensembles.filter(memeContenu);
      if (memes.length === 1) {
        cible = memes[0];
        e.position = { debut: cible.debut, fin: cible.fin };
        avertissements.push(`${e.nomComplet} : new Set([...]) retrouvé ${lignesDe(cible)} de ${e.source.fichier} `
          + `(annoncé ${lignesDe(e.source)}) : toléré ; \`${COMMANDE} --corriger-lignes\``);
      } else if (memes.length > 1) {
        erreurs.push(`${e.nomComplet} : new Set([...]) présent plusieurs fois dans ${e.source.fichier}`);
        continue;
      }
    }
    if (!cible) {
      erreurs.push(`${e.nomComplet} : new Set([...]) introuvable ${lignesDe(e.source)} de ${e.source.fichier}`);
      continue;
    }
    const webSet = new Set(cible.elements);
    for (const x of webSet) if (!swift.has(x)) erreurs.push(`${e.nomComplet} : ${x} présent sur le web, absent du Swift`);
    for (const x of swift) if (!webSet.has(x)) erreurs.push(`${e.nomComplet} : ${x} absent du web`);
    if (swift.size !== e.elements.length) erreurs.push(`${e.nomComplet} : élément répété`);
  }

  for (const l of lus) {
    const racine = l.fichier.racine;
    if (!l.catalogue) { erreurs.push(`${l.fichier.chemin} : \`public static let catalogue: [EntreeTexteWeb] = [\` absent`); continue; }
    const vus = new Set();
    for (const entree of l.catalogue) {
      if (entree.cle !== entree.ref) erreurs.push(`catalogue de ${racine} : ${entree.cle} pointe vers ${entree.ref}`);
      if (!parNom.has(`${racine}.${entree.cle}`)) erreurs.push(`catalogue de ${racine} : ${entree.cle} n'est pas une constante gardée`);
      if (vus.has(entree.cle)) erreurs.push(`catalogue de ${racine} : ${entree.cle} répétée`);
      vus.add(entree.cle);
    }
    for (const c of l.constantes) if (!vus.has(c.nom)) erreurs.push(`catalogue de ${racine} : ${c.nom} absente du catalogue`);
  }

  // Zones de rendu : chaque assemblage ancré, chaque zone retrouvée par son contenu.
  const parAssemblage = new Map(assemblages.map(a => [a.nomComplet, a]));
  const sourcesVues = new Set();
  const zonesLocalisees = localiserZones(zones, lireWeb, constantes);
  for (const z of zonesLocalisees) {
    const { zone } = z;
    const fonctions = zone.fonctions ?? [];
    const fichiers = [...new Set(fonctions.map(n => fichierDeRacine(n.split('.')[0])).filter(Boolean))];
    const aRelire = `relire ${fonctions.join(', ')} dans ${fichiers.map(decrireFichier).join(' et ')} et `
      + `${fichiers.map(f => f.tests).join(' et ')}`;
    if (!fonctions.length || !zone.code?.length) erreurs.push(`zone ${zone.source} : fonctions ou code vides (${ZONES_RENDU_JSON})`);
    if (sourcesVues.has(zone.source)) erreurs.push(`zone ${zone.source} déclarée deux fois (${ZONES_RENDU_JSON}) : fusionner ses fonctions`);
    sourcesVues.add(zone.source);
    for (const nom of fonctions) {
      if (!parAssemblage.has(nom)) erreurs.push(`zone ${zone.source} : ${nom} n'est pas un assemblage de TextesWeb.swift ou de LibellesWeb.swift (${ZONES_RENDU_JSON})`);
    }
    if (z.statut === 'illisible') erreurs.push(`zone « ${zone.source} » : source illisible (${ZONES_RENDU_JSON})`);
    else if (z.statut === 'fichier') erreurs.push(`zone ${zone.source} : fichier ${z.source.fichier} introuvable : ${aRelire}`);
    else if (z.statut === 'decale') {
      avertissements.push(`zone de rendu ${z.source.fichier} ${lignesDe(z.source)} (${fonctions.join(', ')}) inchangée, `
        + `retrouvée ${lignesDe(z.position)} : tolérée ; réaligner ${ZONES_RENDU_JSON} avec \`${COMMANDE} --corriger-lignes\``);
    } else if (z.statut === 'ambigu') {
      erreurs.push(`zone de rendu ${z.source.fichier} ${lignesDe(z.source)} (${fonctions.join(', ')}) déplacée et présente `
        + `plusieurs fois (${z.positions.map(lignesDe).join(', ')}) : ${aRelire}, puis choisir sa « source » dans ${ZONES_RENDU_JSON}`);
    } else if (z.statut === 'modifie') {
      const actuelles = z.web.normes.filter(x => x.ligne >= z.source.debut).slice(0, zone.code.length);
      erreurs.push(`zone de rendu ${z.source.fichier} ${lignesDe(z.source)} modifiée ou disparue`
        + (z.positions.length ? ` (copie identique ${lignesDe(z.positions[0])}, hors de la place de ses textes voisins)` : '')
        + ` : le rendu de ${fonctions.join(', ')} n'est plus prouvé ; ${aRelire} (un changement de TextesWeb.swift est une PR HARD STOP n°4 `
        + `validée par Gabrielle), puis recopier la zone dans ${ZONES_RENDU_JSON}. Code web actuel à partir de l.${z.source.debut} : `
        + actuelles.map(x => `l.${x.ligne} | ${x.code}`).join(' ⏎ '));
    }
  }
  const ancrees = new Set(zones.flatMap(z => z.fonctions ?? []));
  for (const a of assemblages) {
    if (!ancrees.has(a.nomComplet)) {
      erreurs.push(`${a.nomComplet} (${a.fichierSwift}:${a.ligneSwift}) : assemblage sans zone de rendu : ancrer le code web `
        + `qui produit son rendu dans ${ZONES_RENDU_JSON}`);
    }
  }
  for (const r of rendus) {
    if (!parAssemblage.has(r.fonction)) erreurs.push(`rendu « ${r.rendu} » : ${r.fonction} n'est pas un assemblage (${ZONES_RENDU_JSON})`);
  }

  return { erreurs, avertissements, constantes, objets, ensembles, assemblages, zones: zonesLocalisees, rendus };
}

/** Réécrit, sur la ligne d'annotation, `fichier:ancienne` en `fichier:nouvelle`. */
function reannoter(ligne, fichier, ancienne, nouvelle) {
  const avant = `${fichier}:${formatSource(ancienne.debut, ancienne.fin)}`;
  const apres = `${fichier}:${formatSource(nouvelle.debut, nouvelle.fin)}`;
  const i = ligne.indexOf(avant);
  if (i < 0 || !/^(?:\s|$)/.test(ligne.slice(i + avant.length))) return null;
  return ligne.slice(0, i) + apres + ligne.slice(i + avant.length);
}

/**
 * `--corriger-lignes` : réécrit l'annotation de chaque constante (TextesWeb.swift, LibellesWeb.swift),
 * dictionnaire et ensemble dont le texte, INCHANGÉ, est retrouvé à une autre ligne du même fichier
 * web, et la « source » de chaque zone de rendu inchangée retrouvée ailleurs (textes-web-ios-rendus.json).
 * Un texte modifié ou ambigu n'est jamais « corrigé » : l'erreur de la garde demeure. Rend
 * `{ sources: { [chemin]: contenu }, corrections, restantes }`.
 */
export function corrigerLignes({ swiftSource, libellesSource, zonesSource, lireWeb }) {
  const originaux = {
    [TEXTES_SWIFT]: swiftSource ?? lireDepot(TEXTES_SWIFT),
    [LIBELLES_SWIFT]: libellesSource ?? lireDepot(LIBELLES_SWIFT),
    [ZONES_RENDU_JSON]: zonesSource ?? lireDepot(ZONES_RENDU_JSON),
  };
  const lignesSwift = {
    [TEXTES_SWIFT]: originaux[TEXTES_SWIFT].split('\n'),
    [LIBELLES_SWIFT]: originaux[LIBELLES_SWIFT].split('\n'),
  };
  const corrections = [];
  const restantes = [];
  const resultat = verifierTextes({
    swiftSource: originaux[TEXTES_SWIFT], libellesSource: originaux[LIBELLES_SWIFT],
    zonesRendu: JSON.parse(originaux[ZONES_RENDU_JSON]), lireWeb,
  });
  const appliquer = (nom, fichierSwift, ligneAnnotation, fichier, ancienne, nouvelle) => {
    const lignes = lignesSwift[fichierSwift];
    const index = ligneAnnotation - 1;
    const reecrite = reannoter(lignes[index] ?? '', fichier, ancienne, nouvelle);
    if (reecrite === null) { restantes.push(`${nom} : annotation ${fichierSwift}:${ligneAnnotation} illisible`); return; }
    lignes[index] = reecrite;
    corrections.push(`${nom} : ${fichier} l.${formatSource(ancienne.debut, ancienne.fin)} → l.${formatSource(nouvelle.debut, nouvelle.fin)}`);
  };
  for (const c of resultat.constantes) {
    if (c.etat?.statut === 'decale') appliquer(c.nomComplet, c.fichierSwift, c.ligneAnnotation, c.source.fichier, c.source, c.position);
    else if (c.etat?.statut === 'ambigu') {
      restantes.push(`${c.nomComplet} : texte présent ${c.etat.occurrences.map(lignesDe).join(', ')} de ${c.source.fichier}, ligne à choisir à la main`);
    }
  }
  for (const s of [...resultat.objets, ...resultat.ensembles]) {
    if (s.position && s.ligneAnnotation) appliquer(s.nomComplet, s.fichierSwift, s.ligneAnnotation, s.source.fichier, s.source, s.position);
  }
  let zonesTexte = originaux[ZONES_RENDU_JSON];
  for (const z of resultat.zones) {
    if (z.statut !== 'decale') continue;
    const avant = `"source": ${JSON.stringify(z.zone.source)}`;
    const apres = `"source": ${JSON.stringify(`${z.source.fichier}:${formatSource(z.position.debut, z.position.fin)}`)}`;
    if (zonesTexte.split(avant).length !== 2) { restantes.push(`zone ${z.zone.source} : « source » introuvable ou répétée`); continue; }
    zonesTexte = zonesTexte.replace(avant, apres);
    corrections.push(`zone ${z.zone.source} → l.${formatSource(z.position.debut, z.position.fin)}`);
  }
  return {
    sources: {
      [TEXTES_SWIFT]: lignesSwift[TEXTES_SWIFT].join('\n'),
      [LIBELLES_SWIFT]: lignesSwift[LIBELLES_SWIFT].join('\n'),
      [ZONES_RENDU_JSON]: zonesTexte,
    },
    corrections,
    restantes,
  };
}

/** Textes juridiques écrits en dur dans des fichiers Swift du lot 2 (hors fichiers de textes). */
export function textesJuridiquesHorsTL(fichiers) {
  const fautes = [];
  for (const { chemin, contenu } of fichiers) {
    if (FICHIERS_SWIFT.some(f => f.chemin === chemin)) continue;
    if (!DOSSIERS_LOT2.some(d => chemin === d || chemin.startsWith(`${d}/`))) continue;
    let dansMultiLigne = false;
    contenu.split('\n').forEach((ligne, i) => {
      // Littéral multi-ligne : ses lignes intérieures n'ont pas de guillemets, aucune marque n'y
      // serait vue ; il est refusé (signalé à son ouverture).
      const triples = ligne.split(TRIPLE_GUILLEMET).length - 1;
      if (triples || dansMultiLigne) {
        if (triples && !dansMultiLigne) {
          fautes.push(`${chemin}:${i + 1} : littéral multi-ligne (triple guillemet) interdit dans un fichier du lot 2 `
            + '(texte non gardé par TL : utiliser des constantes de TextesWeb.swift ou de LibellesWeb.swift)');
        }
        if (triples % 2) dansMultiLigne = !dansMultiLigne;
        return;
      }
      for (const m of litterauxHorsCommentaire(ligne)) {
        // Un littéral sans espace est un code ou un identifiant (`RGPD_CONSENTEMENT_DONNE`,
        // clé `consentement` de `p_details`), jamais un texte affiché.
        if (!/\s/.test(m[1])) continue;
        if (MARQUES_JURIDIQUES.some(r => r.test(m[1]))) {
          fautes.push(`${chemin}:${i + 1} : texte juridique en dur « ${m[1]} » (le reprendre de ${TEXTES_SWIFT})`);
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

// ---------------------------------------------------------------------------------------------
// Chaînes système iOS (Info.plist, INFOPLIST_KEY_*, fichiers de chaînes)
// ---------------------------------------------------------------------------------------------

const decoderXml = t => t.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
const MESSAGE_CHAINE = 'une chaîne système nouvelle ou modifiée est un texte exposé que cette garde ne compare à aucun '
  + 'texte web (LOT2_PLAN §7 Q5, HARD STOP n°4) : ne l’ajouter qu’avec la validation de Gabrielle, en mettant à jour '
  + `CHAINES_INFO_PLIST (${SCRIPT})`;

/**
 * Chaînes système verrouillées : clés `*UsageDescription*` d'Info.plist égales à
 * `CHAINES_INFO_PLIST` (liste et textes), aucune `INFOPLIST_KEY_*UsageDescription*` dans les
 * réglages de projet, aucun fichier `.strings`/`.xcstrings`/`.stringsdict` (non lus par la garde).
 */
export function chainesSystemeIos({ infoPlist, projets = [], fichiersChaines = [] }) {
  const fautes = [];
  const vues = new Set();
  for (const m of infoPlist.matchAll(/<key>([^<]*UsageDescription[^<]*)<\/key>\s*(?:<string>([^<]*)<\/string>|<(\w+))/g)) {
    const [, cle, valeur, autre] = m;
    vues.add(cle);
    if (!(cle in CHAINES_INFO_PLIST)) fautes.push(`${INFO_PLIST} : ${cle} absente de la liste verrouillée : ${MESSAGE_CHAINE}`);
    else if (autre || decoderXml(valeur) !== CHAINES_INFO_PLIST[cle]) {
      fautes.push(`${INFO_PLIST} : ${cle} ne vaut plus le texte verrouillé : ${MESSAGE_CHAINE}`);
    }
  }
  for (const cle of Object.keys(CHAINES_INFO_PLIST)) {
    if (!vues.has(cle)) fautes.push(`${INFO_PLIST} : ${cle} absente : mettre à jour CHAINES_INFO_PLIST (${SCRIPT}) avec la PR qui la retire`);
  }
  for (const { chemin, contenu } of projets) {
    contenu.split('\n').forEach((ligne, i) => {
      if (/INFOPLIST_KEY_\w*UsageDescription/.test(ligne)) {
        fautes.push(`${chemin}:${i + 1} : chaîne Info.plist injectée par un réglage INFOPLIST_KEY_* : ${MESSAGE_CHAINE}`);
      }
    });
  }
  for (const chemin of fichiersChaines) {
    fautes.push(`${chemin} : fichier de chaînes non lu par la garde des textes (${SCRIPT}) : l’étendre avant d’y écrire un texte`);
  }
  return fautes;
}

function fichiersDe(racine, relatif, garder) {
  const plein = join(racine, relatif);
  if (!existsSync(plein)) return [];
  if (!statSync(plein).isDirectory()) return garder(relatif) ? [relatif] : [];
  return readdirSync(plein)
    .filter(n => !n.startsWith('.') && !['build', 'DerivedData', 'test-results', 'node_modules'].includes(n))
    .flatMap(n => fichiersDe(racine, `${relatif}/${n}`, garder));
}

export function chainesSystemeIosSurDisque(racine = ROOT) {
  const projets = PROJETS_IOS.flatMap(p => fichiersDe(racine, p, c => /\.(?:yml|pbxproj|xcconfig)$/.test(c)))
    .map(chemin => ({ chemin, contenu: readFileSync(join(racine, chemin), 'utf8') }));
  return chainesSystemeIos({
    infoPlist: readFileSync(join(racine, INFO_PLIST), 'utf8'),
    projets,
    fichiersChaines: fichiersDe(racine, 'ios-native', c => /\.(?:strings|xcstrings|stringsdict)$/.test(c)),
  });
}

// ---------------------------------------------------------------------------------------------
// Liste pour la validation de Gabrielle
// ---------------------------------------------------------------------------------------------

const cellule = t => t.replace(/\|/g, '\\|').replace(/\n/g, ' ');

/** Tableaux Markdown : textes HARD STOP (avec nature), rendus assemblés, libellés hors HARD STOP. */
export function listeMarkdown(resultat) {
  const { constantes, rendus, zones } = resultat;
  const src = c => `\`${c.source.fichier}:${formatSource(c.source.debut, c.source.fin)}\``;
  const hs = constantes.filter(c => c.hardStop);
  const lib = constantes.filter(c => !c.hardStop);
  const sortie = [];
  const parNature = NATURES.map(n => `${hs.filter(c => c.nature === n).length} ${n}`).join(', ');
  sortie.push(`### Textes HARD STOP n°4 — \`TextesWeb.swift\` (${hs.length} : ${parNature})`, '');
  sortie.push('| Constante | Nature | Texte (verbatim) | Source |', '|---|---|---|---|');
  for (const c of hs) sortie.push(`| \`${c.nom}\` | ${c.nature} | ${cellule(c.valeur)} | ${src(c)} |`);
  const zonesDe = nom => zones.filter(z => (z.zone.fonctions ?? []).includes(nom)).map(z => `\`${z.zone.source}\``).join(', ');
  sortie.push('', `### Rendus assemblés (${rendus.length}, assertés par les tests Swift ; zones web gardées)`, '');
  sortie.push('| Fonction | Appel | Rendu exact | Fichier | Zones web |', '|---|---|---|---|---|');
  for (const r of rendus) {
    const hardStop = r.fonction.startsWith('TextesWeb.') ? 'HARD STOP' : 'hors HARD STOP';
    sortie.push(`| \`${r.fonction}\` | \`${cellule(r.appel)}\` | ${cellule(r.rendu)} | ${hardStop} | ${zonesDe(r.fonction)} |`);
  }
  sortie.push('', `### Libellés hors HARD STOP — \`LibellesWeb.swift\` (${lib.length}, pour information)`, '');
  sortie.push('| Constante | Texte (verbatim) | Source |', '|---|---|---|');
  for (const c of lib) sortie.push(`| \`${c.nom}\` | ${cellule(c.valeur)} | ${src(c)} |`);
  return sortie.join('\n');
}

export function main(argv = process.argv.slice(2)) {
  const lireWeb = lecteurWeb(fichier => readFileSync(join(ROOT, fichier), 'utf8'));
  if (argv.includes('--corriger-lignes')) {
    const { sources, corrections, restantes } = corrigerLignes({ lireWeb });
    for (const c of corrections) console.log(`↻ ${c}`);
    for (const r of restantes) console.error(`? ${r}`);
    for (const [chemin, contenu] of Object.entries(sources)) {
      if (contenu !== lireDepot(chemin)) {
        writeFileSync(join(ROOT, chemin), contenu);
        console.log(`${chemin} réécrit : relire le diff`);
      }
    }
  }
  const resultat = verifierTextes({ lireWeb });
  const fautes = [...resultat.erreurs, ...textesJuridiquesHorsTLSurDisque(ROOT), ...chainesSystemeIosSurDisque(ROOT)];
  if (argv.includes('--liste')) console.log(listeMarkdown(resultat));
  for (const a of resultat.avertissements) console.error(`⚠ ${a}`);
  if (fautes.length) {
    for (const f of fautes) console.error(`✗ ${f}`);
    return 1;
  }
  if (!argv.includes('--liste')) {
    const hs = resultat.constantes.filter(c => c.hardStop).length;
    console.log(`✓ ${hs} textes HARD STOP (TextesWeb.swift) et ${resultat.constantes.length - hs} libellés (LibellesWeb.swift) `
      + `identiques au web, ${resultat.zones.length} zones de rendu retrouvées`);
  }
  return 0;
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  process.exit(main());
}
