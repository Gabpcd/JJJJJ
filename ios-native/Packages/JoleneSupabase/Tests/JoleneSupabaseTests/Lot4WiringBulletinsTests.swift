import Foundation
import JoleneCore
import XCTest
@testable import JoleneSupabase

/// Câblage Supabase des copies officielles des bulletins (lot 4, T10 ; garde anti-oubli `Lot4Wiring<Domaine>Tests`,
/// `LOT4_PLAN.md` §2.2) : même PR que la fabrique démo, `DemoWorldTests.portsEnAttenteLot4` sans « bulletins ».
final class Lot4WiringBulletinsTests: XCTestCase {
    func testSupabaseCableLesBulletinsCommeLeMondeDemo() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.bulletins is SupabaseBulletinsGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("bulletins"))
        XCTAssertTrue(DemoWorld.gateways().bulletins is DemoBulletinsGateway)
        XCTAssertFalse(DemoWorld.gateways().unwiredPorts.contains("bulletins"))
    }
}
