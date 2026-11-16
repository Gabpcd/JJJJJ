import SwiftUI
import JoleneCore
import JoleneDesign

/// Détail d'une mission : vue de `MissionDetailModel` (JoleneCore). Rémunération et période
/// sont des valeurs serveur formatées par `MissionPresentation` ; rien n'est recalculé ici.
struct MissionDetailScreen: View {
    @StateObject private var model: MissionDetailModel
    @ObservedObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    // Lot 2 T5a : points d'entrée vers les présences (onglet calculé sur l'horloge des gateways de la session).
    private let snapshot: SessionSnapshot
    private let ouvrirOnglet: ((MainTabView.Tab) -> Void)?
    @State private var horloge: (any ClockPort)?

    init(route: MissionRoute, initial: Mission?, session: SessionStore, snapshot: SessionSnapshot,
         ouvrirOnglet: ((MainTabView.Tab) -> Void)? = nil) {
        self.session = session
        self.snapshot = snapshot
        self.ouvrirOnglet = ouvrirOnglet
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
        .task {
            if horloge == nil { horloge = await session.controller.gateways(for: snapshot.epoch)?.clock }
            await model.load()
        }
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
            }
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
            entreePresences(mission)
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

    /// Lot 2 T5a (`DetailMissionSoignant.tsx` l.1477-1494) : « Présences et pointage » (ASSIGNEE, EN_COURS) vers la page
    /// Présences sur l'onglet calculé (`PointsEntreePresences.entreeMission`), rendu seulement quand l'écran sait changer
    /// d'onglet (états vides de la page) ; « Voir mes heures pointées et mes pauses » (TERMINEE) vers le détail natif.
    @ViewBuilder
    private func entreePresences(_ mission: Mission) -> some View {
        if let horloge, let entree = PointsEntreePresences.entreeMission(statut: mission.record.statut, creneaux: mission.creneauxPlanifies,
                                                                          maintenant: horloge.now()) {
            switch entree {
            case let .presences(onglet):
                if let ouvrirOnglet {
                    NavigationLink {
                        PresencesScreen(session: session, snapshot: snapshot, parametreOnglet: onglet.rawValue, ouvrirOnglet: ouvrirOnglet)
                    } label: {
                        boutonEntree(LibellesWeb.DetailMission.presencesEtPointage)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mission-presences")
                }
            case .heures:
                NavigationLink {
                    DetailPresencesScreen(missionId: mission.id, session: session, snapshot: snapshot)
                } label: {
                    boutonEntree(LibellesWeb.DetailMission.heuresPointees)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mission-heures")
            }
        }
    }

    private func boutonEntree(_ titre: String) -> some View {
        Text(titre)
            .font(JoleneFont.button)
            .foregroundStyle(JoleneColor.onGradient)
            .multilineTextAlignment(.center)
            .padding(.horizontal, JoleneSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(JoleneColor.heroGradient)
            .clipShape(Capsule())
            .contentShape(Capsule())
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
