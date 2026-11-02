import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import {
  DOSSIERS_LOT2,
  MOTIFS_Q9,
  ROOT,
  TEXTES_SWIFT,
  ZONES_Q9,
  corrigerLignes,
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

/** Lecteur web où seul `fichier` est remplacé par `contenu` ; les autres analyses sont réutilisées. */
function lireAvec(fichier, contenu) {
  const analyse = lecteurWeb(() => contenu)(fichier);
  return f => (f === fichier ? analyse : lireWeb(f));
}

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

/** Insère `insertion` juste après la première occurrence de `apres` dans le Swift. */
function ajout(apres, insertion, source = swift) {
  const i = source.indexOf(apres);
  assert.ok(i >= 0, `ancre absente : ${apres}`);
  return source.slice(0, i + apres.length) + insertion + source.slice(i + apres.length);
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
    'src/components/profil-soignant/SectionPreferences.tsx',
    'src/pages/CertificatSignaturePage.tsx',
    'src/pages/ContratMission.tsx',
    'src/pages/DetailPresencesMission.tsx',
    'src/pages/DocumentsSoignant.tsx',
    'src/pages/PresencesSoignant.tsx',
  ]);
});

// Lignes exigées par LOT2_PLAN v2 §3 « TL », item par item, dans l'ordre du blueprint (lignes de
// texte relues dans le dépôt au 2 novembre 2026 ; une plage du blueprint est développée en ses
// lignes de texte, les lignes de balises seules en sont exclues).
const EXIGES = {
  // Consentement GPS : ConsentementGPS.tsx l.25-65 (titre, description, deux listes, l.50, boutons).
  'src/components/ConsentementGPS.tsx': [25, 28, 34, 36, 37, 38, 42, 44, 45, 46, 50, 58, 64],
  // Bandeau BandeauSansGPS.tsx l.9.
  'src/components/BandeauSansGPS.tsx': [9],
  // Refus PresencesSoignant.tsx l.101 ; bandeau « à valider » l.716-717 (texte l.717).
  'src/pages/PresencesSoignant.tsx': [101, 717],
  // Retrait depuis le Profil : SectionPreferences.tsx l.129-136 (textes l.129, 132, 135, 136), l.161.
  'src/components/profil-soignant/SectionPreferences.tsx': [129, 132, 135, 136, 161],
  // Relance DetailPresencesMission.tsx l.697-698.
  'src/pages/DetailPresencesMission.tsx': [697, 698],
  // Contestation : seuls les libellés de statut l.48-62 (textes l.49-61) ; aucun texte de délai.
  'src/components/PanneauContestation.tsx': intervalle(49, 61),
  // Justificatifs : l.75, l.93, l.106, l.112, l.131-133 (texte l.132).
  'src/pages/DocumentsSoignant.tsx': [75, 93, 106, 112, 132],
  // Contrats : l.553-574 (bandeaux), l.603, l.623-625, l.631-637, l.743, l.831-837 (trois variantes,
  // « Signature électronique simple. », régularisation des montants).
  'src/pages/ContratMission.tsx': [554, 559, 564, 571, 573, 603, 623, 624, 636, 637, 743, 832, 834, 835, 836],
  // SignerContratOtp.tsx l.216, l.245, l.276, l.30-45 (MESSAGES_ERREUR l.31-43), l.242-246, l.288,
  // l.326-327 (tentatives restantes).
  'src/components/SignerContratOtp.tsx': [216, 242, 244, 245, 276, 288, 326, 327, ...intervalle(31, 43)],
  // Countdown72hSignature.tsx l.43, l.69-70.
  'src/components/Countdown72hSignature.tsx': [43, 69, 70],
  // CertificatSignature.tsx l.172-175.
  'src/components/CertificatSignature.tsx': intervalle(172, 175),
  // CertificatSignaturePage.tsx l.214 (texte l.214-215 de la page /contrat/:id/certificat).
  'src/pages/CertificatSignaturePage.tsx': [214, 215],
};

// Libellés non juridiques repris en plus (revue fraîche de TL) pour que T5a et T9b n'aient aucun
// libellé de ces composants à écrire : minuteur, envoi du code, erreurs réseau, tentatives,
// renvoi (SignerContratOtp) ; relance (DetailPresencesMission) ; durée du compte à rebours ;
// libellé d'accessibilité de l'interrupteur GPS.
const COMPLEMENTS = {
  'src/components/SignerContratOtp.tsx': [110, 140, 151, 156, 167, 171, 188, 197, 202, 214, 230, 265, 296, 299, 305, 319, 336, 339, 348],
  'src/pages/DetailPresencesMission.tsx': [122, 123, 700],
  'src/components/Countdown72hSignature.tsx': [72],
  'src/components/profil-soignant/SectionPreferences.tsx': [140],
};

