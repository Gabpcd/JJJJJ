import Foundation

/// Forme montrable d'un lien (lot 3, T3a) : PRINCIPES §7, aucun identifiant ni jeton dans les logs.
///
/// Un segment de chemin n'est montré que s'il appartient au vocabulaire fixe des routes
/// (`segmentsStatiques`) ; tout autre segment (identifiant, jeton, segment inconnu ou de casse
/// différente) devient `‹masqué›`. La query et le fragment ne sont jamais montrés, seulement leur
/// présence. Un segment manquant au vocabulaire n'expose donc rien : il est masqué à tort.
public enum LienMasque {
    public static let masque = "‹masqué›"

    /// Segments littéraux des chemins connus : table de `LinkRouter` (`src/App.tsx`), motifs AASA
    /// (`AASAPatterns.paths`) et chemins web renvoyés vers Safari par le routage push
    /// (`navigationPathForEvent`) ou l'Accueil (`AccueilPresentation`).
    static let segmentsStatiques: Set<String> = [
        // Table de `LinkRouter`.
        "connexion", "reset-password", "inscription", "confirmer", "soignant", "reprendre", "completer",
        "tableau-de-bord", "recherche-missions", "swipe-missions", "missions", "mes-matches", "planning",
        "calendrier-sync", "historique-missions", "mes-gains", "mes-factures-honoraires", "mes-avances",
        "bulletins-paie", "profil", "reputation", "mon-compte", "parametres", "parametres-complet", "score",
        "fiabilite", "fiabilite-legacy", "notifications", "stripe-connect", "serie", "mission", "mes-favoris",
        // Motifs AASA.
        "etablissement", "groupe", "admin", "auth", "psc", "callback", "etab", "invitation", "contrat",
        // Chemins servis par Safari (`src/App.tsx`, routage push, Accueil).
        "certificat", "completion", "succes", "litiges", "reclamations", "mes-reclamations", "mes-documents",
        "presences", "contrats", "facturation",
    ]

    /// Gabarit d'une URL : chemin masqué, puis `?‹masqué›` et `#‹masqué›` si la query ou le fragment
    /// sont présents et non vides. L'hôte n'est pas montré (toujours l'origine canonique).
    public static func gabarit(_ url: URL) -> String {
        var texte = gabarit(chemin: url.path)
        if let query = url.query, !query.isEmpty { texte += "?" + masque }
        if let fragment = url.fragment, !fragment.isEmpty { texte += "#" + masque }
        return texte
    }

    /// Gabarit d'un chemin (sans query ni fragment) : segments hors vocabulaire masqués.
    public static func gabarit(chemin: String) -> String {
        let segments = chemin.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return "/" }
        return "/" + segments.map { segmentsStatiques.contains($0) ? $0 : masque }.joined(separator: "/")
    }
}

/// Description masquée d'une route : nom du cas et valeurs non sensibles seulement (section,
/// retour Stripe, page d'inscription) ; identifiants, URL, query et identifiants de rappel masqués.
extension JoleneRoute: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .connexion: return "connexion"
        case .resetPassword(let credentials):
            return "resetPassword(\(credentials.map(String.init(describing:)) ?? "sans identifiants"))"
        case .confirmerInscription(let credentials):
            return "confirmerInscription(\(credentials.map(String.init(describing:)) ?? "sans identifiants"))"
        case .inscription(let etape): return "inscription(\(etape.resume))"
        case .accueil: return "accueil"
        case .explorer: return "explorer"
        case .missions: return "missions"
        case .missionDetail: return "missionDetail(id masqué)"
        case .serieDetail: return "serieDetail(id masqué)"
        case .revenus(let section): return "revenus(\(section.rawValue))"
        case .monCompte: return "monCompte"
        case .profil: return "profil"
        case .notifications: return "notifications"
        case .parametresNotifications: return "parametresNotifications"
        case .stripeConnect(let retour):
            switch retour {
            case .succes: return "stripeConnect(succes)"
            case .rafraichir: return "stripeConnect(rafraichir)"
            case nil: return "stripeConnect(sans retour)"
            }
        case .safari(let url): return "safari(\(LienMasque.gabarit(url)))"
        case .etablissement(let url): return "etablissement(\(LienMasque.gabarit(url)))"
        }
    }
    public var debugDescription: String { description }
}

/// La query d'une étape porte un code de parrainage (`ref`, `parrain`) : jamais montrée.
extension EtapeInscription: CustomStringConvertible, CustomDebugStringConvertible {
    var resume: String { "\(page.rawValue), \(query == nil ? "sans query" : "query masquée")" }
    public var description: String { "EtapeInscription(\(resume))" }
    public var debugDescription: String { description }
}
