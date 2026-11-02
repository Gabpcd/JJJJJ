import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/documents.json` (port de `rppsDispenseDiplome` et
/// `diplomeCompatibleProfession`, `src/lib/documents.ts`). Le filtre des exigences par
/// profession et `type_exercice` (`documents-requis.ts`) arrive avec T2b, après la PR web W1.
final class RulesExigencesDocumentsTests: XCTestCase {
    func testVecteursGoldenDocuments() throws {
        let rejoues = try Golden.rejouer("documents") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "PROFESSIONS_SANS_RPPS":
                return .array(ExigencesDocuments.professionsSansRpps.map(JSONValue.string))
            case "rppsDispenseDiplome":
                // `rpps_verifie === true` : null et absent valent « non vérifié ».
                return .bool(ExigencesDocuments.rppsDispenseDiplome(profession: entree["profession"]?.string,
                                                                    rppsVerifie: entree["rppsVerifie"]?.bool))
            case "diplomeCompatibleProfession":
                // `typeof professionCertifiee === 'string'` : toute autre valeur JSON est absente pour le natif.
                return .bool(ExigencesDocuments.diplomeCompatibleProfession(profession: entree["profession"]?.string,
                                                                            professionCertifiee: entree["professionCertifiee"]?.string))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testSpecialitesExigentLeDiplomeExact() {
        for profession in ["IADE", "IBODE"] {
            XCTAssertFalse(ExigencesDocuments.rppsDispenseDiplome(profession: profession, rppsVerifie: true))
            XCTAssertFalse(ExigencesDocuments.diplomeCompatibleProfession(profession: profession, professionCertifiee: "IDE"))
            XCTAssertFalse(ExigencesDocuments.diplomeCompatibleProfession(profession: profession, professionCertifiee: nil))
            XCTAssertTrue(ExigencesDocuments.diplomeCompatibleProfession(profession: profession, professionCertifiee: profession.lowercased()))
        }
        XCTAssertTrue(ExigencesDocuments.rppsDispenseDiplome(profession: "IDE", rppsVerifie: true))
        XCTAssertFalse(ExigencesDocuments.rppsDispenseDiplome(profession: "AS", rppsVerifie: true), "AS sans RPPS")
        XCTAssertFalse(ExigencesDocuments.rppsDispenseDiplome(profession: "IDE", rppsVerifie: nil))
    }
}
