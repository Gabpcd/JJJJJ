import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/completude-planning-mission.json`
/// (port de `src/lib/completude-planning-mission.ts`).
final class RulesCompletudeTests: XCTestCase {
    typealias S = MissionsTestSupport

    private func mission(_ valeur: JSONValue?) throws -> MissionAvecPlanningAttendu {
        let m = try XCTUnwrap(valeur)
        return MissionAvecPlanningAttendu(
            id: m["id"]?.string,
            debutLe: try XCTUnwrap(m["debut_le"]?.string),
            finLe: try XCTUnwrap(m["fin_le"]?.string),
            nbCreneaux: Golden.entier(m["nb_creneaux"])
        )
    }

    private func golden(_ resultat: CompletudePlanningMission) -> JSONValue {
        .object([
            "complet": .bool(resultat.complet),
            "creneauxPlanifies": .array(resultat.creneauxPlanifies.map(\.golden)),
            "nombrePlanifie": .number(Double(resultat.nombrePlanifie)),
            "dureeTotaleHeures": .number(resultat.dureeTotaleHeures),
        ])
    }

    func testVecteursGoldenCompletudePlanning() throws {
        let rejoues = try Golden.rejouer("completude-planning-mission") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "analyserCompletudePlanningMission":
                return golden(CompletudePlanning.analyser(
                    try mission(entree["mission"]),
                    creneaux: try (entree["creneaux"] ?? .array([])).decode([MissionSlot].self)
                ))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    // MARK: - Cas vitest reproduits

    private let missionLongue = MissionAvecPlanningAttendu(id: "mission-1", debutLe: "2026-07-06T08:00:00+02:00", finLe: "2026-08-31T16:00:00+02:00", nbCreneaux: 2)
    private let creneauxExacts = [
        MissionSlot(id: "creneau-1", debut: "2026-07-06T08:00:00+02:00", fin: "2026-07-06T16:00:00+02:00", estPause: false, typeCreneau: "PREVISIONNEL"),
        MissionSlot(id: "creneau-2", debut: "2026-08-31T08:00:00+02:00", fin: "2026-08-31T16:00:00+02:00", estPause: false, typeCreneau: "PREVISIONNEL"),
    ]

    func testAccepteUniquementLeNombreExactDeCreneauxValides() {
        let resultat = CompletudePlanning.analyser(missionLongue, creneaux: creneauxExacts)
        XCTAssertTrue(resultat.complet)
        XCTAssertEqual(resultat.nombrePlanifie, 2)
        XCTAssertEqual(resultat.dureeTotaleHeures, 16)
        XCTAssertEqual(resultat.creneauxPlanifies, creneauxExacts)
    }

    func testEchoueFermeSiLaReponseEstTronquee() {
        let resultat = CompletudePlanning.analyser(missionLongue, creneaux: Array(creneauxExacts.prefix(1)))
        XCTAssertFalse(resultat.complet)
        XCTAssertEqual(resultat.creneauxPlanifies, [])
        XCTAssertEqual(resultat.nombrePlanifie, 0)
        XCTAssertEqual(resultat.dureeTotaleHeures, 0)
    }

    func testEchoueFermeSiUnCreneauEstInvalide() {
        var invalide = creneauxExacts[0]
        invalide.fin = "2026-07-06T07:59:00+02:00"
        var mission = missionLongue
        mission.nbCreneaux = 1
        XCTAssertFalse(CompletudePlanning.analyser(mission, creneaux: [invalide]).complet)
        invalide.fin = invalide.debut
        XCTAssertFalse(CompletudePlanning.analyser(mission, creneaux: [invalide]).complet, "durée nulle")
        invalide.fin = "pas une date"
        XCTAssertFalse(CompletudePlanning.analyser(mission, creneaux: [invalide]).complet, "date illisible : jamais d'exception")
        invalide.fin = nil
        XCTAssertFalse(CompletudePlanning.analyser(mission, creneaux: [invalide]).complet, "sans fin")
    }

    func testConserveLeRepliLegacyPourUnePonctuelleDe24hMaximum() {
        let legacy = MissionAvecPlanningAttendu(id: "mission-legacy", debutLe: "2026-07-06T08:00:00+02:00", finLe: "2026-07-06T16:00:00+02:00", nbCreneaux: nil)
        let resultat = CompletudePlanning.analyser(legacy)
        XCTAssertTrue(resultat.complet)
        XCTAssertEqual(resultat.nombrePlanifie, 1)
        XCTAssertEqual(resultat.dureeTotaleHeures, 8)
        XCTAssertEqual(resultat.creneauxPlanifies.map(\.id), ["mission-ponctuelle-mission-legacy"])
    }

    func testNInventeAucunPlanningPourUneMissionLongueLegacy() {
        let legacy = MissionAvecPlanningAttendu(id: "mission-longue-legacy", debutLe: "2026-07-06T08:00:00+02:00", finLe: "2026-08-31T16:00:00+02:00", nbCreneaux: nil)
        let resultat = CompletudePlanning.analyser(legacy)
        XCTAssertFalse(resultat.complet)
        XCTAssertEqual(resultat.creneauxPlanifies, [])
    }

    func testDepuisUneLigneMissions() {
        let resultat = CompletudePlanning.analyser(MissionAvecPlanningAttendu(S.record()), creneaux: [S.slot()])
        XCTAssertTrue(resultat.complet)
        XCTAssertEqual(resultat.dureeTotaleHeures, 8)
    }
}
