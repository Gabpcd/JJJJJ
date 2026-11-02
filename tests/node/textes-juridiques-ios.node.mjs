import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import {
  DOSSIERS_LOT2,
  ROOT,
  TEXTES_SWIFT,
  echapperSwift,
  lecteurWeb,
  lireTextesSwift,
  textesJuridiquesHorsTL,
  textesJuridiquesHorsTLSurDisque,
  unitesWeb,
  verifierTextes,
} from '../../scripts/mobile/check-textes-juridiques-ios.mjs';

// Garde du lot 2, tranche TL (LOT2_PLAN §3 « TL », critère P9, HARD STOP n°4) : chaque texte
// juridique ou de consentement affiché par l'app iOS est une constante de `TextesWeb.swift`,
// annotée `// source: <fichier>:<ligne>`, ÉGALE au texte que le web affiche à cette ligne
// (après le traitement des espaces JSX, comme React). Aucun réseau, aucun secret : le test ne
// lit que des fichiers du dépôt.

const read = relative => readFileSync(join(ROOT, relative), 'utf8');
const swift = read(TEXTES_SWIFT);
const lireWeb = lecteurWeb(fichier => read(fichier));
const resultat = verifierTextes({ swiftSource: swift, lireWeb });
const { constantes } = lireTextesSwift(swift);

const intervalle = (debut, fin) => Array.from({ length: fin - debut + 1 }, (_, i) => debut + i);

/** Remplace, à sa ligne Swift, le littéral d'une constante par `valeur` (échappée Swift). */
function remplacerConstante(source, constante, valeur) {
  const lignes = source.split('\n');
  const index = constante.ligneSwift - 1;
  const avant = lignes[index];
  const apres = avant.replace(/"(?:[^"\\]|\\.)*"\s*$/, `"${echapperSwift(valeur)}"`);
  assert.notEqual(apres, avant, `${constante.nom} : littéral introuvable l.${constante.ligneSwift}`);
  lignes[index] = apres;
  return lignes.join('\n');
}

/** Mutations d'un caractère : suppression finale, ajout final, substitution, espace doublée. */
function mutations(valeur) {
  const caracteres = [...valeur];
  const milieu = Math.floor(caracteres.length / 2);
  const substitue = [...caracteres];
  substitue[milieu] = caracteres[milieu] === 'x' ? 'y' : 'x';
  const sorties = [caracteres.slice(0, -1).join(''), `${valeur}.`, substitue.join('')];
  const espace = valeur.indexOf(' ');
  if (espace > 0) sorties.push(`${valeur.slice(0, espace)} ${valeur.slice(espace)}`);
  return sorties.filter(m => m !== valeur);
}

test('TL : chaque constante de TextesWeb.swift est le texte exact du web à la ligne annoncée', () => {
  assert.deepEqual(resultat.erreurs, []);
  assert.ok(constantes.length >= 60, `au moins 60 textes attendus, ${constantes.length} lus`);
  const fichiers = new Set(constantes.map(c => c.source.fichier));
  assert.deepEqual([...fichiers].sort(), [
    'src/components/BandeauSansGPS.tsx',
    'src/components/CertificatSignature.tsx',
    'src/components/ConsentementGPS.tsx',
    'src/components/Countdown72hSignature.tsx',
    'src/components/PanneauContestation.tsx',
    'src/components/SignerContratOtp.tsx',
    'src/pages/ContratMission.tsx',
    'src/pages/DetailPresencesMission.tsx',
    'src/pages/DocumentsSoignant.tsx',
    'src/pages/PresencesSoignant.tsx',
  ]);
});

// Lignes exigées par LOT2_PLAN §3 TL (relues dans le dépôt au 2 novembre 2026).
const EXIGES = {
  'src/components/ConsentementGPS.tsx': [25, 28, 34, 36, 37, 38, 42, 44, 45, 46, 50, 58, 64],
  'src/components/BandeauSansGPS.tsx': [9],
  'src/pages/PresencesSoignant.tsx': [101, 717],
  'src/pages/DetailPresencesMission.tsx': [697, 698],
  'src/components/PanneauContestation.tsx': [354, 394],
  'src/pages/DocumentsSoignant.tsx': [75, 93, 106, 112],
  'src/pages/ContratMission.tsx': [554, 559, 564, 571, 573, 603, 623, 624, 636, 637, 743, 834, 836],
  'src/components/SignerContratOtp.tsx': [216, 244, 245, 276, ...intervalle(31, 43)],
  'src/components/Countdown72hSignature.tsx': [43, 69, 70],
  'src/components/CertificatSignature.tsx': intervalle(172, 175),
};

