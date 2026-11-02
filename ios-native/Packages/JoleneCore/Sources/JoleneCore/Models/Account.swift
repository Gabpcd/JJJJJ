import Foundation

/// Utilisateur authentifié tel que vu par le cœur, indépendant du SDK.
public struct AuthenticatedUser: Equatable, Sendable {
    public var id: String
    public var email: String?
    public var emailConfirmedAt: Date?
    /// `app_metadata.role` si présent : raccourci de `src/hooks/useRole.ts`, confirmé ensuite par `fn_get_my_role`.
    public var appMetadataRole: String?
    public var appMetadataEtablissementId: String?

    public init(id: String, email: String?, emailConfirmedAt: Date?, appMetadataRole: String? = nil, appMetadataEtablissementId: String? = nil) {
        self.id = id; self.email = email; self.emailConfirmedAt = emailConfirmedAt
        self.appMetadataRole = appMetadataRole; self.appMetadataEtablissementId = appMetadataEtablissementId
    }
}

/// Admission de navigation uniquement ; le backend authentifié reste l'autorité
/// (port de `validateMobileAccess` dans `mobile-native/src/data/types.ts`).
public enum MobileAccess: Equatable, Sendable {
    case allowed
    case signInRequired
    case emailUnconfirmed
    case unsupportedRole(String?)

    public var message: String? {
        switch self {
        case .allowed: return nil
        case .signInRequired: return "Connectez-vous pour consulter les missions."
        case .emailUnconfirmed: return "Confirmez votre adresse email avant de continuer."
        case .unsupportedRole: return "Cet espace n'est pas encore disponible dans l'application. Rendez-vous sur jolene.app."
        }
    }

    public static func validate(user: AuthenticatedUser?, role: String?) -> MobileAccess {
        guard let user else { return .signInRequired }
        guard user.emailConfirmedAt != nil else { return .emailUnconfirmed }
        guard role == UserRole.soignant.rawValue else { return .unsupportedRole(role) }
        return .allowed
    }
}
