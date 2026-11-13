import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/professions-rpps.json` : vecteur de dérive des listes
/// `PROFESSIONS_SANS_RPPS` et `PROFESSIONS_RPPS_REQUIS` (`src/lib/constantes.ts` l.55, l.61 ;
/// correction 20 et décision 11 du lot 3). Ce n'est pas une règle juridique : seulement la même
/// liste que le web et `register-soignant`.
final class RulesProfessionsRppsTests: XCTestCase {
    func testVecteursGoldenProfessionsRpps() throws {
        let rejoues = try Golden.rejouer("professions-rpps") { vecteur in
            switch vecteur.fonction {
            case "PROFESSIONS_SANS_RPPS":
                return .array(ProfessionsRpps.sansRpps.map(JSONValue.string))
            case "PROFESSIONS_RPPS_REQUIS":
                return .array(ProfessionsRpps.rppsRequis.map(JSONValue.string))
            case "classer":
                let profession = try XCTUnwrap(vecteur.input["profession"]?.string)
                return .object([
                    "sansRpps": .bool(ProfessionsRpps.estSansRpps(profession)),
                    "rppsRequis": .bool(ProfessionsRpps.exigeRpps(profession)),
                ])
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 20)
    }

    func testToutesLesProfessionsDuWebSontClassees() throws {
        // Les 17 professions de `PROFESSIONS` (constantes.ts, même ordre que `MissionPresentation.professions`).
        let classees = try Golden.charger("professions-rpps").filter { $0.fonction == "classer" }.compactMap { $0.input["profession"]?.string }
        XCTAssertTrue(Set(classees).isSuperset(of: MissionPresentation.professions.map(\.valeur)))
        XCTAssertTrue(Set(ProfessionsRpps.sansRpps).isDisjoint(with: ProfessionsRpps.rppsRequis))
    }
}
