import Foundation
import JoleneCore
import XCTest
@testable import JoleneSupabase

final class MissionSlotPagerTests: XCTestCase {
    private func slot(_ id: String, mission: String = "m-1", type: String = "PREVISIONNEL", pause: Bool = false) -> MissionSlot {
        MissionSlot(id: id, missionId: mission, debut: "2026-12-01T19:00:00+00:00", fin: "2026-12-02T01:00:00+00:00", estPause: pause, typeCreneau: type)
    }

    func testTwoPagesAccumulateInServerOrder() throws {
        var pager = MissionSlotPager(batch: ["m-1"])
        XCTAssertTrue(pager.needsMore)
        try pager.ingest(page: [slot("a"), slot("b")], count: 3)
        XCTAssertEqual(pager.offset, 2)
        XCTAssertTrue(pager.needsMore)
        try pager.ingest(page: [slot("c")], count: 3)
        XCTAssertFalse(pager.needsMore)
        XCTAssertEqual(try pager.finish().map { $0.id }, ["a", "b", "c"])
    }

    func testCountMissingIsRejected() {
        var pager = MissionSlotPager(batch: ["m-1"])
        XCTAssertThrowsError(try pager.ingest(page: [], count: nil)) { XCTAssertEqual($0 as? JoleneError, MissionSlotPager.countUnavailable) }
        XCTAssertThrowsError(try pager.ingest(page: [], count: -1)) { XCTAssertEqual($0 as? JoleneError, MissionSlotPager.countUnavailable) }
    }

    func testCountChangingBetweenPagesIsPlanningChanged() throws {
        var pager = MissionSlotPager(batch: ["m-1"])
        try pager.ingest(page: [slot("a")], count: 2)
        XCTAssertThrowsError(try pager.ingest(page: [slot("b")], count: 3)) { XCTAssertEqual($0 as? JoleneError, MissionSlotPager.planningChanged) }
    }

    func testEmptyPageBeforeCountIsIncomplete() {
        var pager = MissionSlotPager(batch: ["m-1"])
        XCTAssertThrowsError(try pager.ingest(page: [], count: 1)) { XCTAssertEqual($0 as? JoleneError, MissionSlotPager.planningIncomplete) }
    }

    func testInconsistentSlotsAreRejected() {
        let cases: [(String, MissionSlot)] = [
            ("mission hors lot", slot("a", mission: "m-9")),
            ("type non prévisionnel", slot("a", type: "EFFECTIF")),
            ("pause", slot("a", pause: true)),
            ("id absent", MissionSlot(id: nil, missionId: "m-1", debut: "x", fin: nil, estPause: false, typeCreneau: "PREVISIONNEL")),
            ("mission_id absent", MissionSlot(id: "a", missionId: nil, debut: "x", fin: nil, estPause: false, typeCreneau: "PREVISIONNEL")),
        ]
        for (label, bad) in cases {
            var pager = MissionSlotPager(batch: ["m-1"])
            XCTAssertThrowsError(try pager.ingest(page: [bad], count: 1), label) {
                XCTAssertEqual($0 as? JoleneError, MissionSlotPager.planningInconsistent, label)
            }
        }
    }

    func testDuplicateIdIsRejected() throws {
        var pager = MissionSlotPager(batch: ["m-1"])
        try pager.ingest(page: [slot("a")], count: 2)
        XCTAssertThrowsError(try pager.ingest(page: [slot("a")], count: 2)) { XCTAssertEqual($0 as? JoleneError, MissionSlotPager.planningInconsistent) }
    }

    func testMoreRowsThanCountIsRejected() {
        var pager = MissionSlotPager(batch: ["m-1"])
        XCTAssertThrowsError(try pager.ingest(page: [slot("a"), slot("b")], count: 1)) { XCTAssertEqual($0 as? JoleneError, MissionSlotPager.planningInconsistent) }
    }

    func testFinishBeforeCountReachedIsIncomplete() throws {
        var pager = MissionSlotPager(batch: ["m-1"])
        try pager.ingest(page: [slot("a")], count: 2)
        XCTAssertThrowsError(try pager.finish()) { XCTAssertEqual($0 as? JoleneError, MissionSlotPager.planningIncomplete) }
        XCTAssertThrowsError(try MissionSlotPager(batch: ["m-1"]).finish())
    }

    func testZeroSlotsIsAValidEmptyPlanning() throws {
        var pager = MissionSlotPager(batch: ["m-1"])
        try pager.ingest(page: [], count: 0)
        XCTAssertFalse(pager.needsMore)
        XCTAssertEqual(try pager.finish(), [])
    }

    func testBatchesOfFiftyUniqueIds() {
        let ids = (1...120).map { "m-\($0)" } + ["m-1", "", "m-2"]
        let batches = MissionSlotPager.batches(ids)
        XCTAssertEqual(batches.map(\.count), [50, 50, 20])
        XCTAssertEqual(batches.first?.first, "m-1")
        XCTAssertEqual(batches.last?.last, "m-120")
        XCTAssertEqual(MissionSlotPager.batches([]), [])
    }
}

