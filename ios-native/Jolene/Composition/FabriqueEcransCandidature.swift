import SwiftUI
import JoleneCore

/// Écrans ouverts depuis le bloc de candidature du détail de mission (lot 1, T6b ; revue B8 m2, m4) : édition du profil
/// (soft-gate) avec les mêmes injections que l'onglet Profil (`MainTabView`, `ProfilEditionRoute` : localisation du
/// profil, photo démo) et « Mes documents » natif du lot 2 (après une candidature envoyée). Le détail est empilé sur
/// l'Accueil, Explorer ou Mes missions : ses liens ne peuvent pas passer par les routes par valeur des piles de
/// l'Accueil et du Profil. Injectée par `MainTabView` ; sans fabrique (aperçus, tests isolés), le bouton des documents
/// n'est pas rendu (jamais un bouton sans effet) et le profil s'ouvre sans injection.
@MainActor
protocol FabriqueEcransCandidature: AnyObject, Sendable {
    func editionProfil(session: SessionStore, snapshot: SessionSnapshot) -> AnyView
    func documents(session: SessionStore, snapshot: SessionSnapshot) -> AnyView
}

@MainActor
final class FabriqueEcransCandidatureNative: FabriqueEcransCandidature {
    private let container: AppContainer

    init(container: AppContainer) { self.container = container }

    func editionProfil(session: SessionStore, snapshot: SessionSnapshot) -> AnyView {
        AnyView(ProfilEditionScreen(session: session, snapshot: snapshot, localisation: container.localisationProfil,
                                    selectionAvatarDemo: container.selectionAvatarDemo))
    }

    func documents(session: SessionStore, snapshot: SessionSnapshot) -> AnyView {
        AnyView(MesDocumentsScreen(container: container, session: session, snapshot: snapshot))
    }
}

private struct FabriqueEcransCandidatureKey: EnvironmentKey {
    static let defaultValue: (any FabriqueEcransCandidature)? = nil
}

extension EnvironmentValues {
    /// Fabrique des écrans du bloc de candidature, `nil` hors des onglets d'une session prête.
    var fabriqueEcransCandidature: (any FabriqueEcransCandidature)? {
        get { self[FabriqueEcransCandidatureKey.self] }
        set { self[FabriqueEcransCandidatureKey.self] = newValue }
    }
}
