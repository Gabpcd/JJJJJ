import Foundation

/// Écrans soignant secondaires du lot 4 (blueprint `docs/mobile-swift/LOT4_PLAN.md` §1.1, §3 T1), portés par
/// `JoleneRoute.secondaire(_:)`. Posé par L4-T1 : chaque écran reste servi par sa page web canonique
/// (`DestinationLien.ecranNatifLivre` à `false`, ou repli natif de `repliAvantLivraison`) tant que sa tranche
/// n'a pas livré l'écran et passé sa ligne à `true` ; l'aiguillage vers l'écran natif est posé par T1c
/// (`SecondaryRouter`).
///
/// Pas de cas `inscriptionSoignant(ref:)` : `/inscription/soignant` appartient au lot 3 (`.inscription`), la
/// capture du code de parrainage est un effet de bord du coordinateur de liens (`ParrainageCapture`, T1c/T6).
///
/// `Hashable` (L4-T1c) : valeur de la route empilée `SecondaireRoute` de l'app (`SecondaryRouter`).
public enum EcranSecondaire: Hashable, Sendable {
    /// Explorer en vue Swipe (`/soignant/swipe-missions`, `/soignant/recherche-missions?vue=swipe`) — T3a/T3b.
    case swipe
    /// Recherches sauvegardées (`/soignant/parametres/recherches-sauvegardees`) — T4.
    case recherches
    /// Disponibilités (`/soignant/disponibilites`) — T5.
    case disponibilites
    /// Parrainage (`/soignant/parrainage`) — T6.
    case parrainage
    /// Litiges et réclamations (`/soignant/litiges?tab=&litige=`, fragment `#<id>` des pushs, alias
    /// `/soignant/reclamations`) — T8.
    case litiges(onglet: OngletLitiges?, litigeId: String?)
    /// Messagerie (`/soignant/messagerie?conv=`) — T7a/T7b.
    case messagerie(conversationId: String?)
    /// Copies officielles des bulletins — T10. `LinkRouter` garde `.revenus(section: .bulletins)` pour
    /// `/soignant/mes-gains?tab=bulletins` et l'alias `bulletins-paie` : T10 en fait la destination de cet écran
    /// (`DestinationLien`) en le livrant, avec l'entrée de Revenus posée par T1c.
    case bulletins(copieId: String?)
    /// Évaluations reçues (`/soignant/evaluations`) — T9.
    case evaluations
    /// Mon score (`/soignant/score`, alias `fiabilite`, `fiabilite-legacy`) — T9.
    case score
    /// Pool urgence (`/soignant/pool-urgence`) — T11.
    case poolUrgence
    /// Établissements exclus (`/soignant/exclusions`) — T11.
    case exclusions
    /// Détail de série (report de la décision 11 du lot 1) — T12. La route web garde `.serieDetail(id:)`
    /// (`LinkRouter`) ; T1c aiguille `.serieDetail` vers cet écran.
    case serie(id: String)

    /// Onglet de `/soignant/litiges` (`LitigesContestationsSoignant.tsx`, valeurs `litiges` et `reclamations`).
    public enum OngletLitiges: String, Hashable, Sendable, CaseIterable {
        case litiges, reclamations

        /// Lecture de `?tab=` (comparaison exacte) ; valeur inconnue ou absente → `nil` (onglet par défaut).
        public init?(tab: String?) {
            guard let tab, let onglet = OngletLitiges(rawValue: tab) else { return nil }
            self = onglet
        }
    }

    /// Nom de l'écran dans la clé de son coupe-circuit `ios_natif_<nom>_actif` (B0-bis, migration
    /// `20261102204450_drapeaux_ios_natif_lots_2_4_5.sql`, décision D18). Valeurs brutes implicites : aucun
    /// littéral Swift ne vaut exactement le nom d'une table de notations (garde-fou 18).
    public enum Nom: String, Equatable, Sendable, CaseIterable {
        case swipe, recherches, disponibilites, parrainage, litiges, reclamations, messagerie, bulletins
        case evaluations, score
        case poolUrgence = "pool_urgence"
        case exclusions, serie
    }

