import XCTest
@testable import JoleneCore

/// Textes de la tranche T5a hors `LibellesWeb` (`Libelles/LibellesDetailPresences.swift`) : textes que le web tutoie,
/// vouvoyés (seule la personne change, décision 9 du lot 1) et textes opérationnels inventoriés dans
/// `DECISIONS_LOT2.md` (« Textes opérationnels hors web (T5a) »). Ce test relit les sources web : il rougit si un texte
/// tutoyé change d'un côté sans l'autre. Les fragments verbatim (`LibellesWeb.DetailPresences`, `.Notation`,
/// `.AllerPointer`, `.OubliDepart`, `.DetailMission`) sont gardés au caractère près par la garde Node.
final class LibellesDetailPresencesTests: XCTestCase {
    private var racine: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JoleneCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // JoleneCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios-native
            .deletingLastPathComponent() // racine du dépôt
    }

    private func source(_ relatif: String) throws -> String {
        try String(contentsOf: racine.appendingPathComponent(relatif), encoding: .utf8)
    }

    func testTextesVouvoyesDontSeuleLaPersonneChange() throws {
        let pointage = try source("src/components/pointage/PointageRotatifSoignant.tsx")
        let notation = try source("src/components/NotationRapide.tsx")
        let vouvoyes: [(natif: String, web: String, fichier: String)] = [
            (LibellesDetailPresences.Notation.description,
             "Un tap suffit — ta note aide les autres soignants à choisir leurs missions.", pointage),
            (LibellesDetailPresences.Notation.remerciement, "Merci pour ta note ⭐", notation),
        ]
        for (natif, web, fichier) in vouvoyes {
            XCTAssertTrue(fichier.contains(web), "source web changée : \(web)")
            XCTAssertEqual(natif, web.replacingOccurrences(of: "ta note", with: "votre note"), "seule la personne change")
        }
    }

    func testTextesOperationnelsInventories() throws {
        // Échec d'envoi hors refus serveur : la première phrase du web (l.55), sans la promesse d'une notation depuis la
        // mission (aucun chemin dans l'application), suivie du repli des écrans natifs.
        let notation = try source("src/components/NotationRapide.tsx")
        // Apostrophe échappée dans le littéral JavaScript (`'La note n\'a pas…'`).
        XCTAssertTrue(notation.contains("La note n\\'a pas pu être enregistrée — tu pourras noter depuis la mission."), "source web changée")
        XCTAssertEqual(LibellesDetailPresences.Notation.erreurEnregistrement, "La note n'a pas pu être enregistrée. Réessayez.")
        XCTAssertEqual(LibellesDetailPresences.voirSurLeWeb, "Voir sur jolene.app", "libellé du lot 1 (AccueilScreen)")
        // Échec de lecture du détail (revue fraîche de T5a, m11) : titres du lot 1 repris, repli lisible quand le port
        // ne porte aucun message (jamais un message vide).
        typealias Echec = LibellesDetailPresences.Echec
        XCTAssertEqual(Echec.sessionAVerifier, "Session à vérifier", "texte du lot 1 (MissionsListScreen)")
        XCTAssertEqual(Echec.verifierMaSession, "Vérifier ma session", "texte du lot 1 (MissionsListScreen)")
        XCTAssertEqual(Echec.chargementImpossible,
                       "Le détail de vos présences n'a pas pu être chargé. Vérifiez votre connexion puis réessayez.")
        XCTAssertEqual(Echec.message(nil, sessionExpiree: false), Echec.chargementImpossible)
        XCTAssertEqual(Echec.message("", sessionExpiree: false), Echec.chargementImpossible, "message vide : repli")
        XCTAssertEqual(Echec.message("  ", sessionExpiree: true), SessionController.sessionExpiredMessage)
        XCTAssertEqual(Echec.message(nil, sessionExpiree: true), "Votre session a expiré. Reconnectez-vous.")
        XCTAssertEqual(Echec.message("Le service ne répond pas.", sessionExpiree: false), "Le service ne répond pas.",
                       "message du port tel quel")
    }

    func testAucunTexteTutoyeVideNiJuridique() {
        let tous = [LibellesDetailPresences.Notation.description, LibellesDetailPresences.Notation.remerciement,
                    LibellesDetailPresences.Notation.erreurEnregistrement, LibellesDetailPresences.voirSurLeWeb,
                    LibellesDetailPresences.Echec.sessionAVerifier, LibellesDetailPresences.Echec.verifierMaSession,
                    LibellesDetailPresences.Echec.chargementImpossible]
            + LibellesDetailPresences.Notation.criteres
        let tutoiement: Set<String> = ["tu", "te", "toi", "ton", "ta", "tes", "t"]
        for texte in tous {
            XCTAssertFalse(texte.trimmingCharacters(in: .whitespaces).isEmpty)
            let mots = texte.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            XCTAssertFalse(mots.contains { tutoiement.contains($0) }, "tutoiement dans « \(texte) »")
            for marque in ["consentement", "RGPD", "72", "Code ", "contester", "litige"] {
                XCTAssertFalse(texte.contains(marque), "« \(texte) » : marque « \(marque) » hors TextesWeb")
            }
        }
    }

    func testFragmentsVerbatimAuCatalogue() {
        let cles = Set(LibellesWeb.catalogue.map(\.cle))
        for cle in ["DetailPresences.syntheseTitre", "DetailPresences.controlesTitre", "DetailPresences.recapitulatifFinancier",
                    "Notation.titre", "Notation.envoyer", "Notation.plusTard", "AllerPointer.allerPointer",
                    "OubliDepart.pointerMonDepart", "DetailMission.presencesEtPointage", "DetailMission.heuresPointees"] {
            XCTAssertTrue(cles.contains(cle), "\(cle) absent du catalogue")
        }
        XCTAssertEqual(LibellesWeb.DetailPresences.introuvableMessage, "Cette mission n’existe pas ou n’est plus accessible.",
                       "apostrophe ’ du web")
        XCTAssertEqual(LibellesWeb.OubliDepart.pointerMonDepart, "Pointer mon départ maintenant")
    }
}
