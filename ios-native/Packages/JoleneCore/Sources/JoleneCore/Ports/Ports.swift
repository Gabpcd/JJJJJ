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

    public init(auth: AuthPort, role: RolePort, missions: MissionsPort, clock: ClockPort = SystemClock()) {
        self.auth = auth; self.role = role; self.missions = missions; self.clock = clock
    }
}