// Lignes que le blueprint EXCLUT (LOT2_PLAN v2 §1.2, correction 14, §7 Q9 ; DECISIONS_LOT2) :
// textes de délai du panneau de contestation, contraires au serveur, non affichés tant que Q9
// n'est pas tranchée par Gabrielle.
const INTERDITS = {
  'src/components/PanneauContestation.tsx': [347, 354, 394],
};

const lignesCouvertes = () => new Set(constantes.flatMap(c => intervalle(c.source.debut, c.source.fin)
  .map(ligne => `${c.source.fichier}:${ligne}`)));
const cles = table => Object.entries(table).flatMap(([fichier, lignes]) => lignes.map(ligne => `${fichier}:${ligne}`));

test('TL : couvre les textes listés par le blueprint v2 et aucun des textes qu’il exclut', () => {
  const couverts = lignesCouvertes();
  assert.deepEqual(cles(EXIGES).filter(cle => !couverts.has(cle)), [], 'textes exigés par LOT2_PLAN §3 TL absents');
  assert.deepEqual(cles(COMPLEMENTS).filter(cle => !couverts.has(cle)), [], 'libellés complémentaires absents');
  assert.deepEqual(cles(INTERDITS).filter(cle => couverts.has(cle)), [], 'texte exclu par LOT2_PLAN (Q9) repris');
});

test('TL : verrou Q9 — aucune constante ne pointe vers les textes de délai du panneau de contestation', () => {
  // Les zones verrouillées contiennent bien, aujourd'hui, les trois textes de délai (sinon le web a
  // bougé : la garde rougit et ZONES_Q9 est à relire).
  const panneau = 'src/components/PanneauContestation.tsx';
  assert.deepEqual(ZONES_Q9.map(z => [z.fichier, z.debut, z.fin]), [[panneau, 343, 356], [panneau, 393, 395]]);
  const unites = lireWeb(panneau).unites;
  for (const ligne of INTERDITS[panneau]) {
    const zone = ZONES_Q9.find(z => ligne >= z.debut && ligne <= z.fin);
    assert.ok(zone, `l.${ligne} hors des zones verrouillées`);
    assert.ok(unites.some(u => u.debut === ligne && MOTIFS_Q9.some(m => m.test(u.valeur))),
      `l.${ligne} : texte de délai introuvable`);
  }
  const ancre = 'public enum Contestation {\n';
  // Constante annotée dans une zone verrouillée (texte pourtant verbatim).
  let r = verifierTextes({
    swiftSource: ajout(ancre, '        // source: src/components/PanneauContestation.tsx:347\n        public static let delai = "72h pour répondre"\n'),
    lireWeb,
  });
  assert.ok(r.erreurs.some(e => e.includes('Contestation.delai') && e.includes('Q9')), JSON.stringify(r.erreurs));
  // Même texte annoncé ailleurs : le verrou porte aussi sur la valeur.
  r = verifierTextes({
    swiftSource: ajout(ancre, '        // source: src/components/PanneauContestation.tsx:366\n        public static let delai = "Vous avez 72 h après la validation pour contester. Sans résolution sous 72 h, l\'admin plateforme tranchera."\n'),
    lireWeb,
  });
  assert.ok(r.erreurs.some(e => e.includes('Contestation.delai') && e.includes('Q9')), JSON.stringify(r.erreurs));
  // Un texte de délai qui bouge dans le web fait rougir la garde (zones à relire).
  const decale = read(panneau).replace('Discussion en cours —', '\nDiscussion en cours —');
  assert.notEqual(decale, read(panneau));
  r = verifierTextes({ swiftSource: swift, lireWeb: lireAvec(panneau, decale) });
  assert.ok(r.erreurs.some(e => e.includes('ZONES_Q9')), JSON.stringify(r.erreurs));
});

