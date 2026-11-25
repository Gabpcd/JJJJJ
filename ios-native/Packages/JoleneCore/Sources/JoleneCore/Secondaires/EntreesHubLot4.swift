import Foundation

/// Entrées du hub du compte vers les écrans secondaires du lot 4 (L4-T1c), dans l'ordre et sous les titres du hub web
/// (`src/pages/MonCompteSoignant.tsx` l.92-110, après « Documents & protection ») : « Recherche & disponibilité »
/// (Recherches sauvegardées, Établissements exclus), Parrainage (section sans titre), « Suivi » (Litiges &
/// contestations). Libellés repris du web, aucun texte nouveau.
///
/// Seules les entrées dont l'écran est **livré** (`EcranSecondaire.estLivre`) sont rendues : un écran non livré garde
/// son renvoi web actuel et n'apparaît pas dans le hub natif. La section de l'app (`ActiviteSoignantSection`) est
/// posée une fois par T1c ; une tranche qui livre son écran passe sa ligne de `DestinationLien.ecranNatifLivre` et
/// son entrée apparaît, sans retoucher le hub (`LOT4_PLAN.md` §4).
///
/// Points d'entrée hors du hub web (intégration de la vague D, décision d, `DECISIONS_LOT4.md` précision 18) :
/// - pool urgence et score sont dans la barre latérale du web (`BarreNavigation.tsx` l.60 « Pool urgence », groupe
///   « Missions » ; l.68 « Mon score », groupe « Activité »), absente de l'app : leurs entrées suivent les sections du
///   hub web, sous les titres des groupes de la barre (`sectionsBarreLaterale`) ;
/// - les évaluations reçues n'ont aucune entrée dans l'interface web (lien, push, centre seulement) : entrée posée sous
///   « Activité », avec le score, libellé = titre de la page web (`EvaluationsSoignant.tsx` l.58, « Mes évaluations ») ;
/// - hors du hub : disponibilités (icône calendrier d'Explorer, comme `RechercheMissions.tsx` l.309-316,
///   `ExplorerDisponibilitesButton`), messagerie (bouton Messages de la barre, `MessagesNavButton`), bulletins (entrée
///   « Paie » de Revenus, lien résolu par `CibleNotification`), swipe (vue d'Explorer) ; la série n'a pas encore de
///   point d'entrée (carte de série du web non portée, `EntreesHubLot4.pointsDEntreeHorsHub`).
public enum EntreesHubLot4 {
    public struct Entree: Equatable, Sendable {
        public let ecran: EcranSecondaire
        public let libelle: String
        /// Identifiant d'accessibilité de l'entrée (`hub-<nom du coupe-circuit>`).
        public var identifiant: String { "hub-\(ecran.nom.rawValue)" }
    }

    public struct Section: Equatable, Sendable {
        /// Titre de la section ; `nil` pour une section sans titre (Parrainage, comme le web).
        public let titre: String?
        public let entrees: [Entree]
    }

    /// Sections du hub web, entrées comprises, avant filtrage.
    public static let sectionsWeb: [Section] = [
        Section(titre: "Recherche & disponibilité", entrees: [
            Entree(ecran: .recherches, libelle: "Recherches sauvegardées"),
            Entree(ecran: .exclusions, libelle: "Établissements exclus"),
        ]),
        Section(titre: nil, entrees: [Entree(ecran: .parrainage, libelle: "Parrainage")]),
        Section(titre: "Suivi", entrees: [
            Entree(ecran: .litiges(onglet: nil, litigeId: nil), libelle: "Litiges & contestations"),
        ]),
    ]

    /// Entrées de la barre latérale du web (`BarreNavigation.tsx`, `getSoignantSidebar`) sans place dans le hub web,
    /// sous les titres de leurs groupes, plus les évaluations (aucune entrée web), après les sections du hub web.
    public static let sectionsBarreLaterale: [Section] = [
        Section(titre: "Missions", entrees: [Entree(ecran: .poolUrgence, libelle: "Pool urgence")]),
        Section(titre: "Activité", entrees: [
            Entree(ecran: .score, libelle: "Mon score"),
            Entree(ecran: .evaluations, libelle: "Mes évaluations"),
        ]),
    ]

    /// Écrans livrés atteints hors du hub, et leur point d'entrée dans l'interface (`nil` : aucun, à poser).
    public static let pointsDEntreeHorsHub: [EcranSecondaire.Nom: String?] = [
        .swipe: "Explorer › commande Swipe · Liste",
        .disponibilites: "Explorer › icône calendrier « Mes disponibilités »",
        .messagerie: "barre de navigation › bouton Messages",
        .reclamations: "Litiges & contestations › onglet Réclamations",
        .bulletins: "Revenus › Paie",
        .serie: nil,
    ]

    /// Sections à rendre : entrées des écrans livrés seulement, sections vides retirées. Vide tant qu'aucune tranche
    /// d'écran du lot 4 n'a livré.
    public static func sections(livre: (EcranSecondaire) -> Bool = { $0.estLivre }) -> [Section] {
        (sectionsWeb + sectionsBarreLaterale).compactMap { section in
            let entrees = section.entrees.filter { livre($0.ecran) }
            return entrees.isEmpty ? nil : Section(titre: section.titre, entrees: entrees)
        }
    }
}
