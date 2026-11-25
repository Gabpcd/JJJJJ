import Foundation
import JoleneCore
import XCTest
@testable import JoleneSupabase

/// Câblage Supabase du swipe (lot 4, T3a ; garde anti-oubli `Lot4Wiring<Domaine>Tests`, `LOT4_PLAN.md` §2.2) : même PR
/// que la fabrique démo, `DemoWorldTests.portsEnAttenteLot4` sans « swipe ».
final class Lot4WiringSwipeTests: XCTestCase {
    func testSupabaseCableLeSwipeCommeLeMondeDemo() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.swipe is SupabaseSwipeGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("swipe"))
        XCTAssertFalse(DemoWorld.gateways().unwiredPorts.contains("swipe"))
    }

    /// T3b : le ❤️ rend ses avis (`warning`, `docs_a_completer`) dans les deux mondes ; un port de candidature qui ne
    /// se conformerait plus à `CandidatureSwipePort` les perdrait en silence (`SwipeModel` retomberait sur `confirmer`).
    func testLePortDeCandidatureRendLesAvisDuLikeDansLesDeuxMondes() {
        XCTAssertTrue(SupabaseGateways.make(client: TestClient.make()).candidature is any CandidatureSwipePort)
        XCTAssertTrue(DemoWorld.gateways().candidature is any CandidatureSwipePort)
    }
}
