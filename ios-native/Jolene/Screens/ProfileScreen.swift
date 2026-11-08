import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Profil du lot 0 : identité minimale, déconnexion, diagnostic démo ; suppression de compte
/// (lot 1, T8, `SuppressionCompteSection`) ; entrée « Réglages › Notifications » vers les préférences de
/// notifications (lot 3, T6, `PreferencesScreen`, hôte définitif de la carte d'autorisation de T4, retirée
/// d'ici : une seule surface — `REVUES_LOT3.md`, section L3-T4). Identifiant de la liste : `profile-list`.
struct ProfileScreen: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    @State private var isSigningOut = false

    var body: some View {
        List {
            Section("Compte") {
                LabeledContent("Email", value: snapshot.user.email ?? "—")
                    .accessibilityIdentifier("profile-email")
                LabeledContent("Rôle", value: snapshot.role.role)
                    .accessibilityIdentifier("profile-role")
                LabeledContent("Profession", value: snapshot.profile.profession)
                    .accessibilityIdentifier("profile-profession")
            }
            Section {
                JoleneButton("Se déconnecter", style: .secondary, isLoading: isSigningOut) {
                    isSigningOut = true
                    Task { await session.signOut() }
                }
                .accessibilityIdentifier("logout-button")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section("Application") {
                LabeledContent("Version", value: "\(JoleneCore.version) · \(container.environment.mode.rawValue)")
                    .accessibilityIdentifier("profile-version")
                #if DEBUG
                if let monitor = container.networkSentinel {
                    NetworkSentinelRow(monitor: monitor)
                }
                #endif
            }
            // Lot 3, T6 : entrée « Notifications » de la section « Réglages » du hub web (`MonCompteSoignant.tsx`
            // l.113-115) vers les préférences, hôte définitif de la carte d'autorisation de T4. Placée après
            // « Application », à l'emplacement de la carte provisoire de T4, pour ne déplacer ni « Se déconnecter »
            // ni les identifiants du lot 0 testés par les XCUITest existants. T11, propriétaire du hub, la reprend
            // (route `.parametresNotifications`) sans seconde carte (`DECISIONS_LOT3.md`, section T6).
            Section(PreferencesTextes.sectionHub) {
                NavigationLink {
                    PreferencesScreen(session: session, snapshot: snapshot, push: container.push,
                                      permission: container.pushPermission)
                } label: {
                    Label(PreferencesTextes.entreeHub, systemImage: "bell")
                }
                .accessibilityIdentifier(PreferencesTextes.identifiantEntreeHub)
            }
            // Lot 1, T8 (Apple 5.1.1) : dernière section, comme sur le web.
            SuppressionCompteSection(session: session, snapshot: snapshot, finDeCompte: container.finDeCompte)
        }
        .accessibilityIdentifier("profile-list")
        .scrollContentBackground(.hidden)
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Profil")
    }
}

#if DEBUG
/// Preuve « aucune requête réseau en démo » : libellé `network-sentinel` (« 0 requête »).
/// DEBUG seulement, comme `NetworkSentinel`.
private struct NetworkSentinelRow: View {
    @ObservedObject var monitor: NetworkSentinel.Monitor

    var body: some View {
        // HStack et non LabeledContent : l'identifiant doit désigner la seule valeur « 0 requête ».
        HStack {
            Text("Requêtes réseau (démo)")
            Spacer()
            Text(monitor.label)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("network-sentinel")
        }
    }
}
#endif
