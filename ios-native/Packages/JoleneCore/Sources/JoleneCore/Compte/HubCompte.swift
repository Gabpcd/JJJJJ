import Foundation

/// Entrées du hub « Mon compte » livrées par le lot 3, T11, hors écrans natifs (`MonCompteSoignant.tsx`).
/// Chaque entrée passe par `JoleneRoute` puis `DestinationLien.destination` : une page web s'ouvre par le
/// présentateur `.safari` (L1-T10), jamais par `openURL` ; tant qu'il n'est pas injecté, l'entrée n'est pas
/// affichée (jamais un lien sans effet).
public enum HubCompte {
    public struct Lien: Identifiable, Equatable, Sendable {
        /// Identifiant d'accessibilité de l'entrée.
        public let id: String
        public let libelle: String
        public let chemin: String
    }

    // source: src/pages/MonCompteSoignant.tsx:113
    public static let titreReglages = "Réglages"
    // source: src/pages/MonCompteSoignant.tsx:126
    public static let titreAideEtLegal = "Aide & légal"

    /// « Aide & légal » (l.126-136) : pages publiques servies par Safari. « Contacter Jolene » (l.131, modale web
    /// `ModalContacterJolene`) n'a pas de page ; « Supprimer mon compte » (l.135) est la section native du lot 1, T8.
    public static let aideEtLegal: [Lien] = [
        // source: src/pages/MonCompteSoignant.tsx:130
        Lien(id: "compte-aide", libelle: "Centre d'aide", chemin: "/aide"),
        // source: src/pages/MonCompteSoignant.tsx:132
        Lien(id: "compte-confidentialite", libelle: "Confidentialité", chemin: "/confidentialite"),
        // source: src/pages/MonCompteSoignant.tsx:133
        Lien(id: "compte-cgu", libelle: "Conditions générales", chemin: "/cgu"),
        // source: src/pages/MonCompteSoignant.tsx:134
        Lien(id: "compte-mentions-legales", libelle: "Mentions légales", chemin: "/mentions-legales"),
    ]

    /// Destination effective d'une entrée (`DestinationLien`) : route native livrée, sinon `.safari(canonique)`.
    public static func destination(_ lien: Lien) -> JoleneRoute? {
        DestinationLien(link: lien.chemin)?.destination
    }
}
