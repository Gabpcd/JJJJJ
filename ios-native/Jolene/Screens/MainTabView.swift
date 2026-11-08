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
/// - taps push : la boîte `BoiteTapsPush` est relue à l'apparition et à chaque tap ; la destination
///   (`DestinationLien`) est présentée par `presenter(_:depuisCentre:)` : onglet, détail de mission sur l'Accueil,
///   centre de notifications, renvoi web par le présentateur `.safari` s'il est injecté (L1-T10). Point de fusion
///   L1-T10 / T3b : le `DeepLinkCoordinator` reprendra cette présentation (`DECISIONS_LOT3.md`). DEBUG : libellé
///   `push-tap-cible` de la dernière route présentée (XCUITest des taps vers un écran pas encore livré).
struct MainTabView: View {
    enum Tab: Hashable { case accueil, explorer, missions, revenus, profil }

    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    @ObservedObject private var taps: BoiteTapsPush
    @StateObject private var prePrompt: PrePromptPushModel
    @State private var selection: Tab = .accueil
    @State private var cheminAccueil = NavigationPath()
    #if DEBUG
    @State private var derniereRouteTap: String?
    #endif
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(container: AppContainer, session: SessionStore, snapshot: SessionSnapshot) {
        self.container = container
        self.session = session
        self.snapshot = snapshot
        self.taps = container.tapsPush
        _prePrompt = StateObject(wrappedValue: PrePromptPushModel(contexte: container.prePrompt, permission: container.pushPermission,
                                                                  push: container.push, snapshot: snapshot))
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack(path: $cheminAccueil) {
                AccueilScreen(session: session, snapshot: snapshot) { selection = $0 }
                    .navigationDestination(for: CentreNotificationsRoute.self) { _ in
                        NotificationsScreen(session: session, snapshot: snapshot, taps: taps) { cible in
                            presenter(cible, depuisCentre: true)
                        }
                    }
            }
            .tabItem { Label("Accueil", systemImage: "house") }
            .tag(Tab.accueil)
            .accessibilityIdentifier("tab-accueil")

            NavigationStack {
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

            NavigationStack {
                ProfileScreen(container: container, session: session, snapshot: snapshot)
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
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if let derniereRouteTap {
                Text(derniereRouteTap)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("push-tap-cible")
            }
        }
        #endif
        .animation(.easeInOut(duration: 0.2), value: prePrompt.visible)
        .task { await prePrompt.evaluer() }
        .onAppear { consommerTap() }
        .onChange(of: taps.tapsRecus) { _ in consommerTap() }
        .onDisappear { taps.fermerEspace(epoch: snapshot.epoch) }
    }

    // MARK: - Taps push et cibles des notifications

    /// Relit la boîte des taps pour cet espace (epoch) et présente la destination, une seule fois.
    private func consommerTap() {
        guard let lien = taps.prendre(pour: snapshot) else { return }
        #if DEBUG
        derniereRouteTap = PushTapIntent.libelleDebug(lien.destination)
        #endif
        presenter(CibleNotification(lien), depuisCentre: false)
    }

    /// Présente une cible : depuis le centre, le détail s'empile au-dessus de lui ; depuis un tap push, la pile de
    /// l'Accueil repart de sa racine (le tap remplace la navigation en cours, comme `history.pushState` du web).
    private func presenter(_ cible: CibleNotification, depuisCentre: Bool) {
        switch cible {
        case .onglet(let ecran):
            selection = Self.onglet(ecran)
        case .mission(let id):
            if !depuisCentre {
                selection = .accueil
                cheminAccueil = NavigationPath()
            }
            cheminAccueil.append(MissionRoute(id: id))
        case .centre:
            guard !depuisCentre else { return }
            selection = .accueil
            cheminAccueil = NavigationPath()
            cheminAccueil.append(CentreNotificationsRoute())
        case .web(let route):
            presentateurRenvoiWeb?.presenter(route)
        case .aucune:
            return
        }
    }

    private static func onglet(_ ecran: EcranNatif) -> Tab {
        switch ecran {
        case .accueil: return .accueil
        case .explorer: return .explorer
        case .missions: return .missions
        case .revenus: return .revenus
        case .profil: return .profil
        }
    }
}
