import Foundation

/// Routeur de liens : Universal Links (`route(url:)`) et liens internes (`resolve(link:)`,
/// réutilisable par le coordinateur push du lot 3 pour le chemin issu de
/// `navigationPathForEvent`, sans rien implémenter du push ici).
///
/// Table de routage (chemin sans query ni fragment, barre oblique finale ignorée), dérivée
/// de `src/App.tsx` (routes soignant et redirections `Navigate`) :
///
/// | Chemin                                            | Destination                       |
/// |---------------------------------------------------|-----------------------------------|
/// | `/connexion`                                      | `.connexion`                      |
/// | `/reset-password`                                 | `.resetPassword(credentials:)`    |
/// | `/inscription/confirmer`                          | `.confirmerInscription(credentials:)` |
/// | `/soignant/tableau-de-bord`                       | `.accueil`                        |
/// | `/soignant/recherche-missions`, `/soignant/swipe-missions` | `.explorer`              |
/// | `/soignant/missions` et alias (`mes-matches`, `planning`, `calendrier-sync`, `historique-missions`) | `.missions` |
/// | `/soignant/missions/serie/{id}`                   | `.serieDetail(id:)`               |
/// | `/soignant/missions/{id}`, `/mission/{id}`        | `.missionDetail(id:)`             |
/// | `/soignant/mes-gains` et alias (`mes-factures-honoraires`, `mes-avances`, `bulletins-paie`) | `.revenus` |
/// | `/soignant/profil`, `mon-compte`, `parametres`, `parametres-complet`, `reputation`, `score`, `fiabilite`, `fiabilite-legacy` | `.profil` |
/// | `/etablissement/*`, `/etab/invitation/*`          | `.etablissement(URL)`             |
/// | tout le reste (`/admin/*`, `/groupe/*`, `/contrat/*`, `/auth/psc/callback`, autres `/inscription/*`, autres `/soignant/*`, chemins hors AASA) | `.safari(URL)` |
///
/// Limite connue du lot 0 : les onglets passés en query (`?tab=passees`, `?tab=factures`)
/// ne sont pas portés par `JoleneRoute` ; ils seront ajoutés avec les écrans concernés.
public enum LinkRouter {
    /// Entrée Universal Link (`onOpenURL`, `NSUserActivity`). N'accepte que les hôtes de
    /// `AASAPatterns.hosts` en https sans port ; retourne `nil` pour tout autre hôte.
    /// Les quinze motifs AASA sont appliqués dans l'ordre du fichier : un chemin qu'aucun motif
    /// ne couvre est renvoyé vers Safari (l'app n'est pas censée le recevoir).
    public static func route(url: URL) -> JoleneRoute? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), AASAPatterns.hosts.contains(host),
              url.port == nil || url.port == 443,
              let link = JoleneLink.normalize(url.absoluteString) else { return nil }
        let path = JoleneLink.split(link: link).path
        guard AASAPatterns.firstMatch(path: path) != nil else {
            return .safari(JoleneLink.canonicalURL(link: link) ?? url)
        }
        return resolve(link: link)
    }

    /// Lien interne (chemin relatif ou URL d'un hôte de `JoleneLink.trustedWebHosts`), par
    /// exemple le `lien` d'une notification push. `nil` si le lien n'est pas un lien Jolene.
    public static func resolve(link rawLink: String) -> JoleneRoute? {
        guard let link = JoleneLink.normalize(rawLink), let url = JoleneLink.canonicalURL(link: link) else { return nil }
        let parts = JoleneLink.split(link: link)
        return resolve(path: parts.path, query: parts.query ?? "", fragment: parts.fragment ?? "", canonical: url)
    }

    private static func resolve(path rawPath: String, query: String, fragment: String, canonical: URL) -> JoleneRoute {
        var path = rawPath
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)

        switch path {
        case "/connexion": return .connexion
        case "/reset-password": return .resetPassword(credentials: .recovery(search: query, fragment: fragment))
        case "/inscription/confirmer": return .confirmerInscription(credentials: .signup(search: query, fragment: fragment))
        case "/soignant/tableau-de-bord": return .accueil
        case "/soignant/recherche-missions", "/soignant/swipe-missions": return .explorer
        case "/soignant/missions", "/soignant/mes-matches", "/soignant/planning",
             "/soignant/calendrier-sync", "/soignant/historique-missions":
            return .missions
        case "/soignant/mes-gains", "/soignant/mes-factures-honoraires", "/soignant/mes-avances", "/soignant/bulletins-paie":
            return .revenus
        case "/soignant/profil", "/soignant/mon-compte", "/soignant/parametres", "/soignant/parametres-complet",
             "/soignant/reputation", "/soignant/score", "/soignant/fiabilite", "/soignant/fiabilite-legacy":
            return .profil
        default: break
        }

        if segments.count == 4, segments[0] == "soignant", segments[1] == "missions", segments[2] == "serie",
           let id = identifier(segments[3]) {
            return .serieDetail(id: id)
        }
        if segments.count == 3, segments[0] == "soignant", segments[1] == "missions", let id = identifier(segments[2]) {
            return .missionDetail(id: id)
        }
        if segments.count == 2, segments[0] == "mission", let id = identifier(segments[1]) {
            return .missionDetail(id: id)
        }
        if segments.count >= 2, segments[0] == "etablissement" || (segments[0] == "etab" && segments[1] == "invitation") {
            return .etablissement(canonical)
        }
        return .safari(canonical)
    }

    /// Segment d'identifiant décodé (le web encode avec `encodeURIComponent`) ; `nil` si vide.
    private static func identifier(_ segment: String) -> String? {
        let decoded = segment.removingPercentEncoding ?? segment
        return decoded.isEmpty ? nil : decoded
    }
}
