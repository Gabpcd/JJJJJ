import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/preferences-modes-exercice.json` : port de
/// `src/lib/preferencesModesExercice.ts` (CDD et vacation = exercice salarié).
final class RulesModesExerciceTests: XCTestCase {
    private func contrats(_ valeur: JSONValue?) throws -> [String] {
        try XCTUnwrap(valeur?.array).map { try XCTUnwrap($0.string) }
    }

    func testVecteursGoldenModesExercice() throws {
        let rejoues = try Golden.rejouer("preferences-modes-exercice") { vecteur in
            let entree = vecteur.input
            let liste = try contrats(entree["contrats"])
            let mode = try XCTUnwrap(PreferenceModeExercice(rawValue: try XCTUnwrap(entree["mode"]?.string)))
            switch vecteur.fonction {
            case "modeExerciceSelectionne":
                return .bool(ModesExercice.estSelectionne(liste, mode: mode))
            case "modifierPreferenceModeExercice":
                let choix = try XCTUnwrap(entree["selectionne"]?.bool)
                return .array(ModesExercice.modifier(liste, mode: mode, selectionne: choix).map(JSONValue.string))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 90)
    }

    func testCodesSalariesHistoriques() {
        XCTAssertEqual(ModesExercice.contratsSalaries, ["CDD", "VACATION", "SALARIE"])
        XCTAssertEqual(PreferenceModeExercice.allCases.map(\.rawValue), ["SALARIE", "LIBERAL"])
    }
}
