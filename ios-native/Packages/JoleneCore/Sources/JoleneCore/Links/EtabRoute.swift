import Foundation

/// Route d'un lien Jolene **dans l'espace établissement** (lot 5, T2b ; `docs/mobile-swift/LOT5_PLAN.md` §3 T2,
/// D29, `PARITE_ETABLISSEMENT.md`). Additive : `LinkRouter.route(url:)`, `LinkRouter.resolve(link:)` et leur
/// `.etablissement(URL)` sont inchangés (espace soignant, lien reçu sans espace). Cette table ne sert que l'espace
/// établissement ouvert (`AiguillageLiens.ouvrirEspaceEtablissement`).
///
/// Table (chemin sans query ni fragment, barre oblique finale ignorée), dérivée des routes établissement de
/// `src/App.tsx` (47 routes, matrice de parité de T0) :
///
/// | Chemin | Route |
/// |---|---|
/// | `/etablissement/tableau-de-bord`, alias `/etablissement/dashboard` (`Navigate`) | `.accueil` |
/// | `/etablissement/missions` (`?statut=`, `?periode=` tels que reçus, `ListeMissions.tsx` l.48-50) | `.missions` |
/// | `/etablissement/missions/creer` | `.publierMission` |
/// | `/etablissement/missions/{id}` | `.missionDetail(id:)` |
/// | `/etablissement/presences` (`?tab=` tel que reçu, `PresencesEtablissement.tsx` l.56) | `.presences(onglet:)` |
/// | `/etablissement/presences/mission/{id}` | `.presencesMission(id:)` |
/// | `/etablissement/contrats` (`?statut=`, `ListeContrats.tsx` l.55), alias `/assurance`, `/contrat-plateforme` (`Navigate`, query perdue) | `.contrats(statut:)` |
/// | `/contrat/{id}` (soignant et établissement : résolu par l'espace courant) | `.contrat(id:)` |
/// | `/etablissement/messagerie` (`?conv=`, `PageMessagerie.tsx` l.128) | `.messagerie(conversation:)` |
/// | `/etablissement/mon-compte` | `.monCompte` |
/// | tout le reste : 34 routes établissement en renvoi web assumé (dont `/etablissement/missions/{id}/modifier`, `/contrat/{id}/certificat`, `/etab/invitation/{token}`, `/inscription/etablissement`), routes soignant, admin, groupe, hors AASA | `.safari(URL)` |
///
/// La table ne dit pas si l'écran est livré : `presentation(canonique:)` renvoie vers Safari une route dont la
/// tranche n'est pas mergée (`EtabDestination.ecranLivre`), comme `DestinationLien` pour l'espace soignant.
/// Journalisation : `description` masque identifiants et query (`LienMasque`), jamais l'URL.
public enum EtabRoute: Equatable, Sendable, CustomStringConvertible {
    case accueil
    case missions(statut: String?, periode: String?)
    case publierMission
    case missionDetail(id: String)
    case presences(onglet: String?)
    case presencesMission(id: String)
    case contrats(statut: String?)
    case contrat(id: String)
    case messagerie(conversation: String?)
    case monCompte
    case safari(URL)

    public var isNative: Bool {
        if case .safari = self { return false }
        return true
    }

    /// Onglet et écran empilé dans l'espace établissement ; nil pour un renvoi web, et pour la liste des contrats
    /// tant que T10 n'a pas choisi son point d'ancrage dans la coquille (aucun onglet « Contrats », D13).
    public var cible: CibleEtablissement? {
        switch self {
        case .accueil: return CibleEtablissement(onglet: .accueil)
        case let .missions(statut, periode): return CibleEtablissement(onglet: .missions, statut: statut, periode: periode)
        case .publierMission: return CibleEtablissement(onglet: .missions, destination: .publication)
        case let .missionDetail(id): return CibleEtablissement(onglet: .missions, destination: .detailMission(id: id))
        case let .presences(onglet): return CibleEtablissement(onglet: .presences, ongletPresences: onglet)
        case let .presencesMission(id): return CibleEtablissement(onglet: .presences, destination: .presencesMission(missionId: id))
        case .contrats: return nil                                                              // T10
        case let .contrat(id): return CibleEtablissement(onglet: .missions, destination: .contrat(id: id))
        case let .messagerie(conversation):
            return CibleEtablissement(onglet: .messages, destination: conversation.map { .conversation(id: $0) })
        case .monCompte: return CibleEtablissement(onglet: .compte)
        case .safari: return nil
        }
    }

