import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/selection-serie-candidat.json`
/// (port de `src/components/planning/selection-serie-candidat.ts`).
final class RulesSelectionSerieTests: XCTestCase {
    /// Mission ouverte d'une série telle que décrite par un vecteur.
    private struct MissionSerieGolden: MissionSerieCandidat, Equatable {
        let id: String
        let planningCandidat: PlanningCandidatInput
    }

    private func missions(_ valeur: JSONValue?) throws -> [MissionSerieGolden] {
        try (valeur?.array ?? []).map { mission in
            MissionSerieGolden(id: try XCTUnwrap(mission["id"]?.string, "mission sans id"),
                               planningCandidat: try RulesPlanningCandidatTests.mission(mission))
        }
    }

    private func ids(_ valeur: JSONValue?) -> Set<String> {
        Set((valeur?.array ?? []).compactMap(\.string))
    }

    private func golden<T>(_ analyse: AnalyseSelectionSerie<T>) -> JSONValue {
        .object([
            "missionsSelectionnees": .array(analyse.missionsSelectionnees.map { .string($0.id) }),
            "idsEnConflit": .array(analyse.idsEnConflit.map(JSONValue.string)),
            "idsPlanningInexact": .array(analyse.idsPlanningInexact.map(JSONValue.string)),
            "peutAccepter": .bool(analyse.peutAccepter),
        ])
    }

    func testVecteursGoldenSelectionSerie() throws {
        let rejoues = try Golden.rejouer("selection-serie-candidat") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "analyserSelectionSerie":
                return golden(SelectionSerieCandidat.analyser(
                    try missions(entree["missionsOuvertes"]),
                    idsSelectionnes: ids(entree["idsSelectionnes"]),
                    idsConflit: ids(entree["idsConflit"])
                ))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testAucuneMissionConflictuelleNEstRetireeSilencieusement() {
        typealias S = MissionsTestSupport
        let serie = (1...3).map { index in
            S.mission(S.record(id: "m\(index)"), slots: [S.slot(id: "c\(index)", missionId: "m\(index)")])
        }
        let analyse = SelectionSerieCandidat.analyser(serie, idsSelectionnes: ["m1", "m2", "m3"], idsConflit: ["m3"])
        XCTAssertEqual(analyse.missionsSelectionnees, serie, "les missions sélectionnées sont rendues telles quelles")
        XCTAssertEqual(analyse.idsEnConflit, ["m3"])
        XCTAssertFalse(analyse.peutAccepter)

        let sansConflit = SelectionSerieCandidat.analyser(serie, idsSelectionnes: ["m1", "m2"], idsConflit: ["m3"])
        XCTAssertEqual(sansConflit.missionsSelectionnees.map(\.id), ["m1", "m2"])
        XCTAssertTrue(sansConflit.peutAccepter, "le sous-ensemble vu, décoché du conflit, est acceptable")
    }

    func testPlanningInexactOuEnErreurBloqueLAcceptation() {
        typealias S = MissionsTestSupport
        let exacte = S.mission(S.record(id: "m1"), slots: [S.slot(id: "c1", missionId: "m1")])
        var enErreur = S.mission(S.record(id: "m2"), slots: [S.slot(id: "c2", missionId: "m2")])
        enErreur.erreurPlanning = true
        let incomplete = S.mission(S.record(id: "m3", nbCreneaux: 2), slots: [S.slot(id: "c3", missionId: "m3")])
        let analyse = SelectionSerieCandidat.analyser([exacte, enErreur, incomplete], idsSelectionnes: ["m1", "m2", "m3"], idsConflit: [])
        XCTAssertEqual(analyse.idsPlanningInexact, ["m2", "m3"])
        XCTAssertFalse(analyse.peutAccepter)
        XCTAssertFalse(SelectionSerieCandidat.analyser([exacte], idsSelectionnes: [], idsConflit: []).peutAccepter,
                       "une sélection vide n'est jamais acceptable")
    }
}
