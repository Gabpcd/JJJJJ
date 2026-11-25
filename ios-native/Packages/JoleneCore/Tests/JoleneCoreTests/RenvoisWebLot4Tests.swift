import XCTest
@testable import JoleneCore

/// L4-T13 (intégration de la vague D, décision f) : contenu définitif des renvois web assumés du lot 4.
final class RenvoisWebLot4Tests: XCTestCase {
    func testDocumentsEtProtectionSeulementLaPrevoyance() {
        XCTAssertEqual(RenvoisWebLot4.titreDocumentsProtection, "Documents & protection")
        XCTAssertEqual(RenvoisWebLot4.entreesDocumentsProtection.map(\.libelle), ["Prévoyance"],
                       "« Passer en libéral » et « Attestation d'heures » dépendent d'une règle juridique jamais recalculée")
        XCTAssertEqual(RenvoisWebLot4.entreesDocumentsProtection.map(\.url.absoluteString), ["https://jolene.app/soignant/prevoyance"])
        XCTAssertEqual(RenvoisWebLot4.entreesDocumentsProtection.map(\.identifiant), ["hub-renvoi-prevoyance"])
    }

    func testLeRenvoiPrevoyanceResteUnRenvoiWebCanonique() throws {
        for entree in RenvoisWebLot4.entreesDocumentsProtection {
            let lien = try XCTUnwrap(DestinationLien(link: entree.url.absoluteString), entree.chemin)
            XCTAssertEqual(lien.destination.externalURL, entree.url, "page web, jamais un écran natif ni un jeton")
            XCTAssertNil(entree.url.query, "aucun paramètre transmis")
        }
    }

    func testTitresDesPagesWeb() {
        let attendus: [EcranSecondaire.Nom: String?] = [
            .swipe: "Trouver une mission", .recherches: "Mes recherches sauvegardées", .disponibilites: "Mes disponibilités",
            .litiges: "Litiges & contestations", .reclamations: "Litiges & contestations", .messagerie: "Messagerie",
            .bulletins: "Revenus", .evaluations: "Mes évaluations", .score: "Mon score", .poolUrgence: "Pool urgence",
            .exclusions: "Exclusions", .parrainage: nil, .serie: nil,
        ]
        XCTAssertEqual(Set(attendus.keys), Set(EcranSecondaire.Nom.allCases), "un titre (ou son absence) par écran")
        for nom in EcranSecondaire.Nom.allCases {
            XCTAssertEqual(RenvoisWebLot4.titreEcran(nom), attendus[nom] ?? nil, nom.rawValue)
        }
    }
}
