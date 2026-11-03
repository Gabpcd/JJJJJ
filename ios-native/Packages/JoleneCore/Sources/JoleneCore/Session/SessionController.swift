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
    /// Revalidation (identité déjà active et état `.ready` ou `.readyEtablissement`, reprise après
    /// 30 minutes) : l'état courant est conservé pendant la vérification (pas de passage par
    /// `.loading`, les onglets ne sont pas démontés) et une erreur transitoire (réseau, délai) le laisse
    /// intact. Seule une absence de session confirmée par le port, ou une réponse serveur
    /// (rôle, profil, périmètre établissement) change l'état ; un changement d'espace ou
    /// d'établissement avance l'epoch (`frontiereDePerimetre`, lot 5 T2a).
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
        let previous = currentState
        if !quiet { currentState = .loading }
        if let resolved = await resolve(user: user, epoch: epochAtStart, quiet: quiet), epochAtStart == currentEpoch {
            currentState = quiet ? frontiereDePerimetre(avant: previous, apres: resolved) : resolved
        }
        return currentState
    }

    /// Revalidation silencieuse à identité constante (lot 5, T2a, §2.2) : un changement d'espace ou
    /// d'établissement est une frontière de périmètre, au même titre qu'un changement d'identité.
    /// - établissement → autre établissement : refus « périmètre divergent » (renvoi web), epoch + 1 ;
    /// - établissement → espace non prêt (accès retiré, compte inactif) : epoch + 1 ;
    /// - soignant ↔ établissement : epoch + 1, instantané ré-étiqueté ;
    /// - même établissement (rôle ou permissions changés) : instantané remplacé à epoch constant.
    private func frontiereDePerimetre(avant: SessionState, apres: SessionState) -> SessionState {
        guard case let .readyEtablissement(precedent) = avant else {
            if case .ready = avant, case .readyEtablissement = apres {
                bumpEpoch()
                return apres.avecEpoch(currentEpoch)
            }
            return apres
        }
        switch apres {
        case let .readyEtablissement(nouveau) where nouveau.context.etablissementId == precedent.context.etablissementId:
            return apres
        case .readyEtablissement:
            bumpEpoch()
            return .blocked(.unsupportedRole(SessionState.etabScopeDivergentCode))
        case .ready:
            bumpEpoch()
            return apres.avecEpoch(currentEpoch)
        case .idle, .loading, .signedOut, .blocked:
            bumpEpoch()
            return apres
        }
    }

    /// Relecture du périmètre après un refus de droit reçu par un écran (lot 5, T2a, §2.2, D12) :
    /// `fn_mes_permissions_etab(NULL)` relu **une fois** par refus (l'écran n'appelle cette méthode
    /// qu'une fois par refus `accesRefuse`), jamais une déconnexion.
    /// - même établissement : rôle et permissions remplacés à epoch constant (écrans re-filtrés) ;
    /// - autre établissement, accès retiré, rôle non servi ou compte inactif : epoch + 1, espace fermé ;
    /// - erreur transitoire (réseau, délai), epoch périmé ou espace non établissement : état conservé.
    public func refreshEtablissementScope(epoch expected: Int) async -> SessionState {
        guard expected == currentEpoch, case .readyEtablissement = currentState else { return currentState }
        let session = configured.etablissement.session
        let reponse: PermissionsEtabResult
        do {
            reponse = try await bounded(timeout: resolutionTimeout) { try await session.permissions(etablissementId: nil) }
        } catch {
            return currentState
        }
        guard expected == currentEpoch, case let .readyEtablissement(courant) = currentState else { return currentState }
        switch EspaceResolution.perimetre(candidat: courant.context.etablissementId, permissions: reponse) {
        case let .confirme(_, role, permissions):
            var mis = courant
            mis.context.roleEtab = role
            mis.context.permissions = permissions
            currentState = .readyEtablissement(mis)
        case let refus:
            bumpEpoch()
            currentState = Self.etat(pour: refus)
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

        // Lot 5 (T2a, D3) : `EspaceResolution` remplace `MobileAccess.validate` (fichier gelé).
        switch EspaceResolution.espace(user: user, role: role?.role) {
        case .soignant: break
        case .etablissement:
            guard let role else { return .blocked(.unsupportedRole(nil)) }
            return await resolveEtablissement(user: user, role: role, gateways: gateways, epoch: expected, quiet: quiet)
        case let .bloque(access): return .blocked(access)
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

    /// Étape « périmètre établissement » (lot 5, T2a, §2.2, D2) à la place du profil soignant :
    /// `fn_mes_permissions_etab(NULL)` fait foi (le candidat `role.etablissementId` lui est seulement
    /// comparé), puis `fn_mon_etablissement_complet()` (sous-ensemble) doit servir le même établissement.
    /// Chaque appel est borné, l'epoch vérifié après chaque `await` ; en revalidation silencieuse, une
    /// erreur transitoire rend nil (état conservé). Aucun profil soignant ni activité soignant (correction 12).
    private func resolveEtablissement(user: AuthenticatedUser, role: RoleResult, gateways: Gateways,
                                      epoch expected: Int, quiet: Bool) async -> SessionState? {
        let session = gateways.etablissement.session
        let reponse: PermissionsEtabResult
        do {
            reponse = try await bounded(timeout: resolutionTimeout) { try await session.permissions(etablissementId: nil) }
        } catch {
            guard currentEpoch == expected else { return nil }
            return quiet ? nil : .signedOut(message: Self.sessionCheckFailedMessage)
        }
        guard currentEpoch == expected else { return nil }
        let perimetre = EspaceResolution.perimetre(candidat: role.etablissementId, permissions: reponse)
        guard case let .confirme(etablissementId, roleEtab, permissions) = perimetre else {
            return Self.etat(pour: perimetre)
        }

        let profil: EtablissementProfil
        do {
            profil = try await bounded(timeout: resolutionTimeout) { try await session.profil() }
        } catch {
            guard currentEpoch == expected else { return nil }
            return quiet ? nil : .signedOut(message: Self.profileLoadFailedMessage)
        }
        guard currentEpoch == expected else { return nil }
        // Un profil d'un autre établissement est une divergence, jamais un repli (Lot5Ports, `profil()`).
        guard profil.id == etablissementId else {
            return .blocked(.unsupportedRole(SessionState.etabScopeDivergentCode))
        }
        let context = EtablissementReadContext(userId: user.id, etablissementId: etablissementId, roleEtab: roleEtab,
                                               permissions: permissions, epoch: expected)
        return .readyEtablissement(EtablissementSessionSnapshot(user: user, role: role, context: context, etablissement: profil))
    }

    /// État d'un périmètre refusé (`EspaceResolution.perimetre`) ; un périmètre confirmé n'a pas d'état
    /// sans profil et n'est jamais passé ici.
    private static func etat(pour perimetre: PerimetreEtablissement) -> SessionState {
        switch perimetre {
        case .compteInactif: return .signedOut(message: sessionCheckFailedMessage)
        case .sansAcces: return .blocked(.unsupportedRole(SessionState.etabSansAccesCode))
        case let .roleNonServi(role): return .blocked(.unsupportedRole(role))
        case .divergent, .confirme: return .blocked(.unsupportedRole(SessionState.etabScopeDivergentCode))
        }
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
