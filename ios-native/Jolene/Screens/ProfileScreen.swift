import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Profil du lot 0 : identité minimale, déconnexion, diagnostic démo ; suppression de compte
/// (lot 1, T8, `SuppressionCompteSection`) ; autorisation des notifications de l'appareil (lot 3, T4,
/// `EtatNotificationsAppareilRow`, hôte provisoire : la carte rejoint les préférences de T6, une seule
/// surface — `REVUES_LOT3.md`, section L3-T4). Identifiant de la liste : `profile-list`.
struct ProfileScreen: View {
    let container: AppContainer
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    @State private var isSigningOut = false
    /// Lot 3, T4 : état de la carte d'autorisation, lu à l'affichage et à chaque retour au premier plan.
    @StateObject private var etatNotifications: EtatNotificationsAppareilModel
    @Environment(\.scenePhase) private var scenePhase

    init(container: AppContainer, session: SessionStore, snapshot: SessionSnapshot) {
        self.container = container
        self.session = session
        self.snapshot = snapshot
        _etatNotifications = StateObject(wrappedValue: EtatNotificationsAppareilModel(
            push: container.push, permission: container.pushPermission, snapshot: snapshot))
    }

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
            ProfilEntreeSection(session: session, snapshot: snapshot) // Lot 3, T9 : « Mon profil » (point de fusion T11)
            // Lot 3, T4 : autorisation des notifications de l'appareil, sous « Notifications » comme l'entrée
            // du hub web (`MonCompteSoignant.tsx` l.115) ; placée après « Application » pour ne déplacer ni
            // « Se déconnecter » ni les identifiants du lot 0 testés par les XCUITest existants. Section
            // absente quand la carte n'a rien à affirmer (jamais demandé, canal push inconnu du hub).
            if etatNotifications.message != nil {
                Section(EtatNotificationsAppareil.sectionHub) {
                    EtatNotificationsAppareilRow(model: etatNotifications)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            // Lot 1, T8 (Apple 5.1.1) : dernière section, comme sur le web.
            SuppressionCompteSection(session: session, snapshot: snapshot, finDeCompte: container.finDeCompte)
        }
        .accessibilityIdentifier("profile-list")
        .scrollContentBackground(.hidden)
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Profil")
        // Lot 3, T4 : lecture à l'affichage de l'onglet, et au retour de Réglages (premier plan).
        .task { await etatNotifications.verifier() }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { await etatNotifications.verifier() }
        }
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
