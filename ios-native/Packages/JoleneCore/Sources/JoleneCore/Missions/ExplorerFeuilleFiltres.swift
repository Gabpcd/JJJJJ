import Foundation

/// Présentation de la feuille « Filtres » d'Explorer (`FiltresSheet`) par `MissionsListScreen`.
///
/// Défaut corrigé (run CI 42526135547, iPad portrait) : « Afficher les missions » appliquait les
/// critères (`MissionsListModel.appliquer` : `.loading`, puis la liste et le badge du bouton
/// « Filtres » reconstruits) pendant la transition de fermeture de la feuille. Présentée par
/// `.sheet(isPresented:)`, une présentation que UIKit refuse pendant une transition laissait la
/// liaison à `true` sans feuille à l'écran : chaque appui suivant sur « Filtres » était inerte.
///
/// Règles :
/// - chaque ouverture est une valeur neuve (`Ouverture`, identifiant unique, présentée par
///   `.sheet(item:)`) qui fige les critères appliqués au moment de l'ouverture : la feuille part
///   toujours d'eux, et une demande d'ouverture n'est jamais l'écriture sans effet d'un `true`
///   déjà posé ;
/// - « Afficher les missions » ne fait qu'enregistrer les critères (`enregistrer`) ; `cloturer()`
///   les rend une seule fois, appelée par `onDismiss`, donc après la transition de fermeture :
///   la liste ne se recharge plus pendant que la feuille se ferme ;
/// - « Fermer », le glissement vers le bas et l'appui hors de la feuille (iPad) n'enregistrent
///   rien : `cloturer()` rend `nil` et la liste ne change pas ;
/// - une ouverture efface tout enregistrement resté en suspens.
public struct ExplorerFeuilleFiltres: Equatable, Sendable {
    /// Une présentation de la feuille.
    public struct Ouverture: Identifiable, Equatable, Sendable {
        public let id: UUID
        /// Critères appliqués au moment de l'ouverture : brouillon initial de la feuille.
        public let filtres: ExplorerFiltres
    }

    /// Feuille présentée (liaison de `.sheet(item:)`), `nil` quand elle est fermée.
    public var ouverture: Ouverture?
    /// Critères enregistrés par « Afficher les missions », à appliquer une fois la feuille fermée.
    public private(set) var enAttente: ExplorerFiltres?

    public init() {}

    /// Appui sur « Filtres » : nouvelle présentation partant des critères appliqués.
    public mutating func ouvrir(avec filtres: ExplorerFiltres) {
        enAttente = nil
        ouverture = Ouverture(id: UUID(), filtres: filtres)
    }

    /// « Afficher les missions » : enregistre les critères, sans rien appliquer pendant la fermeture.
    public mutating func enregistrer(_ filtres: ExplorerFiltres) {
        enAttente = filtres
    }

    /// Fin de la fermeture (`onDismiss`) : les critères enregistrés, une seule fois, ou `nil` si
    /// la feuille a été fermée sans « Afficher les missions ».
    public mutating func cloturer() -> ExplorerFiltres? {
        defer { enAttente = nil }
        return enAttente
    }
}
