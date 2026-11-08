import SwiftUI
import JoleneCore
import JoleneDesign

/// Cinq onglets calqués sur `src/components/BarreNavigation.tsx` l.33-37
/// (`NAV_SOIGNANT_MOBILE`) ; chaque onglet possède sa propre NavigationStack.
///
/// Accessibilité : `.accessibilityIdentifier("tab-*")` est porté par le CONTENU de l'onglet ;
/// UIKit expose le bouton d'onglet lui-même avec le nom de l'image du `Label` pour identifiant
/// (`house`, `magnifyingglass`, `list.clipboard`, `banknote`, `person`). Sur iPadOS 18 et
/// suivants la barre est rendue en haut de l'écran sans élément `TabBar`. Les XCUITest
/// (`JoleneUITestCase.tabButton`) résolvent les deux cas ; ne pas renommer ces symboles
/// sans mettre à jour `tabSymbols` dans `UITestSupport.swift`.
///
/// Lot 3, T5 (blueprint §3 T5, corrigé v2 : surcouche de l'espace prêt, `RootView` appartenant à T7) :
/// - pré-prompt de notification (`PrePromptPushScreen`, `PrePromptPushModel`), évalué à l'apparition de
///   l'espace, et l'issue de l'activation (`push-preprompt-issue`) ;
/// - centre de notifications (`NotificationsScreen`), empilé sur l'onglet Accueil (`CentreNotificationsRoute`) ;
/// - (intégration du lot 3, T6 et T9) préférences de notifications (`PreferencesScreen`,
///   `PreferencesNotificationsRoute`) et édition du profil (`ProfilEditionScreen`, `ProfilEditionRoute`), empilées
///   sur l'onglet Profil : entrées du hub, ligne du centre et tap push ;
/// - liens universels et taps push (lot 3, T3b, reliquat L1-T10) : le coordinateur des liens
///   (`DeepLinkCoordinator`, `container.liens`) est le point d'entrée unique ; l'espace lui signale son ouverture
///   (rejeu du lien ou du tap reçu avant `.ready`), chaque tap reçu (`BoiteTapsPush.tapsRecus`) et sa fermeture, puis
///   exécute ses demandes de navigation (`DemandeNavigation`, epoch de l'espace) par `presenter(_:depuisCentre:)` :
///   onglet, détail de mission sur l'Accueil, centre de notifications, préférences et édition du profil sur le
///   Profil ; un renvoi web passe par le présentateur `.safari` du coordinateur (injecté à la racine). Le libellé DEBUG
///   `deeplink-route` (démo seulement) est posé par le coordinateur, à la racine, quand cet espace exécute la demande
///   (`demandeTraitee`, revue B8 de T3b, m7) ; il remplace `push-tap-cible`. Explorer, l'Accueil et le Profil
///   reviennent à leur racine (piles par chemin ; revue B8 de T3b, m5) ;
/// - une notification lue dans le centre périme le compteur de l'Accueil (`lecturesCentre`, jeton de péremption
///   d'`AccueilModel`, revue L3-T5 m1).
struct MainTabView: View {
    /// Onglets de l'espace : enum dédié de JoleneCore (revue L3-T5, m9), jamais les drapeaux `EcranNatif`.
    typealias Tab = OngletEspace

    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    @ObservedObject private var taps: BoiteTapsPush
    /// Lot 3, T3b : coordinateur des liens (demandes de navigation de cet espace).
    @ObservedObject private var liens: DeepLinkCoordinator
    @StateObject private var prePrompt: PrePromptPushModel
    @State private var selection: Tab = .accueil
    @State private var cheminAccueil = NavigationPath()
    /// Pile de l'onglet Explorer (revue B8 de T3b, m5) : un lien ou un tap vers Explorer revient à sa racine.
    @State private var cheminExplorer = NavigationPath()
    /// Pile de l'onglet Profil (intégration du lot 3) : préférences de notifications et édition du profil.
    @State private var cheminProfil = NavigationPath()
    /// Notifications lues dans le centre (jeton de péremption du compteur de l'Accueil).
    @State private var lecturesCentre = 0
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(container: AppContainer, session: SessionStore, snapshot: SessionSnapshot) {
        self.container = container
        self.session = session
        self.snapshot = snapshot
        self.taps = container.tapsPush
        self.liens = container.liens
        _prePrompt = StateObject(wrappedValue: PrePromptPushModel(contexte: container.prePrompt, permission: container.pushPermission,
                                                                  push: container.push, snapshot: snapshot))
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack(path: $cheminAccueil) {
                AccueilScreen(session: session, snapshot: snapshot, peremption: lecturesCentre) { selection = $0 }
                    .navigationDestination(for: CentreNotificationsRoute.self) { _ in
                        NotificationsScreen(session: session, snapshot: snapshot, taps: taps,
                                            surLecture: { lecturesCentre += 1 }) { cible in
                            presenter(cible, depuisCentre: true)
                        }
                    }
            }
            .tabItem { Label("Accueil", systemImage: "house") }
            .tag(Tab.accueil)
            .accessibilityIdentifier("tab-accueil")

            NavigationStack(path: $cheminExplorer) {
                MissionsListScreen(session: session, snapshot: snapshot)
            }
            .tabItem { Label("Explorer", systemImage: "magnifyingglass") }
            .tag(Tab.explorer)
            .accessibilityIdentifier("tab-explorer")

            NavigationStack {
                PlaceholderScreen(titre: "Mes missions", identifier: "placeholder-missions",
                                  description: "Candidatures, missions à venir et passées arrivent au lot 1.")
            }
            .tabItem { Label("Mes missions", systemImage: "list.clipboard") }
            .tag(Tab.missions)
            .accessibilityIdentifier("tab-missions")

            NavigationStack {
                PlaceholderScreen(titre: "Revenus", identifier: "placeholder-revenus",
                                  description: "Vos gains, factures et bulletins arrivent au lot 1.")
            }
            .tabItem { Label("Revenus", systemImage: "banknote") }
            .tag(Tab.revenus)
            .accessibilityIdentifier("tab-revenus")

            NavigationStack(path: $cheminProfil) {
                ProfileScreen(container: container, session: session, snapshot: snapshot)
                    .navigationDestination(for: PreferencesNotificationsRoute.self) { _ in
                        PreferencesScreen(session: session, snapshot: snapshot, push: container.push,
                                          permission: container.pushPermission)
                    }
                    .navigationDestination(for: ProfilEditionRoute.self) { _ in
                        ProfilEditionScreen(session: session, snapshot: snapshot)
                    }
            }
            .tabItem { Label("Profil", systemImage: "person") }
            .tag(Tab.profil)
            .accessibilityIdentifier("tab-profil")
        }
        .tint(JoleneColor.rose700)
        // Fond de carte (`carteTuiles`) : injecté à la racine par `RootView` (revue T4a), hérité ici.
        // Lot 3, T5 : pré-prompt (surcouche modale) et issue de l'activation.
        .overlay {
            if prePrompt.visible {
                PrePromptPushScreen(model: prePrompt)
            }
        }
        .overlay(alignment: .top) {
            if let issue = prePrompt.issue {
                IssuePrePromptPush(issue: issue) { prePrompt.effacerIssue() }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: prePrompt.visible)
        .task { await prePrompt.evaluer() }
        // Lot 3, T3b : le coordinateur des liens rejoue l'intention reçue avant `.ready` (lien ou tap), puis chaque
        // tap reçu ; l'espace n'exécute que les demandes de son epoch.
        .onAppear {
            liens.espaceOuvert(snapshot)
            executerDemande()
        }
        .onChange(of: taps.tapsRecus) { _ in liens.tapRecu() }
        .onChange(of: liens.demande) { _ in executerDemande() }
        .onDisappear { liens.espaceFerme(epoch: snapshot.epoch) }
    }

