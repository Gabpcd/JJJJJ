import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/selection-serie-candidat.json`
/// (port de `src/components/planning/selection-serie-candidat.ts`).
final class RulesSelectionSerieTests: XCTestCase {
    typealias S = MissionsTestSupport

    private func missions(_ valeur: JSONValue?) throws -> [MissionSerieCandidat] {
        try (valeur?.array ?? []).map { element in
            MissionSerieCandidat(
                id: try XCTUnwrap(element["id"]?.string),
                planning: try RulesPlanningCandidatTests.mission(element)
            )
        }
    }

    private func ids(_ valeur: JSONValue?) -> Set<String> {
        Set((valeur?.array ?? []).compactMap(\.string))
    }

    private func golden<T: MissionSerieCandidatRepresentable>(_ analyse: AnalyseSelectionSerie<T>) -> JSONValue {
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
                    try missions(entree["missions"]),
                    idsSelectionnes: ids(entree["idsSelectionnes"]),
                    idsConflit: ids(entree["idsConflit"])
                ))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    // MARK: - Cas vitest reproduits sur le type enrichi

    private func serie(_ n: Int) -> [Mission] {
        (1...n).map { index in
            let jour = "2026-08-0\(index)"
            let record = S.record(id: "\(index)", finLe: "\(jour)T16:00:00+02:00", nbCreneaux: 1)
            let slot = S.slot(id: "c-\(index)", debut: "\(jour)T08:00:00+02:00", fin: "\(jour)T16:00:00+02:00", missionId: "\(index)")
            return S.mission(record, slots: [slot])
        }
    }

    func testNeRetireJamaisSilencieusementUneMissionConflictuelle() {
        let missions = serie(7)
        let analyse = SelectionSerieCandidat.analyser(missions, idsSelectionnes: Set(missions.map(\.id)), idsConflit: ["7"])
        XCTAssertEqual(analyse.missionsSelectionnees.count, 7)
        XCTAssertEqual(analyse.idsEnConflit, ["7"])
        XCTAssertEqual(analyse.idsPlanningInexact, [])
        XCTAssertFalse(analyse.peutAccepter)
    }

    func testAutoriseLeSousEnsembleApresDecochage() {
        let missions = serie(7)
        let analyse = SelectionSerieCandidat.analyser(missions, idsSelectionnes: Set(missions.prefix(6).map(\.id)), idsConflit: [])
        XCTAssertEqual(analyse.missionsSelectionnees.map(\.id), ["1", "2", "3", "4", "5", "6"], "ordre des missions ouvertes, pas de la sélection")
        XCTAssertTrue(analyse.peutAccepter)
    }

    func testBloqueUneSelectionDontLePlanningEstInexact() {
        let inexacte = S.mission(S.record(id: "1", nbCreneaux: 2), slots: [S.slot(missionId: "1")])
        let analyse = SelectionSerieCandidat.analyser([inexacte], idsSelectionnes: ["1"], idsConflit: [])
        XCTAssertEqual(analyse.idsPlanningInexact, ["1"])
        XCTAssertFalse(analyse.peutAccepter)
    }

    func testSelectionVideOuInconnueNePeutPasEtreAcceptee() {
        let missions = serie(2)
        XCTAssertFalse(SelectionSerieCandidat.analyser(missions, idsSelectionnes: [], idsConflit: []).peutAccepter)
        let inconnue = SelectionSerieCandidat.analyser(missions, idsSelectionnes: ["42"], idsConflit: ["42"])
        XCTAssertTrue(inconnue.missionsSelectionnees.isEmpty)
        XCTAssertEqual(inconnue.idsEnConflit, [], "un conflit sur une mission non ouverte n'est pas rapporté")
        XCTAssertFalse(inconnue.peutAccepter)
    }

    func testMissionSerieCandidatConserveLesClesDuPlanning() {
        let planning = PlanningCandidatInput(id: "m", debutLe: "2026-08-01T08:00:00+02:00", finLe: "2026-08-01T16:00:00+02:00", nbCreneaux: 1)
        let mission = MissionSerieCandidat(id: "m", planning: planning)
        XCTAssertEqual(mission.id, "m")
        XCTAssertEqual(mission.planningCandidat, planning)
        XCTAssertEqual(S.mission().planningCandidat, PlanningCandidatInput(mission: S.mission()))
    }
}