    /// Nom du coupe-circuit : l'onglet Réclamations de `/soignant/litiges` a le sien (`ios_natif_reclamations_actif`).
    public var nom: Nom {
        switch self {
        case .swipe: return .swipe
        case .recherches: return .recherches
        case .disponibilites: return .disponibilites
        case .parrainage: return .parrainage
        case .litiges(onglet: .reclamations, _): return .reclamations
        case .litiges: return .litiges
        case .messagerie: return .messagerie
        case .bulletins: return .bulletins
        case .evaluations: return .evaluations
        case .score: return .score
        case .poolUrgence: return .poolUrgence
        case .exclusions: return .exclusions
        case .serie: return .serie
        }
    }

    /// Clé `parametres_systeme` du coupe-circuit (lue par `FlagsPort` après `.ready`, décision 15 du lot 1).
    public var cleDrapeau: String { "ios_natif_\(nom.rawValue)_actif" }

    /// Destination native déjà servie par l'app avant la livraison de l'écran (comportement d'avant L4-T1
    /// conservé) : Explorer pour le swipe, le hub du compte pour le score. `nil` : page web canonique.
    public var repliAvantLivraison: JoleneRoute? {
        switch self {
        case .swipe: return .explorer
        case .score: return .monCompte
        default: return nil
        }
    }
}

public extension EcranSecondaire {
    /// Lien web de l'écran (L4-T1c) : chemin de `src/App.tsx` lu par `LinkRouter` (query et identifiants compris,
    /// encodés), servi par le renvoi web quand le coupe-circuit de l'écran est coupé (`RenvoiWebScreen`). Aller-retour
    /// exact par `LinkRouter` (`EcranSecondaireLienWebTests`), sauf les bulletins (route `.revenus(section: .bulletins)`
    /// gardée, `mes-gains?tab=bulletins&copie=`) et la série (route `.serieDetail(id:)` gardée).
    var lienWeb: String {
        switch self {
        case .swipe: return "/soignant/swipe-missions"
        case .recherches: return "/soignant/parametres/recherches-sauvegardees"
        case .disponibilites: return "/soignant/disponibilites"
        case .parrainage: return "/soignant/parrainage"
        case let .litiges(onglet, litigeId):
            return Self.lien("/soignant/litiges", [("tab", onglet?.rawValue), ("litige", litigeId)])
        case .messagerie(let conversationId):
            return Self.lien("/soignant/messagerie", [("conv", conversationId)])
        case .bulletins(let copieId):
            return Self.lien("/soignant/mes-gains", [("tab", "bulletins"), ("copie", copieId)])
        case .evaluations: return "/soignant/evaluations"
        case .score: return "/soignant/score"
        case .poolUrgence: return "/soignant/pool-urgence"
        case .exclusions: return "/soignant/exclusions"
        case .serie(let id):
            var permis = CharacterSet.urlPathAllowed
            permis.remove("/")
            return "/soignant/missions/serie/" + (id.addingPercentEncoding(withAllowedCharacters: permis) ?? id)
        }
    }

    /// URL canonique du lien web (`https://jolene.app` + `lienWeb`, `JoleneLink.canonicalURL`).
    var urlWeb: URL? { JoleneLink.canonicalURL(link: lienWeb) }

    /// Écran natif livré : ligne de `DestinationLien.ecranNatifLivre` passée à `true` par sa tranche (T3b…T12). Tant
    /// qu'elle vaut `false`, l'écran garde son renvoi web actuel et aucune entrée native ne le montre (`EntreesLot4`).
    var estLivre: Bool {
        switch self {
        case .serie(let id): return DestinationLien.ecranNatifLivre(.serieDetail(id: id))
        default: return DestinationLien.ecranNatifLivre(.secondaire(self))
        }
    }

    private static func lien(_ chemin: String, _ parametres: [(String, String?)]) -> String {
        var composants = URLComponents()
        composants.path = chemin
        let items = parametres.compactMap { nom, valeur in valeur.map { URLQueryItem(name: nom, value: $0) } }
        composants.queryItems = items.isEmpty ? nil : items
        return composants.percentEncodedPath + (composants.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
}

public extension FlagsPort {
    /// Coupe-circuit d'un écran secondaire du lot 4 (`ios_natif_<nom>_actif`), défaut fail-open (décision 15 du lot 1).
    func ecranActif(_ ecran: EcranSecondaire) async -> Bool {
        await ecranActif(cle: ecran.cleDrapeau, defaut: FlagsPolicy.defautFailOpen)
    }
}
