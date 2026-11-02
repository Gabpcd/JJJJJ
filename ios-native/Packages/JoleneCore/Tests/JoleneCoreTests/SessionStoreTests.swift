import XCTest
import Combine
@testable import JoleneCore

/// Le store publie l'état renvoyé par l'acteur, sans logique propre.
@MainActor
final class SessionStoreTests: XCTestCase {
    private struct StoreAuth: AuthPort {
        var restored: AuthenticatedUser?
        var events: AuthEventEmitter? = nil
        func restoreSession() async throws -> AuthenticatedUser? { restored }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser {
            throw JoleneError(.invalidCredentials, "refusé")
        }
        func signOut() async throws {}
        func authEvents() -> AsyncStream<AuthEvent> { events?.stream() ?? AsyncStream { $0.finish() } }
    }
    private struct StoreRole: RolePort {
        func currentRole() async throws -> RoleResult { RoleResult(role: "SOIGNANT") }
    }
    private struct StoreMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "INFIRMIER") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private func store(restored: AuthenticatedUser?, events: AuthEventEmitter? = nil) -> SessionStore {
        let gateways = Gateways(auth: StoreAuth(restored: restored, events: events), role: StoreRole(), missions: StoreMissions())
        return SessionStore(controller: SessionController(gateways: gateways))
    }

    func testSdkSignedOutEventIsPublishedByTheStore() async {
        let emitter = AuthEventEmitter()
        let user = AuthenticatedUser(id: "u1", email: "u1@example.invalid", emailConfirmedAt: Date(), appMetadataRole: "SOIGNANT")
        let store = store(restored: user, events: emitter)
        store.observeAuthEvents()
        store.observeAuthEvents()
        XCTAssertTrue(store.isObservingAuthEvents)
        await store.start()
        XCTAssertTrue(store.state.isReady)
        emitter.emit(.signedOut)
        await waitUntil { @MainActor in store.state == .signedOut(message: SessionController.sessionExpiredMessage) }
        XCTAssertEqual(store.state, .signedOut(message: SessionController.sessionExpiredMessage))
        XCTAssertFalse(store.canRetryRestore)
    }

    func testStartKeepsReadyStateWhileRevalidating() async {
        let user = AuthenticatedUser(id: "u1", email: "u1@example.invalid", emailConfirmedAt: Date(), appMetadataRole: "SOIGNANT")
        let store = store(restored: user)
        await store.start()
        XCTAssertTrue(store.state.isReady)
        var observed: [SessionState] = []
        let cancellable = store.$state.sink { observed.append($0) }
        await store.start()
        cancellable.cancel()
        XCTAssertFalse(observed.contains(.loading), "aucun .loading publié lors d'une revalidation : \(observed)")
        XCTAssertTrue(store.state.isReady)
    }

    func testInitialStateIsIdle() {
        XCTAssertEqual(store(restored: nil).state, .idle)
    }

    func testStartPublishesControllerState() async {
        let user = AuthenticatedUser(id: "u1", email: "u1@example.invalid", emailConfirmedAt: Date(), appMetadataRole: "SOIGNANT")
        let store = store(restored: user)
        await store.start()
        XCTAssertTrue(store.state.isReady, "obtenu \(store.state)")
        XCTAssertEqual(store.state.snapshot?.user.id, "u1")
        let controllerState = await store.controller.state
        XCTAssertEqual(store.state, controllerState)
    }

    func testSignInFailureThenSignOutArePublished() async {
        let store = store(restored: nil)
        await store.start()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        await store.signIn(email: "u1@example.invalid", password: "secret-value")
        XCTAssertEqual(store.state, .signedOut(message: SessionController.genericSignInMessage))
        XCTAssertFalse(store.state.message?.contains("secret-value") ?? false)
        await store.signOut()
        XCTAssertEqual(store.state, .signedOut(message: nil))
        let epoch = await store.controller.epoch
        XCTAssertEqual(epoch, 2, "connexion puis déconnexion : deux frontières d'identité")
    }
}
