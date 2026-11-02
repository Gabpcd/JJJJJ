import Foundation

/// Normalisation des liens Jolene, portée de `src/lib/nativeLinks.ts`
/// (`normaliserLienJolene`, `urlCallbackPublique`). Aucune valeur n'est journalisée.
public enum JoleneLink {
    /// Hôtes web de confiance pour un lien interne (push, email, navigation in-app).
    /// Même liste que `TRUSTED_WEB_HOSTS` côté web ; les hôtes Universal Link, plus
    /// restrictifs, sont dans `AASAPatterns.hosts`.
    public static let trustedWebHosts: Set<String> = ["jolene.app", "www.jolene.app", "app.jolene.app"]

    /// Origine publique canonique utilisée pour tout callback qui doit revenir par
    /// Universal Link. Dans l'app native il n'existe pas d'autre origine possible
    /// (port de `urlCallbackPublique`, branche `Capacitor.isNativePlatform()`).
    public static let canonicalOrigin = "https://jolene.app"

    /// Convertit un lien Jolene (URL HTTPS absolue ou chemin interne commençant par « / »)
    /// en route web normalisée `chemin?query#fragment`. Query et fragment sont conservés :
    /// Supabase en a besoin pour les callbacks PKCE et les liens de récupération.
    ///
    /// Retourne `nil` pour toute origine, tout port ou tout chemin protocol-relative non
    /// fiables, exactement comme la version web. Différences assumées avec `new URL()` :
    /// les antislashs sont ramenés à « / » (sémantique WHATWG pour les schémas spéciaux),
    /// les segments « . » et « .. » sont résolus, et une chaîne que `URLComponents` ne sait
    /// pas analyser (caractères non encodés) est refusée plutôt qu'encodée à la volée.
    public static func normalize(_ rawLink: String) -> String? {
        guard !rawLink.isEmpty else { return nil }
        // WHATWG : pour https, « \ » est un séparateur équivalent à « / ».
        let raw = rawLink.replacingOccurrences(of: "\\", with: "/")

        let isRelative = raw.hasPrefix("/") && !raw.hasPrefix("//")
        let isAbsoluteHTTPS = raw.lowercased().hasPrefix("https://")
        guard isRelative || isAbsoluteHTTPS else { return nil }

        guard let components = URLComponents(string: isRelative ? canonicalOrigin + raw : raw) else { return nil }
        guard components.scheme?.lowercased() == "https" else { return nil }
        // `url.port` vaut "" en JS pour le port par défaut : 443 explicite reste accepté.
        if let port = components.port, port != 443 { return nil }
        guard let host = components.host?.lowercased(), trustedWebHosts.contains(host) else { return nil }

        var path = components.percentEncodedPath
        if path.isEmpty { path = "/" }
        guard path.hasPrefix("/"), !path.hasPrefix("//") else { return nil }
        path = resolveDotSegments(path)

        var link = path
        if let query = components.percentEncodedQuery, !query.isEmpty { link += "?" + query }
        if let fragment = components.percentEncodedFragment, !fragment.isEmpty { link += "#" + fragment }
        return link
    }

    /// URL web publique d'un callback (reset, confirmation, PSC) : toujours sur
    /// `https://jolene.app`, afin que le retour passe par Universal Link.
    /// Lève `JoleneError(.contract)` si le chemin n'est pas un lien Jolene valide.
    public static func publicCallbackURL(path: String) throws -> URL {
        guard let link = normalize(path), let url = canonicalURL(link: link) else {
            throw JoleneError(.contract, "Chemin de callback Jolene invalide.")
        }
        return url
    }

    /// URL absolue canonique (`https://jolene.app` + lien normalisé). Utilisée pour les
    /// sorties non natives (Safari, espace établissement), quel que soit l'hôte d'origine.
    public static func canonicalURL(link: String) -> URL? {
        guard link.hasPrefix("/") else { return nil }
        return URL(string: canonicalOrigin + link)
    }

    /// Décompose un lien normalisé en chemin, query (sans « ? ») et fragment (sans « # »).
    public static func split(link: String) -> (path: String, query: String?, fragment: String?) {
        var rest = Substring(link)
        var fragment: String? = nil
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = rest[..<hash]
        }
        var query: String? = nil
        if let q = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: q)...])
            rest = rest[..<q]
        }
        return (String(rest), query, fragment)
    }

    /// Résolution WHATWG des segments « . » et « .. » (y compris leurs formes %2e).
    static func resolveDotSegments(_ path: String) -> String {
        let segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        var output: [Substring] = []
        for (index, segment) in segments.enumerated() {
            let isLast = index == segments.count - 1
            switch segment.lowercased() {
            case "..", ".%2e", "%2e.", "%2e%2e":
                if !output.isEmpty { output.removeLast() }
                if isLast { output.append("") }
            case ".", "%2e":
                if isLast { output.append("") }
            default:
                output.append(segment)
            }
        }
        return "/" + output.joined(separator: "/")
    }
}

/// Analyse `application/x-www-form-urlencoded` avec la sémantique de `URLSearchParams.get` :
/// « + » vaut espace, décodage pourcent, première occurrence retenue.
struct FormQuery {
    private let pairs: [(name: String, value: String)]

    init(_ raw: String, strippingPrefix prefix: Character? = nil) {
        var text = Substring(raw)
        if let prefix, text.first == prefix { text = text.dropFirst() }
        pairs = text.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            let name: Substring
            let value: Substring
            if let eq = pair.firstIndex(of: "=") {
                name = pair[..<eq]; value = pair[pair.index(after: eq)...]
            } else {
                name = pair; value = ""
            }
            return (Self.decode(name), Self.decode(value))
        }
    }

    func get(_ name: String) -> String? {
        pairs.first { $0.name == name }?.value
    }

    private static func decode(_ s: Substring) -> String {
        let plusDecoded = s.replacingOccurrences(of: "+", with: " ")
        return plusDecoded.removingPercentEncoding ?? plusDecoded
    }
}
