import XCTest
@testable import JoleneCore

// MARK: - Ports factices (structs Sendable, état partagé via un acteur)

/// Barrière réutilisable : un port peut attendre qu'un test l'ouvre, ce qui
/// permet de faire changer l'identité pendant qu'une réponse réseau est en vol.
actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

/// Journal des appels, pour prouver qu'aucun mot de passe n'est conservé et que
/// les ports sont bien sollicités dans l'ordre attendu.
actor CallLog {
    private(set) var entries: [String] = []
    private(set) var signInCount = 0
    private(set) var signOutCount = 0
    func record(_ entry: String) { entries.append(entry) }
    func signedIn() { signInCount += 1 }
    func signedOut() { signOutCount += 1 }
}

/// État mutable partagé par un port factice : le test fait varier la réponse d'un
/// appel à l'autre (restauration qui échoue puis réussit, par exemple).
actor MutableAuthState {
    var restored: AuthenticatedUser?
    var restoreError: Error?
    init(restored: AuthenticatedUser?, restoreError: Error?) { self.restored = restored; self.restoreError = restoreError }
    func set(restored: AuthenticatedUser?, restoreError: Error?) { self.restored = restored; self.restoreError = restoreError }
}

/// Émetteur d'événements d'auth pour les tests : `emit` pousse dans le flux `authEvents()`.
final class AuthEventEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<AuthEvent>.Continuation] = []

    func stream() -> AsyncStream<AuthEvent> {
        AsyncStream { continuation in
            lock.lock(); continuations.append(continuation); lock.unlock()
        }
    }

    func emit(_ event: AuthEvent) {
        lock.lock(); let targets = continuations; lock.unlock()
        targets.forEach { $0.yield(event) }
    }
}

struct FakeAuth: AuthPort {
    var restored: AuthenticatedUser?
    var restoreError: Error?
    var signInResult: Result<AuthenticatedUser, Error>
    var signOutError: Error?
    var signInGate: Gate?
    var log: CallLog
    var restoreGate: Gate? = nil
    /// Numéro du premier appel `restoreSession` bloqué par `restoreGate` (1 = dès le premier).
    var restoreGateFromCall = 1
    var mutable: MutableAuthState? = nil
    var events: AuthEventEmitter? = nil

    func restoreSession() async throws -> AuthenticatedUser? {
        await log.record("restoreSession")
        let appels = await log.entries.filter { $0 == "restoreSession" }.count
        if let restoreGate, appels >= restoreGateFromCall { await restoreGate.wait() }
        if let mutable {
            if let error = await mutable.restoreError { throw error }
            return await mutable.restored
        }
        if let restoreError { throw restoreError }
        return restored
    }

    func authEvents() -> AsyncStream<AuthEvent> {
        events?.stream() ?? AsyncStream { $0.finish() }
    }

    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        // Le port ne journalise jamais le mot de passe : seule sa longueur est connue du test.
        await log.record("signIn(email=\(email),passwordLength=\(password.count))")
        await log.signedIn()
        if let signInGate { await signInGate.wait() }
        return try signInResult.get()
    }

    func signOut() async throws {
        await log.record("signOut")
        await log.signedOut()
        if let signOutError { throw signOutError }
    }
}

struct FakeRole: RolePort {
    var result: Result<RoleResult, Error>
    var gate: Gate?
    var log: CallLog

    func currentRole() async throws -> RoleResult {
        await log.record("currentRole")
        if let gate { await gate.wait() }
        return try result.get()
    }
}

struct FakeMissions: MissionsPort {
    var profile: SoignantProfile?
    var profileError: Error?
    var gate: Gate?
    var log: CallLog

    func profile(userId: String) async throws -> SoignantProfile? {
        await log.record("profile(\(userId))")
        if let gate { await gate.wait() }
        if let profileError { throw profileError }
        return profile
    }

    func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
    func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
}

// MARK: - Fixtures

private let confirmedAt = Date(timeIntervalSince1970: 1_700_000_000)

private func user(_ id: String = "user-1", role: String? = "SOIGNANT", confirmed: Bool = true,
                  etablissementId: String? = nil) -> AuthenticatedUser {
    AuthenticatedUser(id: id, email: "\(id)@example.invalid", emailConfirmedAt: confirmed ? confirmedAt : nil,
                      appMetadataRole: role, appMetadataEtablissementId: etablissementId)
}

