import SwiftUI
import JoleneCore
import JoleneDesign

/// Détail d'une mission : vue de `MissionDetailModel` (JoleneCore). Rémunération et période
/// sont des valeurs serveur formatées par `MissionPresentation` ; rien n'est recalculé ici.
struct MissionDetailScreen: View {
    @StateObject private var model: MissionDetailModel
    @ObservedObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    /// Lot 1 (T4b) : modèle des favoris d'Explorer (étoile du détail) ; `nil` hors Explorer (Accueil).
    private let favoris: FavorisModel?

    init(route: MissionRoute, initial: Mission?, session: SessionStore, snapshot: SessionSnapshot, favoris: FavorisModel? = nil) {
        self.session = session
        self.favoris = favoris
        _model = StateObject(wrappedValue: MissionDetailModel(missionId: route.id, initial: initial,
                                                              controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            if let mission = model.mission {
                content(mission)
            } else if let message = model.errorMessage, model.sessionExpired {
                EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Session à vérifier", message: message,
                           identifier: "mission-session-expired", actionTitle: "Vérifier ma session",
                           actionIdentifier: "mission-session-check") { Task { await session.start() } }
            } else if let message = model.errorMessage {
                EmptyState(systemImage: "questionmark.circle", title: "Mission indisponible", message: message,
                           identifier: "mission-unavailable", actionTitle: "Revenir aux missions",
                           actionIdentifier: "back-to-missions") { dismiss() }
            } else {
                ProgressView("Ouverture de la mission")
                    .tint(JoleneColor.rose700)
                    .padding(JoleneSpacing.xxl)
                    .accessibilityIdentifier("mission-detail-loading")
            }
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Mission")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("mission-detail")
        .task { await model.load() }
    }

    private func content(_ mission: Mission) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
            HStack(alignment: .top) {
                Text(mission.record.intitule)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("mission-detail-title")
                Spacer(minLength: JoleneSpacing.sm)
                if mission.record.estUrgente { JoleneBadge("Urgente", tone: .warning) }
                if let favoris { BoutonFavoriMission(favoris: favoris, missionId: mission.id) }
            }
            if let favoris { AvisFavoris(favoris: favoris, identifier: "favoris-action-erreur") }
            card {
                detailRow("Établissement", value: mission.etablissement?.nom ?? "Établissement", identifier: "mission-detail-etablissement")
                if let lieu = lieu(mission) { detailRow("Adresse", value: lieu, identifier: "mission-detail-lieu") }
                if let distance = mission.distanceKm {
                    detailRow("Distance", value: Geo.formaterDistance(distance), identifier: "mission-detail-distance")
                }
                detailRow("Période", value: MissionPresentation.periode(mission), identifier: "mission-detail-periode")
                detailRow("Rémunération", value: MissionPresentation.remuneration(mission), identifier: "mission-detail-remuneration")
                if let service = mission.record.service { detailRow("Service", value: service, identifier: "mission-detail-service") }
                if let contrat = mission.record.typeContratRecherche { detailRow("Contrat recherché", value: contrat, identifier: "mission-detail-contrat") }
                detailRow("Profession requise", value: mission.record.professionRequise, identifier: "mission-detail-profession")
            }
            // Lot 1 (T4a) : carte en lecture seule, sur les coordonnées serveur de l'établissement.
            if let point = CarteMission.point(pour: mission) { MissionMapView(point: point) }
            card {
                Text("Créneaux").font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight)
                if mission.creneauxPlanifies.isEmpty {
                    Text(mission.planningExact ? "Aucun créneau communiqué." : "Planning à confirmer avec l'établissement.")
                        .font(JoleneFont.body).foregroundStyle(JoleneColor.bubblegum)
                } else {
                    ForEach(Array(mission.creneauxPlanifies.enumerated()), id: \.offset) { index, slot in
                        HStack {
                            Image(systemName: slot.estPause ? "cup.and.saucer" : "clock")
                                .foregroundStyle(JoleneColor.mauve700)
                                .accessibilityHidden(true)
                            Text(MissionPresentation.creneau(slot))
                                .font(JoleneFont.body)
                                .foregroundStyle(JoleneColor.midnight)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("mission-detail-creneau-\(index + 1)")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mission-detail-creneaux")
            if let description = mission.record.description, !description.isEmpty {
                card {
                    Text("Description").font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight)
                    Text(description).font(JoleneFont.body).foregroundStyle(JoleneColor.midnight)
                }
            }
            Text("Candidature disponible au lot 1.")
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("placeholder-candidature")
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    private func lieu(_ mission: Mission) -> String? {
        let parts = [mission.etablissement?.adresseCodePostal, mission.etablissement?.adresseVille].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) { content() }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    private func detailRow(_ label: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            Text(value).font(JoleneFont.body).foregroundStyle(JoleneColor.midnight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) : \(value)")
        .accessibilityIdentifier(identifier)
    }
}
