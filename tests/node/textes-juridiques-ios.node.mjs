import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import {
  ANCRES_Q9,
  CHAINES_INFO_PLIST,
  DOSSIERS_LOT2,
  FICHIERS_SWIFT,
  INFO_PLIST,
  LIBELLES_SWIFT,
  MOTIFS_Q9,
  NATURES,
  ROOT,
  TEXTES_SWIFT,
  ZONES_RENDU_JSON,
  chainesSystemeIos,
  chainesSystemeIosSurDisque,
  corrigerLignes,
  echapperSwift,
  lecteurWeb,
  listeMarkdown,
  litterauxSwift,
  normaliserLigne,
  textesJuridiquesHorsTL,
  textesJuridiquesHorsTLSurDisque,
  unitesWeb,
  verifierTextes,
} from '../../scripts/mobile/check-textes-juridiques-ios.mjs';

// Garde du lot 2, tranche TL (LOT2_PLAN §3 « TL », critère P9, HARD STOP n°4) : chaque texte que
// l'app iOS reprend du web est une constante de `TextesWeb.swift` (HARD STOP) ou de
// `LibellesWeb.swift` (hors HARD STOP), annotée `// source: <fichier>:<ligne>`, ÉGALE au texte que
// le web affiche (après le traitement des espaces JSX, comme React) ; chaque assemblage est ancré
// sur le code web qui produit son rendu. Aucun réseau, aucun secret : le test ne lit que des
// fichiers du dépôt.

const read = relative => readFileSync(join(ROOT, relative), 'utf8');
const lireWeb = lecteurWeb(fichier => read(fichier));
const disque = { swift: read(TEXTES_SWIFT), libelles: read(LIBELLES_SWIFT), zones: read(ZONES_RENDU_JSON) };
// Référentiel aligné : annotations et zones réalignées EN MÉMOIRE sur le web du dépôt (aucun écart
// sur cette branche). Une PR web qui ne fait que décaler des lignes laisse ainsi cette suite verte :
// les tests de lignes ci-dessous raisonnent sur les positions réelles, jamais sur des numéros figés.
const aligne = corrigerLignes({ swiftSource: disque.swift, libellesSource: disque.libelles, zonesSource: disque.zones, lireWeb });
const swift = aligne.sources[TEXTES_SWIFT];
const libelles = aligne.sources[LIBELLES_SWIFT];
const zonesTexte = aligne.sources[ZONES_RENDU_JSON];
const zonesRendu = JSON.parse(zonesTexte);
const resultat = verifierTextes({ swiftSource: swift, libellesSource: libelles, zonesRendu, lireWeb });
const sourceZone = z => {
  const m = /^(\S+?):(\d+)(?:-(\d+))?$/.exec(z.source);
  return { fichier: m[1], debut: Number(m[2]), fin: Number(m[3] ?? m[2]) };
};
const lignes = (debut, fin) => (debut === fin ? `${debut}` : `${debut}-${fin}`);
const { constantes } = resultat;
const parNom = new Map(constantes.map(c => [c.nomComplet, c]));
const sourceDe = c => (c.fichierSwift === TEXTES_SWIFT ? swift : libelles);
const verifier = (options = {}) => verifierTextes({ swiftSource: swift, libellesSource: libelles, zonesRendu, lireWeb, ...options });

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
  assert.notEqual(apres, avant, `${constante.nomComplet} : littéral introuvable l.${constante.ligneSwift}`);
  lignes[index] = apres;
  return lignes.join('\n');
}

/** Insère `insertion` juste après la première occurrence de `apres` dans `source`. */
function ajout(apres, insertion, source = swift) {
  const i = source.indexOf(apres);
  assert.ok(i >= 0, `ancre absente : ${apres}`);
  return source.slice(0, i + apres.length) + insertion + source.slice(i + apres.length);
}

/** Options de `verifierTextes` où la constante `c` vaut `source` dans son fichier Swift. */
const avecSource = (c, source) => (c.fichierSwift === TEXTES_SWIFT ? { swiftSource: source } : { libellesSource: source });

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

test('TL : chaque constante de TextesWeb.swift et de LibellesWeb.swift est le texte exact du web', t => {
  const surDisque = verifierTextes({ swiftSource: disque.swift, libellesSource: disque.libelles, zonesRendu: JSON.parse(disque.zones), lireWeb });
  assert.deepEqual(surDisque.erreurs, []);
  // Sur cette branche, chaque annotation est à sa ligne ; un décalage ultérieur du web est toléré
  // (avertissement, voir plus bas) et ne fait pas rougir ce test.
  for (const a of surDisque.avertissements) t.diagnostic(a);
  assert.deepEqual(aligne.restantes, []);
  assert.deepEqual(resultat.erreurs, []);
  assert.deepEqual(resultat.avertissements, []);
  const hardStop = constantes.filter(c => c.hardStop);
  assert.ok(hardStop.length >= 60, `au moins 60 textes HARD STOP attendus, ${hardStop.length} lus`);
  assert.ok(constantes.length > hardStop.length, 'LibellesWeb.swift ne porte aucun libellé');
  const fichiers = new Set(constantes.map(c => c.source.fichier));
  assert.deepEqual([...fichiers].sort(), [
    'src/components/AccesEtablissement.tsx', // T9a : erreur de chargement de la liste des contrats
    'src/components/BandeauSansGPS.tsx',
    'src/components/CertificatSignature.tsx',
    'src/components/ConsentementGPS.tsx',
    'src/components/Countdown72hSignature.tsx',
    'src/components/PanneauContestation.tsx',
    'src/components/SignerContratOtp.tsx',
    // T4a : motifs du bloc de pointage, titres « Mes documents » et « Mes contrats » (section « Mon espace »).
    'src/components/pointage/BlocPointageMission.tsx',
    'src/components/profil-soignant/SectionPreferences.tsx',
    'src/pages/CertificatSignaturePage.tsx',
    'src/pages/ContratMission.tsx',
    'src/pages/DetailPresencesMission.tsx',
    'src/pages/DocumentsSoignant.tsx',
    'src/pages/ListeContrats.tsx', // T4a (titre « Mes contrats ») et T9a (liste des contrats)
    'src/pages/MesDocuments.tsx',
    'src/pages/PresencesSoignant.tsx',
  ]);
});

