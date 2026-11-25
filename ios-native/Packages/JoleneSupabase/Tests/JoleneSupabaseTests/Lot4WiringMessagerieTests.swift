import Foundation
import JoleneCore
import XCTest
@testable import JoleneSupabase

/// Câblage Supabase de la messagerie et du Realtime (lot 4, T7a ; garde anti-oubli `Lot4Wiring<Domaine>Tests`,
/// `LOT4_PLAN.md` §2.2) : même PR que les fabriques démo, `DemoWorldTests.portsEnAttenteLot4` sans « messagerie » ni
/// « realtime ». Rien n'est ouvert à la construction : aucun canal, aucune requête.
final class Lot4WiringMessagerieTests: XCTestCase {
    func testSupabaseCableLaMessagerieEtLeRealtimeCommeLeMondeDemo() {
        StubRegistry.shared.reset()
        let client = TestClient.make()
        let gateways = SupabaseGateways.make(client: client)
        XCTAssertTrue(gateways.messagerie is SupabaseMessagerieGateway)
        XCTAssertTrue(gateways.realtime is SupabaseRealtimeGateway)
        for port in ["messagerie", "realtime"] {
            XCTAssertFalse(gateways.unwiredPorts.contains(port), port)
            XCTAssertFalse(DemoWorld.gateways().unwiredPorts.contains(port), port)
        }
        XCTAssertTrue(VerrousLot4.abonnementRealtimePermis(gateways.realtime))
        XCTAssertTrue(client.realtimeV2.channels.isEmpty, "aucun canal ouvert à la construction")
        XCTAssertTrue(StubRegistry.shared.requests.isEmpty, "aucune requête à la construction")
    }

    /// Les RPC de la messagerie sont celles que suit le contrat versionné (`ios-native/rpc-contracts.json`), toutes
    /// passées en `consommee` par cette tranche ; l'envoi ne passe que par l'edge (garde-fou 19).
    func testRPCDeLaPasserelleSuiviesEtConsommees() throws {
        let rpc = [
            SupabaseMessagerieGateway.rpcLister, SupabaseMessagerieGateway.rpcInterlocuteurs, SupabaseMessagerieGateway.rpcMarquerLus,
            SupabaseMessagerieGateway.rpcNonLus, SupabaseMessagerieGateway.rpcSaisieDebut, SupabaseMessagerieGateway.rpcSaisieFin,
            SupabaseMessagerieGateway.rpcPresence, SupabaseMessagerieGateway.rpcEstBloque, SupabaseMessagerieGateway.rpcBloquer,
            SupabaseMessagerieGateway.rpcDebloquer, SupabaseMessagerieGateway.rpcSignaler,
            SupabaseMessagerieGateway.rpcInterlocuteurEtablissement, SupabaseMessagerieGateway.rpcObtenirConversation,
        ]
        XCTAssertEqual(Set(rpc).count, 13)
        let contrats = Dictionary(uniqueKeysWithValues: try Depot.contrats().rpcs.map { ($0.name, $0) })
        for nom in rpc {
            let contrat = try XCTUnwrap(contrats[nom], "\(nom) absente de rpc-contracts.json")
            XCTAssertEqual(contrat.lot, 4, nom)
            XCTAssertEqual(contrat.statut, "consommee", "\(nom) : câblée par T7a")
        }
        XCTAssertEqual(SupabaseMessagerieGateway.edgeEnvoi, "messagerie-validate")
        XCTAssertEqual(SupabaseMessagerieGateway.tableMessages, "messages_chat")
        XCTAssertEqual(SupabaseRealtimeGateway.tableMessages, SupabaseMessagerieGateway.tableMessages)
    }
}
