import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Accueil (lot 1, T3) : vue de `AccueilModel` (JoleneCore), port de
/// `DashboardSoignant.tsx`. Les règles d'état (annulation, rafraîchissement, session expirée,
/// epoch, délai) et les textes sont testés dans JoleneCore (`AccueilModelTests`,
/// `AccueilAssemblageTests`) ; la vue n'ajoute aucune logique ni aucun calcul de montant.
///
/// Sections, dans l'ordre du web : en-tête (salutation, accroche), oubli de pointage (renvoi
/// web : pointage au lot 2), mes prochaines missions (+ calendrier, point d'extension T5),
/// missions pour vous, missions proposées, gains du mois, notifications non lues.
/// Exclus (HARD STOP n°4) : `BandeauAlerte48h` et l'encart « cumul d'activité ».
///
/// Renvois web (pointage, notifications) : routes `.safari` résolues par `LinkRouter`
/// (`AccueilPresentation.renvoiWeb`), jamais une URL écrite en dur.
struct AccueilScreen: View {
    static let renvoiPresences = AccueilPresentation.renvoiWeb(AccueilPresentation.lienPresences)
    static let renvoiNotifications = AccueilPresentation.renvoiWeb(AccueilPresentation.lienNotifications)

    @StateObject private var model: AccueilModel
    @ObservedObject private var session: SessionStore
    private let snapshot: SessionSnapshot
    private let ouvrirOnglet: (MainTabView.Tab) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.ajoutCalendrierMission) private var calendrier
    @State private var issueCalendrier: AjoutCalendrierIssue?

    init(session: SessionStore, snapshot: SessionSnapshot, ouvrirOnglet: @escaping (MainTabView.Tab) -> Void) {
        self.session = session
        self.snapshot = snapshot
        self.ouvrirOnglet = ouvrirOnglet
        _model = StateObject(wrappedValue: AccueilModel(controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                switch model.state {
                case .loading:
                    chargement
                case let .failed(message) where model.sessionExpired:
                    // Session expirée côté serveur : revalider la session plutôt que rejouer la lecture.
                    EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Session à vérifier", message: message,
                               identifier: "accueil-session-expired", actionTitle: "Vérifier ma session",
                               actionIdentifier: "accueil-session-check") { Task { await session.start() } }
                case let .failed(message):
                    EmptyState(systemImage: "wifi.exclamationmark", title: "Impossible de charger votre tableau de bord",
                               message: message, identifier: "accueil-error", actionTitle: "Réessayer",
                               actionIdentifier: "accueil-retry") { Task { await model.load() } }
                case let .loaded(tableau):
                    contenu(tableau)
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.load() }
        .accessibilityIdentifier("accueil-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Accueil")
        .navigationDestination(for: MissionRoute.self) { route in
            MissionDetailScreen(route: route, initial: model.mission(id: route.id), session: session, snapshot: snapshot)
        }
        // Premier affichage, relance après une tâche annulée, relecture au-delà de 60 s.
        .task { await model.loadIfStale() }
    }

    // MARK: - États

    private var chargement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            SkeletonBlock(size: .lg, width: 220)
            SkeletonBlock(size: .sm, width: 280)
            SkeletonCard()
            SkeletonCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accueil-loading")
    }

    @ViewBuilder
    private func contenu(_ tableau: DashboardSnapshot) -> some View {
        if let refreshError = model.refreshError {
            InlineNotice(refreshError, tone: .error, identifier: "accueil-refresh-error", announcesOnAppear: true)
        }
        entete(tableau)
        if let texte = AccueilPresentation.texteOubliPointage(tableau.missionsOublieesCount) {
            oubliPointage(texte)
        }
        if !tableau.prochaines.isEmpty {
            prochaines(tableau.prochaines)
        }
        pourVous(tableau.pourToi)
        if !tableau.propositions.isEmpty {
            propositions(tableau.propositions)
        }
        if let gains = tableau.gains, let texte = AccueilPresentation.texteGains(gains) {
            carteGains(texte, note: AccueilPresentation.afficheNoteNetEstime(gains))
        }
        if let texte = AccueilPresentation.texteNotifications(tableau.notifsNonLues) {
            notifications(texte)
        }
    }

    // MARK: - Sections

    private func entete(_ tableau: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(AccueilPresentation.salutation(prenom: tableau.profil?.prenom, maintenant: model.horloge.now()))
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("accueil-salutation")
            Text(AccueilPresentation.accroche(profil: tableau.profil, nombreOuvertes: tableau.pourToi.count))
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("accueil-accroche")
        }
    }

    private func oubliPointage(_ texte: String) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(texte, title: "Oubli de pointage ?", tone: .warning, identifier: "accueil-oubli-pointage")
            if let route = Self.renvoiPresences {
                JoleneButton("Vérifier mes présences sur jolene.app", style: .secondary) { ouvrir(route) }
                    .accessibilityIdentifier("accueil-oubli-pointage-action")
            }
        }
    }

    private func prochaines(_ missions: [AccueilMission]) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            SectionHeader("Mes prochaines missions", identifier: "accueil-section-prochaines", actionTitle: "Voir tout") {
                ouvrirOnglet(.missions)
            }
            if let issue = issueCalendrier {
                InlineNotice(issue.message, tone: issue.succes ? .success : .error, identifier: "accueil-calendrier-issue",
                             announcesOnAppear: true)
            }
            ForEach(missions) { mission in
                HStack(spacing: JoleneSpacing.sm) {
                    NavigationLink(value: MissionRoute(id: mission.id)) {
                        AccueilMissionLigne(mission: mission, mode: .prochaine)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AccueilMissionLigne.texteAccessible(mission, mode: .prochaine))
                    .accessibilityHint("Ouvre le détail de la mission")
                    .accessibilityIdentifier("accueil-prochaine-\(mission.id)")
                    boutonCalendrier(mission)
                }
                .padding(JoleneSpacing.md)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            }
        }
    }

    /// Affiché seulement si T5 a injecté l'ajout au calendrier et que le planning est vérifié.
    @ViewBuilder
    private func boutonCalendrier(_ mission: AccueilMission) -> some View {
        if let calendrier, let detail = mission.mission, AccueilPresentation.jour(mission.planning) != nil {
            Button {
                Task { issueCalendrier = await calendrier.ajouterAuCalendrier(detail) }
            } label: {
                Image(systemName: "calendar.badge.plus")
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.rose700)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter au calendrier")
            .accessibilityIdentifier("accueil-calendrier-\(mission.id)")
        }
    }

    private func pourVous(_ missions: [AccueilMission]) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            SectionHeader("Missions pour vous", identifier: "accueil-section-pour-toi", actionTitle: "Tout voir") {
                ouvrirOnglet(.explorer)
            }
            if missions.isEmpty {
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                    Text("De nouvelles missions arrivent 🔔")
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                    Text("Les nouvelles missions apparaîtront ici dès leur publication.")
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                    JoleneButton("Explorer les missions", style: .secondary) { ouvrirOnglet(.explorer) }
                        .accessibilityIdentifier("accueil-pour-toi-explorer")
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("accueil-pour-toi-vide")
            } else {
                ForEach(missions.prefix(AccueilPresentation.nombrePourToiAffiches)) { mission in
                    NavigationLink(value: MissionRoute(id: mission.id)) {
                        AccueilMissionLigne(mission: mission, mode: .pourVous)
                            .padding(JoleneSpacing.md)
                            .background(JoleneColor.cloud)
                            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AccueilMissionLigne.texteAccessible(mission, mode: .pourVous))
                    .accessibilityHint("Ouvre le détail de la mission")
                    .accessibilityIdentifier("accueil-pour-toi-\(mission.id)")
                }
            }
        }
    }

    private func propositions(_ propositions: [AccueilProposition]) -> some View {
        // Décompte relu toutes les 30 s sur l'horloge des gateways (fixe en démo). Le filtre est posé
        // au niveau de la section : une carte disparaît à son échéance, et la section entière (en-tête
        // compris) quand toutes ont expiré, comme `CarteProposition` + `onTraitee` du web.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let affichees = AccueilPresentation.propositionsAffichees(propositions, maintenant: model.horloge.now())
            if !affichees.isEmpty {
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                    SectionHeader("🚨 Missions proposées", identifier: "accueil-section-propositions")
                    ForEach(affichees) { affichee in
                        NavigationLink(value: MissionRoute(id: affichee.proposition.proposition.missionId)) {
                            AccueilPropositionCarte(proposition: affichee.proposition, restant: affichee.restant)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AccueilPropositionCarte.texteAccessible(affichee.proposition, restant: affichee.restant))
                        .accessibilityHint("Ouvre le détail de la mission proposée")
                        .accessibilityIdentifier("accueil-proposition-\(affichee.id)")
                    }
                }
            }
        }
    }

    private func carteGains(_ texte: String, note: Bool) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.md) {
                Image(systemName: "banknote")
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.rose700)
                    .accessibilityHidden(true)
                Text(texte)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("accueil-gains")
            }
            if note {
                Text(AccueilPresentation.noteNetEstime)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("accueil-gains-note")
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    private func notifications(_ texte: String) -> some View {
        HStack(spacing: JoleneSpacing.md) {
            Image(systemName: "bell")
                .foregroundStyle(JoleneColor.mauve700)
                .accessibilityHidden(true)
            Text(texte)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityIdentifier("accueil-notifications")
            Spacer(minLength: 0)
            if let route = Self.renvoiNotifications {
                Button("Voir sur jolene.app") { ouvrir(route) }
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose800)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("accueil-notifications-action")
            }
        }
        .padding(.horizontal, JoleneSpacing.lg)
        .padding(.vertical, JoleneSpacing.sm)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }

    // MARK: - Renvois web

    /// Ouvre une route `.safari` hors de l'app. Point de fusion T10 (`LOT1_PLAN.md` §3 T10) : quand
    /// `onOpenURL` / `onContinueUserActivity` seront branchés, ce renvoi passera par le présentateur
    /// `.safari` du `DeepLinkCoordinator` (SFSafariViewController), jamais par `openURL` : ces chemins
    /// sont couverts par l'AASA `/soignant/*` et reviendraient dans l'app par lien universel, que
    /// `LinkRouter` renverrait en `.safari` (boucle).
    private func ouvrir(_ route: JoleneRoute) {
        guard let url = route.externalURL else { return }
        openURL(url)
    }
}