// Textes exigés par LOT2_PLAN v2 §3 « TL », item par item, par NOM de constante (les lignes du
// blueprint, relues dans le dépôt le 2 novembre 2026, restent en commentaire) : un décalage de
// lignes du web ne touche pas cette table. Tous sont dans TextesWeb.swift (HARD STOP).
const EXIGES = {
  // Consentement GPS : ConsentementGPS.tsx l.25-65 (titre, description, deux listes, l.50, boutons).
  'src/components/ConsentementGPS.tsx': [
    'ConsentementGps.titre', 'ConsentementGps.description', 'ConsentementGps.ceQueNousFaisonsTitre',
    'ConsentementGps.ceQueNousFaisons1', 'ConsentementGps.ceQueNousFaisons2', 'ConsentementGps.ceQueNousFaisons3',
    'ConsentementGps.ceQueNousNeFaisonsPasTitre', 'ConsentementGps.ceQueNousNeFaisonsPas1',
    'ConsentementGps.ceQueNousNeFaisonsPas2', 'ConsentementGps.ceQueNousNeFaisonsPas3',
    'ConsentementGps.baseLegale', 'ConsentementGps.refuser', 'ConsentementGps.accepter',
  ],
  // Bandeau BandeauSansGPS.tsx l.9.
  'src/components/BandeauSansGPS.tsx': ['BandeauSansGps.texte'],
  // Refus PresencesSoignant.tsx l.101 ; bandeau « à valider » l.716-717 (texte l.717).
  'src/pages/PresencesSoignant.tsx': ['Presences.pointageSansGpsActive', 'Presences.bandeauAValider'],
  // Retrait depuis le Profil : SectionPreferences.tsx l.129-136 (textes l.129, 132, 135, 136), l.161.
  'src/components/profil-soignant/SectionPreferences.tsx': [
    'ProfilConsentementGps.titre', 'ProfilConsentementGps.libelle', 'ProfilConsentementGps.explicationActive',
    'ProfilConsentementGps.explicationRetiree', 'ProfilConsentementGps.active', 'ProfilConsentementGps.retire',
  ],
  // Relance DetailPresencesMission.tsx l.697-698.
  'src/pages/DetailPresencesMission.tsx': ['Presences.relanceTitre', 'Presences.relanceExplication'],
  // Contestation : seuls les libellés de statut l.48-62 (textes l.49-61) ; aucun texte de délai.
  'src/components/PanneauContestation.tsx': [
    'Contestation.statutOuvert', 'Contestation.statutEnDiscussion', 'Contestation.statutEnMediation',
    'Contestation.statutMediationEnCours', 'Contestation.statutRevueAdmin', 'Contestation.statutResoluSoignant',
    'Contestation.statutResoluEtablissement', 'Contestation.statutResoluAdmin', 'Contestation.statutResoluAccordParties',
    'Contestation.statutResoluFaveurSoignant', 'Contestation.statutResoluFaveurEtab', 'Contestation.statutResoluPartage',
    'Contestation.statutFerme',
  ],
  // Justificatifs : l.75, l.93, l.106, l.112, l.131-133 (texte l.132).
  'src/pages/DocumentsSoignant.tsx': [
    'AttestationSante.titre', 'AttestationSante.vaccinations', 'AttestationSante.medecineDuTravail',
    'AttestationSante.faussesDeclarations', 'AttestationSante.documentsOriginaux',
  ],
  // Contrats : l.553-574 (bandeaux), l.603, l.623-625, l.631-637, l.743, l.831-837 (trois variantes,
  // « Signature électronique simple. », régularisation des montants).
  'src/pages/ContratMission.tsx': [
    'Contrat.annule', 'Contrat.expire', 'Contrat.refuse', 'Contrat.autrePartieASigne', 'Contrat.autrePartieASigneDetail',
    'Contrat.cddAPreparer', 'Contrat.documentFigeLe', 'Contrat.empreinteLibelle', 'Contrat.empreinteEllipse',
    'Contrat.originalIndisponible', 'Contrat.contenuPasDisponible', 'Contrat.otpDescription',
    'Contrat.mentionCadreEmployeur', 'Contrat.mentionSalarieEcrit', 'Contrat.mentionPrestationLiberale',
    'Contrat.signatureElectroniqueSimple', 'Contrat.regularisationMontants',
  ],
  // SignerContratOtp.tsx l.216, l.245, l.276, l.30-45 (MESSAGES_ERREUR l.31-43), l.242-246, l.288,
  // l.326-327 (tentatives restantes).
  'src/components/SignerContratOtp.tsx': [
    'SignatureOtp.signeAvecSucces', 'SignatureOtp.explication', 'SignatureOtp.consentement',
    'SignatureOtp.nonAuthentifie', 'SignatureOtp.nonAutorise', 'SignatureOtp.contratIntrouvable',
    'SignatureOtp.contratInactif', 'SignatureOtp.contratDejaComplet', 'SignatureOtp.telephoneManquant',
    'SignatureOtp.tropDeSms', 'SignatureOtp.otpNonDemande', 'SignatureOtp.otpExpire', 'SignatureOtp.otpIncorrect',
    'SignatureOtp.tropDeTentatives', 'SignatureOtp.dejaSigne', 'SignatureOtp.hashDocumentChange',
    'SignatureOtp.titre', 'SignatureOtp.recevoirCode',
    'SignatureOtp.tentativesCodeIncorrect', 'SignatureOtp.tentativesMot', 'SignatureOtp.tentativesPlurielTentative',
    'SignatureOtp.tentativesRestanteMot', 'SignatureOtp.tentativesPlurielRestante', 'SignatureOtp.tentativesPoint',
    'SignatureOtp.tentativesEpuisees',
  ],
  // Countdown72hSignature.tsx l.43, l.69-70.
  'src/components/Countdown72hSignature.tsx': ['CompteARebours.expire', 'CompteARebours.urgent', 'CompteARebours.aFinaliserSous'],
  // CertificatSignature.tsx l.172-175.
  'src/components/CertificatSignature.tsx': ['Certificat.mention'],
  // CertificatSignaturePage.tsx l.214 (texte l.214-215 de la page /contrat/:id/certificat).
  'src/pages/CertificatSignaturePage.tsx': ['Certificat.mentionPage'],
};