test('TL : couvre les textes juridiques et de consentement listés par le blueprint', () => {
  const couverts = new Set(constantes.flatMap(c => intervalle(c.source.debut, c.source.fin)
    .map(ligne => `${c.source.fichier}:${ligne}`)));
  const manquants = Object.entries(EXIGES)
    .flatMap(([fichier, lignes]) => lignes.map(ligne => `${fichier}:${ligne}`))
    .filter(cle => !couverts.has(cle));
  assert.deepEqual(manquants, []);
});

test('TL : MESSAGES_ERREUR et les codes bloquants de SignerContratOtp sont repris en entier', () => {
  const objet = resultat.objets.find(o => o.source.variable === 'MESSAGES_ERREUR');
  assert.ok(objet, 'dictionnaire MESSAGES_ERREUR absent de TextesWeb.swift');
  assert.equal(objet.entrees.length, 13);
  const ensemble = resultat.ensembles.find(e => e.source.fichier === 'src/components/SignerContratOtp.tsx');
  assert.ok(ensemble, 'ensemble des codes bloquants absent de TextesWeb.swift');
  assert.deepEqual([...ensemble.elements].sort(), [
    'CONTRAT_DEJA_COMPLET', 'CONTRAT_INACTIF', 'DEJA_SIGNE', 'HASH_DOCUMENT_CHANGE',
    'NON_AUTORISE', 'TELEPHONE_MANQUANT', 'TROP_DE_SMS',
  ]);
});

test('TL : la garde rougit sur toute constante altérée d’un caractère (mutation rejouée sur chaque constante)', () => {
  let rejouees = 0;
  for (const constante of constantes) {
    for (const mutation of mutations(constante.valeur)) {
      const { erreurs } = verifierTextes({ swiftSource: remplacerConstante(swift, constante, mutation), lireWeb });
      assert.ok(erreurs.some(e => e.includes(constante.nom)),
        `${constante.nom} muté en « ${mutation} » sans erreur : ${JSON.stringify(erreurs)}`);
      rejouees += 1;
    }
  }
  assert.ok(rejouees >= 3 * constantes.length, `${rejouees} mutations rejouées`);
});

test('TL : la garde rougit si le texte web change d’un caractère à la ligne source', () => {
  for (const constante of constantes) {
    const { fichier } = constante.source;
    const original = read(fichier);
    const unite = unitesWeb(fichier, original).find(u => u.valeur === constante.valeur
      && u.debut === constante.source.debut && u.fin === constante.source.fin);
    assert.ok(unite, `${constante.nom} : unité web introuvable`);
    // Première lettre du texte dans le fichier, remplacée par une autre lettre.
    const extrait = original.slice(unite.offset, unite.offsetFin);
    const decalage = extrait.search(/\p{L}|\p{N}|…/u);
    assert.ok(decalage >= 0, `${constante.nom} : aucun caractère à muter`);
    const position = unite.offset + decalage;
    const remplacant = original[position] === 'x' ? 'y' : 'x';
    const mute = original.slice(0, position) + remplacant + original.slice(position + 1);
    const lireMute = lecteurWeb(f => (f === fichier ? mute : read(f)));
    const { erreurs } = verifierTextes({ swiftSource: swift, lireWeb: lireMute });
    assert.ok(erreurs.some(e => e.includes(constante.nom)),
      `${constante.nom} : texte web muté sans erreur`);
  }
});

test('TL : un décalage de lignes du web rougit avec la ligne où le texte a été retrouvé', () => {
  const fichier = 'src/components/ConsentementGPS.tsx';
  const decale = `// ligne ajoutée\n${read(fichier)}`;
  const { erreurs } = verifierTextes({ swiftSource: swift, lireWeb: lecteurWeb(f => (f === fichier ? decale : read(f))) });
  const titre = erreurs.find(e => e.includes('ConsentementGps.titre'));
  assert.ok(titre, JSON.stringify(erreurs));
  assert.match(titre, /retrouvé l\.26/);
  assert.match(titre, /mettre à jour l’annotation/);
});

