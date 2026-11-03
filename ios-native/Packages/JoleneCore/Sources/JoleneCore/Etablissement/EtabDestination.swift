import Foundation

/// Registre des destinations de l'espace établissement (lot 5, T2a, corrigé v2 ; `LOT5_PLAN.md` §4) :
/// un cas par écran poussé depuis un onglet. L'app rend chaque cas par **une** ligne d'un `switch`
/// (`Jolene/Screens/Etablissement/EtabDestinations.swift`) que seule la tranche du domaine remplace :
/// aucun écran ne référence l'écran d'une autre tranche, il pousse une destination. Le routage des liens
/// (T2b, `LinkRouter.etablissementDestination`) rend aussi ces destinations.
///
/// Accès fail-closed (§2.7) : chaque destination nomme la permission qu'elle exige ; les booléens viennent
/// de `fn_mes_permissions_etab`, le serveur reste l'autorité (aucune table rôle → permission ici).
public enum EtabDestination: Hashable, Sendable {
    /// Détail d'une mission (T5).
    case detailMission(id: String)
    /// Candidatures d'une mission, lecture habilitée (T6).
    case candidatures(missionId: String)
    /// Code rotatif et QR plein écran (T7).
    case pointage(missionId: String)
    /// Présences d'une mission (T8).
    case presencesMission(missionId: String)
    /// Contrat et signature OTP établissement (T10).
    case contrat(id: String)
    /// Fil de messagerie (T11).
    case conversation(id: String)
    /// Publication d'une mission simple ou urgente (T9).
    case publication

    /// Permission exigée (§2.7) ; sans elle, l'écran d'accès refusé remplace la destination.
    public var permissionRequise: PermissionEtab {
        switch self {
        case .detailMission, .presencesMission, .conversation: return .lecture
        case .candidatures: return .candidatures
        case .pointage: return .pointage
        case .contrat: return .contrats
        case .publication: return .missions
        }
    }

    /// Drapeau d'écran (D14). Aucune des sept clés ne vise les contrats : le contrat s'ouvre depuis une
    /// mission et suit le drapeau `missions`.
    public var drapeau: EcranNatifEtablissement {
        switch self {
        case .detailMission, .candidatures, .contrat: return .missions
        case .pointage: return .pointage
        case .presencesMission: return .presences
        case .conversation: return .messages
        case .publication: return .publier
        }
    }

    /// Tranche du lot 5 qui livre l'écran (contenu provisoire jusque-là).
    public var tranche: String {
        switch self {
        case .detailMission: return "T5"
        case .candidatures: return "T6"
        case .pointage: return "T7"
        case .presencesMission: return "T8"
        case .contrat: return "T10"
        case .conversation: return "T11"
        case .publication: return "T9"
        }
    }

    /// Identifiant stable du cas (accessibilité des écrans provisoires : `placeholder-etab-<identifiant>`).
    public var identifiant: String {
        switch self {
        case .detailMission: return "detail-mission"
        case .candidatures: return "candidatures"
        case .pointage: return "pointage"
        case .presencesMission: return "presences-mission"
        case .contrat: return "contrat"
        case .conversation: return "conversation"
        case .publication: return "publication"
        }
    }

    public func accessible(avec permissions: PermissionsEtab) -> Bool {
        permissions[permissionRequise]
    }

    /// Route web équivalente (`src/App.tsx` l.357-376, l.437, l.440), identifiants encodés comme
    /// `encodeURIComponent` ; présentée hors lien universel quand l'écran est coupé par son drapeau.
    public var cheminWeb: String {
        switch self {
        case let .detailMission(id), let .candidatures(id): return "/etablissement/missions/\(Self.segment(id))"
        case let .pointage(id), let .presencesMission(id): return "/etablissement/presences/mission/\(Self.segment(id))"
        case let .contrat(id): return "/contrat/\(Self.segment(id))"
        case .conversation: return "/etablissement/messagerie"
        case .publication: return "/etablissement/missions/creer"
        }
    }

    /// URL canonique du renvoi (`https://jolene.app<chemin>`).
    public var urlWeb: URL {
        // Chemin construit depuis des segments encodés : la construction ne peut pas échouer.
        URL(string: "https://jolene.app\(cheminWeb)")!
    }

    /// Caractères non réservés de RFC 3986 (ceux qu'`encodeURIComponent` laisse aussi intacts, hors `!'()*`).
    private static let nonReserves = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func segment(_ valeur: String) -> String {
        valeur.addingPercentEncoding(withAllowedCharacters: nonReserves) ?? ""
    }
}
