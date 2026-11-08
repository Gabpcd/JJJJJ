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
struct MainTabView: View {
    enum Tab: Hashable { case accueil, explorer, missions, revenus, profil }

    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    @State private var selection: Tab = .accueil

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                AccueilScreen(session: session, snapshot: snapshot) { selection = $0 }
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
        .onDisappear { FichierContratTemporaire.effacerTout() } // lot 2 T9a : copies de contrats effacées au changement d'epoch
        // Fond de carte (`carteTuiles`) : injecté à la racine par `RootView` (revue T4a), hérité ici.
    }
}
