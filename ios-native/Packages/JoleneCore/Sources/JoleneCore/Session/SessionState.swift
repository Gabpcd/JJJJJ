import Foundation

/// Instantané d'une session prête : identité, rôle confirmé, profil soignant et
/// contexte de lecture des missions. `epoch` est la clé de navigation et de cache :
/// deux instantanés d'epochs différents ne partagent jamais de données.
public struct SessionSnapshot: Equatable, Sendable {
    public var user: AuthenticatedUser
    public var role: RoleResult
    public var profile: SoignantProfile
    public var context: MissionReadContext
    public var epoch: Int

    public init(user: AuthenticatedUser, role: RoleResult, profile: SoignantProfile, context: MissionReadContext, epoch: Int) {
        self.user = user; self.role = role; self.profile = profile; self.context = context; self.epoch = epoch
    }
}

/// État observable de la session (plan §4.3). L'interface ne dérive jamais une
/// autorisation de cet état : il n'ouvre qu'un espace de navigation, le serveur
/// reste l'autorité sur chaque lecture et chaque écriture.
public enum SessionState: Equatable, Sendable {
    /// Contrôleur créé, `start()` pas encore appelé.
    case idle
    /// Restauration, connexion ou résolution de rôle en cours.
    case loading
    /// Aucune identité active. `message` est nul après une déconnexion volontaire,
    /// sinon il porte un texte générique sans aucune valeur saisie.
    case signedOut(message: String?)
    /// Identité valide mais espace non servi par l'app (email non confirmé, rôle
    /// non soignant, profil soignant absent).
    case blocked(MobileAccess)
    /// Session complète : profil chargé, rôle confirmé par le serveur.
    case ready(SessionSnapshot)

    /// Code de rôle utilisé lorsque le compte est bien SOIGNANT mais que la ligne
    /// `soignants` n'existe pas encore (inscription non terminée).
    public static let profilIncompletCode = "PROFIL_INCOMPLET"

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var snapshot: SessionSnapshot? {
        if case let .ready(snapshot) = self { return snapshot }
        return nil
    }

    /// Message à présenter à l'utilisateur, ou nil si l'état n'en appelle aucun.
    public var message: String? {
        switch self {
        case .idle, .loading, .ready: return nil
        case let .signedOut(message): return message
        case let .blocked(access): return access.sessionMessage
        }
    }
}

public extension MobileAccess {
    /// Message de `MobileAccess.message`, spécialisé pour le profil soignant non
    /// constitué (le renvoi vers jolene.app serait trompeur dans ce cas).
    var sessionMessage: String? {
        if case let .unsupportedRole(code) = self, code == SessionState.profilIncompletCode {
            return "Votre profil soignant n'est pas encore complet. Terminez votre inscription sur jolene.app puis reconnectez-vous."
        }
        return message
    }
}
