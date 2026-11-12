import Foundation

/// Routeur de liens : Universal Links (`route(url:)`) et liens internes (`resolve(link:)`, dont le
/// chemin issu de `navigationPathForEvent` d'un tap push). Il ne dit que la route du chemin : tout
/// consommateur passe par `DestinationLien(url:)` / `DestinationLien(link:)?.destination` (écran livré
/// ou renvoi web canonique), puis par `DeepLinkIntent` (lot 3, T3b), jamais par la route brute.
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
/// | `/inscription/soignant`, `/inscription/reprendre`, `/inscription/completer` (lot 3) | `.inscription(EtapeInscription)`, query conservée |
/// | `/soignant/mes-gains` (`?tab=` → section, lot 3)  | `.revenus(section:)`              |
/// | alias `mes-factures-honoraires`, `mes-avances`, `bulletins-paie` (`Navigate`, l.395-397) | `.revenus(section: .factures / .avances / .bulletins)` |
/// | `/soignant/profil`, `reputation` (lot 3)          | `.profil` (édition)               |
/// | `/soignant/mon-compte`, `parametres`, `parametres-complet` ; `score`, `fiabilite`, `fiabilite-legacy` (page score au lot 4, écart assumé) | `.monCompte` (hub) |
/// | `/soignant/profil?tab=confidentialite` (export RGPD et suppression, portés par le hub depuis L3-T11) | `.monCompte` (hub) |
/// | `/soignant/notifications` (lot 3)                 | `.notifications`                  |
/// | `/soignant/parametres/notifications` (lot 3)      | `.parametresNotifications`        |
/// | `/soignant/stripe-connect` (`?success=true` / `?refresh=true`, lot 3) | `.stripeConnect(retour:)` |
/// | `/etablissement/*`, `/etab/invitation/*`          | `.etablissement(URL)`             |
/// | tout le reste (`/admin/*`, `/groupe/*`, `/contrat/*`, `/auth/psc/callback`, `/inscription/etablissement`, `/inscription/soignant/completion`, autres `/inscription/*`, autres `/soignant/*`, chemins hors AASA) | `.safari(URL)` |
///
/// Le routeur ne dit pas si l'écran d'une route native est livré : `DestinationLien` renvoie vers
/// Safari une route dont la tranche d'écran n'est pas encore mergée. Limite connue : `?tab=` n'est
/// lu que pour Revenus ; les autres onglets en query (`?tab=passees`) ne sont pas portés.
public enum LinkRouter {
    /// Entrée Universal Link (`onOpenURL`, `NSUserActivity`). N'accepte que les hôtes de
    /// `AASAPatterns.hosts` en https sans port ; retourne `nil` pour tout autre hôte.
    /// Les quinze motifs AASA sont appliqués dans l'ordre du fichier : un chemin qu'aucun motif
    /// ne couvre est renvoyé vers Safari (l'app n'est pas censée le recevoir).
    public static func route(url: URL) -> JoleneRoute? {
        routage(url: url)?.route
    }

    /// Lien interne (chemin relatif ou URL d'un hôte de `JoleneLink.trustedWebHosts`), par
    /// exemple le `lien` d'une notification push. `nil` si le lien n'est pas un lien Jolene.
    public static func resolve(link rawLink: String) -> JoleneRoute? {
        routage(link: rawLink)?.route
    }

    /// Route d'un Universal Link et URL canonique du lien (`https://jolene.app` + chemin, query et
    /// fragment), reprise par `DestinationLien` pour un renvoi Safari.
    static func routage(url: URL) -> (route: JoleneRoute, canonique: URL)? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), AASAPatterns.hosts.contains(host),
              url.port == nil || url.port == 443,
              let link = JoleneLink.normalize(url.absoluteString) else { return nil }
        let path = JoleneLink.split(link: link).path
        guard AASAPatterns.firstMatch(path: path) != nil else {
            let canonique = JoleneLink.canonicalURL(link: link) ?? url
            return (.safari(canonique), canonique)
        }
        return routage(link: link)
    }

    /// Route d'un lien interne et son URL canonique.
    static func routage(link rawLink: String) -> (route: JoleneRoute, canonique: URL)? {
        guard let link = JoleneLink.normalize(rawLink), let url = JoleneLink.canonicalURL(link: link) else { return nil }
        let parts = JoleneLink.split(link: link)
        return (resolve(path: parts.path, query: parts.query ?? "", fragment: parts.fragment ?? "", canonical: url), url)
    }

    private static func resolve(path rawPath: String, query: String, fragment: String, canonical: URL) -> JoleneRoute {
        var path = rawPath
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)

        switch path {
        case "/connexion": return .connexion
        case "/reset-password": return .resetPassword(credentials: .recovery(search: query, fragment: fragment))
        case "/inscription/confirmer": return .confirmerInscription(credentials: .signup(search: query, fragment: fragment))
        case "/inscription/soignant": return .inscription(EtapeInscription(page: .soignant, query: query))
        case "/inscription/reprendre": return .inscription(EtapeInscription(page: .reprendre, query: query))
        case "/inscription/completer": return .inscription(EtapeInscription(page: .completer, query: query))
        case "/soignant/tableau-de-bord": return .accueil
        case "/soignant/recherche-missions", "/soignant/swipe-missions": return .explorer
        case "/soignant/missions", "/soignant/mes-matches", "/soignant/planning",
             "/soignant/calendrier-sync", "/soignant/historique-missions":
            return .missions
        case "/soignant/mes-gains": return .revenus(section: SectionRevenus(tab: FormQuery(query).get("tab")))
        // Alias `Navigate` de `src/App.tsx` l.395-397 : l'onglet est fixé par la redirection.
        case "/soignant/mes-factures-honoraires": return .revenus(section: .factures)
        case "/soignant/mes-avances": return .revenus(section: .avances)
        case "/soignant/bulletins-paie": return .revenus(section: .bulletins)
        // Onglet « Confidentialité » du profil web (`ProfilSoignant.tsx` l.42-44, l.505-507 : export RGPD, suppression
        // de compte ; « Supprimer mon compte » du hub web, `MonCompteSoignant.tsx` l.135) : le hub natif, qui porte la
        // suppression (L1-T8) et l'export (L3-T11) ; ligne passée à `.monCompte` à l'intégration de T11 (revue B8 de T3b,
        // m3 ; garde `LinksRouterTests.testOngletConfidentialiteSuitLExportRGPDDuHub`).
        // Comparaison exacte de `?tab=`, comme le web ; l'alias `reputation` redirige sans query (`src/App.tsx` l.393).
        case "/soignant/profil": return FormQuery(query).get("tab") == "confidentialite" ? .monCompte : .profil
        case "/soignant/reputation": return .profil
        case "/soignant/mon-compte", "/soignant/parametres", "/soignant/parametres-complet",
             "/soignant/score", "/soignant/fiabilite", "/soignant/fiabilite-legacy":
            return .monCompte
        case "/soignant/notifications": return .notifications
        case "/soignant/parametres/notifications": return .parametresNotifications
        case "/soignant/stripe-connect": return .stripeConnect(retour: RetourConnect(query: query))
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
