import XCTest
@testable import JoleneCore

/// Rejoue `Resources/golden/synthese-presence-mission.json`
/// (port de `src/lib/synthese-presence-mission.ts`).
final class RulesSynthesePresenceTests: XCTestCase {
    private func golden(_ synthese: SynthesePresenceMission) -> JSONValue {
        .object([
            "previsionnels": .array(synthese.previsionnels.map(\.golden)),
            "effectifsFermes": .array(synthese.effectifsFermes.map(\.golden)),
            "effectifsOuverts": .array(synthese.effectifsOuverts.map(\.golden)),
            "minutesPlanifiees": .number(synthese.minutesPlanifiees),
            "minutesTravaillees": .number(synthese.minutesTravaillees),
            "dernierPrevisionnelFin": .instant(synthese.dernierPrevisionnelFin),
            "planningTermine": .bool(synthese.planningTermine),
            "validationPossible": .bool(synthese.validationPossible),
        ])
    }

    func testVecteursGoldenSynthesePresence() throws {
        let rejoues = try Golden.rejouer("synthese-presence-mission") { vecteur in
            let entree = vecteur.input
            switch vecteur.fonction {
            case "construireSynthesePresenceMission":
                let creneaux = try (entree["creneaux"] ?? .array([])).decode([MissionSlot].self)
                return golden(SynthesePresence.construire(creneaux, maintenant: try Golden.instant(entree["maintenant"])))
            case "formatDureeMinutes":
                return .string(SynthesePresence.formatDureeMinutes(try XCTUnwrap(entree["minutes"]?.double)))
            default:
                return nil
            }
        }
        XCTAssertGreaterThan(rejoues, 0)
    }

    private func slot(_ debut: String, _ fin: String?, _ type: String = "PREVISIONNEL", pause: Bool = false, id: String? = nil) -> MissionSlot {
        MissionSlot(id: id, debut: debut, fin: fin, estPause: pause, typeCreneau: type)
    }

    func testSeulsLesEffectifsFermesSontDesHeuresTravaillees() throws {
        // Les champs de `presences` couvrent les jours de repos d'une mission longue : seule la
        // somme des segments EFFECTIF fermés fait foi, jamais un écart arrivée/départ.
        let synthese = SynthesePresence.construire([
            slot("2026-07-06T08:00:00+02:00", "2026-07-06T16:00:00+02:00"),
            slot("2026-08-31T08:00:00+02:00", "2026-08-31T16:00:00+02:00"),
            slot("2026-07-06T08:15:00+02:00", "2026-07-06T14:15:00+02:00", "EFFECTIF"),
            slot("2026-08-31T08:00:00+02:00", "2026-08-31T16:00:00+02:00", "EFFECTIF"),
            slot("2026-07-06T12:00:00+02:00", "2026-07-06T12:30:00+02:00", "EFFECTIF", pause: true),
        ], maintenant: try DateHeureParis.instantJolene("2026-09-01T08:00:00+02:00"))
        XCTAssertEqual(synthese.minutesPlanifiees, 16 * 60)
        XCTAssertEqual(synthese.minutesTravaillees, 14 * 60, "6 h puis 8 h, la pause n'est jamais comptée")
        XCTAssertTrue(synthese.validationPossible)
        XCTAssertEqual(SynthesePresence.formatDureeMinutes(synthese.minutesTravaillees), "14h00")
    }

    func testUnSegmentOuvertInterditLaValidation() throws {
        let synthese = SynthesePresence.construire([
            slot("2026-07-31T06:00:00Z", "2026-07-31T14:00:00Z"),
            slot("2026-07-31T06:00:00Z", "2026-07-31T10:00:00Z", "EFFECTIF"),
            slot("2026-07-31T10:30:00Z", nil, "EFFECTIF", id: "ouvert"),
        ], maintenant: try DateHeureParis.instantJolene("2026-08-01T00:00:00Z"))
        XCTAssertTrue(synthese.planningTermine)
        XCTAssertEqual(synthese.effectifsOuverts.map(\.id), ["ouvert"])
        XCTAssertFalse(synthese.validationPossible)
    }

    func testFinDuPlanningIllisibleNEstJamaisTerminee() throws {
        let synthese = SynthesePresence.construire([slot("2026-07-31T06:00:00Z", "pas une date")],
                                                   maintenant: try DateHeureParis.instantJolene("2030-01-01T00:00:00Z"))
        XCTAssertNil(synthese.dernierPrevisionnelFin)
        XCTAssertFalse(synthese.planningTermine, "échec fermé : une borne illisible ne termine pas le planning")
        XCTAssertEqual(synthese.minutesPlanifiees, 0)
    }

    func testFormatDureeArrondiCommeLeWeb() {
        XCTAssertEqual(SynthesePresence.formatDureeMinutes(0), "0h00")
        XCTAssertEqual(SynthesePresence.formatDureeMinutes(450), "7h30")
        XCTAssertEqual(SynthesePresence.formatDureeMinutes(119.6), "1h60", "parité web : Math.round du reste")
        XCTAssertEqual(SynthesePresence.formatDureeMinutes(0.49999999999999994), "0h00", "Math.round, pas floor(x + 0,5)")
        XCTAssertEqual(SynthesePresence.formatDureeMinutes(-30), "-1h-30")
    }
}
