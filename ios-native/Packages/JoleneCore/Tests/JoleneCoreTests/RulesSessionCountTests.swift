import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/session-count.json` : port de `src/lib/session-count.ts`
/// (`lireCompteur`, `incrementerSession`, `estSessionRecurrente`), qui séquence le pré-prompt push
/// à partir de la 2e session (`DemandePermissionPush.tsx`, décision 1 du lot 3).
final class RulesSessionCountTests: XCTestCase {
    func testVecteursGoldenSessionCount() throws {
        let rejoues = try Golden.rejouer("session-count") { vecteur in
            let brut = vecteur.input["compteur"]?.string
            switch vecteur.fonction {
            case "estSessionRecurrente":
                let compteur = CompteurSessions(compteurBrut: brut)
                return .object(["numero": .number(compteur.numero), "recurrente": .bool(compteur.estRecurrente)])
            case "incrementerSession":
                var compteur = CompteurSessions(compteurBrut: brut,
                                                dejaCompteeCetteSession: try XCTUnwrap(vecteur.input["dejaCompteeCetteSession"]?.bool))
                var retours: [JSONValue] = []
                for _ in 0..<(try XCTUnwrap(vecteur.input["appels"]?.int)) {
                    retours.append(.number(compteur.incrementer()))
                }
                return .object([
                    "retours": .array(retours),
                    "compteurApres": .chaine(compteur.compteurBrut),
                    "recurrenteApres": .bool(compteur.estRecurrente),
                ])
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 50)
    }

    func testSeuilDeLaDeuxiemeSession() {
        XCTAssertEqual(PushPolicy.seuilSessionRecurrente, 2)
        XCTAssertFalse(PushPolicy.estSessionRecurrente(numero: 1))
        XCTAssertTrue(PushPolicy.estSessionRecurrente(numero: 2))
    }

    func testUnLancementNeCompteQuUneFois() {
        var premier = CompteurSessions(compteurBrut: nil)
        XCTAssertEqual(premier.incrementer(), 1)
        XCTAssertEqual(premier.incrementer(), 1, "drapeau de chargement : pas de double comptage")
        XCTAssertEqual(premier.compteurBrut, "1")
        XCTAssertFalse(premier.estRecurrente)

        // Lancement suivant : nouvelle instance, même valeur persistée.
        var second = CompteurSessions(compteurBrut: premier.compteurBrut)
        XCTAssertEqual(second.incrementer(), 2)
        XCTAssertEqual(second.compteurBrut, "2")
        XCTAssertTrue(second.estRecurrente)
    }
}
