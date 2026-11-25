import Foundation
import JoleneCore
import XCTest
@testable import JoleneSupabase

/// Câblage Supabase des évaluations reçues et du score (lot 4, T9 ; garde anti-oubli `Lot4Wiring<Domaine>Tests`,
/// `LOT4_PLAN.md` §2.2) : même PR que les fabriques démo, `DemoWorldTests.portsEnAttenteLot4` sans les deux ports.
final class Lot4WiringEvaluationsScoreTests: XCTestCase {
    func testSupabaseCableLesEvaluationsEtLeScoreCommeLeMondeDemo() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.evaluationsRecues is SupabaseEvaluationsGateway)
        XCTAssertTrue(gateways.score is SupabaseScoreGateway)
        for port in ["evaluationsRecues", "score"] {
            XCTAssertFalse(gateways.unwiredPorts.contains(port), port)
            XCTAssertFalse(DemoWorld.gateways().unwiredPorts.contains(port), port)
        }
    }

    /// Les sept RPC de la tranche sont suivies et consommées dans le contrat versionné (`ios-native/rpc-contracts.json`).
    func testRPCDeLaTrancheSuiviesEtConsommees() throws {
        let contrats = try Depot.contrats().rpcs
        for rpc in [SupabaseEvaluationsGateway.rpcLecture, SupabaseEvaluationsGateway.rpcSignaler, SupabaseScoreGateway.rpcBreakdown,
                    SupabaseScoreGateway.rpcEvolution, SupabaseScoreGateway.rpcEvenements, SupabaseScoreGateway.rpcNotations,
                    SupabaseScoreGateway.rpcContester] {
            let contrat = try XCTUnwrap(contrats.first { $0.name == rpc }, "\(rpc) : absente du contrat versionné")
            XCTAssertEqual(contrat.statut, "consommee", rpc)
            XCTAssertEqual(contrat.lot, 4, rpc)
        }
    }
}
