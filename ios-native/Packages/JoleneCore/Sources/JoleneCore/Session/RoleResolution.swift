import Foundation

/// Règles pures de résolution du rôle, portées de `src/hooks/useRole.ts`
/// (`normaliserRole`) et de `src/hooks/useEtablissementScope.ts` (repli legacy).
/// Aucune règle d'autorisation ici : seulement l'espace de navigation à ouvrir.
public enum RoleResolution {
    /// Normalise une valeur brute (`app_metadata.role` ou réponse `fn_get_my_role`)
    /// vers les valeurs canoniques de `UserRole`. Retourne nil pour toute valeur
    /// inconnue ou absente (équivalent de `INCONNU` côté web).
    public static func normalize(_ raw: String?) -> String? {
        switch raw {
        case "SOIGNANT": return UserRole.soignant.rawValue
        case "ADMIN_ETABLISSEMENT", "ETABLISSEMENT": return UserRole.adminEtablissement.rawValue
        case "ADMIN_GROUPE": return UserRole.adminGroupe.rawValue
        case "ADMIN_PLATEFORME", "ADMIN": return UserRole.adminPlateforme.rawValue
        default: return nil
        }
    }

    /// Rôle provisoire tiré d'`app_metadata` (signé par Supabase Auth). Il ouvre
    /// l'interface sans attendre la RPC, puis le serveur le confirme ou le remplace.
    public static func provisional(from user: AuthenticatedUser) -> RoleResult? {
        guard let role = normalize(user.appMetadataRole) else { return nil }
        return RoleResult(role: role, etablissementId: user.appMetadataEtablissementId)
    }

    /// Combine la réponse serveur et le raccourci signé. Le serveur gagne toujours
    /// lorsqu'il a répondu ; le raccourci ne sert qu'en cas d'indisponibilité.
    /// Le repli legacy mono-établissement (`etablissementId = user.id`) n'est
    /// appliqué qu'à l'alias signé `ETABLISSEMENT`, comme sur le web.
    public static func resolve(server: RoleResult?, user: AuthenticatedUser) -> RoleResult? {
        let candidate: RoleResult?
        if let server {
            // Réponse serveur non normalisable (INCONNU, valeur inattendue) : aucun
            // espace n'est ouvert, et le raccourci signé ne sert pas de repli.
            candidate = normalize(server.role).map { RoleResult(role: $0, etablissementId: server.etablissementId) }
        } else {
            candidate = provisional(from: user)
        }
        guard var result = candidate else { return nil }
        if result.role == UserRole.adminEtablissement.rawValue,
           result.etablissementId == nil,
           user.appMetadataRole == UserRole.etablissementLegacy.rawValue {
            result.etablissementId = user.id
        }
        return result
    }
}
