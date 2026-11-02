import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Explorer : vue de `MissionsListModel` (JoleneCore). Les règles d'état (annulation
/// de tâche ignorée, rafraîchissement sans démontage de la liste, session expirée) sont
/// testées dans `MissionsModelsTests` ; la vue n'ajoute aucune logique.
struct MissionRoute: Hashable {
    let id: String
}

struct MissionsListScreen: View {
    @StateObject private var model: MissionsListModel
    @ObservedObject private var session: SessionStore
    private let controller: SessionController
    private let snapshot: SessionSnapshot

    init(session: SessionStore, snapshot: SessionSnapshot) {
        self.session = session
        self.controller = session.controller
        self.snapshot = snapshot
        _model = StateObject(wrappedValue: MissionsListModel(controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Recherche des missions")
                    .tint(JoleneColor.rose700)
                    .accessibilityIdentifier("missions-loading")
            case let .failed(message) where model.sessionExpired:
                // Session expirée côté serveur : revalider la session (start) plutôt que rejouer la requête.
                EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Session à vérifier", message: message,
                           identifier: "missions-session-expired", actionTitle: "Vérifier ma session",
                           actionIdentifier: "missions-session-check") {
                    Task { await session.start() }
                }
            case let .failed(message):
                EmptyState(systemImage: "wifi.exclamationmark", title: "Connexion interrompue", message: message,
                           identifier: "missions-error", actionTitle: "Réessayer", actionIdentifier: "missions-retry") {
                    Task { await model.load() }
                }
            case let .loaded(missions) where missions.isEmpty:
                EmptyState(systemImage: "tray", title: "Aucune mission pour le moment",
                           message: "Les nouvelles missions apparaîtront ici dès leur publication.",
                           identifier: "missions-empty", actionTitle: "Actualiser", actionIdentifier: "missions-refresh") {
                    Task { await model.load() }
                }
            case let .loaded(missions):
                missionList(missions)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Explorer")
        .navigationDestination(for: MissionRoute.self) { route in
            MissionDetailScreen(route: route, initial: model.mission(id: route.id), session: session, snapshot: snapshot)
        }
        // Une tâche annulée (changement d'onglet, retour) laisse l'état à .loading : relance ici.
        .task { if case .loading = model.state { await model.load() } }
    }

    private func missionList(_ missions: [Mission]) -> some View {
        List {
            if let refreshError = model.refreshError {
                Section {
                    Text(refreshError)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.rose700)
                        .listRowBackground(JoleneColor.rose100)
                        .accessibilityIdentifier("missions-refresh-error")
                }
            }
            Section {
                ForEach(missions) { mission in
                    NavigationLink(value: MissionRoute(id: mission.id)) {
                        MissionCard(MissionsListScreen.cardContent(mission))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: JoleneSpacing.xs, leading: JoleneSpacing.lg, bottom: JoleneSpacing.xs, trailing: JoleneSpacing.lg))
                    .accessibilityIdentifier("mission-row-\(mission.id)")
                }
            } header: {
                Text("\(missions.count) mission\(missions.count > 1 ? "s" : "")")
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .textCase(nil)
                    .accessibilityIdentifier("missions-count")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
        .accessibilityIdentifier("missions-list")
    }

    static func cardContent(_ mission: Mission) -> MissionCard.Content {
        let lieu = [mission.etablissement?.adresseCodePostal, mission.etablissement?.adresseVille]
            .compactMap { $0 }.joined(separator: " ")
        return MissionCard.Content(
            titre: mission.record.intitule,
            etablissement: mission.etablissement?.nom ?? "Établissement",
            lieu: lieu.isEmpty ? nil : lieu,
            periode: MissionPresentation.periode(mission),
            remuneration: MissionPresentation.remuneration(mission),
            estUrgente: mission.record.estUrgente,
            typeContrat: mission.record.typeContratRecherche)
    }
}
