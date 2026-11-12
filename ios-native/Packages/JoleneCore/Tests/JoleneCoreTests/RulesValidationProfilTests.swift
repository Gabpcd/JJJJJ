import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/valider-profil-soignant.json` : port de
/// `src/lib/valider-profil-soignant.ts` (garde de la réponse de `fn_mon_profil_soignant_complet`).
final class RulesValidationProfilTests: XCTestCase {
    func testVecteursGoldenValidationProfil() throws {
        let rejoues = try Golden.rejouer("valider-profil-soignant") { vecteur in
            guard vecteur.fonction == "validerProfilSoignant" else { return nil }
            let donnees = try (vecteur.input["data"] ?? .null).decode(ValeurJSON.self)
            let userId = try XCTUnwrap(vecteur.input["userId"]?.string)
            do {
                let specialites = try ValidationProfil.valider(donnees, userId: userId)
                return .object(["specialites": .array(specialites.map(JSONValue.string))])
            } catch ValidationProfil.Erreur.profilInvalide {
                return .object(["erreur": .string("PROFIL_INVALIDE")])
            }
        }
        XCTAssertGreaterThan(rejoues, 250)
    }

    private let base: [String: ValeurJSON] = ["id": .chaine("a"), "prenom": .null, "nom": .null, "email": .null, "profession": .null]

    func testNombreNonFiniRefuse() {
        // Cas vitest `{ adresse_lat: Infinity }` : non représentable en JSON, rejoué ici.
        var ligne = base
        ligne["adresse_lat"] = .nombre(.infinity)
        XCTAssertThrowsError(try ValidationProfil.valider(.objet(ligne), userId: "a")) { erreur in
            XCTAssertEqual(erreur as? ValidationProfil.Erreur, .profilInvalide)
        }
        ligne["adresse_lat"] = .nombre(.nan)
        XCTAssertThrowsError(try ValidationProfil.valider(.objet(ligne), userId: "a"))
    }

    func testSpecialitesJSONStrictes() throws {
        XCTAssertEqual(try ValidationProfil.specialitesDepuisJSON(#" ["Urgences", "Blocé"] "#), ["Urgences", "Blocé"])
        XCTAssertEqual(try ValidationProfil.specialitesDepuisJSON(#"["😀"]"#), ["😀"])
        for texte in [#"["a",]"#, "[", #"["\ud83d"]"#, "\u{FEFF}[]", #"["a"] x"#, "null", "[1]"] {
            XCTAssertThrowsError(try ValidationProfil.specialitesDepuisJSON(texte), texte)
        }
    }
}
