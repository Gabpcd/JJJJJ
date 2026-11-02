import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

final class SupabaseErrorMappingTests: XCTestCase {
    private let fallback = "Impossible de charger. Réessayez."

    private func httpError(_ status: Int) -> HTTPError {
        HTTPError(data: Data("<html>moved</html>".utf8),
                  response: HTTPURLResponse(url: TestClient.url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func testPostgrestContractCodesAreDefinitive() {
        for code in ["PGRST200", "PGRST201", "PGRST202", "PGRST203"] {
            let mapped = SupabaseErrorMapping.map(PostgrestError(code: code, message: "secret detail"), fallback: fallback)
            XCTAssertEqual(mapped.kind, .contract, code)
            XCTAssertEqual(mapped.message, SupabaseErrorMapping.contractMessage)
            XCTAssertFalse(mapped.message.contains("secret"))
        }
    }

    func testHttpRedirectStatusesAreContract() {
        for status in 300...303 {
            XCTAssertEqual(SupabaseErrorMapping.map(httpError(status), fallback: fallback).kind, .contract, "\(status)")
        }
        XCTAssertEqual(SupabaseErrorMapping.map(httpError(304), fallback: fallback).kind, .unknown)
        XCTAssertEqual(SupabaseErrorMapping.map(httpError(500), fallback: fallback).message, fallback)
    }

    func testUnauthorizedMappings() {
        XCTAssertEqual(SupabaseErrorMapping.map(httpError(401), fallback: fallback).kind, .unauthorized)
        XCTAssertEqual(SupabaseErrorMapping.map(httpError(403), fallback: fallback).kind, .unauthorized)
        for code in ["PGRST301", "PGRST302", "PGRST303", "42501"] {
            XCTAssertEqual(SupabaseErrorMapping.map(PostgrestError(code: code, message: "x"), fallback: fallback).kind, .unauthorized, code)
        }
        XCTAssertEqual(SupabaseErrorMapping.map(AuthError.sessionMissing, fallback: fallback).kind, .unauthorized)
    }

    func testNetworkAndCancellation() {
        XCTAssertEqual(SupabaseErrorMapping.map(URLError(.notConnectedToInternet), fallback: fallback).kind, .network)
        XCTAssertEqual(SupabaseErrorMapping.map(URLError(.timedOut), fallback: fallback).message, SupabaseErrorMapping.networkMessage)
        XCTAssertEqual(SupabaseErrorMapping.map(URLError(.cancelled), fallback: fallback).kind, .cancelled)
        XCTAssertEqual(SupabaseErrorMapping.map(CancellationError(), fallback: fallback).kind, .cancelled)
    }

    func testUnknownPostgrestCodeUsesFallbackMessage() {
        let mapped = SupabaseErrorMapping.map(PostgrestError(code: "23505", message: "duplicate key value violates"), fallback: fallback)
        XCTAssertEqual(mapped, JoleneError(.unknown, fallback))
        XCTAssertEqual(SupabaseErrorMapping.map(PostgrestError(message: "no code"), fallback: fallback).kind, .unknown)
    }

    func testJoleneErrorPassesThroughUnchanged() {
        let original = JoleneError(.demoOnly, "Démo.")
        XCTAssertEqual(SupabaseErrorMapping.map(original, fallback: fallback), original)
    }

    func testSignInErrorMapping() {
        func api(_ status: Int, code: String = "invalid_credentials") -> AuthError {
            .api(message: "Invalid login credentials", errorCode: ErrorCode(code), underlyingData: Data(),
                 underlyingResponse: HTTPURLResponse(url: TestClient.url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        for status in [400, 401, 403, 422] {
            let mapped = SupabaseAuthGateway.signInError(api(status))
            XCTAssertEqual(mapped.kind, .invalidCredentials, "\(status)")
            XCTAssertEqual(mapped.message, SupabaseAuthGateway.invalidCredentialsMessage)
        }
        XCTAssertEqual(SupabaseAuthGateway.signInError(api(400, code: "email_not_confirmed")).message, SupabaseAuthGateway.emailUnconfirmedMessage)
        XCTAssertEqual(SupabaseAuthGateway.signInError(api(429, code: "over_request_rate_limit")).message, SupabaseAuthGateway.tooManyAttemptsMessage)
        XCTAssertEqual(SupabaseAuthGateway.signInError(api(503, code: "unexpected_failure")).message, SupabaseAuthGateway.signInFallbackMessage)
        XCTAssertEqual(SupabaseAuthGateway.signInError(.sessionMissing).kind, .unauthorized)
    }
}