private func profile(_ id: String = "user-1") -> SoignantProfile {
    SoignantProfile(id: id, profession: "INFIRMIER", tousDocumentsValides: true)
}

private struct Fixture {
    var log = CallLog()
    var restored: AuthenticatedUser?
    var restoreError: Error?
    var signInResult: Result<AuthenticatedUser, Error> = .success(user())
    var signOutError: Error?
    var signInGate: Gate?
    var role: Result<RoleResult, Error> = .success(RoleResult(role: "SOIGNANT"))
    var roleGate: Gate?
    var profile: SoignantProfile? = JoleneCoreTests_profileDefault
    var profileError: Error?
    var profileGate: Gate?
    var restoreGate: Gate?
    var restoreGateFromCall = 1
    var mutable: MutableAuthState?
    var events: AuthEventEmitter?
    var timeout: TimeInterval = SessionController.defaultResolutionTimeout
    /// Lot 5 (T2a) : ports de l'espace établissement ; non câblés par défaut (un rôle établissement
    /// échoue alors à la confirmation du périmètre : jamais ouvert sans `fn_mes_permissions_etab`).
    var etablissement: EtablissementGateways = .nonCable

    func gateways() -> Gateways {
        var gateways = Gateways(
            auth: FakeAuth(restored: restored, restoreError: restoreError, signInResult: signInResult,
                           signOutError: signOutError, signInGate: signInGate, log: log,
                           restoreGate: restoreGate, restoreGateFromCall: restoreGateFromCall, mutable: mutable, events: events),
            role: FakeRole(result: role, gate: roleGate, log: log),
            missions: FakeMissions(profile: profile, profileError: profileError, gate: profileGate, log: log),
            clock: FixedClock(confirmedAt)
        )
        gateways.etablissement = etablissement
        return gateways
    }

    func controller() -> SessionController { SessionController(gateways: gateways(), resolutionTimeout: timeout) }
}

private let JoleneCoreTests_profileDefault = profile()

private struct FakeNetworkError: Error {}

// MARK: - Tests

final class SessionControllerTests: XCTestCase {

    func testIdleBeforeStart() async {
        let controller = Fixture().controller()
        let state = await controller.state
        XCTAssertEqual(state, .idle)
        let epoch = await controller.epoch
        XCTAssertEqual(epoch, 0)
    }

    func testEmptyRestoreYieldsSignedOutWithoutMessageAndWithoutEpochChange() async {
        var fixture = Fixture()
        fixture.restored = nil
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertEqual(state, .signedOut(message: nil))
        let epoch = await controller.epoch
        XCTAssertEqual(epoch, 0, "aucune identité n'a changé : l'epoch reste à 0")
        let entries = await fixture.log.entries
        XCTAssertEqual(entries, ["restoreSession"], "aucun appel rôle ni profil sans session")
        let gateways = await controller.gateways(for: 0)
        XCTAssertNotNil(gateways)
    }

    func testRestoreFailureKeepsSessionRecoverable() async {
        var fixture = Fixture()
        fixture.restoreError = FakeNetworkError()
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertEqual(state, .signedOut(message: SessionController.restoreFailedMessage))
        let retryable = await controller.canRetryRestore
        XCTAssertTrue(retryable, "le Keychain peut encore détenir une session : start() suffit, pas de mot de passe")
        let epoch = await controller.epoch
        XCTAssertEqual(epoch, 0)
    }

