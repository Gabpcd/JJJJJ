import XCTest
@testable import JoleneCore

/// Libellés de l'écran Justificatifs (lot 2 T7) : chaque texte est celui du web à la ligne annoncée, repris tel quel ou
/// vouvoyé quand le web tutoie (décision 9 du lot 1, même règle que `MessagesDocuments` : seule la personne change, verbe,
/// pronom et possessif). Ce test relit les sources web : il rougit si un texte change d'un côté sans l'autre. Les textes
/// juridiques (attestation santé) restent dans `Legal/TextesWeb.swift` (HARD STOP n°4) ; les textes opérationnels sans
/// équivalent web sont inventoriés dans `docs/mobile-swift/DECISIONS_LOT2.md` (« Textes opérationnels hors web (T7) »).
final class LibellesJustificatifsTests: XCTestCase {
    private typealias L = LibellesJustificatifs

    private var racine: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JoleneCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // JoleneCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios-native
            .deletingLastPathComponent() // racine du dépôt
    }

    private func lignes(_ relatif: String) throws -> [String] {
        try String(contentsOf: racine.appendingPathComponent(relatif), encoding: .utf8)
            .components(separatedBy: "\n")
    }

    /// Ligne web (1-indexée), échappements des littéraux entre apostrophes droites décodés (`\'` → `'`).
    private func ligneWeb(_ relatif: String, _ numero: Int) throws -> String {
        let toutes = try lignes(relatif)
        XCTAssertGreaterThanOrEqual(toutes.count, numero, relatif)
        guard numero >= 1, numero <= toutes.count else { return "" }
        return toutes[numero - 1].replacingOccurrences(of: "\\'", with: "'")
    }

    private static let page = "src/pages/DocumentsSoignant.tsx"
    private static let modale = "src/components/ModalTeleversement.tsx"
    private static let onglets = "src/pages/MesDocuments.tsx"

    /// Textes repris tels quels : (natif, fichier, ligne).
    private var verbatim: [(String, String, Int)] {
        [
            (L.titre, Self.onglets, 27), (L.ongletJustificatifs, Self.onglets, 36), (L.ongletContrats, Self.onglets, 40),
            (L.ongletDpae, Self.onglets, 44),
            (L.documentsIndisponibles, Self.page, 490), (L.reessayer, Self.page, 499),
            (L.dossierTitre, Self.page, 509), (L.dossierTexte, Self.page, 511),
            (L.professionNonDefinie, Self.page, 534), (L.modeExerciceTitre, Self.page, 547),
            (L.resteDocument, Self.page, 561), (L.resteFin, Self.page, 561),
            (L.prochaineEtape, Self.page, 566), (L.televerserPrefixe, Self.page, 575),
            (L.aJourSansExercice, Self.page, 590), (L.vosJustificatifs, Self.page, 595), (L.aucunObligatoire, Self.page, 596),
            (L.expireDans, Self.page, 605), (L.jour, Self.page, 605), (L.mettreAJour, Self.page, 606),
            (L.documentsOptionnels, Self.page, 671), (L.obligatoire, Self.page, 684),
            (L.televerseLe, Self.page, 693), (L.verifie, Self.page, 697), (L.qualificationDebut, Self.page, 702),
            (L.verificationAutomatiqueEnCours, Self.page, 708), (L.analyseNonConclue, Self.page, 708),
            (L.demandeRecue, Self.page, 713), (L.verificationIndisponible, Self.page, 718),
            (L.delivreLe, Self.page, 722), (L.valideJusquau, Self.page, 725), (L.voirLeDocument, Self.page, 728),
            (L.reverifier, Self.page, 736), (L.demandeEnCours, Self.page, 745), (L.demanderRevue, Self.page, 745),
            (L.remplacer, Self.page, 748), (L.verificationEnCours, Self.page, 756), (L.documentNonValide, Self.page, 761),
            (L.rejete, Self.page, 763), (L.reessayer, Self.page, 767), (L.voir, Self.page, 768),
            (L.expireDepuis, Self.page, 788), (L.expireDepuisFin, Self.page, 788), (L.expire, Self.page, 789),
            (L.televerserNouveau, Self.page, 791), (L.aTeleverser, Self.page, 804), (L.plusTeleverser, Self.page, 806),
            (L.etudiantInterne, Self.page, 862), (L.titreScolarite, Self.page, 865), (L.titreLicence, Self.page, 880),
            (L.titreQualification, Self.page, 895), (L.statutAActualiser, Self.page, 897),
            (L.remplacerAttestation, Self.page, 899), (L.ajouterAttestation, Self.page, 899),
            (L.derniereEtape, Self.page, 908),
            (L.verificationDemandee, Self.page, 428), (L.verificationManuelle, Self.page, 419),
            (L.televersementImpossible, Self.page, 377), (L.revueEnvoyee, Self.page, 354),
            (L.reverificationVerifie, Self.page, 318), (L.reverificationRejete, Self.page, 320),
            (L.reverificationNonConforme, Self.page, 320), (L.reverificationRevue, Self.page, 322),
            (L.reverificationAttente, Self.page, 324),
            (L.televerserTitre, Self.modale, 121), (L.aidePhoto, Self.modale, 124), (L.prendrePhoto, Self.modale, 138),
            (L.choisirGalerie, Self.modale, 163), (L.choisirFichier, Self.modale, 200),
            (L.choisirFichierAccessibilite, Self.modale, 183), (L.formats, Self.modale, 201),
            (L.formatsAccessibilite, Self.modale, 191), (L.fichierChoisi, Self.modale, 194), (L.ko, Self.modale, 195),
            (L.libelleOptionnel, Self.modale, 208), (L.placeholderParDefaut, Self.modale, 52),
            (L.annuler, Self.modale, 213), (L.envoi, Self.modale, 215), (L.televerser, Self.modale, 215),
            (L.fermerAccessibilite, Self.modale, 117), (L.cameraImpossible, Self.modale, 106),
            (L.galerieImpossible, Self.modale, 158),
        ]
    }

    /// Textes vouvoyés : (natif, texte web tutoyé, fichier, ligne, conversions appliquées dans l'ordre).
    private var vouvoyes: [(String, String, String, Int, [(String, String)])] {
        [
            (L.professionNonDefinieTexte, "Renseigne ta profession dans ton profil pour voir les documents qui te concernent.",
             Self.page, 536, [("Renseigne ta", "Renseignez votre"), ("ton profil", "votre profil"), ("qui te concernent", "qui vous concernent")]),
            (L.modeExerciceTexte,
             "Les justificatifs communs sont affichés ici. Les pièces propres au salariat ou au libéral seront précisées quand tu renseigneras ton mode d’exercice. Tu peux continuer à explorer les missions.",
             Self.page, 549, [("quand tu renseigneras ton", "quand vous renseignerez votre"), ("Tu peux", "Vous pouvez")]),
            (L.resteDebut, "Il te reste", Self.page, 561, [("Il te reste", "Il vous reste")]),
            (L.postulerDesMaintenant, "Tu peux postuler dès maintenant — valide tes documents pour être accepté par les établissements.",
             Self.page, 583, [("Tu peux", "Vous pouvez"), ("valide tes", "validez vos")]),
            (L.aJourExercice, "Tous tes documents obligatoires sont à jour 🎉", Self.page, 590, [("Tous tes", "Tous vos")]),
            (L.retrouvezIci, "Retrouve ici tes justificatifs et leurs dates de validité.", Self.page, 591,
             [("Retrouve ici tes", "Retrouvez ici vos")]),
            (L.expirePrefixe, "⏰ Ton", Self.page, 605, [("Ton", "Votre")]),
            (L.rcpExpireeCoherence, "Ton assurance RCP est expirée", Self.page, 293, [("Ton", "Votre")]),
            (L.incoherencePrefixe, "⚠️ Incohérence détectée entre tes documents :", Self.page, 647, [("entre tes", "entre vos")]),
            (L.incoherenceFin, "Vérifie que tous tes documents sont à jour et au même nom.", Self.page, 647,
             [("Vérifie que tous tes", "Vérifiez que tous vos")]),
            (L.qualificationFin, "n’est pas confirmée par ce diplôme. Tu peux le remplacer ou demander une nouvelle vérification.",
             Self.page, 702, [("Tu peux", "Vous pouvez")]),
            (L.documentNonValideFin, ". Tu peux le remplacer ou demander une revue humaine.", Self.page, 761, [("Tu peux", "Vous pouvez")]),
            (L.descriptionQualification,
             "Tu es désormais médecin inscrit à l’Ordre ? Ajoute l’attestation précisant ta qualification. L’équipe vérifiera cette preuve pour mettre à jour ton parcours.",
             Self.page, 896, [("Tu es", "Vous êtes"), ("Ajoute l’attestation précisant ta", "Ajoutez l’attestation précisant votre"),
                              ("ton parcours", "votre parcours")]),
        ]
    }

    func testTextesRepristelsQuelsDuWeb() throws {
        for (natif, fichier, ligne) in verbatim {
            XCTAssertFalse(natif.isEmpty)
            XCTAssertTrue(try ligneWeb(fichier, ligne).contains(natif), "« \(natif) » absent de \(fichier):\(ligne)")
        }
    }

    func testTextesVouvoyesDontSeuleLaPersonneChange() throws {
        for (natif, web, fichier, ligne, conversions) in vouvoyes {
            XCTAssertTrue(try ligneWeb(fichier, ligne).contains(web), "source web changée : \(fichier):\(ligne) « \(web) »")
            var converti = web
            for (avant, apres) in conversions {
                XCTAssertTrue(converti.contains(avant), "conversion inutile « \(avant) » pour « \(web) »")
                converti = converti.replacingOccurrences(of: avant, with: apres)
            }
            XCTAssertEqual(natif, converti, "seule la personne change (\(fichier):\(ligne))")
        }
    }

    /// `TYPES_DOCUMENTS`, `STATUTS_VERIFICATION[*].label` (`src/lib/documents.ts`) et `PLACEHOLDERS_LIBELLE`
    /// (`ModalTeleversement.tsx`) : mêmes clés, mêmes textes, relus ligne à ligne.
    func testDictionnairesDuWebCleParCle() throws {
        func objet(_ fichier: String, debut: Int, fin: Int, motif: String) throws -> [String: String] {
            let expression = try NSRegularExpression(pattern: motif)
            var resultat: [String: String] = [:]
            for numero in debut...fin {
                let ligne = try ligneWeb(fichier, numero)
                let plage = NSRange(ligne.startIndex..., in: ligne)
                guard let m = expression.firstMatch(in: ligne, range: plage),
                      let cle = Range(m.range(at: 1), in: ligne), let valeur = Range(m.range(at: 2), in: ligne) else {
                    XCTFail("\(fichier):\(numero) illisible : \(ligne)")
                    continue
                }
                resultat[String(ligne[cle])] = String(ligne[valeur])
            }
            return resultat
        }
        let types = try objet("src/lib/documents.ts", debut: 5, fin: 22, motif: #"^\s*'([A-Z_]+)':\s*'(.*)',\s*$"#)
        XCTAssertEqual(L.typesDocuments, types)
        let statuts = try objet("src/lib/documents.ts", debut: 29, fin: 34, motif: #"^\s*'([A-Z_]+)':\s*\{\s*label:\s*'([^']*)'"#)
        XCTAssertEqual(L.statutsVerification, statuts)
        let exemples = try objet(Self.modale, debut: 12, fin: 25, motif: #"^\s*'([A-Z_]+)':\s*'(.*)',\s*$"#)
        XCTAssertEqual(L.placeholders, exemples)
        XCTAssertEqual(try lignes("src/lib/documents.ts")[22].trimmingCharacters(in: .whitespaces), "};", "objet complet")
        XCTAssertEqual(try lignes(Self.modale)[25].trimmingCharacters(in: .whitespaces), "};", "objet complet")
    }

    /// `TYPES_DOCUMENTS[t] || t` (l.566, l.575, l.605) ; `PLACEHOLDERS_LIBELLE[t] || 'Ex : Description du document'` (l.52).
    func testReplisDesDictionnairesCommeLeWeb() {
        XCTAssertEqual(L.libelleType("DIPLOME"), "Diplôme d'État")
        XCTAssertEqual(L.libelleType("CARTE_ORDRE"), "Attestation d’inscription à l’Ordre / carte professionnelle")
        XCTAssertEqual(L.libelleType("TYPE_INCONNU"), "TYPE_INCONNU")
        XCTAssertEqual(L.placeholder(typeDocument: "DIPLOME"), "Ex : Diplôme IDE 2020")
        XCTAssertEqual(L.placeholder(typeDocument: "ATTESTATION_SCOLARITE"), "Ex : Description du document")
    }

    /// Textes repris tels quels d'écrans natifs déjà livrés (aucun texte nouveau).
    func testTextesReprisDesLotsPrecedents() throws {
        XCTAssertEqual(L.espaceNonDisponible, MobileAccess.unsupportedRole(nil).message)
        // « Voir sur jolene.app » : libellé du renvoi web de l'Accueil au lot 1, retiré de l'Accueil à la fusion des lots 2
        // et 3 (centre de notifications natif, L3-T5) ; le même libellé reste celui d'un écran natif livré (lot 3, T9 :
        // renvoi web du type d'exercice de « Mon profil »), aucun texte nouveau.
        XCTAssertEqual(L.voirSurJoleneApp, ProfilEdition.Textes.voirSurLeWeb, "lot 3 : renvoi web de « Mon profil »")
        let profil = try lignes("ios-native/Jolene/Screens/Profil/ProfilEditionScreen.swift").joined(separator: "\n")
        XCTAssertTrue(profil.contains("JoleneButton(Textes.voirSurLeWeb"), "lot 3 : bouton du renvoi web de « Mon profil »")
        let missions = try lignes("ios-native/Jolene/Screens/MissionsListScreen.swift").joined(separator: "\n")
        XCTAssertTrue(missions.contains("title: \"\(L.sessionAVerifier)\""))
        XCTAssertTrue(missions.contains("actionTitle: \"\(L.verifierMaSession)\""))
        XCTAssertEqual(L.messageSessionExpiree, SessionController.sessionExpiredMessage)
    }

    /// Textes opérationnels sans équivalent web : inventoriés mot pour mot dans DECISIONS_LOT2.md (T7).
    func testTextesOperationnelsInventories() throws {
        let decisions = try lignes("docs/mobile-swift/DECISIONS_LOT2.md").joined(separator: "\n")
        XCTAssertTrue(decisions.contains("## Textes opérationnels hors web (T7)"))
        for texte in L.textesOperationnels {
            XCTAssertTrue(decisions.contains("« \(texte) »"), "texte non inventorié : \(texte)")
        }
        XCTAssertEqual(L.textesOperationnels.count, 5)
    }

    func testAucunTexteTutoyeNiVideNiGabarit() {
        let marques: Set<String> = ["tu", "te", "toi", "ton", "ta", "tes", "t"]
        let tous = verbatim.map(\.0) + vouvoyes.map(\.0) + L.textesOperationnels + Array(L.typesDocuments.values)
            + Array(L.statutsVerification.values) + Array(L.placeholders.values)
        for texte in tous {
            XCTAssertFalse(texte.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertEqual(texte, texte.trimmingCharacters(in: .whitespaces), "« \(texte) » : espace de bord")
            let mots = texte.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            XCTAssertFalse(mots.contains { marques.contains($0) }, "tutoiement dans « \(texte) »")
            for marqueur in ["{", "}", "${", "%@", "\\("] {
                XCTAssertFalse(texte.contains(marqueur), "« \(texte) » contient « \(marqueur) »")
            }
        }
    }

    /// Onglets de `MesDocuments.tsx` l.13-24 : valeur inconnue ou absente → Justificatifs.
    func testOngletDesDocumentsCommeLeWeb() {
        XCTAssertEqual(OngletDocuments(parametre: "contrats"), .contrats)
        XCTAssertEqual(OngletDocuments(parametre: "dpae"), .dpae)
        XCTAssertEqual(OngletDocuments(parametre: "justificatifs"), .justificatifs)
        XCTAssertEqual(OngletDocuments(parametre: nil), .justificatifs)
        XCTAssertEqual(OngletDocuments(parametre: "inconnu"), .justificatifs)
        XCTAssertEqual(OngletDocuments.allCases, [.justificatifs, .contrats, .dpae], "ordre des onglets du web (l.34-46)")
        XCTAssertEqual(OngletDocuments.allCases.map(\.libelle), ["Justificatifs", "Contrats", "DPAE"])
    }
}
