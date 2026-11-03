import Foundation

/// Espace de navigation ouvert par une identité (lot 5, T2a ; `docs/mobile-swift/LOT5_PLAN.md` §2.2).
/// Il n'accorde aucun droit : le serveur reste l'autorité sur chaque lecture et chaque écriture.
public enum EspaceAcces: Equatable, Sendable {
    case soignant
    case etablissement
    case bloque(MobileAccess)
}

/// Périmètre de l'espace établissement, tel que le confirme `fn_mes_permissions_etab(NULL)`
/// (`supabase/schema/public.sql` l.42265-42302), le même `mon_etablissement_id()` que toutes les RPC
/// du lot (correction 3).
public enum PerimetreEtablissement: Equatable, Sendable {
    /// Établissement confirmé par le serveur, rôle d'équipe connu et permissions servies telles quelles.
    case confirme(etablissementId: String, role: RoleEtab, permissions: PermissionsEtab)
    /// `{success:false}` : compte inactif ou sans session (l.42274).
    case compteInactif
    /// Aucun rôle ou aucun établissement : membre révoqué, rattachement perdu (l.42277, l.42282).
    case sansAcces
    /// Rôle hors des cinq rôles d'équipe (administrateur servi en `ADMIN_PLATEFORME`, l.42287).
    case roleNonServi(String)
    /// Le candidat (`fn_get_my_role`, `app_metadata`, repli legacy `user.id`) diffère du périmètre
    /// serveur : multi-établissement ou métadonnée périmée, renvoi web.
    case divergent
}

/// Règles pures de l'espace (D2, D3). Aucune correspondance rôle → permission n'est écrite ici : le
/// natif lit les booléens servis.
public enum EspaceResolution {
    /// Remplace `MobileAccess.validate` (`Models/Account.swift`, fichier gelé, conservé tel quel) dans
    /// le contrôleur de session. `role` est la valeur normalisée par `RoleResolution` (l'alias legacy
    /// signé `ETABLISSEMENT` est accepté tel quel par prudence) ; seuls les rôles que l'app sert
    /// (`UserRole.isNativelyServed`, D3) ouvrent un espace.
    public static func espace(user: AuthenticatedUser?, role: String?) -> EspaceAcces {
        guard let user else { return .bloque(.signInRequired) }
        guard user.emailConfirmedAt != nil else { return .bloque(.emailUnconfirmed) }
        guard let servi = role.flatMap(UserRole.init(rawValue:)), servi.isNativelyServed else {
            return .bloque(.unsupportedRole(role))
        }
        switch servi {
        case .soignant: return .soignant
        case .adminEtablissement, .etablissementLegacy: return .etablissement
        case .adminPlateforme, .adminGroupe: return .bloque(.unsupportedRole(role))
        }
    }

    /// Périmètre confirmé par la réponse serveur. Le candidat n'est **jamais** une valeur de filtre
    /// (correction 2) : nul, il laisse le serveur décider ; non nul, il doit égaler l'établissement servi.
    /// Ordre : compte inactif, puis rattachement absent, puis rôle non servi, puis divergence.
    public static func perimetre(candidat: String?, permissions reponse: PermissionsEtabResult) -> PerimetreEtablissement {
        guard reponse.success else { return .compteInactif }
        guard let role = reponse.role, let etablissementId = reponse.etablissementId else { return .sansAcces }
        guard role.estConnu else { return .roleNonServi(role.brut) }
        if let candidat, candidat != etablissementId { return .divergent }
        return .confirme(etablissementId: etablissementId, role: role, permissions: reponse.permissions)
    }
}