    // MARK: - Liens, taps push et cibles des notifications

    /// Exécute la demande de navigation du coordinateur pour cet espace (epoch), une seule fois.
    private func executerDemande() {
        guard let demande = liens.demande, demande.epoch == snapshot.epoch else { return }
        liens.demandeTraitee(demande)
        presenter(demande.cible, depuisCentre: false)
    }

    /// Présente une cible présentable (`CibleNotification.estPresentable`, rien sinon) : depuis le centre, le détail
    /// s'empile au-dessus de lui ; depuis un tap push, la pile de l'Accueil repart de sa racine (le tap remplace la
    /// navigation en cours, comme `history.pushState` du web). L'Accueil revient toujours à sa racine (revue L3-T5,
    /// m5 : sans quoi rien ne serait visible depuis le centre). Une tranche qui ajoute une cible
    /// (`CibleNotification`) ajoute ici sa présentation.
    private func presenter(_ cible: CibleNotification, depuisCentre: Bool) {
        guard cible.estPresentable(renvoiWebDisponible: presentateurRenvoiWeb != nil, depuisCentre: depuisCentre) else {
            return
        }
        switch cible {
        case .accueil:
            selection = .accueil
            cheminAccueil = NavigationPath()
        case .explorer:
            // Revue B8 de T3b, m5 : un détail empilé sur Explorer est retiré (Mes missions et Revenus n'ont pas de pile).
            selection = .explorer
            cheminExplorer = NavigationPath()
        case .missions:
            selection = .missions
        case .revenus:
            // Seule la racine (`.apercu`) est présentable avant T12/T13 (garde de `estPresentable`).
            selection = .revenus
        case .monCompte:
            selection = .profil
            cheminProfil = NavigationPath()
        case .mission(let id):
            if !depuisCentre {
                selection = .accueil
                cheminAccueil = NavigationPath()
            }
            cheminAccueil.append(MissionRoute(id: id))
        case .centre:
            selection = .accueil
            cheminAccueil = NavigationPath()
            cheminAccueil.append(CentreNotificationsRoute())
        case .preferences:
            // Depuis le centre comme depuis un tap : le Profil repart de sa racine, puis les préférences s'y empilent.
            selection = .profil
            cheminProfil = NavigationPath()
            cheminProfil.append(PreferencesNotificationsRoute())
        case .profil:
            // Même règle que les préférences : le Profil repart de sa racine, puis l'édition s'y empile.
            selection = .profil
            cheminProfil = NavigationPath()
            cheminProfil.append(ProfilEditionRoute())
        case .web(let route):
            presentateurRenvoiWeb?.presenter(route)
        case .aucune:
            return
        }
    }
}
