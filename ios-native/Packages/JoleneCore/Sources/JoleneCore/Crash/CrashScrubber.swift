import Foundation

/// Lot 3, T15 (D21, blueprint `LOT3_PLAN.md` §2.6) — nettoyage de tout ce que Sentry reçoit. Règle pure, sans Sentry :
/// la cible app (`Jolene/Composition/CrashReporting.swift`) l'applique dans `beforeSend` et `beforeBreadcrumb`, propriété
/// par propriété (recensement de Sentry 9.32.0 : `CrashReportingTests`, revue B8 n°1, M1 et m3).
///
/// Masqués, où qu'ils apparaissent dans un texte :
/// - la valeur d'un paramètre sensible (`finsDeNomsSensibles` : famille des jetons — `token`, `access_token`,
///   `refresh_token`, `provider_token`, `provider_refresh_token`, `token_hash`, formes camelCase comprises — et mots de
///   passe ; `nomsSensiblesExacts` : `code`, `email`, `iban`) : en requête ou en fragment, encodé une ou deux fois (`%3D`,
///   `%253D`), en JSON (échappé ou non) et dans une description Swift (`refreshToken: "…"`) — jamais `error_code`,
///   `status_code`, `barcode`, `token_type` ;
/// - les jetons porteurs (`Bearer …`) et les JWT isolés ;
/// - les adresses e-mail (`@`, `%40` ou `%2540`) ;
/// - les IBAN (compacts, ou par groupes de quatre séparés par une espace, une espace insécable U+00A0 ou U+202F, ou un
///   tiret ; toutes casses), contrôle mod 97 non exigé : un IBAN mal saisi reste une donnée bancaire. Un UUID (mission,
///   présence) n'est jamais pris pour un IBAN.
/// Un texte de plus de `longueurMaximale` caractères est tronqué avant tout traitement (`marqueTroncature`) : le coût
/// reste borné (revue B8 n°1, m1). Dans un dictionnaire, la valeur d'une clé sensible (`estCleSensible`) est masquée
/// quel qu'en soit le type (texte, tableau, dictionnaire, nombre) ; seul un nombre sous la clé `code` est conservé (code
/// d'erreur NSError ou HTTP). Le nom de l'appareil (contexte `device`, souvent le prénom de la personne) est retiré. Les
/// fils d'Ariane réseau (`http`) sont rejetés.
///
/// Masquer trop (un hexadécimal pris pour un IBAN) est accepté ; laisser passer une donnée ne l'est pas.
public enum CrashScrubber {
    /// Remplace toute valeur sensible.
    public static let masque = "[masqué]"

    /// Longueur (en caractères) au-delà de laquelle un texte est tronqué avant nettoyage.
    public static let longueurMaximale = 8_192
    /// Ajouté à la fin d'un texte tronqué.
    public static let marqueTroncature = "…[tronqué]"

    /// Fins de noms de paramètres sensibles (motif, sans casse) : tout nom qui se termine ainsi est sensible, quel que soit
    /// son préfixe (`refresh_token`, `refreshToken`, `provider_refresh_token`, `tokenHash`, `new_password`, `motDePasse`).
    static let finsDeNomsSensibles = #"token(?:[_-]?hash)?|password|mot[_-]?de[_-]?passe"#
    /// Noms de paramètres sensibles exacts (motif, sans casse) : jamais la fin d'un autre nom (`error_code`, `barcode`).
    static let nomsSensiblesExacts = #"code|email|iban"#

    /// Clés de dictionnaire sensibles exactes, comparées sans casse ni séparateur (`_`, `-`).
    public static let clesSensibles: Set<String> = ["code", "email", "iban"]
    /// Fins de clés sensibles, comparées sans casse ni séparateur : `refresh_token`, `refreshToken`,
    /// `provider_refresh_token`, `token_hash`, `tokenHash`, `new_password`, `mot_de_passe`…
    public static let suffixesSensibles = ["token", "tokenhash", "password", "motdepasse"]

    /// Catégories ou types de fils d'Ariane rejetés : réseau (`enableNetworkBreadcrumbs = false`, défense en profondeur).
    public static let filsRejetes: Set<String> = ["http"]

    // MARK: - Textes

