import SwiftUI
import JoleneCore
import JoleneDesign

/// Coquille de l'espace établissement (lot 5, T2a ; D13) : Accueil · Missions · Présences · Messages ·
/// Compte. « Publier » n'est pas un onglet (un onglet qui disparaît selon le rôle déplacerait la barre) :
/// c'est un bouton de la barre de Missions, masqué sans la permission `missions`. Chaque onglet possède
/// sa `NavigationStack`, le registre de destinations (`EtabDestinations.swift`) et son pilotage
/// permission → drapeau (`Composition/EtabFeatureFlags.swift`) ; son contenu vit dans un `…Root.swift`
/// que seule la tranche du domaine remplit.
///
/// Monté par `RootView` avec `.id(snapshot.epoch)` : une nouvelle identité ou un nouveau périmètre
/// reconstruit tout l'espace ; une relecture des permissions à epoch constant le re-filtre sans le démonter.
///
/// Accessibilité : `.accessibilityIdentifier("tab-etab-*")` est porté par le CONTENU de l'onglet ; UIKit
/// expose le bouton d'onglet avec le nom de l'image de son `Label` (`house`, `list.clipboard`,
/// `checkmark.seal`, `bubble.left.and.bubble.right`, `person.crop.circle`). Ne pas renommer ces symboles
/// sans mettre à jour `tabSymbols` dans `UITestSupport.swift`.
struct EtablissementTabView: View {
    enum Tab: Hashable { case accueil, missions, presences, messages, compte }

    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: EtablissementSessionSnapshot
    @State private var selection: Tab = .accueil

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                EtabAccueilRoot(session: session, snapshot: snapshot)
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.accueil, snapshot: snapshot, session: session)
            .tabItem { Label("Accueil", systemImage: "house") }
            .tag(Tab.accueil)
            .accessibilityIdentifier("tab-etab-accueil")

            NavigationStack {
                EtabMissionsRoot(session: session, snapshot: snapshot)
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.missions, snapshot: snapshot, session: session)
            .tabItem { Label("Missions", systemImage: "list.clipboard") }
            .tag(Tab.missions)
            .accessibilityIdentifier("tab-etab-missions")

            NavigationStack {
                EtabPresencesRoot(session: session, snapshot: snapshot)
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.presences, snapshot: snapshot, session: session)
            .tabItem { Label("Présences", systemImage: "checkmark.seal") }
            .tag(Tab.presences)
            .accessibilityIdentifier("tab-etab-presences")

            NavigationStack {
                EtabMessagesRoot(session: session, snapshot: snapshot)
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.messages, snapshot: snapshot, session: session)
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
            .tag(Tab.messages)
            .accessibilityIdentifier("tab-etab-messages")

            NavigationStack {
                EtabCompteRoot(container: container, session: session, snapshot: snapshot)
                    .destinationsEtablissement(snapshot: snapshot, session: session)
            }
            .ecranEtablissement(.compte, snapshot: snapshot, session: session) { Task { await session.signOut() } }
            .tabItem { Label("Compte", systemImage: "person.crop.circle") }
            .tag(Tab.compte)
            .accessibilityIdentifier("tab-etab-compte")
        }
        .tint(JoleneColor.rose700)
    }
}
