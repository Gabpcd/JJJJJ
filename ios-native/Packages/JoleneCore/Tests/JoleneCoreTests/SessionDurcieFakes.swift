import Foundation
@testable import JoleneCore

// Doubles de la tranche T9 (session durcie : audit, biométrie, drapeaux). Fichier propre à la
// tranche pour ne pas allonger `Lot1Fakes.swift`, que les tranches parallèles complètent aussi.
// Les doubles du lot 0 (`Gate`, `AuthEventEmitter`) et `AuditJournal` (`Lot1Fakes.swift`) sont
// réutilisés tels quels.

// MARK: - Auth journalisée

/// Session persistée du double d'auth : remplie par `signIn`, vidée par `signOut`.
actor JournalAuthState {
    private(set) var session: AuthenticatedUser?
    init(session: AuthenticatedUser?) { self.session = session }
    func set(_ user: AuthenticatedUser?) { session = user }
}

/// Auth qui écrit dans le même journal que l'audit : l'ordre « audit de déconnexion puis
/// révocation » se lit dans une seule liste. `restoreSession` / `signOut` journalisés = accès à la
/// session persistée (Keychain côté Supabase).
struct JournalAuth: AuthPort {
    let journal: AuditJournal
    let state: JournalAuthState
    /// Utilisateur rendu par `signIn` ; nil = identifiants refusés.
    var signInUser: AuthenticatedUser?
    var events: AuthEventEmitter? = nil

    func restoreSession() async throws -> AuthenticatedUser? {
        await journal.record("restoreSession")
        return await state.session
    }

    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        await journal.record("signIn")
        guard let signInUser else { throw JoleneError(.invalidCredentials, "refusé") }
        await state.set(signInUser)
        return signInUser
    }

    func signOut() async throws {
        await journal.record("signOut")
        await state.set(nil)
    }

    func authEvents() -> AsyncStream<AuthEvent> { events?.stream() ?? AsyncStream { $0.finish() } }
}

struct FixedRolePort: RolePort {
    var role: String = UserRole.soignant.rawValue
    func currentRole() async throws -> RoleResult { RoleResult(role: role) }
}

struct ProfilePort: MissionsPort {
    var sansProfil = false
    func profile(userId: String) async throws -> SoignantProfile? {
        sansProfil ? nil : SoignantProfile(id: userId, profession: "IDE")
    }
    func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
    func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
}

// MARK: - Audit scripté

/// Audit qui écrit `audit:<action>` dans le journal partagé ; erreur et barrière optionnelles.
struct ScriptedAudit: AuditPort {
    let journal: AuditJournal
    var erreur: JoleneError? = nil
    var gate: Gate? = nil

    func connexion() async throws -> AuditResultat { try await trace("audit:connexion") }
    func deconnexion() async throws -> AuditResultat { try await trace("audit:deconnexion") }
    func activite() async throws -> AuditResultat { try await trace("audit:activite") }
    func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                context: MissionReadContext) async throws -> AuditResultat {
        try await trace("audit:\(action.rawValue)")
    }

    private func trace(_ entry: String) async throws -> AuditResultat {
        await journal.record(entry)
        if let gate { await gate.wait() }
        if let erreur { throw erreur }
        return .enregistre
    }
}

// MARK: - Drapeaux scriptés

/// Valeurs de `parametres_systeme` vues par le double, modifiables entre deux lectures.
actor FlagScript {
    private var valeurs: [String: Bool]
    /// Appels reçus, avant toute barrière ; `lectures` : appels servis.
    private(set) var demandes: [String] = []
    private(set) var lectures: [String] = []
    init(_ valeurs: [String: Bool] = [:]) { self.valeurs = valeurs }
    func set(_ cle: String, _ valeur: Bool?) { valeurs[cle] = valeur }
    func demander(_ cle: String) { demandes.append(cle) }
    func lire(_ cle: String, defaut: Bool) -> Bool {
        lectures.append(cle)
        return valeurs[cle] ?? defaut
    }
}

struct ScriptedFlags: FlagsPort {
    let script: FlagScript
    var gate: Gate? = nil
    func ecranActif(cle: String, defaut: Bool) async -> Bool {
        await script.demander(cle)
        if let gate { await gate.wait() }
        return await script.lire(cle, defaut: defaut)
    }
}

// MARK: - Biométrie scriptée

/// Disponibilité et issues de `LAContext` vues par le double ; chaque appel est compté.
actor BiometricScript {
    private var disponibilite: BiometricAvailability
    private var issues: [BiometricResult]
    private(set) var raisons: [String] = []
    private(set) var verificationsDisponibilite = 0

    init(availability: BiometricAvailability = .available(.faceID), results: [BiometricResult] = [.success]) {
        self.disponibilite = availability
        self.issues = results
    }

    func set(availability: BiometricAvailability) { disponibilite = availability }
    func set(results: [BiometricResult]) { issues = results }

    func availability() -> BiometricAvailability {
        verificationsDisponibilite += 1
        return disponibilite
    }

    /// Issues consommées dans l'ordre ; la dernière se répète.
    func next(reason: String) -> BiometricResult {
        raisons.append(reason)
        guard let premiere = issues.first else { return .failed }
        if issues.count > 1 { issues.removeFirst() }
        return premiere
    }
}

struct FakeBiometrics: BiometricPort {
    let script: BiometricScript
    var gate: Gate? = nil
    func availability() async -> BiometricAvailability { await script.availability() }
    func authenticate(reason: String) async -> BiometricResult {
        if let gate { await gate.wait() }
        return await script.next(reason: reason)
    }
}

// MARK: - Monde de session

let soignantDurci = AuthenticatedUser(id: "soignant-t9", email: "t9@example.invalid",
                                      emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                      appMetadataRole: UserRole.soignant.rawValue)

/// Jeu de ports de session pour les tests T9 : auth, rôle et profil réels pour le contrôleur, audit
/// et drapeaux injectés, journal partagé.
struct SessionDurcieMonde {
    var journal = AuditJournal()
    var restored: AuthenticatedUser? = nil
    var signInUser: AuthenticatedUser? = soignantDurci
    var role: String = UserRole.soignant.rawValue
    var sansProfil = false
    var audit: AuditPort? = nil
    var flags: FlagsPort = FakeFlags()
    var events: AuthEventEmitter? = nil
    var timeout: TimeInterval = SessionController.defaultResolutionTimeout
    var authState: JournalAuthState

    init(restored: AuthenticatedUser? = nil) {
        self.restored = restored
        self.authState = JournalAuthState(session: restored)
    }

    func gateways() -> Gateways {
        var gateways = Gateways(auth: JournalAuth(journal: journal, state: authState, signInUser: signInUser, events: events),
                                role: FixedRolePort(role: role), missions: ProfilePort(sansProfil: sansProfil),
                                clock: FixedClock(Date(timeIntervalSince1970: 1_793_577_600)))
        gateways.audit = audit ?? ScriptedAudit(journal: journal)
        gateways.flags = flags
        return gateways
    }

    @MainActor
    func store(biometrie: BiometricGate = .inactif) -> SessionStore {
        SessionStore(controller: SessionController(gateways: gateways(), resolutionTimeout: timeout), biometrie: biometrie)
    }
}

extension AuditJournal {
    /// Entrées d'audit seules (sans les accès à la session).
    func audits() -> [String] { entries.filter { $0.hasPrefix("audit:") } }
}
