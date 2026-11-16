import XCTest
@testable import JoleneCore

/// Messages des justificatifs (lot 2 T6) : textes du web repris tels quels, ou vouvoyés quand le web tutoie (décision 9
/// du lot 1, même règle que la décision 6 du lot 2 : seule la personne du verbe change). Ce test relit la source web : il
/// rougit si un texte change d'un côté sans l'autre. Aucun texte juridique (garde `check-textes-juridiques-ios`).
final class MessagesDocumentsTests: XCTestCase {
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

    /// Le web écrit `n\'a` dans ses littéraux entre apostrophes droites.
    private func litteralWeb(_ texte: String) -> String { texte.replacingOccurrences(of: "'", with: "\\'") }

    func testTextesRepristelsQuelsDuWeb() throws {
        let page = try source("src/pages/DocumentsSoignant.tsx")
        let verbatim = [
            MessagesDocuments.chargementImpossible, MessagesDocuments.revueMotifInvalide, MessagesDocuments.motifRevue,
            MessagesDocuments.reverificationErreur, MessagesDocuments.signatureAttestationErreur,
            MessagesDocuments.consultationImpossible,
        ]
        for texte in verbatim {
            XCTAssertTrue(page.contains("'\(litteralWeb(texte))'"), "absent de DocumentsSoignant.tsx : \(texte)")
        }
        let erreurs = try source("src/lib/erreurs.ts")
        XCTAssertTrue(erreurs.contains("fallback = '\(MessagesDocuments.erreurGenerique)'"), "repli de messageErreurEdgeFn")
    }

    func testTextesVouvoyesDontSeuleLaPersonneDuVerbeChange() throws {
        let page = try source("src/pages/DocumentsSoignant.tsx")
        let vouvoyes: [(natif: String, web: String)] = [
            (MessagesDocuments.revueDocumentIntrouvable,
             "Ce document a été remplacé ou supprimé. Actualise la page puis réessaie avec le document actif."),
            (MessagesDocuments.enregistrementImpossible, "Le document ne peut pas être enregistré. Vérifie son format puis réessaie."),
            (MessagesDocuments.verificationImpossible,
             "Le document n'a pas pu être vérifié. Vérifie le type de document et sa lisibilité."),
        ]
        let conjugaisons = [("Actualise ", "Actualisez "), ("réessaie", "réessayez"), ("Vérifie ", "Vérifiez ")]
        for (natif, web) in vouvoyes {
            XCTAssertTrue(page.contains("'\(litteralWeb(web))'"), "source web changée : \(web)")
            let converti = conjugaisons.reduce(web) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
            XCTAssertEqual(natif, converti, "seule la personne du verbe change")
        }
    }

    func testAucunMessageVideNiTutoye() {
        let tous = [MessagesDocuments.chargementImpossible, MessagesDocuments.enregistrementImpossible,
                    MessagesDocuments.verificationImpossible, MessagesDocuments.reverificationErreur,
                    MessagesDocuments.revueDocumentIntrouvable, MessagesDocuments.revueMotifInvalide,
                    MessagesDocuments.signatureAttestationErreur, MessagesDocuments.consultationImpossible,
                    MessagesDocuments.erreurGenerique]
        for texte in tous {
            XCTAssertFalse(texte.trimmingCharacters(in: .whitespaces).isEmpty)
            for marque in [" tu ", " ton ", " ta ", " tes ", "Actualise ", "réessaie ", "Vérifie "] {
                XCTAssertFalse(texte.contains(marque), "tutoiement dans « \(texte) »")
            }
        }
    }
}