test('TL : MESSAGES_ERREUR, les codes bloquants et les libellés de statut sont repris en entier', () => {
  const objet = resultat.objets.find(o => o.source.variable === 'MESSAGES_ERREUR');
  assert.ok(objet, 'dictionnaire MESSAGES_ERREUR absent de TextesWeb.swift');
  assert.equal(objet.entrees.length, 13);
  const ensemble = resultat.ensembles.find(e => e.source.fichier === 'src/components/SignerContratOtp.tsx');
  assert.ok(ensemble, 'ensemble des codes bloquants absent de TextesWeb.swift');
  assert.deepEqual([...ensemble.elements].sort(), [
    'CONTRAT_DEJA_COMPLET', 'CONTRAT_INACTIF', 'DEJA_SIGNE', 'HASH_DOCUMENT_CHANGE',
    'NON_AUTORISE', 'TELEPHONE_MANQUANT', 'TROP_DE_SMS',
  ]);
  const statuts = resultat.objets.find(o => o.source.variable === 'STATUT_CONFIG' && o.source.champ === 'label');
  assert.ok(statuts, 'libellés STATUT_CONFIG.label absents de TextesWeb.swift');
  assert.deepEqual(statuts.entrees.map(e => e.cle).sort(), [
    'EN_DISCUSSION', 'EN_MEDIATION', 'FERME', 'MEDIATION_EN_COURS', 'OUVERT', 'RESOLU_ACCORD_PARTIES',
    'RESOLU_ADMIN', 'RESOLU_ETABLISSEMENT', 'RESOLU_FAVEUR_ETAB', 'RESOLU_FAVEUR_SOIGNANT', 'RESOLU_PARTAGE',
    'RESOLU_SOIGNANT', 'REVUE_ADMIN',
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
    // Premier caractère du texte dans le fichier (lettre, chiffre, sinon ponctuation hors
    // délimiteurs de gabarit ou de chaîne), remplacé par un autre.
    const extrait = original.slice(unite.offset, unite.offsetFin);
    let decalage = extrait.search(/\p{L}|\p{N}|…/u);
    if (decalage < 0) decalage = extrait.search(/[^\s{}`$'"]/u);
    assert.ok(decalage >= 0, `${constante.nom} : aucun caractère à muter`);
    const position = unite.offset + decalage;
    const remplacant = original[position] === 'x' ? 'y' : 'x';
    const mute = original.slice(0, position) + remplacant + original.slice(position + 1);
    const { erreurs } = verifierTextes({ swiftSource: swift, lireWeb: lireAvec(fichier, mute) });
    assert.ok(erreurs.some(e => e.includes(constante.nom)),
      `${constante.nom} : texte web muté sans erreur`);
  }
});

test('TL : un décalage de lignes du web rougit avec la ligne où le texte a été retrouvé', () => {
  const fichier = 'src/components/ConsentementGPS.tsx';
  const decale = `// ligne ajoutée\n${read(fichier)}`;
  const { erreurs } = verifierTextes({ swiftSource: swift, lireWeb: lireAvec(fichier, decale) });
  const titre = erreurs.find(e => e.includes('ConsentementGps.titre'));
  assert.ok(titre, JSON.stringify(erreurs));
  assert.match(titre, /retrouvé l\.26/);
  assert.match(titre, /--corriger-lignes/);
});

test('TL : --corriger-lignes réécrit les annotations d’un texte inchangé retrouvé ailleurs, rien d’autre', () => {
  // Décalage d'une ligne : toutes les annotations du fichier suivent, la garde redevient verte.
  const fichier = 'src/components/ConsentementGPS.tsx';
  const lire = lireAvec(fichier, `// ligne ajoutée\n${read(fichier)}`);
  const { source, corrections, restantes } = corrigerLignes({ swiftSource: swift, lireWeb: lire });
  assert.equal(corrections.length, constantes.filter(c => c.source.fichier === fichier).length);
  assert.deepEqual(restantes, []);
  assert.deepEqual(verifierTextes({ swiftSource: source, lireWeb: lire }).erreurs, []);
  assert.match(source, /\/\/ source: src\/components\/ConsentementGPS\.tsx:26\n\s+public static let titre = /);
  // Texte présent deux fois (l.156 et l.202) : le décalage commun du fichier départage ; le
  // dictionnaire et l'ensemble suivent aussi.
  const otp = 'src/components/SignerContratOtp.tsx';
  const lireOtp = lireAvec(otp, `// ligne ajoutée\n${read(otp)}`);
  const otpCorrige = corrigerLignes({ swiftSource: swift, lireWeb: lireOtp });
  assert.deepEqual(otpCorrige.restantes, []);
  assert.deepEqual(verifierTextes({ swiftSource: otpCorrige.source, lireWeb: lireOtp }).erreurs, []);
  assert.match(otpCorrige.source, /\/\/ source-objet: src\/components\/SignerContratOtp\.tsx:31 MESSAGES_ERREUR\n/);
  assert.match(otpCorrige.source, /\/\/ source-ensemble: src\/components\/SignerContratOtp\.tsx:116-120\n/);
  // Texte modifié : jamais « corrigé », l'erreur reste.
  const mute = read(fichier).replace('Autorisation de géolocalisation', 'Autorisation de la géolocalisation');
  const lireMute = lireAvec(fichier, mute);
  const r = corrigerLignes({ swiftSource: swift, lireWeb: lireMute });
  assert.equal(r.source, swift);
  assert.ok(verifierTextes({ swiftSource: r.source, lireWeb: lireMute }).erreurs.some(e => e.includes('ConsentementGps.titre')));
});

test('TL : toute constante, tout littéral et toute structure de TextesWeb.swift sont gardés', () => {
  const ancre = 'public enum ConsentementGps {\n';
  // Constante sans annotation de source.
  let r = verifierTextes({ swiftSource: ajout(ancre, '        public static let ajout = "Bonjour"\n'), lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('ConsentementGps.ajout') && e.includes('sans annotation')), JSON.stringify(r.erreurs));
  // Littéral hors constante annotée (texte glissé dans une fonction).
  r = verifierTextes({ swiftSource: ajout(ancre, '        static func f() -> String { "Texte libre" }\n'), lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('littéral non gardé') && e.includes('Texte libre')), JSON.stringify(r.erreurs));
  // Littéral contenant « // » : jamais pris pour un commentaire.
  r = verifierTextes({ swiftSource: ajout(ancre, '        static func g() -> String { "voir https://jolene.app" }\n'), lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('littéral non gardé') && e.includes('https://jolene.app')), JSON.stringify(r.erreurs));
  // Littéral multi-ligne : ses lignes intérieures n'ont pas de guillemets, il est refusé en bloc.
  r = verifierTextes({ swiftSource: ajout(ancre, '        static let h = """\n        Texte libre sur plusieurs lignes\n        """\n'), lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('multi-ligne')), JSON.stringify(r.erreurs));
  r = verifierTextes({ swiftSource: ajout(ancre, '        // source: src/components/ConsentementGPS.tsx:25\n        public static let titre2 = #"""\n        Autorisation de géolocalisation\n        """#\n'), lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('multi-ligne')), JSON.stringify(r.erreurs));
  // Une annotation ne passe pas à la constante d'après si une autre déclaration s'intercale.
  r = verifierTextes({
    swiftSource: ajout(ancre, '        // source: src/components/ConsentementGPS.tsx:25\n        public static let liste = [titre]\n'
      + '        public static let orpheline = "Autorisation de géolocalisation"\n'),
    lireWeb,
  });
  assert.ok(r.erreurs.some(e => e.includes('annotation qui ne précède aucune constante')), JSON.stringify(r.erreurs));
  assert.ok(r.erreurs.some(e => e.includes('ConsentementGps.orpheline') && e.includes('sans annotation')), JSON.stringify(r.erreurs));
  // Interpolation Swift interdite.
  r = verifierTextes({ swiftSource: ajout(ancre, '        // source: src/components/ConsentementGPS.tsx:25\n        public static let gabarit = "Autorisation \\(x)"\n'), lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('ConsentementGps.gabarit') && e.includes('interpolation')), JSON.stringify(r.erreurs));
  // Entrée absente du catalogue (le test Swift parcourt le catalogue).
  const sansCatalogue = swift.replace(/^\s*\.init\(cle: "ConsentementGps\.titre", texte: ConsentementGps\.titre\),\n/m, '');
  assert.notEqual(sansCatalogue, swift);
  r = verifierTextes({ swiftSource: sansCatalogue, lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('catalogue') && e.includes('ConsentementGps.titre')), JSON.stringify(r.erreurs));
});

test('TL : les dictionnaires et l’ensemble des bloquants suivent le web clé par clé', () => {
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
  // Libellé de statut attaché au mauvais statut, puis statut oublié.
  const statutPermute = swift.replace('"FERME": statutFerme,', '"FERME": statutOuvert,');
  assert.notEqual(statutPermute, swift);
  r = verifierTextes({ swiftSource: statutPermute, lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('FERME') && e.includes('STATUT_CONFIG.label')), JSON.stringify(r.erreurs));
  const statutOubli = swift.replace(/^\s*"REVUE_ADMIN": statutRevueAdmin,\n/m, '');
  assert.notEqual(statutOubli, swift);
  r = verifierTextes({ swiftSource: statutOubli, lireWeb });
  assert.ok(r.erreurs.some(e => e.includes('REVUE_ADMIN') && e.includes('absente')), JSON.stringify(r.erreurs));
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

test('TL : aucun texte juridique écrit en dur dans les fichiers Swift du lot 2 hors TextesWeb.swift', () => {
  assert.deepEqual(textesJuridiquesHorsTLSurDisque(ROOT), []);
  // Fichiers du lot 2 placés hors des trois dossiers d'écrans (revue fraîche de TL).
  for (const chemin of [
    'ios-native/Jolene/Screens/Profil/ConsentementGpsRow.swift',
    'ios-native/Jolene/Screens/Profil/EspaceSoignantSection.swift',
    'ios-native/Packages/JoleneDesign/Sources/JoleneDesign/Components/CountdownLabel.swift',
    'ios-native/Jolene/Composition/Media/ShareSheet.swift',
  ]) {
    assert.ok(DOSSIERS_LOT2.some(d => chemin === d || chemin.startsWith(`${d}/`)), `${chemin} hors de DOSSIERS_LOT2`);
  }
  const dossier = DOSSIERS_LOT2[0];
  const fautes = textesJuridiquesHorsTL([
    { chemin: `${dossier}/Exemple.swift`, contenu: 'let a = "Conforme art. 1366-1367 Code civil."\n// Code civil en commentaire : permis\nlet b = "Bonjour"' },
    { chemin: TEXTES_SWIFT, contenu: 'let c = "Base légale : consentement (Art. 6.1.a RGPD)."' },
    { chemin: 'ios-native/Jolene/Screens/Profil/ConsentementGpsRow.swift', contenu: 'Text("Consentement GPS")\n.accessibilityIdentifier("profil-gps-consentement")' },
    { chemin: 'ios-native/Packages/JoleneDesign/Sources/JoleneDesign/Components/CountdownLabel.swift', contenu: 'Text("Délai de signature expiré (72h dépassées).")' },
    // Littéral multi-ligne : ses lignes intérieures échapperaient à la détection, il est refusé.
    { chemin: `${dossier}/Multi.swift`, contenu: 'let m = """\nJ\'atteste sur l\'honneur\n"""' },
  ]);
  assert.equal(fautes.length, 4, JSON.stringify(fautes));
  assert.match(fautes[0], /Exemple\.swift:1/);
  assert.match(fautes[1], /ConsentementGpsRow\.swift:1/);
  assert.match(fautes[2], /CountdownLabel\.swift:1/);
  assert.match(fautes[3], /Multi\.swift:1 .*multi-ligne/);
});

test('validate-pr.yml : l’étape « Garde de livraison mobile » (check requis Typecheck + build) exécute cette garde', () => {
  const wf = read('.github/workflows/validate-pr.yml');
  const job = wf.indexOf('\n  typecheck-and-build:\n');
  assert.ok(job >= 0, 'job typecheck-and-build introuvable');
  const finJob = wf.slice(job + 1).search(/\n {2}[a-z][a-z0-9-]*:\n/);
  const corps = wf.slice(job, finJob < 0 ? undefined : job + 1 + finJob);
  const etape = corps.indexOf('\n      - name: Garde de livraison mobile\n');
  assert.ok(etape >= 0, 'étape « Garde de livraison mobile » absente du job Typecheck + build');
  const suite = corps.slice(etape + 1);
  const fin = suite.search(/\n {6}- name: /);
  const bloc = suite.slice(0, fin < 0 ? undefined : fin);
  const run = bloc.split('\n').find(l => /^\s+run: /.test(l));
  assert.ok(run && run.includes('node --test') && run.includes('tests/node/textes-juridiques-ios.node.mjs'),
    `run: n'exécute pas la garde TL : ${run}`);
  assert.ok(!/^\s+if: /m.test(bloc) && !bloc.includes('continue-on-error'), 'étape conditionnelle ou non bloquante');
});