    /// Ce que l'espace établissement présente pour ce lien : l'onglet (écran provisoire compris) ou l'écran empilé
    /// livré, sinon un renvoi web sur l'URL canonique (query et fragment conservés). Jamais un lien sans effet.
    public func presentation(canonique: URL) -> PresentationLienEtablissement {
        guard let cible, cible.ecranLivre else { return .renvoiWeb(canonique) }
        return .naviguer(cible)
    }

    /// Cas de route, identifiants et valeurs de query masqués.
    public var description: String {
        let m = LienMasque.masque
        switch self {
        case .accueil: return "EtabRoute.accueil"
        case let .missions(statut, periode):
            return "EtabRoute.missions(statut: \(statut == nil ? "nil" : m), periode: \(periode == nil ? "nil" : m))"
        case .publierMission: return "EtabRoute.publierMission"
        case .missionDetail: return "EtabRoute.missionDetail(\(m))"
        case let .presences(onglet): return "EtabRoute.presences(\(onglet == nil ? "nil" : m))"
        case .presencesMission: return "EtabRoute.presencesMission(\(m))"
        case let .contrats(statut): return "EtabRoute.contrats(\(statut == nil ? "nil" : m))"
        case .contrat: return "EtabRoute.contrat(\(m))"
        case let .messagerie(conversation): return "EtabRoute.messagerie(\(conversation == nil ? "nil" : m))"
        case .monCompte: return "EtabRoute.monCompte"
        case .safari: return "EtabRoute.safari(\(m))"
        }
    }

    /// Libellé DEBUG `deeplink-route` (démo seulement : données fictives), format de `PushTapIntent.libelleDebug`.
    public var libelleDebug: String {
        switch self {
        case .accueil: return "etab accueil"
        case let .missions(statut, _): return "etab missions" + (statut.map { "(\($0))" } ?? "")
        case .publierMission: return "etab publierMission"
        case let .missionDetail(id): return "etab missionDetail \(id)"
        case let .presences(onglet): return "etab presences" + (onglet.map { "(\($0))" } ?? "")
        case let .presencesMission(id): return "etab presencesMission \(id)"
        case let .contrats(statut): return "etab contrats" + (statut.map { "(\($0))" } ?? "")
        case let .contrat(id): return "etab contrat \(id)"
        case let .messagerie(conversation): return "etab messagerie" + (conversation.map { "(\($0))" } ?? "")
        case .monCompte: return "etab monCompte"
        case let .safari(url): return "etab safari \(url.absoluteString)"
        }
    }
}

/// Onglet de la coquille établissement (D13) et écran empilé éventuel (`EtabDestination`, registre de T2a), avec les
/// valeurs de query que l'écran de la tranche lira (portées brutes, comme `searchParams.get` du web ; l'écran décide).
public struct CibleEtablissement: Equatable, Sendable {
    public enum Onglet: String, Equatable, Sendable, CaseIterable {
        case accueil, missions, presences, messages, compte
    }

    public var onglet: Onglet
    public var destination: EtabDestination?
    /// `?statut=` et `?periode=` de la liste des missions (T5).
    public var statut: String?
    public var periode: String?
    /// `?tab=` de la page Présences (T8).
    public var ongletPresences: String?

    public init(onglet: Onglet, destination: EtabDestination? = nil, statut: String? = nil, periode: String? = nil,
                ongletPresences: String? = nil) {
        self.onglet = onglet; self.destination = destination
        self.statut = statut; self.periode = periode; self.ongletPresences = ongletPresences
    }

