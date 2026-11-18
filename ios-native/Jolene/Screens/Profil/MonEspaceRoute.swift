import SwiftUI
import JoleneCore

/// Écrans de « Mon espace » (lot 2) empilés **par valeur** (L2-T10 ; revue B8 de la PR #1131, m3) : entrées de la section
/// du Profil (`EspaceSoignantSection`), points d'entrée de l'Accueil (widget « Aller pointer », oubli de départ) et
/// destinations des liens universels, des taps push et du centre de notifications (`CibleNotification`, présentées par
/// `MainTabView.presenter` sur l'onglet Profil).
///
/// Pourquoi par valeur : le coordinateur des liens ramène la pile de l'onglet à sa racine avant d'empiler la cible
/// (`cheminProfil = NavigationPath()`). Un écran poussé à la racine par `NavigationLink { destination }` n'est pas dans
/// ce chemin : vider un chemin déjà vide ne le retirerait pas, et la cible s'empilerait par-dessus lui. Enregistrée par
/// `destinationsMonEspace` sur les piles de l'Accueil et du Profil (une fois par pile).
///
/// Les liens internes aux écrans du lot 2 (« Voir le contrat » d'un bloc de pointage, « Détail » d'une ligne
/// d'historique, carte d'un contrat, certificat ouvert depuis le contrat) restent des `NavigationLink { destination }` :
/// ils s'empilent toujours au-dessus d'une de ces routes, que le retour à la racine retire avec elle.
///
/// Présentée par `MainTabView.presenter`, la route est enveloppée d'un jeton (`PresentationJetonnee<MonEspaceRoute>`,
/// revue B8 n°1 de L2-T10, m1) : présenter la route déjà à la base de la pile change quand même le chemin, et l'écran,
/// dont l'identité suit le jeton (`.id`), est reconstruit (modèles relus, onglet du lien rétabli). Les entrées du hub et
/// de l'Accueil (`NavigationLink(value:)`) empilent la route nue : chaque toucher pousse déjà un nouvel élément.
enum MonEspaceRoute: Hashable {
    /// Page Présences, `?tab=` et `?filtre=` bruts (`PresencesScreen(parametreOnglet:parametreFiltre:)`).
    case presences(onglet: String?, filtre: String?)
    /// Détail des présences d'une mission (`DetailPresencesScreen`).
    case detailPresences(missionId: String)
    /// « Mes documents » sur un onglet (`MesDocumentsScreen(ongletInitial:)`).
    case documents(onglet: OngletDocuments)
    /// « Mes contrats » du Profil (`ContratsDestination.liste`, présentation écran).
    case contrats
    /// Page d'un contrat (`ContratsDestination.contrat`).
    case contrat(id: String)
    /// Certificat des signatures d'un contrat (`ContratsDestination.certificat`).
    case certificat(contratId: String)

    /// Route d'une cible de l'espace ; nil pour une cible hors « Mon espace ».
    init?(_ cible: CibleNotification) {
        switch cible {
        case let .presences(onglet, filtre): self = .presences(onglet: onglet, filtre: filtre)
        case .detailPresences(let missionId): self = .detailPresences(missionId: missionId)
        case .documents(let onglet): self = .documents(onglet: onglet)
        case .contrat(let id): self = .contrat(id: id)
        case .certificat(let contratId): self = .certificat(contratId: contratId)
        case .accueil, .explorer, .missions, .revenus, .monCompte, .mission, .centre, .preferences, .profil, .stripeConnect,
             .web, .aucune:
            return nil
        case .favoris: // L1-T4b : onglet Explorer
            return nil
        case .secondaire: // L4-T1c : écrans secondaires (`SecondaireRoute`)
            return nil
        }
    }
}

extension View {
    /// Enregistre les écrans de « Mon espace » sur la pile qui porte cette vue (racine de l'Accueil ou du Profil) : route
    /// nue (entrées par valeur) et route jetonnée (présentateur de l'espace, m1).
    func destinationsMonEspace(container: AppContainer, session: SessionStore, snapshot: SessionSnapshot,
                               ouvrirOnglet: @escaping (MainTabView.Tab) -> Void) -> some View {
        navigationDestination(for: MonEspaceRoute.self) { route in
            MonEspaceDestination(route: route, container: container, session: session, snapshot: snapshot,
                                 ouvrirOnglet: ouvrirOnglet)
        }
        .navigationDestination(for: PresentationJetonnee<MonEspaceRoute>.self) { presentation in
            MonEspaceDestination(route: presentation.route, container: container, session: session, snapshot: snapshot,
                                 ouvrirOnglet: ouvrirOnglet)
                // Identité de l'écran liée au jeton : à la même position de la pile, SwiftUI sert la nouvelle valeur à
                // l'écran déjà monté (modèles `@StateObject` et onglet `@State` conservés, constaté en XCUITest) ;
                // `.id` le reconstruit, donc le relit.
                .id(presentation.jeton)
        }
    }
}

/// Écran d'une route de « Mon espace » : chaque écran possède ses modèles (`@StateObject`), créés une fois par route
/// empilée.
private struct MonEspaceDestination: View {
    let route: MonEspaceRoute
    let container: AppContainer
    let session: SessionStore
    let snapshot: SessionSnapshot
    let ouvrirOnglet: (MainTabView.Tab) -> Void

    var body: some View {
        switch route {
        case let .presences(onglet, filtre):
            PresencesScreen(session: session, snapshot: snapshot, parametreOnglet: onglet, parametreFiltre: filtre,
                            ouvrirOnglet: ouvrirOnglet)
        case .detailPresences(let missionId):
            DetailPresencesScreen(missionId: missionId, session: session, snapshot: snapshot)
                #if DEBUG
                // Revue B8 n°1 de L2-T10, m2 : identifiant de la mission présentée, lu par les XCUITest (valeur
                // d'accessibilité de `presence-detail-screen`) ; démo seulement, jamais en STAGING où il serait réel.
                .accessibilityValue(container.isDemo ? missionId : "")
                #endif
        case .documents(let onglet):
            MesDocumentsScreen(container: container, session: session, snapshot: snapshot, ongletInitial: onglet)
        case .contrats:
            ContratsDestination.liste(session: session, snapshot: snapshot)
        case .contrat(let id):
            ContratsDestination.contrat(session: session, snapshot: snapshot, contratId: id)
        case .certificat(let contratId):
            ContratsDestination.certificat(session: session, snapshot: snapshot, contratId: contratId)
        }
    }
}
