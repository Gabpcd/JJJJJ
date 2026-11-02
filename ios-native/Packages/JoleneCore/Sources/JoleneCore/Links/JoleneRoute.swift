import Foundation

/// Destination d'un lien Jolene dans l'app native (lot 0). Les cas natifs reflètent les
/// cinq onglets et les écrans du parcours soignant ; les deux sorties non natives
/// renvoient vers le web avec l'URL canonique (`https://jolene.app/...`, query et fragment
/// conservés).
public enum JoleneRoute: Equatable, Sendable {
    case connexion
    /// `/reset-password` : identifiants extraits de la query et du fragment, `nil` si le lien
    /// ne porte aucun format reconnu (l'écran affiche alors « lien invalide ou expiré »).
    case resetPassword(credentials: AuthCallbackCredentials?)
    /// `/inscription/confirmer` : mêmes trois formats, types `signup` / `email`.
    case confirmerInscription(credentials: AuthCallbackCredentials?)
    case accueil
    case explorer
    case missions
    case missionDetail(id: String)
    case serieDetail(id: String)
    case revenus
    case profil
    /// Chemin servi par Safari (`SFSafariViewController`) : `/admin/*`, `/groupe/*` et tout
    /// chemin sans écran natif.
    case safari(URL)
    /// Espace établissement (lot 5) : renvoi Safari tant qu'il n'est pas natif.
    case etablissement(URL)

    /// Vrai pour une destination rendue dans l'app, faux pour un renvoi web.
    public var isNative: Bool {
        switch self {
        case .safari, .etablissement: return false
        default: return true
        }
    }

    /// URL à ouvrir hors de l'app, `nil` pour une destination native.
    public var externalURL: URL? {
        switch self {
        case .safari(let url), .etablissement(let url): return url
        default: return nil
        }
    }
}
