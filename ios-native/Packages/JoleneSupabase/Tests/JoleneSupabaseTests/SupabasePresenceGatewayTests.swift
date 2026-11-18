import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Confirmation de présence (lot 1, T6c) sur `fn_confirmer_presence_mission` : une forme de réponse = un test. Refus
/// serveur verbatim (`public.sql` l.24999-25002), succès annoncé seulement après relecture de `presence_confirmee_le`,
/// une seule requête (la RPC n'est pas idempotente).
final class SupabasePresenceGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let missionId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let rpc = "/rest/v1/rpc/fn_confirmer_presence_mission"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func confirmer() async throws -> PresenceOutcome {
        try await SupabasePresenceGateway(client: TestClient.make()).confirmerPresence(missionId: missionId, context: TestClient.context)
    }

    private func erreur(_ operation: () async throws -> Void) async -> JoleneError? {
        do {
            try await operation()
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    private func relecture(_ confirmee: String?, soignant: String = TestClient.userId) -> String {
        let date = confirmee.map { "\"\($0)\"" } ?? "null"
        return #"[{"id":"\#(missionId)","statut":"ASSIGNEE","soignant_assigne_id":"\#(soignant)","presence_confirmee_le":\#(date)}]"#
    }

    func testSuccesRelitPresenceConfirmee() async throws {
        registry.add("POST", rpc, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, relecture("2026-11-02T10:00:00+00:00")))
        let issue = try await confirmer()
        XCTAssertEqual(issue, .confirmee(presenceConfirmeeLe: "2026-11-02T10:00:00+00:00"))
        let corps = try XCTUnwrap(registry.requests(to: rpc).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_mission_id"] as? String, missionId)
        let lecture = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(lecture.query("select"), SupabasePresenceGateway.relectureColumns)
        XCTAssertEqual(lecture.query("id"), "eq.\(missionId)")
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "une seule requête, aucun renvoi")
    }

    func testRefusServeurVerbatimSansRelecture() async throws {
        for message in ["Cette mission n'est plus active.", "Mission introuvable"] {
            registry.reset()
            registry.add("POST", rpc, respond: .json(200, #"{"error":"\#(message)"}"#))
            let issue = try await confirmer()
            XCTAssertEqual(issue, .refusee(message: message), "message serveur verbatim")
            XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty, "aucune relecture sur un refus")
        }
    }

    func testRelectureSansDateOuDUnAutreSoignantEstUneErreur() async throws {
        registry.add("POST", rpc, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, relecture(nil)))
        let sansDate = await erreur { _ = try await self.confirmer() }
        XCTAssertEqual(sansDate, JoleneError(.contract, SupabasePresenceGateway.relectureMessage))
        registry.reset()
        registry.add("POST", rpc, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, relecture("2026-11-02T10:00:00+00:00", soignant: "autre")))
        let autre = await erreur { _ = try await self.confirmer() }
        XCTAssertEqual(autre, JoleneError(.contract, SupabasePresenceGateway.relectureMessage))
    }

    func testCorpsVideJamaisUnSucces() async throws {
        registry.add("POST", rpc, respond: .json(200, "{}"))
        let vide = await erreur { _ = try await self.confirmer() }
        XCTAssertEqual(vide?.kind, .contract, "jamais un succès sans `success:true`")
        XCTAssertTrue(registry.requests(to: "/rest/v1/missions").isEmpty)
    }

    func testRepliWebDuRefusSansMessage() {
        XCTAssertEqual(PresenceRules.messageRefus(nil), "Confirmation impossible.")
        XCTAssertEqual(PresenceRules.messageRefus(""), "Confirmation impossible.")
        XCTAssertEqual(TextesWeb.ConfirmationPresence.repliRefus, "Confirmation impossible.")
    }
}
