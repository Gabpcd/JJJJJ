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
/// - (intégration du lot 3, T6) préférences de notifications (`PreferencesScreen`), empilées sur l'onglet Profil
///   (`PreferencesNotificationsRoute`) : entrée « Réglages › Notifications » du hub, ligne du centre et tap push ;
/// - taps push : la boîte `BoiteTapsPush` est relue à l'apparition et à chaque tap ; la destination
///   (`DestinationLien`) est présentée par `presenter(_:depuisCentre:)` : onglet, détail de mission sur l'Accueil,
///   centre de notifications, préférences sur le Profil, renvoi web par le présentateur `.safari` s'il est injecté (L1-T10). Point de fusion
///   L1-T10 / T3b : le `DeepLinkCoordinator` reprendra cette présentation (`DECISIONS_LOT3.md`). DEBUG et démo
///   seulement : libellé `push-tap-cible` de la dernière route présentée (XCUITest des taps vers un écran pas encore
///   livré ; jamais en STAGING, revue L3-T5 m8) ;
/// - une notification lue dans le centre périme le compteur de l'Accueil (`lecturesCentre`, jeton de péremption
///   d'`AccueilModel`, revue L3-T5 m1).
struct MainTabView: View {
    /// Onglets de l'espace : enum dédié de JoleneCore (revue L3-T5, m9), jamais les drapeaux `EcranNatif`.
    typealias Tab = OngletEspace

    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    @ObservedObject private var taps: BoiteTapsPush
    @StateObject private var prePrompt: PrePromptPushModel
    @State private var selection: Tab = .accueil
    @State private var cheminAccueil = NavigationPath()
    /// Pile de l'onglet Profil (intégration du lot 3) : les préférences de notifications y sont empilées.
    @State private var cheminProfil = NavigationPath()
    /// Notifications lues dans le centre (jeton de péremption du compteur de l'Accueil).
    @State private var lecturesCentre = 0
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

            NavigationStack(path: $cheminProfil) {
                ProfileScreen(container: container, session: session, snapshot: snapshot)
                    .navigationDestination(for: PreferencesNotificationsRoute.self) { _ in
                        PreferencesScreen(session: session, snapshot: snapshot, push: container.push,
                                          permission: container.pushPermission)
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
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if container.isDemo, let derniereRouteTap {
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
        // Démo seulement : la route porte les identifiants et l'URL réels d'un tap STAGING (revue L3-T5, m8).
        if container.isDemo { derniereRouteTap = PushTapIntent.libelleDebug(lien.destination) }
        #endif
        presenter(CibleNotification(lien), depuisCentre: false)
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
            selection = .explorer
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
        case .web(let route):
            presentateurRenvoiWeb?.presenter(route)
        case .aucune:
            return
        }
    }
}
