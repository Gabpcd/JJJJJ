import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

final class SupabaseAuthGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    func testSignInSuccessMapsUserAndPersistsSession() async throws {
        let storage = InMemoryAuthStorage()
        let gateway = SupabaseAuthGateway(client: TestClient.make(storage: storage))
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))

        let user = try await gateway.signIn(email: TestClient.email, password: "motdepasse-test")

        XCTAssertEqual(user.id, TestClient.userId)
        XCTAssertEqual(user.email, TestClient.email)
        XCTAssertNotNil(user.emailConfirmedAt)
        XCTAssertEqual(user.appMetadataRole, "SOIGNANT")
        XCTAssertNil(user.appMetadataEtablissementId)

        let tokenRequests = registry.requests(to: "/auth/v1/token")
        XCTAssertEqual(tokenRequests.count, 1)
        let request = try XCTUnwrap(tokenRequests.first)
        XCTAssertEqual(request.query("grant_type"), "password")
        XCTAssertEqual(request.header("X-Client-Info"), "jolene-ios/2.0.0")
        XCTAssertEqual(request.header("apikey"), TestClient.publishableKey)
        XCTAssertTrue(registry.unmatched.isEmpty, "requêtes non stubées : \(registry.unmatched.map(\.path))")
        // Relecture après mutation : la session est persistée dans le stockage injecté.
        XCTAssertEqual(storage.keys, ["sb-mejpriaetwgtcstbgfid-auth-token"])
    }

    func testSignInRefusedBecomesGenericInvalidCredentials() async throws {
        let gateway = SupabaseAuthGateway(client: TestClient.make())
        registry.add("POST", "/auth/v1/token", respond: .json(
            400, #"{"code":"invalid_credentials","message":"Invalid login credentials"}"#,
            headers: ["X-Supabase-Api-Version": "2024-01-01"]
        ))

        do {
            _ = try await gateway.signIn(email: TestClient.email, password: TestClient.motDePasseRefuse)
            XCTFail("La connexion aurait dû être refusée")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .invalidCredentials)
            XCTAssertEqual(error.message, SupabaseAuthGateway.invalidCredentialsMessage)
            XCTAssertFalse(error.message.contains(TestClient.email))
            XCTAssertFalse(error.message.lowercased().contains("invalid login"))
        }
        XCTAssertEqual(registry.requests(to: "/auth/v1/token").count, 1, "aucun retry sur un refus")
    }

    func testSignInEmailNotConfirmedIsUnauthorizedWithoutEmail() async throws {
        let gateway = SupabaseAuthGateway(client: TestClient.make())
        registry.add("POST", "/auth/v1/token", respond: .json(
            400, #"{"code":"email_not_confirmed","message":"Email not confirmed"}"#,
            headers: ["X-Supabase-Api-Version": "2024-01-01"]
        ))
        do {
            _ = try await gateway.signIn(email: TestClient.email, password: "motdepasse-test")
            XCTFail("attendu : refus")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
            XCTAssertEqual(error.message, SupabaseAuthGateway.emailUnconfirmedMessage)
            XCTAssertFalse(error.message.contains(TestClient.email))
        }
    }

    func testSignInNetworkFailureIsNetworkError() async throws {
        let gateway = SupabaseAuthGateway(client: TestClient.make())
        registry.add("POST", "/auth/v1/token", respond: .networkFailure())
        do {
            _ = try await gateway.signIn(email: TestClient.email, password: "motdepasse-test")
            XCTFail("attendu : erreur réseau")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
            XCTAssertEqual(error.message, SupabaseErrorMapping.networkMessage)
        }
    }

    func testSignInEmptyInputsNeverReachNetwork() async throws {
        let gateway = SupabaseAuthGateway(client: TestClient.make())
        do {
            _ = try await gateway.signIn(email: "   ", password: "")
            XCTFail("attendu : refus local")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .invalidCredentials)
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }

    func testRestoreSessionReadsPersistedSessionWithoutNetwork() async throws {
        let storage = InMemoryAuthStorage()
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        _ = try await SupabaseAuthGateway(client: TestClient.make(storage: storage))
            .signIn(email: TestClient.email, password: "motdepasse-test")
        registry.reset()

        // Nouveau client (nouveau lancement d'app) sur le même stockage.
        let restored = try await SupabaseAuthGateway(client: TestClient.make(storage: storage)).restoreSession()

        let user = try XCTUnwrap(restored)
        XCTAssertEqual(user.id, TestClient.userId)
        XCTAssertEqual(user.appMetadataRole, "SOIGNANT")
        XCTAssertTrue(registry.requests.isEmpty, "la restauration d'une session valide ne fait aucun appel réseau")
    }

    func testRestoreSessionWithoutStoredSessionReturnsNil() async throws {
        let restored = try await SupabaseAuthGateway(client: TestClient.make()).restoreSession()
        XCTAssertNil(restored)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    func testSignOutClearsLocalSessionEvenWhenServerFails() async throws {
        let storage = InMemoryAuthStorage()
        let client = TestClient.make(storage: storage)
        let gateway = SupabaseAuthGateway(client: client)
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        _ = try await gateway.signIn(email: TestClient.email, password: "motdepasse-test")
        registry.add("POST", "/auth/v1/logout", respond: .json(500, #"{"message":"boom"}"#))

        try await gateway.signOut()

        XCTAssertNil(client.auth.currentSession)
        XCTAssertTrue(storage.keys.isEmpty, "la session persistée est retirée")
        let logout = try XCTUnwrap(registry.requests(to: "/auth/v1/logout").first)
        XCTAssertEqual(logout.query("scope"), "global")
    }

    func testSignOutWithServerSuccess() async throws {
        let client = TestClient.make()
        let gateway = SupabaseAuthGateway(client: client)
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        _ = try await gateway.signIn(email: TestClient.email, password: "motdepasse-test")
        registry.add("POST", "/auth/v1/logout", respond: .json(204, ""))

        try await gateway.signOut()

        XCTAssertNil(client.auth.currentSession)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }
}

/// Flux `authEvents()` (relecture lot 0) : les événements du SDK sont traduits en `AuthEvent`
/// pour que `SessionController` bascule sur une session effacée côté serveur.
final class SupabaseAuthEventsTests: XCTestCase {
    private let registry = StubRegistry.shared

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    func testEventMappingCoversEverySdkEvent() {
        XCTAssertEqual(SupabaseAuthGateway.authEvent(.signedOut, session: nil), .signedOut)
        XCTAssertNil(SupabaseAuthGateway.authEvent(.initialSession, session: nil), "sans session, c'est restoreSession qui tranche")
        XCTAssertNil(SupabaseAuthGateway.authEvent(.tokenRefreshed, session: nil))
    }

    func testSignInThenSignOutAreStreamedAsSessionThenSignedOut() async throws {
        let gateway = SupabaseAuthGateway(client: TestClient.make())
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        registry.add("POST", "/auth/v1/logout", respond: .json(204, ""))

        let collected = EventCollector()
        let stream = gateway.authEvents()
        let consumer = Task {
            for await event in stream { await collected.append(event) }
        }
        _ = try await gateway.signIn(email: TestClient.email, password: "motdepasse-test")
        await collected.waitUntil { $0.contains(.session(userId: TestClient.userId)) }
        try await gateway.signOut()
        await collected.waitUntil { $0.last == .signedOut }
        consumer.cancel()

        let events = await collected.events
        XCTAssertTrue(events.contains(.session(userId: TestClient.userId)), "obtenu \(events)")
        XCTAssertEqual(events.last, .signedOut, "obtenu \(events)")
    }
}

actor EventCollector {
    private(set) var events: [AuthEvent] = []
    func append(_ event: AuthEvent) { events.append(event) }

    /// Attente bornée (2 s) : jamais de sommeil arbitraire sans condition.
    func waitUntil(_ condition: ([AuthEvent]) -> Bool) async {
        for _ in 0..<400 {
            if condition(events) { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