// Libellés et textes repris en plus du blueprint (revues fraîches de TL), pour que les écrans du
// lot 2 n'aient aucun texte de ces surfaces à écrire : formulaire et en-tête du panneau de
// contestation (T5b), relance (T5a), signature OTP (T9b), certificat et sa page (T9a).
const COMPLEMENTS = [
  // SignerContratOtp.tsx : erreurs génériques, envoi, minuteur, SMS restants, renvoi (hors HARD STOP).
  'LibellesWeb.SignatureOtp.messageParDefaut', 'LibellesWeb.SignatureOtp.repliEnvoi', 'LibellesWeb.SignatureOtp.repliSignature',
  'LibellesWeb.SignatureOtp.codeSixChiffresRequis', 'LibellesWeb.SignatureOtp.signatureNonDisponible',
  'LibellesWeb.SignatureOtp.codeEnvoyePrefixe', 'LibellesWeb.SignatureOtp.erreurReseauEnvoi',
  'LibellesWeb.SignatureOtp.erreurReseauSignature', 'LibellesWeb.SignatureOtp.verificationSignatureEnCours',
  'LibellesWeb.SignatureOtp.codeEnvoyeAuLibelle', 'LibellesWeb.SignatureOtp.smsDernierEnvoi',
  'LibellesWeb.SignatureOtp.minuteurSeparateur', 'LibellesWeb.SignatureOtp.minuteurExpire',
  'LibellesWeb.SignatureOtp.champCodeAccessibilite', 'LibellesWeb.SignatureOtp.renvoiNonAutoriseRecette',
  'LibellesWeb.SignatureOtp.plafondSmsAtteint', 'LibellesWeb.SignatureOtp.recevoirNouveauCode',
  'LibellesWeb.SignatureOtp.renvoyerCode',
  // SignerContratOtp.tsx l.316 : texte indicatif du champ du code (revue fraîche de T9b, m7).
  'LibellesWeb.SignatureOtp.champCodeIndication',
  // SignerContratOtp.tsx : consentement requis, bouton « Signer », confirmation (l.197, l.214) (HARD STOP).
  'TextesWeb.SignatureOtp.consentementRequis', 'TextesWeb.SignatureOtp.signer',
  'TextesWeb.SignatureOtp.contratSigneMessage', 'TextesWeb.SignatureOtp.missionConfirmee', 'TextesWeb.SignatureOtp.contratSigne',
  // DetailPresencesMission.tsx l.700, l.122-123 : bouton et retours de la relance.
  'LibellesWeb.Presences.relancer', 'LibellesWeb.Presences.relanceEnvoi', 'LibellesWeb.Presences.relanceSucces',
  'LibellesWeb.Presences.relanceImpossible',
  // PanneauContestation.tsx : en-tête l.262, formulaire l.366, l.376, l.387 (« Envoi… » et envoi), l.390.
  'LibellesWeb.Contestation.titre', 'LibellesWeb.Contestation.contester', 'LibellesWeb.Contestation.placeholderSoignant',
  'LibellesWeb.Contestation.envoi', 'LibellesWeb.Contestation.envoyer', 'LibellesWeb.Contestation.annuler',
  // Countdown72hSignature.tsx l.72 : unités de la durée.
  'LibellesWeb.CompteARebours.uniteHeures', 'LibellesWeb.CompteARebours.uniteMinutes', 'LibellesWeb.CompteARebours.uniteSecondes',
  // SectionPreferences.tsx l.140 : libellé d'accessibilité de l'interrupteur (formule du consentement).
  'TextesWeb.ProfilConsentementGps.libelleAccessibilite',
  // CertificatSignature.tsx : titre, statut, preuves et leurs valeurs ✓ / — (l.95-165).
  'TextesWeb.Certificat.titre', 'TextesWeb.Certificat.signe', 'TextesWeb.Certificat.dateHeure', 'TextesWeb.Certificat.otpValide',
  'TextesWeb.Certificat.codeSmsVerifie', 'TextesWeb.Certificat.rppsVerifie', 'TextesWeb.Certificat.rppsOui',
  'TextesWeb.Certificat.rppsNon', 'TextesWeb.Certificat.pscActif', 'TextesWeb.Certificat.pscOui', 'TextesWeb.Certificat.pscNon',
  // CertificatSignaturePage.tsx : en-tête l.185-186 et bloc « Empreinte du document signé » l.203-208.
  'TextesWeb.Certificat.titrePage', 'LibellesWeb.Certificat.contratPrefixe', 'TextesWeb.Certificat.empreinteTitre',
  'TextesWeb.Certificat.empreinteExplicationDebut', 'TextesWeb.Certificat.empreinteStorageAbsent',
  'TextesWeb.Certificat.empreinteExplicationFin',
];

const TEST_TABLE = 'table EXIGES de tests/node/textes-juridiques-ios.node.mjs';

test('TL : TextesWeb.swift (HARD STOP) porte tous les textes listés par le blueprint v2, par nom', () => {
  const absents = [];
  for (const [fichier, noms] of Object.entries(EXIGES)) {
    for (const nom of noms) {
      const c = parNom.get(`TextesWeb.${nom}`);
      if (!c) absents.push(`TextesWeb.${nom} (absent de ${TEXTES_SWIFT})`);
      else if (c.source.fichier !== fichier) absents.push(`TextesWeb.${nom} (source ${c.source.fichier}, attendu ${fichier})`);
    }
  }
  assert.deepEqual(absents, [], 'textes exigés par LOT2_PLAN §3 TL absents de TextesWeb.swift (noms de constantes : '
    + `${TEST_TABLE})`);
  assert.ok(resultat.objets.some(o => o.fichierSwift === TEXTES_SWIFT && o.source.variable === 'MESSAGES_ERREUR'));
  // Un décalage de lignes du web (cas de W1 : lignes retirées de PresencesSoignant.tsx entre les
  // textes l.101 et l.717 ; seul le dernier texte gardé du fichier se décale) ne fait rougir ni la
  // garde ni cette table.
  const presences = 'src/pages/PresencesSoignant.tsx';
  const bandeau = parNom.get('TextesWeb.Presences.bandeauAValider').source.debut;
  const refus = parNom.get('TextesWeb.Presences.pointageSansGpsActive').source.debut;
  const lignesPresences = read(presences).split('\n');
  const vides = lignesPresences.map((l, i) => i).filter(i => i > refus && i < bandeau - 2 && !lignesPresences[i].trim()).slice(0, 3);
  assert.equal(vides.length, 3);
  const retire = lignesPresences.filter((_, i) => !vides.includes(i)).join('\n');
  const r = verifier({ lireWeb: lireAvec(presences, retire) });
  assert.deepEqual(r.erreurs, []);
  assert.ok(r.avertissements.some(a => a.includes('TextesWeb.Presences.bandeauAValider') && a.includes(`retrouvé l.${bandeau - 3} `)
    && a.includes('--corriger-lignes')), JSON.stringify(r.avertissements));
});

test('TL : libellés et textes complémentaires présents (aucun texte de ces surfaces à écrire)', () => {
  assert.deepEqual(COMPLEMENTS.filter(nom => !parNom.has(nom)), [], 'libellés complémentaires absents');
});

test('TL : nature de chaque texte HARD STOP ; LibellesWeb.swift sans nature ni marque juridique', () => {
  const exiges = new Set(Object.values(EXIGES).flat().map(n => `TextesWeb.${n}`));
  for (const c of constantes) {
    if (c.hardStop) {
      assert.ok(NATURES.includes(c.nature), `${c.nomComplet} : nature « ${c.nature} »`);
      // « libellé » n'entre dans le fichier HARD STOP que parce que le blueprint l'y liste.
      if (c.nature === 'libellé') assert.ok(exiges.has(c.nomComplet), `${c.nomComplet} : libellé non listé par le blueprint, à mettre dans LibellesWeb.swift`);
    } else {
      assert.equal(c.nature, null, `${c.nomComplet} : nature dans LibellesWeb.swift`);
    }
  }
  // Nature absente ou inconnue dans TextesWeb.swift.
  const ancre = 'public enum ConsentementGps {\n';
  let r = verifier({ swiftSource: ajout(ancre, '        // source: src/components/ConsentementGPS.tsx:25\n        public static let titre2 = "Autorisation de géolocalisation"\n') });
  assert.ok(r.erreurs.some(e => e.includes('nature manquante')), JSON.stringify(r.erreurs));
  r = verifier({ swiftSource: ajout(ancre, '        // source: src/components/ConsentementGPS.tsx:25 [important]\n        public static let titre2 = "Autorisation de géolocalisation"\n') });
  assert.ok(r.erreurs.some(e => e.includes('nature manquante ou inconnue « important »')), JSON.stringify(r.erreurs));
  // Nature dans LibellesWeb.swift, et texte juridique glissé hors HARD STOP.
  const ancreLib = 'public enum Contestation {\n';
  r = verifier({ libellesSource: ajout(ancreLib, '        // source: src/components/PanneauContestation.tsx:262 [libellé]\n        public static let titre2 = "Contestation"\n', libelles) });
  assert.ok(r.erreurs.some(e => e.includes('nature « libellé » interdite')), JSON.stringify(r.erreurs));
  r = verifier({ libellesSource: ajout(ancreLib, '        // source: src/pages/ContratMission.tsx:743\n        public static let otp = "Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil."\n', libelles) });
  assert.ok(r.erreurs.some(e => e.includes('LibellesWeb.Contestation.otp') && e.includes('hors HARD STOP')), JSON.stringify(r.erreurs));
});

