import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/completude-planning-mission.json`
/// (port de `src/lib/completude-planning-mission.ts`).
final class RulesCompletudeTests: XCTestCase {
    private func mission(_ valeur: JSONValue?) throws -> MissionAvecPlanningAttendu {
        let mission = try XCTUnwrap(valeur, "mission absente du vecteur")
        return MissionAvecPlanningAttendu(
            id: mission["id"]?.string,
            debutLe: try XCTUnwrap(mission["debut_le"]?.string),
            finLe: try XCTUnwrap(mission["fin_le"]?.string),
            nbCreneaux: Golden.entier(mission["nb_creneaux"])
        )
    }

    private func golden(_ completude: CompletudePlanningMission) -> JSONValue {
        .object([
            "complet": .bool(completude.complet),
            "creneauxPlanifies": .array(completude.creneauxPlanifies.map(\.golden)),
            "nombrePlanifie": .number(Double(completude.nombrePlanifie)),
            "dureeTotaleHeures": .number(completude.dureeTotaleHeures),
        ])
    }

    func testVecteursGoldenCompletudePlanning() throws {
        let rejoues = try Golden.rejouer("completude-planning-mission") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "analyserCompletudePlanningMission":
                let mission = try mission(entree["mission"])
                // `creneaux` absent : valeur par défaut `[]` du web.
                guard let creneaux = entree["creneaux"] else { return golden(CompletudePlanning.analyser(mission)) }
                return golden(CompletudePlanning.analyser(mission, creneaux: try creneaux.decode([MissionSlot].self)))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    func testUnResultatPartielNEstJamaisExpose() {
        let mission = MissionAvecPlanningAttendu(id: "m", debutLe: "2026-07-06T08:00:00+02:00", finLe: "2026-07-07T16:00:00+02:00", nbCreneaux: 2)
        let un = MissionSlot(id: "c1", debut: "2026-07-06T08:00:00+02:00", fin: "2026-07-06T16:00:00+02:00", estPause: false, typeCreneau: "PREVISIONNEL")
        let deux = MissionSlot(id: "c2", debut: "2026-07-07T08:00:00+02:00", fin: "2026-07-07T16:00:00+02:00", estPause: false, typeCreneau: "PREVISIONNEL")
        let tronque = CompletudePlanning.analyser(mission, creneaux: [un])
        XCTAssertEqual(tronque, CompletudePlanningMission(complet: false, creneauxPlanifies: [], nombrePlanifie: 0, dureeTotaleHeures: 0))
        let complet = CompletudePlanning.analyser(mission, creneaux: [deux, un])
        XCTAssertTrue(complet.complet)
        XCTAssertEqual(complet.creneauxPlanifies.map(\.id), ["c1", "c2"], "tri par début")
        XCTAssertEqual(complet.nombrePlanifie, 2)
        XCTAssertEqual(complet.dureeTotaleHeures, 16)
    }

    func testLigneIllisibleEchoueFermeSansLever() {
        // Comme le web (`creneauValide` capture l'erreur de `instantJolene`) : refus, jamais d'exception.
        let mission = MissionAvecPlanningAttendu(id: "m", debutLe: "2026-07-06T08:00:00+02:00", finLe: "2026-07-06T16:00:00+02:00", nbCreneaux: 1)
        let illisible = MissionSlot(id: "x", debut: "pas une date", fin: "2026-07-06T16:00:00+02:00", estPause: false, typeCreneau: "PREVISIONNEL")
        XCTAssertFalse(CompletudePlanning.analyser(mission, creneaux: [illisible]).complet)
    }

    func testLigneMissionUtilisableDirectement() {
        typealias S = MissionsTestSupport
        let record = S.record(nbCreneaux: 1)
        let attendu = MissionAvecPlanningAttendu(record: record)
        XCTAssertEqual(attendu, MissionAvecPlanningAttendu(id: "mission-1", debutLe: "2026-10-27T08:00:00Z", finLe: "2026-10-27T16:00:00Z", nbCreneaux: 1))
        let completude = CompletudePlanning.analyser(attendu, creneaux: [S.slot()])
        XCTAssertTrue(completude.complet)
        XCTAssertEqual(completude.dureeTotaleHeures, 8)
        // Repli legacy : mission ponctuelle sans compteur ni ligne.
        let legacy = CompletudePlanning.analyser(MissionAvecPlanningAttendu(record: S.record(nbCreneaux: nil)))
        XCTAssertEqual(legacy.creneauxPlanifies.map(\.id), ["mission-ponctuelle-mission-1"])
    }
}
