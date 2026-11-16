import Foundation

/// Lot 3, T15 (D21, blueprint `LOT3_PLAN.md` §2.6) — nettoyage de tout ce que Sentry reçoit. Règle pure, sans Sentry :
/// la cible app (`Jolene/Composition/CrashReporting.swift`) l'applique dans `beforeSend` (message, valeurs d'exception,
/// transaction, empreinte, étiquettes, `extra`, contextes, fils d'Ariane de l'événement) et dans `beforeBreadcrumb`
/// (message et données de chaque fil d'Ariane).
///
/// Masqués, où qu'ils apparaissent dans un texte :
/// - les paramètres de rappel et de session `token_hash`, `code`, `access_token`, `refresh_token` (requête, fragment,
///   forme encodée `%3D`, forme JSON) — jamais `error_code`, `status_code` ni `barcode` ;
/// - les jetons porteurs (`Bearer …`) et les JWT isolés ;
/// - les adresses e-mail (forme encodée `%40` comprise) ;
/// - les IBAN (compacts ou par groupes de quatre, toutes casses), contrôle mod 97 non exigé : un IBAN mal saisi reste une
///   donnée bancaire.
/// Dans un dictionnaire, la valeur texte d'une clé sensible (`clesSensibles`) est masquée quel que soit son contenu ; les
/// nombres sont conservés (un `code` numérique est un code d'erreur, pas une valeur de session). Le nom de l'appareil
/// (contexte `device`, souvent le prénom de la personne) est retiré. Les fils d'Ariane réseau (`http`) sont rejetés.
///
/// Masquer trop (un hexadécimal pris pour un IBAN) est accepté ; laisser passer une donnée ne l'est pas.
public enum CrashScrubber {
    /// Remplace toute valeur sensible.
    public static let masque = "[masqué]"

    /// Paramètres de rappel et de session jamais transmis (blueprint §2.6).
    public static let parametresSensibles = ["token_hash", "code", "access_token", "refresh_token"]

    /// Clés dont la valeur texte est toujours masquée (comparaison sans casse).
    public static let clesSensibles: Set<String> = [
        "token_hash", "code", "access_token", "refresh_token", "email", "iban", "password", "mot_de_passe",
    ]

    /// Catégories ou types de fils d'Ariane rejetés : réseau (`enableNetworkBreadcrumbs = false`, défense en profondeur).
    public static let filsRejetes: Set<String> = ["http"]

    // MARK: - Textes

    /// Texte nettoyé (idempotent : un texte déjà nettoyé est rendu tel quel).
    public static func texte(_ brut: String) -> String {
        guard !brut.isEmpty else { return brut }
        var net = brut
        for regle in regles {
            net = remplacer(regle.motif, dans: net, par: regle.gabarit)
        }
        return net
    }

    // MARK: - Valeurs et dictionnaires

    /// Valeur nettoyée : texte et URL (rendue en texte) nettoyés, dictionnaires et tableaux parcourus, nombres, dates et
    /// booléens conservés.
    public static func valeur(_ brute: Any) -> Any {
        switch brute {
        case let chaine as String: return texte(chaine)
        case let url as URL: return texte(url.absoluteString)
        case let dictionnaire as [String: Any]: return self.dictionnaire(dictionnaire)
        case let tableau as [Any]: return tableau.map(valeur)
        default: return brute
        }
    }

    /// Dictionnaire nettoyé (données d'un fil d'Ariane, `extra`, un contexte).
    public static func dictionnaire(_ brut: [String: Any]) -> [String: Any] {
        var net: [String: Any] = [:]
        for (cle, valeurBrute) in brut {
            if clesSensibles.contains(cle.lowercased()), valeurBrute is String || valeurBrute is URL {
                net[cle] = masque
            } else {
                net[cle] = valeur(valeurBrute)
            }
        }
        return net
    }

    /// Étiquettes nettoyées (`tags`).
    public static func etiquettes(_ brutes: [String: String]) -> [String: String] {
        var net: [String: String] = [:]
        for (cle, valeur) in brutes {
            net[cle] = clesSensibles.contains(cle.lowercased()) ? masque : texte(valeur)
        }
        return net
    }

    /// Contextes nettoyés, sans le nom de l'appareil.
    public static func contextes(_ bruts: [String: [String: Any]]) -> [String: [String: Any]] {
        var net: [String: [String: Any]] = [:]
        for (nom, contexte) in bruts {
            var propre = dictionnaire(contexte)
            if nom == "device" { propre.removeValue(forKey: "name") }
            net[nom] = propre
        }
        return net
    }

    // MARK: - Fils d'Ariane

    /// Faux pour un fil d'Ariane réseau, rejeté par `beforeBreadcrumb`.
    public static func filConserve(categorie: String, type: String?) -> Bool {
        !filsRejetes.contains(categorie.lowercased()) && !filsRejetes.contains((type ?? "").lowercased())
    }

    // MARK: - Règles

    private struct Regle {
        let motif: String
        let gabarit: String
    }

    /// Ordre : jetons d'abord (un JWT contient des points et des tirets), puis paramètres, e-mails, IBAN.
    private static let regles: [Regle] = {
        let noms = parametresSensibles.joined(separator: "|")
        let m = NSRegularExpression.escapedTemplate(for: masque)
        return [
            // Jeton porteur : `Bearer <jeton>`.
            Regle(motif: #"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]+"#, gabarit: "$1 \(m)"),
            // JWT isolé (trois segments base64url, en-tête `eyJ`).
            Regle(motif: #"eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}"#, gabarit: m),
            // Paramètre de requête ou de fragment, éventuellement encodé (`%3F`, `%26`, `%23` avant le nom, `%3D` après) ;
            // le nom n'est jamais la fin d'un autre (`error_code`, `barcode`).
            Regle(motif: #"(?i)(?:(?<![A-Za-z0-9_])|(?<=%3F|%26|%23))("# + noms + #")(\s*=\s*|%3D)[^&#\s"'<>]*"#,
                  gabarit: "$1$2\(m)"),
            // Clé JSON dans un texte (corps de réponse illisible, description d'erreur).
            Regle(motif: #"(?i)("(?:"# + noms + #")"\s*:\s*)"[^"]*""#, gabarit: "$1\"\(m)\""),
            // Adresse e-mail, `@` ou `%40`.
            Regle(motif: #"(?i)[A-Z0-9._%+-]+(?:@|%40)[A-Z0-9.-]+\.[A-Z]{2,}"#, gabarit: m),
            // IBAN : pays, clé, puis 8 à 32 caractères par groupes de quatre (espaces facultatifs).
            Regle(motif: #"(?i)\b[A-Z]{2}[0-9]{2}(?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,4})?\b"#, gabarit: m),
        ]
    }()

    private static func remplacer(_ motif: String, dans texte: String, par gabarit: String) -> String {
        // Motifs constants, couverts par `CrashScrubberTests` : une compilation impossible serait un défaut du code.
        guard let expression = try? NSRegularExpression(pattern: motif) else { return masque }
        let plage = NSRange(texte.startIndex..<texte.endIndex, in: texte)
        return expression.stringByReplacingMatches(in: texte, range: plage, withTemplate: gabarit)
    }
}
