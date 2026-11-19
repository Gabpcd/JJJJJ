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
}
