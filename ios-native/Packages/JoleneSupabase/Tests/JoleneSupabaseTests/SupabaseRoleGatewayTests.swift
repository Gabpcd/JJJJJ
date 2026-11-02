import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

final class SupabaseRoleGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    func testCurrentRoleDecodesJsonbPayload() async throws {
        let gateway = SupabaseRoleGateway(client: TestClient.make())
        registry.add("POST", "/rest/v1/rpc/fn_get_my_role", respond: .json(200, #"{"role":"SOIGNANT","etablissement_id":null}"#))

        let result = try await gateway.currentRole()

        XCTAssertEqual(result, RoleResult(role: "SOIGNANT", etablissementId: nil))
        let request = try XCTUnwrap(registry.requests(to: "/rest/v1/rpc/fn_get_my_role").first)
        XCTAssertEqual(request.header("X-Client-Info"), "jolene-ios/2.0.0")
        XCTAssertEqual(request.header("apikey"), TestClient.publishableKey)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testCurrentRoleWithEtablissement() async throws {
        let gateway = SupabaseRoleGateway(client: TestClient.make())
        registry.add("POST", "/rest/v1/rpc/fn_get_my_role", respond: .json(200, #"{"role":"ADMIN_ETABLISSEMENT","etablissement_id":"etab-42"}"#))
        let result = try await gateway.currentRole()
        XCTAssertEqual(result, RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-42"))
    }

    func testUnknownOrMalformedRoleBecomesInconnu() {
        XCTAssertEqual(SupabaseRoleGateway.roleResult(from: .null).role, "INCONNU")
        XCTAssertEqual(SupabaseRoleGateway.roleResult(from: .object([:])).role, "INCONNU")
        XCTAssertEqual(SupabaseRoleGateway.roleResult(from: .object(["role": .integer(3)])).role, "INCONNU")
        XCTAssertEqual(SupabaseRoleGateway.roleResult(from: .object(["role": .string("SOIGNANT"), "etablissement_id": .integer(1)])),
                       RoleResult(role: "SOIGNANT", etablissementId: nil))
    }

    func testMissingFunctionPGRST202IsContractErrorWithoutRetry() async throws {
        let gateway = SupabaseRoleGateway(client: TestClient.make())
        registry.add("POST", "/rest/v1/rpc/fn_get_my_role", respond: .json(404, """
        {"code":"PGRST202","details":"Searched for the function public.fn_get_my_role without parameters in the schema cache",
         "hint":null,"message":"Could not find the function public.fn_get_my_role without parameters in the schema cache"}
        """))

        do {
            _ = try await gateway.currentRole()
            XCTFail("attendu : erreur de contrat")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
            XCTAssertEqual(error.message, SupabaseErrorMapping.contractMessage)
            XCTAssertFalse(error.message.contains("PGRST"), "aucun détail technique dans le message")
        }
        XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/fn_get_my_role").count, 1, "refus définitif : un seul appel")
    }

    func testJWTExpiredIsUnauthorized() async throws {
        let gateway = SupabaseRoleGateway(client: TestClient.make())
        registry.add("POST", "/rest/v1/rpc/fn_get_my_role", respond: .json(401, #"{"code":"PGRST301","message":"JWT expired","details":null,"hint":null}"#))
        do {
            _ = try await gateway.currentRole()
            XCTFail("attendu : non autorisé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
    }

    func testNetworkFailureIsNetworkError() async throws {
        let gateway = SupabaseRoleGateway(client: TestClient.make())
        registry.add("POST", "/rest/v1/rpc/fn_get_my_role", respond: .networkFailure())
        do {
            _ = try await gateway.currentRole()
            XCTFail("attendu : erreur réseau")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        }
    }
}