final class MissionQueryTests: XCTestCase {
    func testCompatibleProfessionFilterMirrorsHierarchy() {
        XCTAssertEqual(MissionQuery.compatibleProfessionFilter("IADE"), "profession_requise.eq.IADE,profession_requise.eq.IDE")
        XCTAssertEqual(MissionQuery.compatibleProfessionFilter("IBODE"), "profession_requise.eq.IBODE,profession_requise.eq.IDE")
        XCTAssertNil(MissionQuery.compatibleProfessionFilter("IDE"))
        XCTAssertNil(MissionQuery.compatibleProfessionFilter("MEDECIN"))
        XCTAssertNil(MissionQuery.compatibleProfessionFilter(""))
        XCTAssertNil(MissionQuery.compatibleProfessionFilter(nil))
    }

    func testHaversineMatchesWebRounding() {
        XCTAssertEqual(MissionQuery.distanceKm(lat1: 48.8566, lng1: 2.3522, lat2: 45.764, lng2: 4.8357), 391.5, "Paris -> Lyon, même formule que src/lib/geo.ts")
        XCTAssertEqual(MissionQuery.distanceKm(lat1: 45.75, lng1: 4.85, lat2: 45.75, lng2: 4.85), 0)
        XCTAssertNil(MissionQuery.distanceKm(lat1: nil, lng1: 4.85, lat2: 45.75, lng2: 4.85))
        XCTAssertNil(MissionQuery.distanceKm(lat1: 45.75, lng1: 4.85, lat2: 45.75, lng2: nil))
    }

    func testIsoTimestampMatchesJavaScriptToISOString() {
        XCTAssertEqual(MissionQuery.isoTimestamp(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(MissionQuery.isoTimestamp(Date(timeIntervalSince1970: 1_790_000_000.5)), "2026-09-21T14:13:20.500Z")
    }

    func testServerFiltersApplyPilotDefaults() {
        let profile = TestClient.profile // taux_horaire_minimum 25
        let defaults = MissionQuery.serverFilters(MissionFilters(), profile: profile)
        XCTAssertEqual(defaults, MissionQuery.ServerFilters(profession: nil, tauxMin: 25, urgentesOnly: false, etablissementId: nil))

        let explicit = MissionQuery.serverFilters(MissionFilters(tauxMin: 30, profession: "", urgentesOnly: true, etablissementId: ""), profile: profile)
        XCTAssertEqual(explicit, MissionQuery.ServerFilters(profession: nil, tauxMin: 30, urgentesOnly: true, etablissementId: nil))

        var noMinimum = profile
        noMinimum.tauxHoraireMinimum = nil
        XCTAssertEqual(MissionQuery.serverFilters(MissionFilters(), profile: noMinimum).tauxMin, 0)
    }

    func testValidateContextRejectsMismatch() {
        XCTAssertNoThrow(try MissionQuery.validate(context: TestClient.context))
        XCTAssertThrowsError(try MissionQuery.validate(context: MissionReadContext(userId: "", email: nil, profile: TestClient.profile)))
        var noProfession = TestClient.profile
        noProfession.profession = ""
        XCTAssertThrowsError(try MissionQuery.validate(context: MissionReadContext(userId: TestClient.userId, email: nil, profile: noProfession)))
    }

    func testDefaultEnrichKeepsServerOrderAndDerivesPlanningExact() {
        let decoder = JSONDecoder()
        let record = try! decoder.decode(MissionRecord.self, from: Data(TestClient.missionJSON.utf8))
        var second = record
        second.id = "m-2"
        second.etablissementId = "etab-inconnu"
        let etab = EtablissementSummary(id: "etab-1", nom: "Clinique", adresseLat: 45.76, adresseLng: 4.85)
        let slots = [
            MissionSlot(id: "s-2", missionId: "m-1", debut: "2026-12-02T01:00:00+00:00", fin: "2026-12-02T07:00:00+00:00", estPause: false, typeCreneau: "PREVISIONNEL"),
            MissionSlot(id: "s-1", missionId: "m-1", debut: "2026-12-01T19:00:00+00:00", fin: "2026-12-02T01:00:00+00:00", estPause: false, typeCreneau: "PREVISIONNEL"),
        ]
        let missions = MissionQuery.defaultEnrich(TestClient.context, [record, second], ["etab-1": etab], slots)
        XCTAssertEqual(missions.map(\.id), ["m-1", "m-2"])
        XCTAssertEqual(missions[0].creneauxPlanifies.map { $0.id }, ["s-1", "s-2"], "tri début puis id")
        XCTAssertTrue(missions[0].planningExact, "nb_creneaux = 2, deux créneaux fermés : planning candidat exact")
        XCTAssertEqual(missions[0].distanceKm, 1.1)
        XCTAssertNil(missions[1].etablissement)
        XCTAssertNil(missions[1].distanceKm)
        XCTAssertFalse(missions[1].planningExact, "aucun créneau pour nb_creneaux = 2")

        // Créneaux sans fin : présents mais non vérifiables, le planning n'est pas exact
        // (l'ancien critère « créneaux présents » est abandonné).
        let ouverts = slots.map { slot in
            var copie = slot; copie.fin = nil; return copie
        }
        let nonExact = MissionQuery.defaultEnrich(TestClient.context, [record], ["etab-1": etab], ouverts)
        XCTAssertFalse(nonExact[0].planningExact)
        XCTAssertEqual(nonExact[0].creneauxPlanifies.map { $0.id }, ["s-1", "s-2"], "les créneaux chargés restent affichables")
    }
}
