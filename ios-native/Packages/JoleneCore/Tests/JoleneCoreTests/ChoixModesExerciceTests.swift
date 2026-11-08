import XCTest
@testable import JoleneCore

/// Port de `ChoixModesExercice.tsx` (lot 3, T9) : modes affichés et messages selon la réponse de
/// `fn_types_exercice_autorises` (table paramétrée, aucune règle en dur), cas par cas du composant web.
final class ChoixModesExerciceTests: XCTestCase {
    private typealias Textes = ChoixModesExercice.Textes

    private func presenter(_ valeur: [String], _ types: [String]?, chargement: Bool = false,
                           indisponible: Bool = false) -> ChoixModesExercice {
        ChoixModesExercice.presenter(valeur: valeur, typesAutorises: types, chargement: chargement, indisponible: indisponible)
    }

    func testReferentielConnuAvecLesDeuxModes() {
        let choix = presenter(["CDD"], ["SALARIE", "LIBERAL", "MIXTE"])
        XCTAssertEqual(choix.options.map(\.mode), [.salarie, .liberal])
        XCTAssertEqual(choix.options.map(\.libelle), [Textes.libelleSalarie, Textes.libelleLiberal])
        XCTAssertEqual(choix.options.map(\.selectionne), [true, false])
        XCTAssertFalse(choix.liberalNonPropose)
        XCTAssertFalse(choix.anciennePreference)
        XCTAssertFalse(choix.aucunMode)
    }

    func testMixteSeulOuvreLesDeuxModes() {
        XCTAssertEqual(presenter([], ["MIXTE"]).options.map(\.mode), [.salarie, .liberal])
    }

    func testLiberalNonProposePourUneProfessionSalarieeSeulement() {
        let choix = presenter(["SALARIE"], ["SALARIE"])
        XCTAssertEqual(choix.options.map(\.mode), [.salarie])
        XCTAssertTrue(choix.liberalNonPropose)
        XCTAssertFalse(choix.anciennePreference)
    }

    func testAnciennePreferenceAfficheeEtConserveeTantQuElleEstCochee() {
        let choix = presenter(["CDD", "LIBERAL"], ["SALARIE"])
        XCTAssertEqual(choix.options.map(\.mode), [.salarie, .liberal], "le libéral coché reste visible pour être décoché")
        XCTAssertEqual(choix.options.map(\.autorise), [true, false])
        XCTAssertTrue(choix.anciennePreference)
    }

    func testReferentielInconnuSalarieToujoursProposeLiberalSeulementSIlEstDejaCoche() {
        // Chargement ou indisponibilité : `connus = false`, `salarieAutorise = true`, `liberalAutorise = false`.
        let indisponible = presenter(["CDD", "LIBERAL"], nil, indisponible: true)
        XCTAssertEqual(indisponible.options.map(\.mode), [.salarie, .liberal])
        XCTAssertTrue(indisponible.indisponible)
        XCTAssertFalse(indisponible.liberalNonPropose, "aucun verdict sans référentiel")
        XCTAssertFalse(indisponible.anciennePreference)
        let chargement = presenter(["CDD"], nil, chargement: true)
        XCTAssertEqual(chargement.options.map(\.mode), [.salarie], "l'ajout du libéral attend la vérification")
        XCTAssertTrue(chargement.chargement)
    }

    func testAucunModeSelectionne() {
        XCTAssertTrue(presenter([], ["SALARIE"]).aucunMode)
    }

    func testBasculerSuitLaRegleGoldenEtNeVideJamaisLaListe() {
        XCTAssertEqual(ChoixModesExercice.basculer(["CDD", "LIBERAL"], mode: .liberal, selectionne: false), ["CDD"])
        XCTAssertEqual(ChoixModesExercice.basculer(["CDD"], mode: .liberal, selectionne: true), ["CDD", "LIBERAL"])
        XCTAssertEqual(ChoixModesExercice.basculer(["CDD", "VACATION", "LIBERAL"], mode: .salarie, selectionne: false), ["LIBERAL"])
        // `if (valeur.length) setTypesContrat(valeur)` : décocher le dernier mode ne change rien.
        XCTAssertEqual(ChoixModesExercice.basculer(["CDD"], mode: .salarie, selectionne: false), ["CDD"])
        XCTAssertEqual(ChoixModesExercice.basculer(["LIBERAL"], mode: .liberal, selectionne: false), ["LIBERAL"])
    }
}