test('TL : chaque fragment et chaque assemblage HARD STOP figurent dans un rendu asserté par les tests Swift', () => {
  const { rendus } = zonesRendu;
  const rendusHardStop = rendus.filter(r => r.fonction.startsWith('TextesWeb.'));
  for (const c of constantes.filter(x => x.nature === 'fragment')) {
    assert.ok(rendusHardStop.some(r => r.rendu.includes(c.valeur)), `${c.nomComplet} : fragment absent des rendus montrés à Gabrielle`);
  }
  for (const a of resultat.assemblages.filter(x => x.public && x.genre !== 'liste')) {
    assert.ok(rendus.some(r => r.fonction === a.nomComplet), `${a.nomComplet} : aucun rendu dans ${ZONES_RENDU_JSON}`);
  }
  for (const f of FICHIERS_SWIFT) {
    const litteraux = new Set(litterauxSwift(read(f.tests)));
    for (const r of rendus.filter(x => x.fonction.startsWith(`${f.racine}.`))) {
      assert.ok(litteraux.has(r.rendu), `rendu « ${r.rendu} » (${r.fonction}) non asserté mot pour mot par ${f.tests}`);
    }
  }
});

test('TL : zones de rendu — chaque assemblage est ancré sur le code web qui produit son rendu', () => {
  assert.ok(resultat.zones.length >= 20);
  assert.deepEqual(resultat.zones.filter(z => z.statut !== 'exact').map(z => `${z.zone.source} ${z.statut}`), []);
  const ancrees = new Set(zonesRendu.zones.flatMap(z => z.fonctions));
  assert.deepEqual(resultat.assemblages.map(a => a.nomComplet).filter(n => !ancrees.has(n)), []);
  for (const z of zonesRendu.zones) assert.deepEqual(z.code, z.code.map(normaliserLigne), `${z.source} : code non normalisé`);
  // Un assemblage sans zone fait rougir la garde.
  const sansZone = { ...zonesRendu, zones: zonesRendu.zones.filter(z => !z.fonctions.includes('TextesWeb.Contrat.piedDePage')) };
  let r = verifier({ zonesRendu: sansZone });
  assert.ok(r.erreurs.some(e => e.includes('TextesWeb.Contrat.piedDePage') && e.includes('sans zone')), JSON.stringify(r.erreurs));
  // Une fonction annoncée qui n'existe plus aussi.
  const fantome = { ...zonesRendu, zones: [...zonesRendu.zones, { ...zonesRendu.zones[0], source: 'src/components/ConsentementGPS.tsx:35-40', fonctions: ['TextesWeb.Fantome.f'] }] };
  r = verifier({ zonesRendu: fantome });
  assert.ok(r.erreurs.some(e => e.includes('TextesWeb.Fantome.f') && e.includes("n'est pas un assemblage")), JSON.stringify(r.erreurs));
});

