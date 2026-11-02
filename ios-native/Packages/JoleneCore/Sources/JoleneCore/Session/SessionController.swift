import Foundation

/// Contrôleur de session à epoch (plan §4.1, §4.3), porté de
/// `mobile-native/src/session/controller.ts`.
///
/// L'epoch change à chaque frontière d'identité : connexion, déconnexion,
/// restauration d'un utilisateur différent, session effacée par le SDK. Toute
/// réponse réseau reçue pour un epoch périmé est ignorée, et `gateways(for:)`
/// refuse de servir un epoch périmé, ce qui invalide d'un coup tous les caches
/// construits sur l'ancienne identité.
///
/// Chaque appel de port est borné par `resolutionTimeout` (15 s par défaut, comme
/// le pilote) : un backend muet ne laisse jamais l'écran de chargement sans issue.
///
/// Le mot de passe traverse `signIn` sans être conservé ni journalisé ; aucun
/// message d'état ne reprend une valeur saisie.
public actor SessionController {
    public static let genericSignInMessage = "Vérifiez votre adresse email et votre mot de passe, puis réessayez."
    public static let sessionCheckFailedMessage = "Impossible de vérifier votre accès. Vérifiez votre connexion puis réessayez."
    public static let profileLoadFailedMessage = "Impossible de charger votre profil. Vérifiez votre connexion puis réessayez."
    public static let restoreFailedMessage = "Votre session n'a pas pu être restaurée. Vous pouvez vous reconnecter."
    public static let sessionExpiredMessage = "Votre session a expiré. Reconnectez-vous."
    public static let timeoutMessage = "Le service ne répond pas. Vérifiez votre connexion puis réessayez."
    /// Délai maximal par appel de port (restauration, rôle, profil), identique au pilote (15 s).
    public static let defaultResolutionTimeout: TimeInterval = 15

    private let configured: Gateways
    /// Délai de chaque appel de port. Public et `nonisolated` (lot 1) : les modèles d'écran
    /// bornent leurs lectures et mutations au même délai via `bounded(timeout:_:)`.
    public nonisolated let resolutionTimeout: TimeInterval
    private var currentEpoch = 0
    private var currentState: SessionState = .idle
    private var activeUserId: String?
    /// Vrai quand la dernière restauration a échoué pour une cause transitoire (réseau,
    /// délai) alors que le SDK peut encore détenir une session : un nouvel appel à
    /// `start()` suffit, aucun mot de passe n'est requis.
    private var restoreRetryable = false

    public init(gateways: Gateways, resolutionTimeout: TimeInterval = SessionController.defaultResolutionTimeout) {
        self.configured = gateways
        self.resolutionTimeout = resolutionTimeout
    }

    public var state: SessionState { currentState }

    public var epoch: Int { currentEpoch }

    /// Vrai après un `start()` dont la restauration a échoué de façon transitoire.
    public var canRetryRestore: Bool { restoreRetryable }

    /// Ports utilisables pour un epoch donné, ou nil si cet epoch est périmé.
    /// Un appelant qui obtient nil abandonne son travail : son identité a changé.
    public func gateways(for epoch: Int) -> Gateways? {
        epoch == currentEpoch ? configured : nil
    }

    /// Flux des événements d'auth du port (`AuthPort.authEvents`), à relier à `handleAuthEvent`.
    public nonisolated func authEvents() -> AsyncStream<AuthEvent> {
        configured.auth.authEvents()
    }

    /// Restaure la session persistée puis résout rôle et profil.
    ///
    /// Revalidation (identité déjà active et état `.ready`, reprise après 30 minutes) :
    /// l'état courant est conservé pendant la vérification (pas de passage par `.loading`,
    /// `MainTabView` n'est pas démonté) et une erreur transitoire (réseau, délai) le laisse
    /// intact. Seule une absence de session confirmée par le port, ou une réponse serveur
    /// (rôle, profil) change l'état.
    public func start() async -> SessionState {
        let startedAt = currentEpoch
        let revalidating = activeUserId != nil && currentState.isReady
        if !revalidating { currentState = .loading }
        restoreRetryable = false
        let auth = configured.auth
        let restored: AuthenticatedUser?
        do {
            restored = try await bounded(timeout: resolutionTimeout) { try await auth.restoreSession() }
        } catch {
            guard startedAt == currentEpoch else { return currentState }
            if revalidating { return currentState }
            restoreRetryable = true
            currentState = .signedOut(message: Self.restoreFailedMessage)
            return currentState
        }
        guard startedAt == currentEpoch else { return currentState }
        guard let user = restored else {
            if activeUserId != nil { bumpEpoch() }
            activeUserId = nil
            currentState = .signedOut(message: nil)
            return currentState
        }
        let sameIdentity = user.id == activeUserId
        if !sameIdentity { bumpEpoch() }
        activeUserId = user.id
        return await resolveAndStore(user: user, quiet: revalidating && sameIdentity)
    }

    /// Connexion email + mot de passe. Le mot de passe n'est ni stocké ni journalisé.
    public func signIn(email: String, password: String) async -> SessionState {
        bumpEpoch()
        activeUserId = nil
        restoreRetryable = false
        currentState = .loading
        let signedInAt = currentEpoch
        let auth = configured.auth
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let user: AuthenticatedUser
        do {
            user = try await bounded(timeout: resolutionTimeout) { try await auth.signIn(email: trimmedEmail, password: password) }
        } catch {
            guard signedInAt == currentEpoch else { return currentState }
            currentState = .signedOut(message: Self.signInMessage(for: error))
            return currentState
        }
        guard signedInAt == currentEpoch else { return currentState }
        activeUserId = user.id
        return await resolveAndStore(user: user, quiet: false)
    }

    /// Déconnexion : l'écran bascule immédiatement, l'epoch avance avant même
    /// l'appel réseau, et une révocation distante indisponible ne bloque pas.
    public func signOut() async -> SessionState {
        bumpEpoch()
        activeUserId = nil
        restoreRetryable = false
        currentState = .signedOut(message: nil)
        let signedOutAt = currentEpoch
        do {
            try await configured.auth.signOut()
        } catch {
            // Le port est responsable de l'effacement local (Keychain) ; une erreur
            // de révocation distante ne doit pas ressusciter l'identité.
        }
        guard signedOutAt == currentEpoch else { return currentState }
        return currentState
    }

    /// Fin de session locale après la suppression du compte (lot 1, T8) : comme `signOut()`, l'identité
    /// est retirée (epoch avancé, état `.signedOut(nil)`) AVANT la purge, si bien que l'événement
    /// `.signedOut` que le SDK émet ensuite est ignoré par `handleAuthEvent` : jamais « Votre session a
    /// expiré » après une suppression. La purge passe par `AuthPort.signOutLocally()`, sans révocation
    /// globale (l'edge `delete-account` a déjà révoqué les sessions), bornée à `resolutionTimeout` et
    /// tolérée en échec (le port retire la session locale avant tout appel réseau).
    public func signOutLocally() async -> SessionState {
        bumpEpoch()
        activeUserId = nil
        restoreRetryable = false
        currentState = .signedOut(message: nil)
        let signedOutAt = currentEpoch
        let auth = configured.auth
        _ = try? await bounded(timeout: resolutionTimeout) { await auth.signOutLocally() }
        guard signedOutAt == currentEpoch else { return currentState }
        return currentState
    }

    /// Verrou biométrique refusé (lot 1, T9, décision 1 ; `BiometricGate`) : l'espace se ferme sans
    /// qu'aucun port ne soit appelé — ni `restoreSession`, ni `signOut` : la session persistée
    /// (Keychain) reste intacte. Une identité active (reprise après 30 minutes) est retirée (epoch
    /// avancé, caches invalidés) ; `canRetryRestore` devient vrai : « Réessayer sans mot de passe »
    /// relance `start()`, donc le verrou. Une connexion par mot de passe reste possible.
    public func lockForBiometrics() -> SessionState {
        if activeUserId != nil { bumpEpoch() }
        activeUserId = nil
        restoreRetryable = true
        currentState = .signedOut(message: nil)
        return currentState
    }

    /// Événement d'auth reçu du SDK hors de tout appel de l'app.
    /// - `.signedOut` pendant qu'une identité est active (session révoquée, déconnexion
    ///   globale depuis le web, refresh refusé) : l'epoch avance, tous les caches sont
    ///   invalidés et l'écran de connexion s'affiche avec un message générique.
    ///   Ignoré sans identité active (déconnexion volontaire déjà traitée, connexion en vol).
    /// - `.session(userId)` pour un autre utilisateur que l'identité active : `start()`
    ///   relit la session. Ignoré pendant une opération (`.loading`) ou sans identité.
    public func handleAuthEvent(_ event: AuthEvent) async -> SessionState {
        switch event {
        case .signedOut:
            guard activeUserId != nil else { return currentState }
            bumpEpoch()
            activeUserId = nil
            restoreRetryable = false
            currentState = .signedOut(message: Self.sessionExpiredMessage)
            return currentState
        case let .session(userId):
            guard let active = activeUserId, active != userId, currentState != .loading else { return currentState }
            return await start()
        }
    }

    // MARK: - Résolution

    private func bumpEpoch() {
        currentEpoch += 1
    }

    private func resolveAndStore(user: AuthenticatedUser, quiet: Bool) async -> SessionState {
        let epochAtStart = currentEpoch
        if !quiet { currentState = .loading }
        if let resolved = await resolve(user: user, epoch: epochAtStart, quiet: quiet), epochAtStart == currentEpoch {
            currentState = resolved
        }
        return currentState
    }

    /// Résout rôle puis profil pour `epoch`. Retourne nil dès que l'epoch est
    /// périmé, ou, en revalidation silencieuse (`quiet`), sur une erreur transitoire :
    /// l'état courant est alors conservé par l'appelant.
    private func resolve(user: AuthenticatedUser, epoch expected: Int, quiet: Bool) async -> SessionState? {
        guard let gateways = gateways(for: expected) else { return nil }

        // 1. Email non confirmé : aucun appel réseau nécessaire.
        if user.emailConfirmedAt == nil {
            return .blocked(.emailUnconfirmed)
        }

        // 2. Rôle : raccourci app_metadata, puis confirmation serveur (le serveur gagne).
        let provisional = RoleResolution.provisional(from: user)
        let rolePort = gateways.role
        var serverRole: RoleResult?
        do {
            serverRole = try await bounded(timeout: resolutionTimeout) { try await rolePort.currentRole() }
        } catch {
            guard currentEpoch == expected else { return nil }
            if provisional == nil {
                return quiet ? nil : .signedOut(message: Self.sessionCheckFailedMessage)
            }
        }
        guard currentEpoch == expected else { return nil }
        let role = RoleResolution.resolve(server: serverRole, user: user)

        switch MobileAccess.validate(user: user, role: role?.role) {
        case .allowed: break
        case let access: return .blocked(access)
        }
        guard let role else { return .blocked(.unsupportedRole(nil)) }

        // 3. Profil soignant : absent signifie inscription non terminée.
        let missionsPort = gateways.missions
        let userId = user.id
        let profile: SoignantProfile?
        do {
            profile = try await bounded(timeout: resolutionTimeout) { try await missionsPort.profile(userId: userId) }
        } catch {
            guard currentEpoch == expected else { return nil }
            return quiet ? nil : .signedOut(message: Self.profileLoadFailedMessage)
        }
        guard currentEpoch == expected else { return nil }
        guard let profile else {
            return .blocked(.unsupportedRole(SessionState.profilIncompletCode))
        }

        let context = MissionReadContext(userId: user.id, email: user.email, profile: profile)
        return .ready(SessionSnapshot(user: user, role: role, profile: profile, context: context, epoch: expected))
    }

    /// Message générique de connexion. Jamais l'erreur brute du SDK : elle pourrait
    /// citer l'adresse saisie ou un détail technique.
    private static func signInMessage(for error: Error) -> String {
        if let jolene = error as? JoleneError {
            switch jolene.kind {
            case .network: return "Connexion impossible pour le moment. Vérifiez votre réseau puis réessayez."
            case .invalidCredentials, .unauthorized: return genericSignInMessage
            default: return genericSignInMessage
            }
        }
        return genericSignInMessage
    }
}
