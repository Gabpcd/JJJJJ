import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/alertes-recherche-missions.json` (port de `src/lib/alertes-recherche-missions.ts`, L4-T2).
/// Les textes obtenus sont aussi comparés unité UTF-16 par unité : l'égalité de `JSONValue` (`String` Swift) est
/// canonique et confondrait une forme décomposée avec la forme composée.
final class RulesAlerteRechercheTests: XCTestCase {
    static func criteres(_ valeur: JSONValue?) throws -> FiltresAlerte {
        let c = try XCTUnwrap(valeur, "critères absents du vecteur")
        return FiltresAlerte(
            profession: try XCTUnwrap(c["profession"]?.string), rayonKm: try XCTUnwrap(c["rayonKm"]?.int),
            tauxMin: try XCTUnwrap(c["tauxMin"]?.double), typeContrat: try XCTUnwrap(c["typeContrat"]?.string),
            urgentesOnly: try XCTUnwrap(c["urgentesOnly"]?.bool), horaire: try XCTUnwrap(c["horaire"]?.string),
            villeRecherche: try XCTUnwrap(c["villeRecherche"]?.string))
    }

    static func golden(_ filtres: FiltresAlerte) throws -> JSONValue {
        try JSONValue.depuis(AlerteRecherche.valeur(filtres))
    }

    private func memesUnites(_ obtenu: String, _ attendu: JSONValue?, _ vecteur: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let attendu = attendu?.string else { return }
        XCTAssertEqual(Array(obtenu.utf16), Array(attendu.utf16), "vecteur « \(vecteur) » : unités UTF-16 différentes", file: file, line: line)
    }

    func testVecteursGoldenAlertesRecherche() throws {
        var parFonction: [String: Int] = [:]
        let rejoues = try Golden.rejouer("alertes-recherche-missions") { vecteur in
            let entree = vecteur.input
            parFonction[vecteur.fonction, default: 0] += 1
            switch vecteur.fonction {
            case "preparerAlerteMissions":
                let recherches = try XCTUnwrap(entree["recherches"]?.array).map { r in
                    FiltreSauvegarde(id: try XCTUnwrap(r["id"]?.string), nom: try XCTUnwrap(r["nom"]?.string),
                                     filtres: try (r["filtres"] ?? .null).decode(ValeurJSON.self),
                                     alerteActive: r["alerte_active"]?.bool ?? false, frequence: nil)
                }
                let preparation = AlerteRecherche.preparer(criteres: try Self.criteres(entree["criteres"]), recherches: recherches,
                                                           nomBase: try XCTUnwrap(entree["nomBase"]?.string))
                memesUnites(preparation.nom, vecteur.expected["nom"], vecteur.name)
                return .object(["dejaId": .chaine(preparation.deja?.id), "nom": .string(preparation.nom),
                                "filtres": try Self.golden(preparation.filtres)])
            case "cleComparaison":
                let cle = AlerteRecherche.cle(try XCTUnwrap(entree["valeur"]).decode(ValeurJSON.self))
                memesUnites(cle, vecteur.expected, vecteur.name)
                return .string(cle)
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 100)
        for fonction in ["preparerAlerteMissions", "cleComparaison"] {
            XCTAssertGreaterThan(parFonction[fonction] ?? 0, 0, "aucun vecteur golden pour \(fonction)")
        }
    }

    /// Risque §5 du blueprint : `50` et `50.0` sont le même nombre, jamais deux recherches distinctes.
    func testEntierEtDecimalIdentiquesDansLaCle() {
        XCTAssertEqual(AlerteRecherche.cle(.objet(["rayonKm": .nombre(50.0)])), #"{"rayonKm":50}"#)
        let criteres = FiltresAlerte(profession: "", rayonKm: 50, tauxMin: 0, typeContrat: "TOUS", urgentesOnly: false,
                                     horaire: "TOUS", villeRecherche: "")
        let stockee = FiltreSauvegarde(id: "r", nom: "Alerte", filtres: AlerteRecherche.valeur(criteres), alerteActive: false, frequence: nil)
        XCTAssertEqual(AlerteRecherche.preparer(criteres: criteres, recherches: [stockee], nomBase: "Alerte").deja?.id, "r")
    }

    /// Troncature hors domaine golden : le web couperait la paire de substitution, Swift s'arrête avant elle.
    func testTroncatureNeCoupeJamaisUnePaireDeSubstitution() {
        let nom = String(repeating: "a", count: 89) + "😀"
        XCTAssertEqual(AlerteRecherche.tronquer(nom, 90), String(repeating: "a", count: 89))
        XCTAssertEqual(AlerteRecherche.tronquer("court", 90), "court")
    }

    /// `Object.entries` d'un non-objet : index des éléments, ou des unités UTF-16 d'un texte (demi-paires échappées).
    func testCleDUnNonObjet() {
        XCTAssertEqual(AlerteRecherche.cle(.tableau([.nombre(1), .nombre(2)])), #"{"0":1,"1":2}"#)
        XCTAssertEqual(AlerteRecherche.cle(.chaine("é😀")), #"{"0":"é","1":"\ud83d","2":"\ude00"}"#)
        XCTAssertEqual(AlerteRecherche.cle(.nombre(25)), "{}")
        XCTAssertEqual(AlerteRecherche.cle(.null), "{}")
    }
}
