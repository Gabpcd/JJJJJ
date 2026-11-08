import Foundation

/// Erreurs métier présentées à l'utilisateur. Le message est en français et ne
/// contient jamais de valeur saisie ni de détail technique.
public struct JoleneError: Error, Equatable, Sendable, LocalizedError {
    public enum Kind: Equatable, Sendable {
        case network, unauthorized, invalidCredentials, cancelled, contract, environment, demoOnly, unknown
    }
    public var kind: Kind
    public var message: String
    public init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
    public var errorDescription: String? { message }
}

public protocol ClockPort: Sendable {
    func now() -> Date
}

public struct SystemClock: ClockPort {
    public init() {}
    public func now() -> Date { Date() }
}

public struct FixedClock: ClockPort {
    public let fixed: Date
    public init(_ fixed: Date) { self.fixed = fixed }
    public func now() -> Date { fixed }
}

/// Événement d'authentification émis par le SDK hors de tout appel de l'app
/// (révocation, déconnexion globale depuis le web, rotation de refresh token).
public enum AuthEvent: Equatable, Sendable {
    /// La session locale a été effacée : plus aucune identité côté SDK.
    case signedOut
    /// Une session est présente pour cet utilisateur (connexion, restauration, rafraîchissement).
    case session(userId: String)
}

/// Authentification email + mot de passe et session persistée (Keychain côté implémentation).
public protocol AuthPort: Sendable {
    func restoreSession() async throws -> AuthenticatedUser?
    func signIn(email: String, password: String) async throws -> AuthenticatedUser
    func signOut() async throws
    /// Flux des événements d'auth du SDK (`onAuthStateChange`). Implémentation par défaut :
    /// flux vide et terminé, pour les ports sans événement (démo, doubles de test).
    func authEvents() -> AsyncStream<AuthEvent>
}

public extension AuthPort {
    func authEvents() -> AsyncStream<AuthEvent> {
        AsyncStream { $0.finish() }
    }
}

/// Résolution du rôle via `fn_get_my_role` (raccourci `app_metadata` géré par le contrôleur de session).
public protocol RolePort: Sendable {
    func currentRole() async throws -> RoleResult
}

/// Lecture des missions du parcours soignant. Aucune écriture dans ce port au lot 0.
public protocol MissionsPort: Sendable {
    func profile(userId: String) async throws -> SoignantProfile?
    func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission]
    func mission(id: String, context: MissionReadContext) async throws -> Mission?
}

/// Un jeu complet de ports pour un mode d'exécution (démo, staging, production).
public struct Gateways: Sendable {
    public var auth: AuthPort
    public var role: RolePort
    public var missions: MissionsPort
    public var clock: ClockPort

    // Lot 1 — ajout additif (PRINCIPES §2) : Swift interdit les propriétés stockées en
    // extension, les ports du lot 1 sont donc déclarés ici, chacun « non câblé » par défaut
    // (`Ports/Lot1Ports.swift`) : il refuse explicitement tant que sa tranche ne l'a pas livré.
    // L'init du lot 0 ci-dessous est conservé tel quel ; `unwiredPorts` nomme les ports encore
    // stubs pour que chaque monde (démo, Supabase) prouve son câblage par test.
    public var dashboard: DashboardPort = UnwiredDashboardPort()
    public var candidature: CandidaturePort = UnwiredCandidaturePort()
    public var presence: PresencePort = UnwiredPresencePort()
    public var favoris: FavorisPort = UnwiredFavorisPort()
    public var mesMissions: MesMissionsPort = UnwiredMesMissionsPort()
    public var compte: AccountPort = UnwiredAccountPort()
    public var audit: AuditPort = UnwiredAuditPort()
    public var flags: FlagsPort = UnwiredFlagsPort()
    public var recovery: RecoveryPort = UnwiredRecoveryPort()
    public var justificatifs: JustificatifStoragePort = UnwiredJustificatifStoragePort()

    // Lot 2 — ajout additif (PRINCIPES §2, blueprint `LOT2_PLAN.md` §2.2) : même règle que le lot 1,
    // stubs dans `Ports/Lot2Ports.swift` (message : « …livré par la tranche Tn du lot 2 »). Pas de
    // troisième init : chaque monde assigne ces ports après l'init complet du lot 1, dans sa fonction
    // `câblerLot2(_:)` (`DemoWorld`, `SupabaseGateways`) ; liste attendue `DemoWorldTests.portsEnAttenteLot2`.
    public var pointage: PointagePort = UnwiredPointagePort()                 // T3
    public var contestation: ContestationPort = UnwiredContestationPort()     // T5b
    public var notation: NotationPort = UnwiredNotationPort()                 // T5a
    public var documents: DocumentsPort = UnwiredDocumentsPort()              // T6
    public var contrats: ContratsPort = UnwiredContratsPort()                 // T8

    public init(auth: AuthPort, role: RolePort, missions: MissionsPort, clock: ClockPort = SystemClock()) {
        self.auth = auth; self.role = role; self.missions = missions; self.clock = clock
    }

    /// Jeu complet du lot 1 : chaque port est nommé, aucun défaut implicite (un port encore
    /// livré par sa tranche est passé explicitement en `Unwired…`).
    public init(auth: AuthPort, role: RolePort, missions: MissionsPort, clock: ClockPort,
                dashboard: DashboardPort, candidature: CandidaturePort, presence: PresencePort,
                favoris: FavorisPort, mesMissions: MesMissionsPort, compte: AccountPort,
                audit: AuditPort, flags: FlagsPort, recovery: RecoveryPort, justificatifs: JustificatifStoragePort) {
        self.init(auth: auth, role: role, missions: missions, clock: clock)
        self.dashboard = dashboard; self.candidature = candidature; self.presence = presence
        self.favoris = favoris; self.mesMissions = mesMissions; self.compte = compte
        self.audit = audit; self.flags = flags; self.recovery = recovery; self.justificatifs = justificatifs
    }

    /// Noms des champs du lot 1, puis du lot 2, encore servis par un stub « non câblé », dans
    /// l'ordre de déclaration. Vide pour un monde complet.
    public var unwiredPorts: [String] {
        let ports: [(nom: String, port: Any)] = [
            ("dashboard", dashboard), ("candidature", candidature), ("presence", presence),
            ("favoris", favoris), ("mesMissions", mesMissions), ("compte", compte),
            ("audit", audit), ("flags", flags), ("recovery", recovery), ("justificatifs", justificatifs),
            // Lot 2
            ("pointage", pointage), ("contestation", contestation), ("notation", notation),
            ("documents", documents), ("contrats", contrats),
        ]
        return ports.filter { $0.port is UnwiredPort }.map(\.nom)
    }
}
