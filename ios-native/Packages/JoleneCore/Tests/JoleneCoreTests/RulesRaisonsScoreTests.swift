import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/raisons-score-matching.json` (port de `src/lib/raisons-score-matching.ts`, L4-T2). Le
/// breakdown des vecteurs est une liste de paires ordonnées : l'ordre départage les égalités.
final class RulesRaisonsScoreTests: XCTestCase {
    func testVecteursGoldenRaisonsScore() throws {
        var parFonction: [String: Int] = [:]
        let rejoues = try Golden.rejouer("raisons-score-matching") { vecteur in
            let entree = vecteur.input
            parFonction[vecteur.fonction, default: 0] += 1
            switch vecteur.fonction {
            case "RAISON_LABELS":
                return .object(RaisonsScore.libelles.mapValues(JSONValue.string))
            case "RAISONS_EPINGLEES":
                return .array(RaisonsScore.epinglees.map(JSONValue.string))
            case "raisonsScore":
                if let entrees = entree["entrees"]?.array {
                    let paires = try entrees.map { paire -> (cle: String, valeur: ValeurJSON) in
                        let elements = try XCTUnwrap(paire.array, "paire attendue dans « \(vecteur.name) »")
                        return (try XCTUnwrap(elements.first?.string), try elements[1].decode(ValeurJSON.self))
                    }
                    return .string(RaisonsScore.raisons(paires))
                }
                if entree["absent"]?.bool == true { return .string(RaisonsScore.raisons(json: nil)) }
                return .string(RaisonsScore.raisons(json: try XCTUnwrap(entree["breakdown"]).decode(ValeurJSON.self)))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 400)
        for fonction in ["RAISON_LABELS", "RAISONS_EPINGLEES", "raisonsScore"] {
            XCTAssertGreaterThan(parFonction[fonction] ?? 0, 0, "aucun vecteur golden pour \(fonction)")
        }
    }

    /// `CarteSwipe.breakdown` perd l'ordre : il est relu dans l'ordre `jsonb` du serveur (longueur, puis octets).
    func testBreakdownSansOrdreReluDansOrdreJsonb() {
        XCTAssertEqual(RaisonsScore.ordreJsonb(["distance", "tarif", "horaire", "urgence", "etablissement"]),
                       ["tarif", "horaire", "urgence", "distance", "etablissement"])
        // « é » compte deux octets : « éa » (3 octets) passe après « abc » (3 octets, 0x61 < 0xC3).
        XCTAssertEqual(RaisonsScore.ordreJsonb(["éa", "abc", "ab"]), ["ab", "abc", "éa"])
        // Égalité tarif/horaire/distance : ordre jsonb tarif (5), horaire (7), distance (8).
        XCTAssertEqual(RaisonsScore.raisons(breakdownJsonb: ["distance": 10, "tarif": 10, "horaire": 10]),
                       "bien payée vs le marché · à tes horaires préférés")
        XCTAssertEqual(RaisonsScore.raisons(json: .objet(["distance": .nombre(10), "tarif": .nombre(10), "horaire": .nombre(10)])),
                       "bien payée vs le marché · à tes horaires préférés")
        XCTAssertEqual(RaisonsScore.raisons(breakdownJsonb: ["paiement_rapide": 1, "distance": 30]),
                       "paiement rapide ⚡ · proche de chez toi")
        XCTAssertEqual(RaisonsScore.raisons(breakdownJsonb: [:]), "")
    }

    /// Écart assumé (W0) : une clé de la chaîne de prototype n'est jamais une raison côté Swift.
    func testClesDePrototypeIgnorees() {
        XCTAssertEqual(RaisonsScore.raisons([(cle: "constructor", valeur: .nombre(99)), (cle: "toString", valeur: .nombre(50)),
                                             (cle: "__proto__", valeur: .nombre(40)), (cle: "horaire", valeur: .nombre(1))]),
                       "à tes horaires préférés")
    }
}