    func testRestoreRetryAfterTransientFailureNeedsNoPassword() async {
        let mutable = MutableAuthState(restored: nil, restoreError: FakeNetworkError())
        var fixture = Fixture()
        fixture.mutable = mutable
        let controller = fixture.controller()
        _ = await controller.start()
        await mutable.set(restored: user(), restoreError: nil)
        let state = await controller.start()
        XCTAssertTrue(state.isReady, "obtenu \(state)")
        let retryable = await controller.canRetryRestore
        XCTAssertFalse(retryable)
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains { $0.hasPrefix("signIn") }, "aucune saisie de mot de passe exigée")
    }

    // MARK: Revalidation (reprise après 30 minutes)

    func testRevalidationWithSameUserKeepsReadyWithoutLoading() async {
        let mutable = MutableAuthState(restored: user(), restoreError: nil)
        var fixture = Fixture()
        fixture.mutable = mutable
        let gate = Gate()
        let controller = fixture.controller()
        let first = await controller.start()
        XCTAssertTrue(first.isReady)
        let epoch = await controller.epoch

        // Restauration en vol : l'état observable reste .ready, jamais .loading.
        var blocked = Fixture()
        blocked.restored = user()
        blocked.restoreGate = gate
        blocked.restoreGateFromCall = 2 // la première restauration passe, la revalidation est bloquée
        let gatedController = blocked.controller()
        _ = await gatedController.start() // première identité
        let task = Task { await gatedController.start() } // revalidation, bloquée par la barrière
        let log = blocked.log
        await waitUntil { await log.entries.filter { $0 == "restoreSession" }.count == 2 }
        let during = await gatedController.state
        XCTAssertTrue(during.isReady, "pas de passage par .loading pendant la revalidation : obtenu \(during)")
        await gate.open()
        let after = await task.value
        XCTAssertTrue(after.isReady)

        // Même identité : epoch inchangé.
        let again = await controller.start()
        XCTAssertTrue(again.isReady)
        let sameEpoch = await controller.epoch
        XCTAssertEqual(sameEpoch, epoch)
    }

    func testRevalidationNetworkFailureKeepsReadyAndEpoch() async {
        let mutable = MutableAuthState(restored: user(), restoreError: nil)
        var fixture = Fixture()
        fixture.mutable = mutable
        let controller = fixture.controller()
        let first = await controller.start()
        XCTAssertTrue(first.isReady)
        let epoch = await controller.epoch
        await mutable.set(restored: nil, restoreError: FakeNetworkError())
        let state = await controller.start()
        XCTAssertEqual(state, first, "une restauration impossible (réseau) conserve la session prête")
        let sameEpoch = await controller.epoch
        XCTAssertEqual(sameEpoch, epoch)
        let gateways = await controller.gateways(for: epoch)
        XCTAssertNotNil(gateways)
        let retryable = await controller.canRetryRestore
        XCTAssertFalse(retryable)
    }

    func testRevalidationConfirmedAbsenceSignsOut() async {
        let mutable = MutableAuthState(restored: user(), restoreError: nil)
        var fixture = Fixture()
        fixture.mutable = mutable
        let controller = fixture.controller()
        _ = await controller.start()
        let epoch = await controller.epoch
        await mutable.set(restored: nil, restoreError: nil)
        let state = await controller.start()
        XCTAssertEqual(state, .signedOut(message: nil), "le port confirme l'absence de session : déconnexion")
        let newEpoch = await controller.epoch
        XCTAssertEqual(newEpoch, epoch + 1)
    }

    // MARK: Délai maximal

    func testRoleTimeoutWithoutAppMetadataSignsOutRecoverably() async {
        var fixture = Fixture()
        fixture.restored = user(role: nil)
        fixture.roleGate = Gate() // jamais ouverte : le backend ne répond pas
        fixture.timeout = 0.05
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertEqual(state, .signedOut(message: SessionController.sessionCheckFailedMessage))
        let epoch = await controller.epoch
        let gateways = await controller.gateways(for: epoch)
        XCTAssertNotNil(gateways, "l'epoch reste valide : aucune identité n'a changé")
    }

    func testRoleTimeoutWithAppMetadataFallsBackToSignedRole() async {
        var fixture = Fixture()
        fixture.restored = user(role: "SOIGNANT")
        fixture.roleGate = Gate()
        fixture.timeout = 0.05
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertTrue(state.isReady, "obtenu \(state)")
        XCTAssertEqual(state.snapshot?.role, RoleResult(role: "SOIGNANT"))
    }

    func testRestoreTimeoutIsRecoverable() async {
        var fixture = Fixture()
        fixture.restored = user()
        fixture.restoreGate = Gate()
        fixture.timeout = 0.05
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertEqual(state, .signedOut(message: SessionController.restoreFailedMessage))
        let retryable = await controller.canRetryRestore
        XCTAssertTrue(retryable)
    }

    // MARK: Événements d'auth du SDK

    func testSdkSignedOutDuringReadyInvalidatesEpochAndSignsOut() async {
        var fixture = Fixture()
        fixture.restored = user()
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertTrue(state.isReady)
        let before = await controller.epoch
        let after = await controller.handleAuthEvent(.signedOut)
        XCTAssertEqual(after, .signedOut(message: SessionController.sessionExpiredMessage))
        let stale = await controller.gateways(for: before)
        XCTAssertNil(stale, "l'ancien epoch ne sert plus aucune gateway")
        let current = await controller.epoch
        XCTAssertEqual(current, before + 1)
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains("signOut"), "le SDK a déjà effacé la session : aucun appel signOut")
    }

    func testSdkSignedOutWithoutActiveIdentityIsIgnored() async {
        var fixture = Fixture()
        fixture.restored = nil
        let controller = fixture.controller()
        _ = await controller.start()
        let state = await controller.handleAuthEvent(.signedOut)
        XCTAssertEqual(state, .signedOut(message: nil), "déconnexion volontaire déjà traitée : message inchangé")
        let epoch = await controller.epoch
        XCTAssertEqual(epoch, 0)
    }

    func testSdkSessionForOtherUserRestartsSession() async {
        let mutable = MutableAuthState(restored: user("user-1"), restoreError: nil)
        var fixture = Fixture()
        fixture.mutable = mutable
        let controller = fixture.controller()
        _ = await controller.start()
        let before = await controller.epoch
        await mutable.set(restored: user("user-2"), restoreError: nil)
        let state = await controller.handleAuthEvent(.session(userId: "user-2"))
        let after = await controller.epoch
        XCTAssertEqual(after, before + 1, "nouvelle identité côté SDK : frontière d'identité")
        XCTAssertNotEqual(state, .idle)
        let same = await controller.handleAuthEvent(.session(userId: "user-2"))
        let unchanged = await controller.epoch
        XCTAssertEqual(unchanged, after, "même identité : aucun redémarrage")
        XCTAssertEqual(same, state)
    }

    func testRestoredUserBumpsEpochAndResolvesToReady() async {
        var fixture = Fixture()
        fixture.restored = user()
        let controller = fixture.controller()
        let state = await controller.start()
        guard case let .ready(snapshot) = state else { return XCTFail("attendu ready, obtenu \(state)") }
        XCTAssertEqual(snapshot.user.id, "user-1")
        XCTAssertEqual(snapshot.role, RoleResult(role: "SOIGNANT"))
        XCTAssertEqual(snapshot.profile, profile())
        XCTAssertEqual(snapshot.context, MissionReadContext(userId: "user-1", email: "user-1@example.invalid", profile: profile()))
        XCTAssertEqual(snapshot.epoch, 1, "un utilisateur restauré est une nouvelle identité")
        let epoch = await controller.epoch
        XCTAssertEqual(epoch, 1)
        let entries = await fixture.log.entries
        XCTAssertEqual(entries, ["restoreSession", "currentRole", "profile(user-1)"])
    }

    func testRestartWithSameUserKeepsEpoch() async {
        var fixture = Fixture()
        fixture.restored = user()
        let controller = fixture.controller()
        _ = await controller.start()
        let first = await controller.epoch
        let again = await controller.start()
        XCTAssertTrue(again.isReady)
        let second = await controller.epoch
        XCTAssertEqual(first, second, "même utilisateur restauré : pas de frontière d'identité")
    }

    func testRestartWithDifferentUserBumpsEpoch() async {
        var fixture = Fixture()
        fixture.restored = user("user-1")
        let controller = fixture.controller()
        _ = await controller.start()
        let first = await controller.epoch
        // Un contrôleur neuf avec un autre utilisateur restauré sert ici de second cycle :
        // on vérifie la règle via signIn vers une identité différente, qui est le même chemin.
        fixture.signInResult = .success(user("user-2"))
        fixture.profile = profile("user-2")
        let controller2 = SessionController(gateways: fixture.gateways())
        _ = await controller2.start()
        let state = await controller2.signIn(email: "user-2@example.invalid", password: "secret-value")
        XCTAssertEqual(state.snapshot?.user.id, "user-2")
        let epoch2 = await controller2.epoch
        XCTAssertEqual(epoch2, first + 1)
    }

    func testSuccessfulSignInBumpsEpochAndNeverRetainsPassword() async {
        var fixture = Fixture()
        fixture.restored = nil
        let controller = fixture.controller()
        _ = await controller.start()
        let before = await controller.epoch
        let state = await controller.signIn(email: "  user-1@example.invalid  ", password: "p4ss-never-logged")
        guard case let .ready(snapshot) = state else { return XCTFail("attendu ready, obtenu \(state)") }
        let after = await controller.epoch
        XCTAssertEqual(after, before + 1)
        XCTAssertEqual(snapshot.epoch, after)
        let entries = await fixture.log.entries
        XCTAssertEqual(entries, ["restoreSession", "signIn(email=user-1@example.invalid,passwordLength=17)", "currentRole", "profile(user-1)"])
        // Le contrôleur n'expose le mot de passe nulle part : ni état, ni message.
        XCTAssertFalse(String(describing: state).contains("p4ss-never-logged"))
        let stale = await controller.gateways(for: before)
        XCTAssertNil(stale, "l'epoch précédant la connexion est périmé")
        let live = await controller.gateways(for: after)
        XCTAssertNotNil(live)
    }

    func testFailedSignInGivesGenericMessageWithoutEchoingInput() async {
        var fixture = Fixture()
        fixture.signInResult = .failure(JoleneError(.invalidCredentials, "Invalid login for user-1@example.invalid with password wrong-secret"))
        let controller = fixture.controller()
        _ = await controller.start()
        let state = await controller.signIn(email: "user-1@example.invalid", password: "wrong-secret")
        guard case let .signedOut(message) = state, let message else { return XCTFail("attendu signedOut avec message, obtenu \(state)") }
        XCTAssertEqual(message, SessionController.genericSignInMessage)
        XCTAssertFalse(message.contains("user-1@example.invalid"))
        XCTAssertFalse(message.contains("wrong-secret"))
        XCTAssertEqual(state.message, message)
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains { $0.contains("currentRole") }, "pas de résolution de rôle après un échec de connexion")
    }

    /// Changé volontairement au lot 5 (T2a, correction 11) : le lot 0 bloquait l'établissement. Le serveur
    /// gagne toujours, mais ouvre désormais l'espace établissement, confirmé par `fn_mes_permissions_etab`.
    func testServerRoleOverridesAppMetadataShortcut() async {
        var fixture = Fixture()
        fixture.restored = user(role: "SOIGNANT")
        fixture.role = .success(RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-9"))
        var etablissement = EtablissementGateways()
        etablissement.session = FakeEtabSession(etablissementId: "etab-9", log: fixture.log)
        fixture.etablissement = etablissement
        let controller = fixture.controller()
        let state = await controller.start()
        guard case let .readyEtablissement(snapshot) = state else {
            return XCTFail("app_metadata disait SOIGNANT, le serveur gagne : espace établissement attendu, obtenu \(state)")
        }
        XCTAssertEqual(snapshot.context.etablissementId, "etab-9")
        XCTAssertNil(state.snapshot, "aucun instantané soignant fabriqué")
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains { $0.hasPrefix("profile(") }, "aucun chargement de profil soignant pour un établissement")
    }

    func testServerRoleUpgradesStaleAppMetadata() async {
        var fixture = Fixture()
        fixture.restored = user(role: "ETABLISSEMENT")
        fixture.role = .success(RoleResult(role: "SOIGNANT"))
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertTrue(state.isReady, "app_metadata périmé, le serveur confirme SOIGNANT : \(state)")
        XCTAssertEqual(state.snapshot?.role.role, "SOIGNANT")
    }

    func testServerUnavailableFallsBackToSignedAppMetadata() async {
        var fixture = Fixture()
        fixture.restored = user(role: "SOIGNANT")
        fixture.role = .failure(FakeNetworkError())
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertTrue(state.isReady, "le raccourci signé suffit quand la RPC est indisponible : \(state)")
        XCTAssertEqual(state.snapshot?.role, RoleResult(role: "SOIGNANT"))
    }

    func testServerUnavailableWithoutAppMetadataIsNotTreatedAsUnsupportedRole() async {
        var fixture = Fixture()
        fixture.restored = user(role: nil)
        fixture.role = .failure(FakeNetworkError())
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertEqual(state, .signedOut(message: SessionController.sessionCheckFailedMessage))
        let signOuts = await fixture.log.signOutCount
        XCTAssertEqual(signOuts, 0, "une panne réseau ne purge pas la session persistée")
    }

    func testUnconfirmedEmailIsBlockedWithoutNetwork() async {
        var fixture = Fixture()
        fixture.restored = user(confirmed: false)
        let controller = fixture.controller()
        let state = await controller.start()
        XCTAssertEqual(state, .blocked(.emailUnconfirmed))
        XCTAssertEqual(state.message, MobileAccess.emailUnconfirmed.message)
        let entries = await fixture.log.entries
        XCTAssertEqual(entries, ["restoreSession"])
    }

    /// Changé volontairement au lot 5 (T2a, correction 11) : `ADMIN_ETABLISSEMENT` est servi
    /// (`SessionControllerEtablissementTests`) ; seuls les rôles d'administration restent bloqués.
    func testNonSoignantRoleIsBlocked() async {
        for raw in ["ADMIN_PLATEFORME", "ADMIN_GROUPE"] {
            var fixture = Fixture()
            fixture.restored = user(role: raw)
            fixture.role = .success(RoleResult(role: raw))
            let state = await fixture.controller().start()
            XCTAssertEqual(state, .blocked(.unsupportedRole(raw)))
        }
    }

    func testUnknownRoleIsBlockedWithNil() async {
        var fixture = Fixture()
        fixture.restored = user(role: nil)
        fixture.role = .success(RoleResult(role: "INCONNU"))
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(nil)))
    }

    func testMissingProfileIsBlockedAsProfilIncomplet() async {
        var fixture = Fixture()
        fixture.restored = user()
        fixture.profile = nil
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .blocked(.unsupportedRole(SessionState.profilIncompletCode)))
        let message = state.message ?? ""
        XCTAssertTrue(message.contains("profil soignant"), "message adapté attendu, obtenu : \(message)")
        XCTAssertNotEqual(message, MobileAccess.unsupportedRole("X").message)
    }

    func testProfileLoadFailureDoesNotPurgeSession() async {
        var fixture = Fixture()
        fixture.restored = user()
        fixture.profileError = FakeNetworkError()
        let state = await fixture.controller().start()
        XCTAssertEqual(state, .signedOut(message: SessionController.profileLoadFailedMessage))
        let signOuts = await fixture.log.signOutCount
        XCTAssertEqual(signOuts, 0)
    }

    func testStaleRoleResponseIsIgnoredAfterSignOut() async {
        var fixture = Fixture()
        fixture.restored = user()
        let gate = Gate()
        fixture.roleGate = gate
        let controller = fixture.controller()

        let log = fixture.log
        let startTask = Task { await controller.start() }
        // La résolution de rôle est en vol (bloquée par la barrière) : on déconnecte.
        await waitUntil { await log.entries.contains("currentRole") }
        let startEpoch = await controller.epoch
        XCTAssertEqual(startEpoch, 1)
        let signedOut = await controller.signOut()
        XCTAssertEqual(signedOut, .signedOut(message: nil))
        let epochAfterSignOut = await controller.epoch
        XCTAssertEqual(epochAfterSignOut, 2)

        // La réponse réseau arrive pour l'epoch 1, périmé : elle doit être jetée.
        await gate.open()
        let startResult = await startTask.value
        XCTAssertEqual(startResult, .signedOut(message: nil), "le start périmé renvoie l'état courant, pas ready")
        let finalState = await controller.state
        XCTAssertEqual(finalState, .signedOut(message: nil))
        let stale = await controller.gateways(for: 1)
        XCTAssertNil(stale)
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains("profile(user-1)"), "aucun chargement de profil pour un epoch périmé")
    }

    func testStaleProfileResponseCannotOverwriteNewerIdentity() async {
        var fixture = Fixture()
        fixture.restored = user("user-1")
        let gate = Gate()
        fixture.profileGate = gate
        let controller = fixture.controller()

        let log = fixture.log
        let startTask = Task { await controller.start() }
        await waitUntil { await log.entries.contains("profile(user-1)") }

        // Nouvelle identité pendant que le profil de user-1 est en vol.
        fixture.signInResult = .success(user("user-2"))
        fixture.profile = profile("user-2")
        // Les ports du contrôleur sont figés : on ouvre la barrière après la
        // déconnexion pour simuler la réponse tardive de user-1.
        let signedOut = await controller.signOut()
        XCTAssertEqual(signedOut, .signedOut(message: nil))
        await gate.open()
        let late = await startTask.value
        XCTAssertEqual(late, .signedOut(message: nil))
        let state = await controller.state
        XCTAssertEqual(state, .signedOut(message: nil), "le profil tardif de user-1 n'a pas ressuscité la session")
    }

    func testSignOutInvalidatesEpochEvenWhenRemoteRevocationFails() async {
        var fixture = Fixture()
        fixture.restored = user()
        fixture.signOutError = FakeNetworkError()
        let controller = fixture.controller()
        let ready = await controller.start()
        XCTAssertTrue(ready.isReady)
        let readyEpoch = await controller.epoch
        let state = await controller.signOut()
        XCTAssertEqual(state, .signedOut(message: nil))
        let stored = await controller.state
        XCTAssertEqual(stored, .signedOut(message: nil))
        let stale = await controller.gateways(for: readyEpoch)
        XCTAssertNil(stale, "l'epoch de la session fermée est invalidé")
        let epoch = await controller.epoch
        XCTAssertEqual(epoch, readyEpoch + 1)
        let signOuts = await fixture.log.signOutCount
        XCTAssertEqual(signOuts, 1)
    }

    func testSignOutDuringPendingSignInDiscardsLateSuccess() async {
        var fixture = Fixture()
        let gate = Gate()
        fixture.signInGate = gate
        let controller = fixture.controller()
        _ = await controller.start()
        let log = fixture.log
        let signInTask = Task { await controller.signIn(email: "user-1@example.invalid", password: "late-secret") }
        await waitUntil { await log.signInCount == 1 }
        let signedOut = await controller.signOut()
        XCTAssertEqual(signedOut, .signedOut(message: nil))
        await gate.open()
        let late = await signInTask.value
        XCTAssertEqual(late, .signedOut(message: nil), "la connexion tardive est ignorée")
        let entries = await fixture.log.entries
        XCTAssertFalse(entries.contains("currentRole"), "aucune résolution pour une connexion périmée")
    }

    // MARK: - RoleResolution (règles pures)

    func testNormalizeMatchesWebNormaliserRole() {
        XCTAssertEqual(RoleResolution.normalize("SOIGNANT"), "SOIGNANT")
        XCTAssertEqual(RoleResolution.normalize("ETABLISSEMENT"), "ADMIN_ETABLISSEMENT")
        XCTAssertEqual(RoleResolution.normalize("ADMIN_ETABLISSEMENT"), "ADMIN_ETABLISSEMENT")
        XCTAssertEqual(RoleResolution.normalize("ADMIN"), "ADMIN_PLATEFORME")
        XCTAssertEqual(RoleResolution.normalize("ADMIN_PLATEFORME"), "ADMIN_PLATEFORME")
        XCTAssertEqual(RoleResolution.normalize("ADMIN_GROUPE"), "ADMIN_GROUPE")
        XCTAssertNil(RoleResolution.normalize("INCONNU"))
        XCTAssertNil(RoleResolution.normalize("soignant"))
        XCTAssertNil(RoleResolution.normalize(nil))
    }

    func testLegacyEtablissementScopeFallsBackToUserId() {
        let legacy = user("etab-user", role: "ETABLISSEMENT")
        let resolved = RoleResolution.resolve(server: RoleResult(role: "ADMIN_ETABLISSEMENT"), user: legacy)
        XCTAssertEqual(resolved, RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-user"))

        let scoped = RoleResolution.resolve(server: RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-42"), user: legacy)
        XCTAssertEqual(scoped?.etablissementId, "etab-42", "un scope serveur explicite prime sur le repli")

        let modern = user("u", role: "ADMIN_ETABLISSEMENT")
        let noFallback = RoleResolution.resolve(server: RoleResult(role: "ADMIN_ETABLISSEMENT"), user: modern)
        XCTAssertNil(noFallback?.etablissementId, "le repli est borné à l'alias signé ETABLISSEMENT")
    }

    func testProvisionalRoleCarriesAppMetadataScope() {
        let provisional = RoleResolution.provisional(from: user("u", role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1"))
        XCTAssertEqual(provisional, RoleResult(role: "ADMIN_ETABLISSEMENT", etablissementId: "etab-1"))
        XCTAssertNil(RoleResolution.provisional(from: user("u", role: nil)))
    }
}

/// Attente active bornée (200 x 5 ms) sur une condition asynchrone.
func waitUntil(_ condition: @Sendable () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("condition non atteinte dans le délai", file: file, line: line)
}
