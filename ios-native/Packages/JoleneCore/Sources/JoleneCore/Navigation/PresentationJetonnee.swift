import Foundation

/// Route empilée par le présentateur de l'espace (`MainTabView.presenter` : lien universel, tap push, centre de
/// notifications, ligne de Revenus), avec un jeton propre à chaque présentation (revue B8 n°1 de L2-T10, m1).
///
/// Pourquoi : le présentateur remet la pile de l'onglet à sa racine puis y empile la route. Sans jeton, présenter la route
/// déjà à la base de la pile rendait un chemin **égal** à l'ancien : SwiftUI n'y voyait aucun changement, l'écran n'était
/// ni relu (modèles `@StateObject` conservés) ni remis au premier plan (un écran poussé au-dessus par
/// `NavigationLink { destination }`, comme le certificat ouvert depuis le contrat, restait affiché). Avec le jeton, deux
/// présentations de la même route sont deux valeurs différentes : le chemin change toujours et l'écran est reconstruit.
public struct PresentationJetonnee<Route: Hashable>: Hashable {
    public let route: Route
    /// Rang de la présentation dans sa pile (`JetonsDePresentation`), strictement croissant.
    public let jeton: Int

    public init(route: Route, jeton: Int) {
        self.route = route
        self.jeton = jeton
    }
}

extension PresentationJetonnee: Sendable where Route: Sendable {}

/// Jetons des présentations d'une pile (`PresentationJetonnee`) : chaque appel rend un jeton supérieur au précédent.
public struct JetonsDePresentation: Hashable, Sendable {
    public private(set) var dernier = 0

    public init() {}

    /// Présentation suivante de `route` : jamais égale à une présentation précédente, même de la même route.
    public mutating func presenter<Route: Hashable>(_ route: Route) -> PresentationJetonnee<Route> {
        dernier += 1
        return PresentationJetonnee(route: route, jeton: dernier)
    }
}
