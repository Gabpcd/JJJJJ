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

    func testTexteEntierEcritLesChiffresLesPlusCourtsCommeStringDeJavaScript() {
        // `String(n)` (Number::toString) : chiffres les plus courts qui relisent le même Double,
        // complétés de zéros ; sous 2^53, ce sont tous les chiffres. Attendus produits par Node 24.
        let attendus: [(Double, String)] = [
            (0, "0"), (-0.0, "0"), (1, "1"), (42, "42"), (0x1p53, "9007199254740992"), (0x1p53 + 2, "9007199254740994"),
            (1e15, "1000000000000000"), (1e16, "10000000000000000"), (1e17, "100000000000000000"),
            (0x1p60, "1152921504606847000"), (0x1p63, "9223372036854776000"), (0x1p69, "590295810358705700000"),
            (1e20, "100000000000000000000"), (1.23456789012345678901e20, "123456789012345680000"),
            (4.35e20, "435000000000000000000"),
        ]
        for (valeur, texte) in attendus {
            XCTAssertEqual(PrimitivesJS.texteEntier(valeur), texte, "String(\(valeur))")
        }
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