test('TL : toute constante, tout littéral et toute structure de TextesWeb.swift sont gardés', () => {
  const ajout = (apres, insertion) => {
    const i = swift.indexOf(apres);
    assert.ok(i >= 0, `ancre absente : ${apres}`);
    return swift.slice(0, i + apres.length) + insertion + swift.slice(i + apres.length);
  };
  const ancre = 'public enum ConsentementGps {\n';
  // Constante sans annotation de source.
  let r = verifierTextes({ swiftSource: ajout(ancre, '        public static let ajout = "Bonjour"\n'), lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('ConsentementGps.ajout') && e.includes('sans annotation')), JSON.stringify(r.erreurs));
  // Littéral hors constante annotée (texte glissé dans une fonction).
  r = verifierTextes({ swiftSource: ajout(ancre, '        static func f() -> String { "Texte libre" }\n'), lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('littéral non gardé') && e.includes('Texte libre')), JSON.stringify(r.erreurs));
  // Interpolation Swift interdite.
  r = verifierTextes({ swiftSource: ajout(ancre, '        // source: src/components/ConsentementGPS.tsx:25\n        public static let gabarit = "Autorisation \\(x)"\n'), lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('ConsentementGps.gabarit') && e.includes('interpolation')), JSON.stringify(r.erreurs));
  // Entrée absente du catalogue (le test Swift parcourt le catalogue).
  const sansCatalogue = swift.replace(/^\s*\.init\(cle: "ConsentementGps\.titre", texte: ConsentementGps\.titre\),\n/m, '');
  assert.notEqual(sansCatalogue, swift);
  r = verifierTextes({ swiftSource: sansCatalogue, lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('catalogue') && e.includes('ConsentementGps.titre')), JSON.stringify(r.erreurs));
});

test('TL : le dictionnaire des codes et l’ensemble des bloquants suivent le web clé par clé', () => {
  // Deux messages permutés : chaque texte reste verbatim, mais attaché au mauvais code.
  const permute = swift
    .replace('"OTP_EXPIRE": otpExpire,', '"OTP_EXPIRE": __TMP__,')
    .replace('"OTP_INCORRECT": otpIncorrect,', '"OTP_INCORRECT": otpExpire,')
    .replace('"OTP_EXPIRE": __TMP__,', '"OTP_EXPIRE": otpIncorrect,');
  assert.notEqual(permute, swift);
  let r = verifierTextes({ swiftSource: permute, lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('OTP_EXPIRE')), JSON.stringify(r.erreurs));
  // Code oublié.
  const oubli = swift.replace(/^\s*"TROP_DE_SMS": tropDeSms,\n/m, '');
  assert.notEqual(oubli, swift);
  r = verifierTextes({ swiftSource: oubli, lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('TROP_DE_SMS') && e.includes('absent')), JSON.stringify(r.erreurs));
  // Code bloquant oublié.
  const bloquant = swift.replace('"HASH_DOCUMENT_CHANGE",\n', '');
  assert.notEqual(bloquant, swift);
  r = verifierTextes({ swiftSource: bloquant, lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('HASH_DOCUMENT_CHANGE')), JSON.stringify(r.erreurs));
});

test('TL : les espaces JSX suivent React (lignes jointes par une espace, bords coupés)', () => {
  const tsx = [
    'export const A = () => (',
    '  <p className="x">',
    '    Première ligne,',
    '    seconde ligne. {valeur}',
    '    <span> Badge</span>',
    "    {'Littéral l\\'apostrophe '}",
    '  </p>',
    ');',
  ].join('\n');
  const unites = unitesWeb('exemple.tsx', tsx).map(u => [u.valeur, u.debut, u.fin, u.genre]);
  assert.ok(unites.some(([v, d, f, g]) => v === 'Première ligne, seconde ligne.' && d === 3 && f === 4 && g === 'jsx'),
    JSON.stringify(unites));
  assert.ok(unites.some(([v, d, , g]) => v === 'Badge' && d === 5 && g === 'jsx'), JSON.stringify(unites));
  assert.ok(unites.some(([v, d, , g]) => v === "Littéral l'apostrophe" && d === 6 && g === 'chaine'), JSON.stringify(unites));
  // Une apostrophe du texte JSX n'ouvre pas de chaîne : « l'admin » reste dans le texte.
  const apostrophe = unitesWeb('b.tsx', "export const B = () => <p>\n  si pas de résolution, l'admin tranchera.\n</p>;");
  assert.ok(apostrophe.some(u => u.valeur === "si pas de résolution, l'admin tranchera." && u.debut === 2));
});

test('TL : aucun texte juridique écrit en dur dans les dossiers Swift du lot 2 hors TextesWeb.swift', () => {
  assert.deepEqual(textesJuridiquesHorsTLSurDisque(ROOT), []);
  const fautes = textesJuridiquesHorsTL([
    { chemin: `${DOSSIERS_LOT2[0]}/Exemple.swift`, contenu: 'let a = "Conforme art. 1366-1367 Code civil."\n// Code civil en commentaire : permis\nlet b = "Bonjour"' },
    { chemin: TEXTES_SWIFT, contenu: 'let c = "Base légale : consentement (Art. 6.1.a RGPD)."' },
  ]);
  assert.equal(fautes.length, 1);
  assert.match(fautes[0], /Exemple\.swift:1/);
});