    /// Onglet seul : toujours présent dans la coquille (écran provisoire compris, comme les onglets soignant de
    /// `DestinationLien.ecranNatifLivre`) ; écran empilé : livré par sa tranche (`EtabDestination.ecranLivre`).
    public var ecranLivre: Bool { destination?.ecranLivre ?? true }
}

/// Présentation d'un lien dans l'espace établissement ouvert.
public enum PresentationLienEtablissement: Equatable, Sendable {
    case naviguer(CibleEtablissement)
    /// URL canonique servie par Safari (présentateur `.safari`, jamais `openURL`).
    case renvoiWeb(URL)
}

extension EtabDestination {
    /// Écran livré dans l'app : une ligne par tranche, que la tranche qui livre l'écran passe à `true` (avec sa ligne
    /// de `EtabDestinations.swift`). Avant : le lien qui y mène est un renvoi web, jamais un écran provisoire empilé.
    public var ecranLivre: Bool {
        switch self {
        case .detailMission: return true         // T5
        case .candidatures: return true          // T6
        case .pointage: return true              // T7
        case .presencesMission: return false     // T8
        case .publication: return false          // T9
        case .contrat: return false              // T10
        case .conversation: return false         // T11
        }
    }
}

extension LinkRouter {
    /// Route d'un lien interne (chemin relatif ou URL d'un hôte de `JoleneLink.trustedWebHosts`) dans l'espace
    /// établissement, et URL canonique du lien (renvoi web). `nil` si le lien n'est pas un lien Jolene. Additif :
    /// `resolve(link:)` reste la table de l'espace soignant.
    public static func etablissementDestination(link rawLink: String) -> (route: EtabRoute, canonique: URL)? {
        guard let link = JoleneLink.normalize(rawLink), let canonique = JoleneLink.canonicalURL(link: link) else { return nil }
        let parts = JoleneLink.split(link: link)
        return (routeEtablissement(path: parts.path, query: parts.query ?? "", canonique: canonique), canonique)
    }

    private static func routeEtablissement(path rawPath: String, query: String, canonique: URL) -> EtabRoute {
        var path = rawPath
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        let parametres = FormQuery(query)

        switch path {
        case "/etablissement/tableau-de-bord", "/etablissement/dashboard": return .accueil
        case "/etablissement/missions": return .missions(statut: parametres.get("statut"), periode: parametres.get("periode"))
        case "/etablissement/missions/creer": return .publierMission
        case "/etablissement/presences": return .presences(onglet: parametres.get("tab"))
        case "/etablissement/contrats": return .contrats(statut: parametres.get("statut"))
        // Alias `Navigate` (`src/App.tsx` l.424, l.434) : la redirection ne reprend pas la query du lien.
        case "/etablissement/assurance", "/etablissement/contrat-plateforme": return .contrats(statut: nil)
        case "/etablissement/messagerie": return .messagerie(conversation: parametres.get("conv"))
        case "/etablissement/mon-compte": return .monCompte
        default: break
        }
        if segments.count == 3, segments[0] == "etablissement", segments[1] == "missions", let id = identifiant(segments[2]) {
            return .missionDetail(id: id)
        }
        if segments.count == 4, segments[0] == "etablissement", segments[1] == "presences", segments[2] == "mission",
           let id = identifiant(segments[3]) {
            return .presencesMission(id: id)
        }
        if segments.count == 2, segments[0] == "contrat", let id = identifiant(segments[1]) {
            return .contrat(id: id)
        }
        return .safari(canonique)
    }

    /// Segment d'identifiant décodé (le web encode avec `encodeURIComponent`) ; `nil` si vide.
    private static func identifiant(_ segment: String) -> String? {
        let decode = segment.removingPercentEncoding ?? segment
        return decode.isEmpty ? nil : decode
    }
}
