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

/// Instantané d'une session établissement prête (lot 5, T2a, D1) : identité, rôle résolu (candidat),
/// contexte **confirmé par le serveur** (`fn_mes_permissions_etab(NULL)` : établissement, rôle d'équipe,
/// permissions, epoch) et sous-ensemble du profil d'établissement. Aucun `SoignantProfile` n'est
/// fabriqué ; `SessionSnapshot` est inchangé.
public struct EtablissementSessionSnapshot: Equatable, Sendable {
    public var user: AuthenticatedUser
    public var role: RoleResult
    public var context: EtablissementReadContext
    public var etablissement: EtablissementProfil

    public init(user: AuthenticatedUser, role: RoleResult, context: EtablissementReadContext, etablissement: EtablissementProfil) {
        self.user = user; self.role = role; self.context = context; self.etablissement = etablissement
    }

    /// Clé de navigation et de cache : celle du contexte (source unique).
    public var epoch: Int { context.epoch }
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
    /// non servi, profil soignant absent, établissement sans accès ou divergent).
    case blocked(MobileAccess)
    /// Session complète : profil chargé, rôle confirmé par le serveur.
    case ready(SessionSnapshot)
    /// Session établissement complète (lot 5, T2a) : périmètre confirmé par le serveur.
    case readyEtablissement(EtablissementSessionSnapshot)

    /// Code de rôle utilisé lorsque le compte est bien SOIGNANT mais que la ligne
    /// `soignants` n'existe pas encore (inscription non terminée).
    public static let profilIncompletCode = "PROFIL_INCOMPLET"
    /// Établissement : aucun rôle ni établissement servi (membre révoqué, rattachement perdu).
    public static let etabSansAccesCode = "ETAB_SANS_ACCES"
    /// Établissement : le candidat diffère du périmètre serveur (multi-établissement, métadonnée périmée).
    public static let etabScopeDivergentCode = "ETAB_SCOPE_DIVERGENT"

    /// Vrai pour un espace prêt, soignant ou établissement.
    public var isReady: Bool {
        switch self {
        case .ready, .readyEtablissement: return true
        case .idle, .loading, .signedOut, .blocked: return false
        }
    }

    /// Instantané soignant ; nil dans l'espace établissement.
    public var snapshot: SessionSnapshot? {
        if case let .ready(snapshot) = self { return snapshot }
        return nil
    }

    /// Instantané établissement ; nil dans l'espace soignant.
    public var snapshotEtablissement: EtablissementSessionSnapshot? {
        if case let .readyEtablissement(snapshot) = self { return snapshot }
        return nil
    }

    /// Message à présenter à l'utilisateur, ou nil si l'état n'en appelle aucun.
    public var message: String? {
        switch self {
        case .idle, .loading, .ready, .readyEtablissement: return nil
        case let .signedOut(message): return message
        case let .blocked(access): return access.sessionMessage
        }
    }

    /// Même état, ré-étiqueté pour `epoch` (frontière d'espace à identité constante, T2a).
    func avecEpoch(_ epoch: Int) -> SessionState {
        switch self {
        case var .ready(snapshot):
            snapshot.epoch = epoch
            return .ready(snapshot)
        case var .readyEtablissement(snapshot):
            snapshot.context.epoch = epoch
            return .readyEtablissement(snapshot)
        case .idle, .loading, .signedOut, .blocked:
            return self
        }
    }
}

public extension MobileAccess {
    /// Message de `MobileAccess.message`, spécialisé pour le profil soignant non
    /// constitué (le renvoi vers jolene.app serait trompeur dans ce cas) et pour les deux
    /// refus de périmètre de l'espace établissement (lot 5, T2a).
    var sessionMessage: String? {
        if case let .unsupportedRole(code) = self {
            switch code {
            case SessionState.profilIncompletCode:
                return "Votre profil soignant n'est pas encore complet. Terminez votre inscription sur jolene.app puis reconnectez-vous."
            case SessionState.etabSansAccesCode:
                return "Aucun établissement actif n'est rattaché à votre compte. Rendez-vous sur jolene.app."
            case SessionState.etabScopeDivergentCode:
                return "L'établissement de votre compte n'a pas pu être confirmé dans l'application. Ouvrez votre espace sur jolene.app."
            default:
                break
            }
        }
        return message
    }

    /// Vrai pour le refus « périmètre divergent » (écran `etab-scope-divergent`).
    var estPerimetreDivergent: Bool {
        if case let .unsupportedRole(code) = self { return code == SessionState.etabScopeDivergentCode }
        return false
    }
}