test('TL : la condition de la régularisation des montants (ContratMission.tsx l.836) est gardée', () => {
  const fichier = 'src/pages/ContratMission.tsx';
  const original = read(fichier);
  const mute = original.replace("{!texteEmployeur && 'Les montants", "{'Les montants");
  assert.notEqual(mute, original);
  const r = verifier({ lireWeb: lireAvec(fichier, mute) });
  // Toutes les unités restent identiques : seule la zone de rendu le voit.
  assert.ok(!r.erreurs.some(e => e.startsWith('TextesWeb.Contrat.regularisationMontants')), JSON.stringify(r.erreurs));
  const zone = sourceZone(zonesRendu.zones.find(z => z.fonctions.includes('TextesWeb.Contrat.piedDePage')));
  const erreur = r.erreurs.find(e => e.includes(`zone de rendu ${fichier} l.${lignes(zone.debut, zone.fin)}`));
  assert.ok(erreur, JSON.stringify(r.erreurs));
  assert.match(erreur, /TextesWeb\.Contrat\.piedDePage/);
  assert.match(erreur, /TextesWeb\.swift \(HARD STOP n°4/);
  assert.match(erreur, /TextesWebTests\.swift/);
  assert.match(erreur, /textes-web-ios-rendus\.json/);
});

test('TL : toute modification d’une zone de rendu rougit en nommant ses fonctions Swift', () => {
  for (const zone of zonesRendu.zones) {
    const source = /^(\S+?):(\d+)(?:-(\d+))?$/.exec(zone.source);
    const [fichier, debut] = [source[1], Number(source[2])];
    const lignes = read(fichier).split('\n');
    // Un caractère ajouté au milieu de la première ligne de la zone.
    const l = lignes[debut - 1];
    const milieu = l.length - Math.floor(l.trimStart().length / 2);
    lignes[debut - 1] = `${l.slice(0, milieu)}§${l.slice(milieu)}`;
    const r = verifier({ lireWeb: lireAvec(fichier, lignes.join('\n')) });
    const erreur = r.erreurs.find(e => e.includes(`zone de rendu ${fichier}`) && e.includes('modifiée'));
    assert.ok(erreur, `${zone.source} muté sans erreur : ${JSON.stringify(r.erreurs)}`);
    for (const nom of zone.fonctions) assert.ok(erreur.includes(nom), `${zone.source} : ${nom} non nommé`);
  }
});

test('TL : un décalage de lignes du web est toléré (avertissement) ; texte modifié, disparu ou ambigu : rouge', () => {
  const fichier = 'src/components/ConsentementGPS.tsx';
  const decale = `// ligne ajoutée\n${read(fichier)}`;
  let r = verifier({ lireWeb: lireAvec(fichier, decale) });
  assert.deepEqual(r.erreurs, []);
  const titre = r.avertissements.find(a => a.includes('TextesWeb.ConsentementGps.titre'));
  assert.ok(titre, JSON.stringify(r.avertissements));
  assert.ok(titre.includes(`retrouvé l.${parNom.get('TextesWeb.ConsentementGps.titre').source.debut + 1} `), titre);
  assert.match(titre, /--corriger-lignes/);
  assert.match(titre, /TextesWeb\.swift/);
  const liste = sourceZone(zonesRendu.zones.find(z => z.fonctions.includes('TextesWeb.ConsentementGps.ceQueNousFaisons')));
  assert.ok(r.avertissements.some(a => a.includes(`zone de rendu ${fichier} l.${lignes(liste.debut, liste.fin)}`)
    && a.includes(`retrouvée l.${lignes(liste.debut + 1, liste.fin + 1)}`)), JSON.stringify(r.avertissements));
  // Deux décalages différents dans un même fichier (ligne ajoutée en tête, ligne vide au milieu) :
  // les textes répétés (« s », « Code envoyé au », « Trop de tentatives… ») sont départagés par
  // leurs voisines ; --corriger-lignes réaligne tout.
  const signer = 'src/components/SignerContratOtp.tsx';
  const lignesOtp = read(signer).split('\n');
  lignesOtp.splice(302, 0, '');
  lignesOtp.splice(1, 0, '// ligne ajoutée');
  const lireDeux = lireAvec(signer, lignesOtp.join('\n'));
  r = verifier({ lireWeb: lireDeux });
  assert.deepEqual(r.erreurs, []);
  assert.ok(r.avertissements.length > 20, JSON.stringify(r.avertissements));
  const deux = corrigerLignes({ swiftSource: swift, libellesSource: libelles, zonesSource: zonesTexte, lireWeb: lireDeux });
  assert.deepEqual(deux.restantes, []);
  const realigne = verifierTextes({
    swiftSource: deux.sources[TEXTES_SWIFT], libellesSource: deux.sources[LIBELLES_SWIFT],
    zonesRendu: JSON.parse(deux.sources[ZONES_RENDU_JSON]), lireWeb: lireDeux,
  });
  assert.deepEqual([realigne.erreurs, realigne.avertissements], [[], []]);
  // Texte modifié : rouge, avec les fichiers à toucher.
  r = verifier({ lireWeb: lireAvec(fichier, read(fichier).replace('Je refuse', 'Je décline')) });
  const refus = r.erreurs.find(e => e.startsWith('TextesWeb.ConsentementGps.refuser'));
  assert.ok(refus, JSON.stringify(r.erreurs));
  assert.match(refus, /TextesWeb\.swift \(HARD STOP n°4/);
  assert.match(refus, /TextesWebTests\.swift/);
  // Texte modifié à sa ligne alors qu'un texte identique existe ailleurs, hors de la place de ses
  // voisines : ce n'est pas un décalage, rouge.
  const otp = 'src/components/SignerContratOtp.tsx';
  const finEnvoi = "' });\n    } finally {\n      operationEnCours.current = false;\n      if (actif.current) setLoading(false);\n    }\n  }\n\n  async function signer";
  const copie = read(otp).replace(`'Erreur réseau. Réessayez.${finEnvoi}`,
    `'Erreur réseau.${finEnvoi.replace('\n\n  async function signer', "\n  const x = ['Erreur réseau. Réessayez.'];\n  async function signer")}`);
  assert.notEqual(copie, read(otp));
  r = verifier({ lireWeb: lireAvec(otp, copie) });
  assert.ok(r.erreurs.some(e => e.startsWith('LibellesWeb.SignatureOtp.erreurReseauEnvoi') && e.includes('hors de la place de ses voisines')),
    JSON.stringify(r.erreurs));
  // Texte court modifié à sa ligne alors qu'une copie fortuite existe plus haut
  // (`usePageTitle('Certificat de signature')`) : rouge, la copie n'est pas à la place du titre.
  const page = 'src/pages/CertificatSignaturePage.tsx';
  const titrePage = read(page).replace('text-foreground">Certificat de signature</h1>', 'text-foreground">Certificat de signature électronique</h1>');
  assert.notEqual(titrePage, read(page));
  r = verifier({ lireWeb: lireAvec(page, titrePage) });
  assert.ok(r.erreurs.some(e => e.startsWith('TextesWeb.Certificat.titrePage') && e.includes('hors de la place de ses voisines')),
    JSON.stringify(r.erreurs));
  // Texte présent deux fois ailleurs, sans décalage commun : ambigu, rouge.
  const double = `${read(otp).replace(`'Erreur réseau. Réessayez.${finEnvoi}`, `'Erreur réseau.${finEnvoi}`)}\nconst x = ['Erreur réseau. Réessayez.'];\nconst y = ['Erreur réseau. Réessayez.'];\n`;
  r = verifier({ lireWeb: lireAvec(otp, double) });
  assert.ok(r.erreurs.some(e => e.startsWith('LibellesWeb.SignatureOtp.erreurReseauEnvoi') && e.includes('plusieurs fois')), JSON.stringify(r.erreurs));
  // Texte supprimé à sa ligne mais présent ailleurs, déjà pris par une autre constante : modifié.
  const seul = read(otp).replace("extraireMessageErreur(err) || 'Erreur réseau. Réessayez.' });\n    } finally {\n      operationEnCours.current = false;\n      if (actif.current) setLoading(false);\n    }\n  }\n\n  async function signer",
    "extraireMessageErreur(err) || '' });\n    } finally {\n      operationEnCours.current = false;\n      if (actif.current) setLoading(false);\n    }\n  }\n\n  async function signer");
  assert.notEqual(seul, read(otp));
  r = verifier({ lireWeb: lireAvec(otp, seul) });
  assert.ok(r.erreurs.some(e => e.startsWith('LibellesWeb.SignatureOtp.erreurReseauEnvoi') && e.includes("n'affiche plus")), JSON.stringify(r.erreurs));
});

test('TL : --corriger-lignes suit les décalages (textes, libellés, objets, ensembles, zones), jamais un texte modifié', () => {
  const fichier = 'src/components/ConsentementGPS.tsx';
  const lire = lireAvec(fichier, `// ligne ajoutée\n${read(fichier)}`);
  const { sources, corrections, restantes } = corrigerLignes({ swiftSource: swift, libellesSource: libelles, zonesSource: zonesTexte, lireWeb: lire });
  assert.deepEqual(restantes, []);
  assert.equal(corrections.length, constantes.filter(c => c.source.fichier === fichier).length
    + zonesRendu.zones.filter(z => z.source.startsWith(`${fichier}:`)).length);
  const apres = verifierTextes({
    swiftSource: sources[TEXTES_SWIFT], libellesSource: sources[LIBELLES_SWIFT], zonesRendu: JSON.parse(sources[ZONES_RENDU_JSON]), lireWeb: lire,
  });
  assert.deepEqual(apres.erreurs, []);
  assert.deepEqual(apres.avertissements, []);
  const titre = parNom.get('TextesWeb.ConsentementGps.titre').source;
  assert.ok(sources[TEXTES_SWIFT].includes(`// source: ${fichier}:${titre.debut + 1} [consentement]\n        public static let titre = `));
  const liste = sourceZone(zonesRendu.zones.find(z => z.fonctions.includes('TextesWeb.ConsentementGps.ceQueNousFaisons')));
  assert.ok(sources[ZONES_RENDU_JSON].includes(`"source": "${fichier}:${lignes(liste.debut + 1, liste.fin + 1)}"`));
  // SignerContratOtp : textes des deux fichiers, texte présent deux fois (l.156 et l.202) départagé
  // par le décalage commun, dictionnaire, ensemble et zones suivent.
  const otp = 'src/components/SignerContratOtp.tsx';
  const lireOtp = lireAvec(otp, `// ligne ajoutée\n${read(otp)}`);
  const otpCorrige = corrigerLignes({ swiftSource: swift, libellesSource: libelles, zonesSource: zonesTexte, lireWeb: lireOtp });
  assert.deepEqual(otpCorrige.restantes, []);
  const apresOtp = verifierTextes({
    swiftSource: otpCorrige.sources[TEXTES_SWIFT], libellesSource: otpCorrige.sources[LIBELLES_SWIFT],
    zonesRendu: JSON.parse(otpCorrige.sources[ZONES_RENDU_JSON]), lireWeb: lireOtp,
  });
  assert.deepEqual(apresOtp.erreurs, []);
  assert.deepEqual(apresOtp.avertissements, []);
  const objet = resultat.objets.find(o => o.source.variable === 'MESSAGES_ERREUR').source;
  const ensemble = resultat.ensembles.find(e => e.source.fichier === otp).source;
  const reseau = parNom.get('LibellesWeb.SignatureOtp.erreurReseauSignature').source;
  const confirmation = sourceZone(zonesRendu.zones.find(z => z.fonctions.includes('TextesWeb.SignatureOtp.confirmationSignature')));
  assert.ok(otpCorrige.sources[TEXTES_SWIFT].includes(`// source-objet: ${otp}:${objet.debut + 1} MESSAGES_ERREUR\n`));
  assert.ok(otpCorrige.sources[TEXTES_SWIFT].includes(`// source-ensemble: ${otp}:${lignes(ensemble.debut + 1, ensemble.fin + 1)}\n`));
  assert.ok(otpCorrige.sources[LIBELLES_SWIFT].includes(`// source: ${otp}:${reseau.debut + 1}\n        public static let erreurReseauSignature`));
  assert.ok(otpCorrige.sources[ZONES_RENDU_JSON].includes(`"source": "${otp}:${lignes(confirmation.debut + 1, confirmation.fin + 1)}"`));
  // Texte modifié : jamais « corrigé », l'erreur reste.
  const lireMute = lireAvec(fichier, read(fichier).replace('Autorisation de géolocalisation', 'Autorisation de la géolocalisation'));
  const r = corrigerLignes({ swiftSource: swift, libellesSource: libelles, zonesSource: zonesTexte, lireWeb: lireMute });
  assert.equal(r.sources[TEXTES_SWIFT], swift);
  assert.equal(r.sources[ZONES_RENDU_JSON], zonesTexte);
  assert.ok(verifier({ lireWeb: lireMute }).erreurs.some(e => e.includes('ConsentementGps.titre')));
});

test('TL : verrou Q9 — aucun texte de délai de contestation, localisé par son texte', () => {
  const panneau = 'src/components/PanneauContestation.tsx';
  const unites = lireWeb(panneau).unites;
  // Les trois textes de délai existent aujourd'hui (sinon le web a bougé : la garde rougit).
  for (const motif of MOTIFS_Q9) assert.ok(unites.some(u => motif.test(u.valeur)), `${motif} introuvable`);
  assert.ok(ANCRES_Q9.every(a => a.fichier === panneau));
  // Aucune constante ne couvre un de ces textes.
  for (const u of unites.filter(x => MOTIFS_Q9.some(m => m.test(x.valeur)))) {
    assert.ok(!constantes.some(c => c.source.fichier === panneau && c.source.debut <= u.bloc.fin && c.source.fin >= u.bloc.debut),
      `l.${u.debut} repris`);
  }
  const ancre = 'public enum Contestation {\n';
  const ligne347 = unites.find(u => /72\s?h pour répondre/.test(u.valeur)).debut;
  // Constante annotée dans un bloc verrouillé (texte pourtant verbatim).
  let r = verifier({ swiftSource: ajout(ancre, `        // source: ${panneau}:${ligne347} [juridique]\n        public static let delai = "72h pour répondre"\n`) });
  assert.ok(r.erreurs.some(e => e.includes('Contestation.delai') && e.includes('Q9')), JSON.stringify(r.erreurs));
  // Même texte annoncé ailleurs : le verrou porte aussi sur la valeur.
  r = verifier({ swiftSource: ajout(ancre, `        // source: ${panneau}:366 [juridique]\n        public static let delai = "Vous avez 72 h après la validation pour contester. Sans résolution sous 72 h, l'admin plateforme tranchera."\n`) });
  assert.ok(r.erreurs.some(e => e.includes('Contestation.delai') && e.includes('Q9')), JSON.stringify(r.erreurs));
  // Délai de contestation reformulé ailleurs, dans un autre groupe et dans LibellesWeb.swift.
  r = verifier({ swiftSource: ajout('public enum Presences {\n', `        // source: ${panneau}:366 [juridique]\n        public static let delai = "48 h pour contester"\n`) });
  assert.ok(r.erreurs.some(e => e.includes('TextesWeb.Presences.delai') && e.includes('Q9')), JSON.stringify(r.erreurs));
  r = verifier({ libellesSource: ajout('public enum Presences {\n', `        // source: ${panneau}:366\n        public static let delai = "Délai du litige dépassé"\n`, libelles) });
  assert.ok(r.erreurs.some(e => e.includes('LibellesWeb.Presences.delai') && e.includes('Q9')), JSON.stringify(r.erreurs));
  // Un texte de délai déplacé dans le web reste verrouillé, sans rougir (localisé par son texte).
  const decale = read(panneau).replace('Discussion en cours —', '\nDiscussion en cours —');
  assert.notEqual(decale, read(panneau));
  r = verifier({ lireWeb: lireAvec(panneau, decale) });
  assert.deepEqual(r.erreurs, []);
  // Un texte de délai disparu fait rougir la garde : Q9 est à relire.
  const retire = read(panneau).replace('72h pour répondre', 'réponse attendue');
  r = verifier({ lireWeb: lireAvec(panneau, retire) });
  assert.ok(r.erreurs.some(e => e.startsWith('ANCRES_Q9') && e.includes('relire Q9')), JSON.stringify(r.erreurs));
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
      const { erreurs } = verifier(avecSource(constante, remplacerConstante(sourceDe(constante), constante, mutation)));
      assert.ok(erreurs.some(e => e.includes(constante.nomComplet)),
        `${constante.nomComplet} muté en « ${mutation} » sans erreur : ${JSON.stringify(erreurs)}`);
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
    assert.ok(unite, `${constante.nomComplet} : unité web introuvable`);
    // Premier caractère du texte dans le fichier (lettre, chiffre, sinon ponctuation hors
    // délimiteurs de gabarit ou de chaîne), remplacé par un autre.
    const extrait = original.slice(unite.offset, unite.offsetFin);
    let decalage = extrait.search(/\p{L}|\p{N}|…/u);
    if (decalage < 0) decalage = extrait.search(/[^\s{}`$'"]/u);
    assert.ok(decalage >= 0, `${constante.nomComplet} : aucun caractère à muter`);
    const position = unite.offset + decalage;
    const remplacant = original[position] === 'x' ? 'y' : 'x';
    const mute = original.slice(0, position) + remplacant + original.slice(position + 1);
    const { erreurs } = verifier({ lireWeb: lireAvec(fichier, mute) });
    assert.ok(erreurs.some(e => e.includes(constante.nomComplet)), `${constante.nomComplet} : texte web muté sans erreur`);
  }
});

test('TL : toute constante, tout littéral et toute structure des deux fichiers sont gardés', () => {
  const ancre = 'public enum ConsentementGps {\n';
  // Constante sans annotation de source.
  let r = verifier({ swiftSource: ajout(ancre, '        public static let ajout = "Bonjour"\n') });
  assert.ok(r.erreurs.some(e => e.includes('ConsentementGps.ajout') && e.includes('sans annotation')), JSON.stringify(r.erreurs));
  // Littéral hors constante annotée (texte glissé dans une fonction), dans chacun des fichiers.
  r = verifier({ swiftSource: ajout(ancre, '        static func f() -> String { "Texte libre" }\n') });
  assert.ok(r.erreurs.some(e => e.includes('littéral non gardé') && e.includes('Texte libre')), JSON.stringify(r.erreurs));
  r = verifier({ libellesSource: ajout('public enum Presences {\n', '        static func f() -> String { "Texte libre" }\n', libelles) });
  assert.ok(r.erreurs.some(e => e.includes(LIBELLES_SWIFT) && e.includes('littéral non gardé')), JSON.stringify(r.erreurs));
  // Littéral contenant « // » : jamais pris pour un commentaire.
  r = verifier({ swiftSource: ajout(ancre, '        static func g() -> String { "voir https://jolene.app" }\n') });
  assert.ok(r.erreurs.some(e => e.includes('littéral non gardé') && e.includes('https://jolene.app')), JSON.stringify(r.erreurs));
  // Littéral multi-ligne : ses lignes intérieures n'ont pas de guillemets, il est refusé en bloc.
  r = verifier({ swiftSource: ajout(ancre, '        static let h = """\n        Texte libre sur plusieurs lignes\n        """\n') });
  assert.ok(r.erreurs.some(e => e.includes('multi-ligne')), JSON.stringify(r.erreurs));
  r = verifier({ swiftSource: ajout(ancre, '        // source: src/components/ConsentementGPS.tsx:25 [consentement]\n        public static let titre2 = #"""\n        Autorisation de géolocalisation\n        """#\n') });
  assert.ok(r.erreurs.some(e => e.includes('multi-ligne')), JSON.stringify(r.erreurs));
  // Une annotation ne passe pas à la constante d'après si une autre déclaration s'intercale.
  r = verifier({
    swiftSource: ajout(ancre, '        // source: src/components/ConsentementGPS.tsx:25 [consentement]\n        public static let liste = [titre]\n'
      + '        public static let orpheline = "Autorisation de géolocalisation"\n'),
  });
  assert.ok(r.erreurs.some(e => e.includes('annotation qui ne précède aucune constante')), JSON.stringify(r.erreurs));
  assert.ok(r.erreurs.some(e => e.includes('ConsentementGps.orpheline') && e.includes('sans annotation')), JSON.stringify(r.erreurs));
  // Interpolation Swift interdite.
  r = verifier({ swiftSource: ajout(ancre, '        // source: src/components/ConsentementGPS.tsx:25 [consentement]\n        public static let gabarit = "Autorisation \\(x)"\n') });
  assert.ok(r.erreurs.some(e => e.includes('ConsentementGps.gabarit') && e.includes('interpolation')), JSON.stringify(r.erreurs));
  // Entrée absente du catalogue (les tests Swift parcourent le catalogue), dans chacun des fichiers.
  const sansCatalogue = swift.replace(/^\s*\.init\(cle: "ConsentementGps\.titre", texte: ConsentementGps\.titre\),\n/m, '');
  assert.notEqual(sansCatalogue, swift);
  r = verifier({ swiftSource: sansCatalogue });
  assert.ok(r.erreurs.some(e => e.includes('catalogue de TextesWeb') && e.includes('ConsentementGps.titre')), JSON.stringify(r.erreurs));
  const sansCatalogueLib = libelles.replace(/^\s*\.init\(cle: "Contestation\.annuler", texte: Contestation\.annuler\),\n/m, '');
  assert.notEqual(sansCatalogueLib, libelles);
  r = verifier({ libellesSource: sansCatalogueLib });
  assert.ok(r.erreurs.some(e => e.includes('catalogue de LibellesWeb') && e.includes('Contestation.annuler')), JSON.stringify(r.erreurs));
});

test('TL : les dictionnaires et l’ensemble des bloquants suivent le web clé par clé', () => {
  // Deux messages permutés : chaque texte reste verbatim, mais attaché au mauvais code.
  const permute = swift
    .replace('"OTP_EXPIRE": otpExpire,', '"OTP_EXPIRE": __TMP__,')
    .replace('"OTP_INCORRECT": otpIncorrect,', '"OTP_INCORRECT": otpExpire,')
    .replace('"OTP_EXPIRE": __TMP__,', '"OTP_EXPIRE": otpIncorrect,');
  assert.notEqual(permute, swift);
  let r = verifier({ swiftSource: permute });
  assert.ok(r.erreurs.some(e => e.includes('OTP_EXPIRE')), JSON.stringify(r.erreurs));
  // Code oublié.
  const oubli = swift.replace(/^\s*"TROP_DE_SMS": tropDeSms,\n/m, '');
  assert.notEqual(oubli, swift);
  r = verifier({ swiftSource: oubli });
  assert.ok(r.erreurs.some(e => e.includes('TROP_DE_SMS') && e.includes('absent')), JSON.stringify(r.erreurs));
  // Code bloquant oublié.
  const bloquant = swift.replace('"HASH_DOCUMENT_CHANGE",\n', '');
  assert.notEqual(bloquant, swift);
  r = verifier({ swiftSource: bloquant });
  assert.ok(r.erreurs.some(e => e.includes('HASH_DOCUMENT_CHANGE')), JSON.stringify(r.erreurs));
  // Libellé de statut attaché au mauvais statut, puis statut oublié.
  const statutPermute = swift.replace('"FERME": statutFerme,', '"FERME": statutOuvert,');
  assert.notEqual(statutPermute, swift);
  r = verifier({ swiftSource: statutPermute });
  assert.ok(r.erreurs.some(e => e.includes('FERME') && e.includes('STATUT_CONFIG.label')), JSON.stringify(r.erreurs));
  const statutOubli = swift.replace(/^\s*"REVUE_ADMIN": statutRevueAdmin,\n/m, '');
  assert.notEqual(statutOubli, swift);
  r = verifier({ swiftSource: statutOubli });
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
  const unites = unitesWeb('exemple.tsx', tsx).map(u => [u.valeur, u.debut, u.fin, u.genre, u.bloc]);
  assert.ok(unites.some(([v, d, f, g]) => v === 'Première ligne, seconde ligne.' && d === 3 && f === 4 && g === 'jsx'),
    JSON.stringify(unites));
  assert.ok(unites.some(([v, d, , g, b]) => v === 'Badge' && d === 5 && g === 'jsx' && b.debut === 5 && b.fin === 5), JSON.stringify(unites));
  assert.ok(unites.some(([v, d, , g, b]) => v === "Littéral l'apostrophe" && d === 6 && g === 'chaine' && b.debut === 2 && b.fin === 7),
    JSON.stringify(unites));
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
    // T4a : libellés vouvoyés et assemblages de la page Présences, hors LibellesWeb.swift.
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Libelles/LibellesPresences.swift',
  ]) {
    assert.ok(DOSSIERS_LOT2.some(d => chemin === d || chemin.startsWith(`${d}/`)), `${chemin} hors de DOSSIERS_LOT2`);
  }
  // Fondation du lot 2 (T1, déjà livrée) qui porte des textes affichés (revue fraîche de T1, seconde passe).
  for (const chemin of [
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Receipts/RecuScan.swift',
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Receipts/RecuDocument.swift',
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Receipts/ReceiptJournal.swift',
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Models/Lot2Results.swift',
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Ports/Lot2Ports.swift',
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Ports/AppareilPorts.swift',
    'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Keychain/KeychainTerminalIdentity.swift',
    'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Keychain/KeychainReceiptStore.swift',
  ]) {
    assert.ok(DOSSIERS_LOT2.some(d => chemin === d || chemin.startsWith(`${d}/`)), `${chemin} hors de DOSSIERS_LOT2`);
    assert.ok(existsSync(join(ROOT, chemin)), `${chemin} absent du dépôt`);
  }
  // Aucun fichier du lot 1 n'entre dans la garde (en-tête de DOSSIERS_LOT2).
  for (const chemin of [
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Ports/Lot1Ports.swift',
    'ios-native/Packages/JoleneCore/Sources/JoleneCore/Ports/Ports.swift',
    'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Keychain/KeychainSessionStorage.swift',
  ]) {
    assert.ok(!DOSSIERS_LOT2.some(d => chemin === d || chemin.startsWith(`${d}/`)), `${chemin} (lot 1) dans DOSSIERS_LOT2`);
  }
  // Un texte juridique ajouté plus tard à un message du journal de reçus ou du trousseau fait rougir la garde.
  const fondation = textesJuridiquesHorsTL([
    { chemin: 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Receipts/RecuScan.swift',
      contenu: 'public static let messageIllisible = "Horodatage non vérifiable : pointez depuis jolene.app."' },
    { chemin: 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Keychain/KeychainTerminalIdentity.swift',
      contenu: 'static let messageIllisible = "Retirez votre consentement depuis votre profil."' },
  ]);
  assert.equal(fondation.length, 2, JSON.stringify(fondation));
  assert.match(fondation[0], /RecuScan\.swift:1/);
  assert.match(fondation[1], /KeychainTerminalIdentity\.swift:1/);
  const dossier = DOSSIERS_LOT2[0];
  const fautes = textesJuridiquesHorsTL([
    { chemin: `${dossier}/Exemple.swift`, contenu: 'let a = "Conforme art. 1366-1367 Code civil."\n// Code civil en commentaire : permis\nlet b = "Bonjour"' },
    { chemin: TEXTES_SWIFT, contenu: 'let c = "Base légale : consentement (Art. 6.1.a RGPD)."' },
    { chemin: 'ios-native/Jolene/Screens/Profil/ConsentementGpsRow.swift', contenu: 'Text("Consentement GPS")\n.accessibilityIdentifier("profil-gps-consentement")' },
    { chemin: 'ios-native/Packages/JoleneDesign/Sources/JoleneDesign/Components/CountdownLabel.swift', contenu: 'Text("Délai de signature expiré (72h dépassées).")' },
    // Littéral multi-ligne : ses lignes intérieures échapperaient à la détection, il est refusé.
    { chemin: `${dossier}/Multi.swift`, contenu: 'let m = """\nJ\'atteste sur l\'honneur\n"""' },
    // Affirmation probatoire (bloc « Empreinte du document signé ») : marques preuve / SHA-256 / horodatage.
    { chemin: 'ios-native/Jolene/Screens/Contrats/CertificatView.swift', contenu: 'Text("c\'est la preuve que le document n\'a pas été modifié")\nText("Empreinte SHA-256 du contrat")\nText("Horodatage, IP et hash conservés")' },
  ]);
  assert.equal(fautes.length, 7, JSON.stringify(fautes));
  assert.match(fautes[0], /Exemple\.swift:1/);
  assert.match(fautes[1], /ConsentementGpsRow\.swift:1/);
  assert.match(fautes[2], /CountdownLabel\.swift:1/);
  assert.match(fautes[3], /Multi\.swift:1 .*multi-ligne/);
  assert.match(fautes[4], /CertificatView\.swift:1/);
  assert.match(fautes[5], /CertificatView\.swift:2/);
  assert.match(fautes[6], /CertificatView\.swift:3/);
  // Codes et identifiants (littéraux sans espace) : l'audit de T4b à parité avec
  // PresencesSoignant.tsx l.76-78 (décision Q4) ne fait pas rougir la garde.
  const audit = textesJuridiquesHorsTL([
    { chemin: 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Pointage/SupabaseConsentementGateway.swift',
      contenu: 'let action = "RGPD_CONSENTEMENT_DONNE"\nlet details: [String: AnyJSON] = ["type": "gps", "consentement": true]' },
    { chemin: 'ios-native/Packages/JoleneCore/Sources/JoleneCore/Pointage/ConsentementGpsModel.swift',
      contenu: 'let id = "gps-consent-sheet"\nlet cle = "consentement_gps"' },
  ]);
  assert.deepEqual(audit, []);
});

test('TL : chaînes système iOS verrouillées (Info.plist, INFOPLIST_KEY_*, fichiers de chaînes)', () => {
  assert.deepEqual(chainesSystemeIosSurDisque(ROOT), []);
  const plist = read(INFO_PLIST);
  assert.equal(Object.keys(CHAINES_INFO_PLIST).length, 8);
  // Nouvelle chaîne (précision temporaire, refusée par LOT2_PLAN §7 Q5).
  const temporaire = plist.replace('<key>ITSAppUsesNonExemptEncryption</key>',
    '<key>NSLocationTemporaryUsageDescriptionDictionary</key>\n\t<dict>\n\t\t<key>Pointage</key>\n\t\t<string>Précision exacte pour le pointage.</string>\n\t</dict>\n\t<key>ITSAppUsesNonExemptEncryption</key>');
  assert.notEqual(temporaire, plist);
  let fautes = chainesSystemeIos({ infoPlist: temporaire });
  assert.ok(fautes.some(f => f.includes('NSLocationTemporaryUsageDescriptionDictionary') && f.includes('Q5')), JSON.stringify(fautes));
  // Texte modifié.
  const modifie = plist.replace('scanner les QR codes de pointage', 'scanner les QR codes');
  assert.notEqual(modifie, plist);
  fautes = chainesSystemeIos({ infoPlist: modifie });
  assert.ok(fautes.some(f => f.includes('NSCameraUsageDescription') && f.includes('verrouillé')), JSON.stringify(fautes));
  // Chaîne injectée par un réglage de projet, puis fichier de chaînes.
  fautes = chainesSystemeIos({
    infoPlist: plist,
    projets: [{ chemin: 'ios-native/project.yml', contenu: 'settings:\n  INFOPLIST_KEY_NSMicrophoneUsageDescription: "Micro"' }],
    fichiersChaines: ['ios-native/Jolene/Localizable.xcstrings'],
  });
  assert.equal(fautes.length, 2, JSON.stringify(fautes));
  assert.match(fautes[0], /project\.yml:2/);
  assert.match(fautes[1], /Localizable\.xcstrings/);
});

test('TL : --liste donne la nature de chaque texte HARD STOP, les rendus assemblés et les libellés à part', () => {
  const liste = listeMarkdown(resultat);
  assert.match(liste, /### Textes HARD STOP n°4 — `TextesWeb\.swift`/);
  assert.match(liste, /\| Constante \| Nature \| Texte \(verbatim\) \| Source \|/);
  assert.match(liste, /\| `Contrat\.regularisationMontants` \| fragment \|/);
  assert.match(liste, /### Rendus assemblés/);
  assert.ok(liste.includes('Contrat salarié préparé selon le cadre déclaré par l’employeur. Signature électronique simple. | HARD STOP'));
  assert.ok(liste.includes('Code incorrect. 4 tentatives restantes.'));
  assert.ok(liste.includes('Code envoyé au 06 •• •• •• 12. Valide 10 min. | hors HARD STOP'));
  assert.match(liste, /### Libellés hors HARD STOP — `LibellesWeb\.swift`/);
  const lignesHardStop = liste.split('### Rendus')[0].split('\n').filter(l => l.startsWith('| `'));
  assert.equal(lignesHardStop.length, constantes.filter(c => c.hardStop).length);
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
