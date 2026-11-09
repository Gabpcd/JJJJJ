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
///   `.sheet(item:)`) qui fige ses critères de départ, ceux appliqués au moment de l'appui (voir
///   la dernière règle pour le choix encore en attente). Une demande d'ouverture n'est donc
///   jamais l'écriture sans effet d'un `true` déjà posé ;
/// - « Afficher les missions » ne fait qu'enregistrer les critères (`enregistrer`) ; `cloturer()`
///   les rend une seule fois, appelée par `onDismiss`, donc après la transition de fermeture :
///   la liste ne se recharge plus pendant que la feuille se ferme ;
/// - « Fermer », le glissement vers le bas et l'appui hors de la feuille (iPad) n'enregistrent
///   rien : `cloturer()` rend `nil` et la liste ne change pas ;
/// - un « Afficher les missions » validé n'est jamais perdu (revue B8, m1) : une ouverture qui
///   arrive avant `onDismiss` part des critères enregistrés (`enAttente ?? filtres`), puis vide
///   l'enregistrement. L'utilisateur revoit son choix et le revalide, et la clôture de la
///   présentation précédente n'applique rien : il n'y a qu'un chemin d'application.
public struct ExplorerFeuilleFiltres: Equatable, Sendable {
    /// Une présentation de la feuille.
    public struct Ouverture: Identifiable, Equatable, Sendable {
        public let id: UUID
        /// Brouillon initial de la feuille : les critères appliqués, ou le choix validé encore en
        /// attente d'application.
        public let filtres: ExplorerFiltres
    }

    /// Feuille présentée (liaison de `.sheet(item:)`), `nil` quand elle est fermée.
    public var ouverture: Ouverture?
    /// Critères enregistrés par « Afficher les missions », à appliquer une fois la feuille fermée.
    public private(set) var enAttente: ExplorerFiltres?

    public init() {}

    /// Appui sur « Filtres » : nouvelle présentation partant des critères appliqués (`filtres`),
    /// ou du choix validé que la fermeture précédente n'a pas encore appliqué.
    public mutating func ouvrir(avec filtres: ExplorerFiltres) {
        let depart = enAttente ?? filtres
        enAttente = nil
        ouverture = Ouverture(id: UUID(), filtres: depart)
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
