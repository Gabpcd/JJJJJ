import Foundation
import JoleneCore
import XCTest
@testable import JoleneSupabase

/// Câblage Supabase de la série (lot 4, T12 ; garde anti-oubli `Lot4Wiring<Domaine>Tests`, `LOT4_PLAN.md` §2.2) : même
/// PR que la fabrique démo. Quatorzième port du lot 4 (précision 13 de `DECISIONS_LOT4.md`), jamais en attente.
final class Lot4WiringSerieTests: XCTestCase {
    func testSupabaseCableLaSerieCommeLeMondeDemo() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.serie is SupabaseSerieGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("serie"))
        XCTAssertFalse(DemoWorld.gateways().unwiredPorts.contains("serie"))
        XCTAssertEqual(gateways.unwiredPorts, DemoWorld.gateways().unwiredPorts, "les deux mondes câblent les mêmes ports")
    }
}
