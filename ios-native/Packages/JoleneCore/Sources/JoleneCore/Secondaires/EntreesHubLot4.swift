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
/// Hors du hub web, donc hors de cette liste : score et pool urgence (barre latérale web), évaluations, disponibilités
/// (Explorer web), messagerie (bouton Messages de la barre, `MessagesNavButton`), bulletins (entrée de Revenus, lien
/// résolu par `CibleNotification`), série (détail d'une mission).
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

    /// Sections à rendre : entrées des écrans livrés seulement, sections vides retirées. Vide tant qu'aucune tranche
    /// d'écran du lot 4 n'a livré.
    public static func sections(livre: (EcranSecondaire) -> Bool = { $0.estLivre }) -> [Section] {
        sectionsWeb.compactMap { section in
            let entrees = section.entrees.filter { livre($0.ecran) }
            return entrees.isEmpty ? nil : Section(titre: section.titre, entrees: entrees)
        }
    }
}