    /// Texte nettoyé, tronqué au-delà de `longueurMaximale` (idempotent sous cette longueur).
    public static func texte(_ brut: String) -> String {
        guard !brut.isEmpty else { return brut }
        guard let regles else { return masque } // repli fermé : motif invalide (exclu par `CrashScrubberTests`)
        var net = brut
        var tronque = false
        if let coupure = brut.index(brut.startIndex, offsetBy: longueurMaximale, limitedBy: brut.endIndex),
           coupure < brut.endIndex {
            net = String(brut[..<coupure])
            tronque = true
        }
        for regle in regles {
            if regle.adresse {
                net = masquerAdresses(net, arobase: regle.expression)
            } else {
                let plage = NSRange(net.startIndex..<net.endIndex, in: net)
                net = regle.expression.stringByReplacingMatches(in: net, range: plage, withTemplate: regle.gabarit)
            }
        }
        return tronque ? net + marqueTroncature : net
    }

    /// Caractères d'une partie locale d'adresse e-mail (forme encodée `%40` comprise).
    private static let partieLocale = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._%+-")

    /// Adresses e-mail : chaque arobase suivie d'un domaine (`arobase`, recherche ancrée sur `@`, `%40` ou `%2540`) est
    /// masquée avec la partie locale qui la précède, lue à rebours sur 64 caractères au plus (RFC 5321). Coût linéaire :
    /// aucune position du texte n'est essayée comme début d'adresse (revue B8 n°1, m1).
    private static func masquerAdresses(_ texte: String, arobase: NSRegularExpression) -> String {
        let source = texte as NSString
        var net = ""
        var curseur = 0
        for trouve in arobase.matches(in: texte, range: NSRange(location: 0, length: source.length)) {
            var debut = trouve.range.location
            while debut > curseur, trouve.range.location - debut < 64,
                  let caractere = UnicodeScalar(source.character(at: debut - 1)), partieLocale.contains(caractere) {
                debut -= 1
            }
            guard debut < trouve.range.location else { continue } // `@domaine` sans partie locale : pas une adresse
            net += source.substring(with: NSRange(location: curseur, length: debut - curseur)) + masque
            curseur = NSMaxRange(trouve.range)
        }
        return curseur == 0 ? texte : net + source.substring(from: curseur)
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

    /// Vrai pour une clé dont toute valeur est masquée (sans casse ni séparateur `_` ou `-`).
    public static func estCleSensible(_ cle: String) -> Bool {
        let normalisee = cle.lowercased().filter { $0 != "_" && $0 != "-" }
        return clesSensibles.contains(normalisee) || suffixesSensibles.contains { normalisee.hasSuffix($0) }
    }

    /// Dictionnaire nettoyé (données d'un fil d'Ariane, `extra`, un contexte, `mechanism.data`).
    public static func dictionnaire(_ brut: [String: Any]) -> [String: Any] {
        var net: [String: Any] = [:]
        for (cle, valeurBrute) in brut {
            if estCleSensible(cle), !(cle.lowercased() == "code" && valeurBrute is NSNumber) {
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
            net[cle] = estCleSensible(cle) ? masque : texte(valeur)
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

    struct Regle {
        let expression: NSRegularExpression
        let gabarit: String
        /// Vrai pour la règle des adresses e-mail : `expression` trouve l'arobase et le domaine, la partie locale est
        /// lue à rebours par `masquerAdresses` ; `gabarit` n'est pas utilisé.
        var adresse = false
    }

    /// Expressions compilées une seule fois (revue B8 n°1, m1) ; nil si l'une ne compile pas (repli fermé de `texte`).
    /// Ordre : jetons d'abord (un JWT contient des points et des tirets), puis paramètres, JSON, descriptions Swift,
    /// e-mails, IBAN. Coût linéaire : chaque motif commence par un caractère précis (`%`, `"`, `\`, `@`, l'initiale d'un
    /// nom sensible), ce qui laisse le moteur sauter les autres positions, ou par une borne explicite (JWT, IBAN) ; les
    /// parties variables sont bornées (adresse e-mail) ou sans chevauchement avec ce qui les suit. Les bornes sont écrites
    /// en classes ASCII plutôt qu'en `\b`, cinq fois plus lent dès que le texte n'est plus ASCII (un « [masqué] » suffit).
    static let regles: [Regle]? = {
        let fins = finsDeNomsSensibles, exacts = nomsSensiblesExacts
        let m = NSRegularExpression.escapedTemplate(for: masque)
        // Nom sensible dans un texte : fin de nom sensible (le préfixe reste hors de la correspondance), ou nom exact qui
        // n'est pas la fin d'un autre.
        let nom = "(" + fins + #"|(?<![A-Za-z0-9_])(?:"# + exacts + "))"
        // Nom sensible complet, entre guillemets (JSON).
        let nomComplet = #"(?:[A-Za-z0-9_-]*(?:"# + fins + ")|" + exacts + ")"
        // Chaîne JSON ou Swift entre guillemets (échappements compris), coupée par la fin du texte au besoin.
        let chaine = #""(?:[^"\\]|\\.)*(?:"|\z)"#
        // Séparateur d'une valeur de paramètre : `=`, ou `%3D` et `%253D` (encodé une ou deux fois).
        let egal = #"(\s*=\s*|%3D|%253D)"#
        // Valeur d'un paramètre : entre guillemets, ou nue jusqu'au séparateur suivant (`&`, `#`, blanc, encodés compris).
        let valeurDeParametre = #"(?:"# + chaine + #"|'[^']*(?:'|\z)|(?:[^&#\s"'<>%]|%(?!26|23|2526|2523))*)"#
        let separateurIBAN = #"[ \x{00A0}\x{202F}-]"#
        let uuid = #"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}(?![A-Z0-9_])"#
        // Gabarit nil : règle des adresses e-mail, appliquée par `masquerAdresses`.
        let motifs: [(String, String?)] = [
            // Jeton porteur : `Bearer <jeton>`.
            (#"(?i)(?<![A-Z0-9_])(bearer)\s+[A-Za-z0-9._~+/=-]+"#, "$1 \(m)"),
            // JWT isolé (trois segments base64url, en-tête `eyJ`), jamais commencé au milieu d'un autre segment.
            (#"(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{4,}+\.[A-Za-z0-9_-]{4,}+\.[A-Za-z0-9_-]{4,}+"#, m),
            // Paramètre de requête ou de fragment : `refresh_token=…`, `provider_refresh_token%3D…`, `code=…`.
            ("(?i)" + nom + egal + valeurDeParametre, "$1$2\(m)"),
            // Nom exact après un séparateur encodé une ou deux fois (`%3Fcode%3D…`, `%253Fcode%253D…`) : la règle
            // précédente exige qu'aucune lettre ni aucun chiffre ne le précède.
            (#"(?i)(%3F|%26|%23|%253F|%2526|%2523)("# + exacts + ")" + egal + valeurDeParametre, "$1$2$3\(m)"),
            // Clé JSON échappée (JSON dans une chaîne JSON) : `\"refresh_token\":\"…\"`.
            (#"(?i)(\\""# + nomComplet + #"\\"\s*:\s*)\\"(?:[^"\\]|\\(?!"))*(?:\\"|\z)"#, #"$1\\"\#(m)\\""#),
            // Clé JSON dans un texte (corps de réponse illisible, description d'erreur).
            (#"(?i)(""# + nomComplet + #""\s*:\s*)"# + chaine, "$1\"\(m)\""),
            // Description Swift (`String(describing:)`, `dump`) : `refreshToken: "…"`, `tokenHash: Optional("…")`.
            ("(?i)" + nom + #"(\s*:\s*(?:Optional\()?)"# + chaine, "$1$2\"\(m)\""),
            // Adresse e-mail : arobase (`@`, `%40` ou `%2540`) et domaine borné (RFC 5321) ; la partie locale, au plus 64
            // caractères avant l'arobase, est lue à rebours (`masquerAdresses`).
            (#"(?i)(?:@|%2540|%40)[A-Z0-9-]{1,63}(?:\.[A-Z0-9-]{1,63}){0,8}\.[A-Z]{2,63}"#, nil),
            // IBAN : pays, clé, puis 8 à 32 caractères par groupes de quatre (séparateurs facultatifs) ; jamais un UUID ni
            // la suite d'un identifiant à tirets.
            (#"(?i)(?<![A-Z0-9_-])(?!"# + uuid + #")[A-Z]{2}[0-9]{2}(?:"# + separateurIBAN + #"?[A-Z0-9]{4}){2,7}(?:"#
                + separateurIBAN + #"?[A-Z0-9]{1,4})?(?![A-Z0-9_])"#, m),
        ]
        var compilees: [Regle] = []
        for (motif, gabarit) in motifs {
            guard let expression = try? NSRegularExpression(pattern: motif) else { return nil }
            compilees.append(Regle(expression: expression, gabarit: gabarit ?? "", adresse: gabarit == nil))
        }
        return compilees
    }()
}
