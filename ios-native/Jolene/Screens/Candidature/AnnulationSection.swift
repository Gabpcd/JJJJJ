import SwiftUI
import JoleneCore
import JoleneDesign

/// « Annuler ma participation » du détail d'une mission (lot 1, T7), port de `DetailMissionSoignant.tsx` l.1516-1523 :
/// rendu seulement pour une mission `ASSIGNEE` au soignant. Candidature `ACCEPTEE` relue → modale de candidature
/// (`AnnulationSheet`) ; sinon confirmation simple (web : `ModalConfirmation`), affichée dans la section, sans le message
/// de pénalité du web (barème client contredit par le serveur, décision 4). Issue annoncée après la relecture
/// (`AnnulationModel`), avec les textes du web (`TextesWeb.Annulation`, HARD STOP n°4).
///
/// Identifiants : `annulation-section`, `annulation-ouvrir`, `annulation-chargement-erreur`, `annulation-recharger`,
/// `annulation-mission-confirmation` (+ `-titre`), `annulation-mission-oui`, `annulation-mission-non`, `annulation-succes`,
/// `annulation-erreur`, `annulation-renvoi-web`.
struct AnnulationSection: View {
    private typealias L = LibellesAnnulation

    let mission: Mission
    @ObservedObject private var session: SessionStore
    @StateObject private var model: AnnulationModel
    @Environment(\.appareil) private var appareil
    @Environment(\.mediaDemo) private var mediaDemo
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @State private var confirmationOuverte = false
    @State private var feuille: DemandeAnnulation?
    /// Journal illisible (revue B8 de #1156, m7) : la modale demande le renvoi web, présenté une fois la modale fermée
    /// (une seule feuille par niveau).
    @State private var renvoiApresFermeture = false
    /// Relecture de la mission de l'écran après une annulation relue (revue B8 de #1156, M1) : rien de l'état « assignée »
    /// ne reste affiché (le web quitte le détail, `DetailMissionSoignant.tsx` l.917 et l.1656).
    private let relireMission: (@MainActor @Sendable () async -> Void)?

    init(mission: Mission, session: SessionStore, snapshot: SessionSnapshot,
         relireMission: (@MainActor @Sendable () async -> Void)? = nil) {
        self.mission = mission
        self.session = session
        self.relireMission = relireMission
        _model = StateObject(wrappedValue: AnnulationModel(missionId: mission.id, controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            if let erreur = model.erreurChargement {
                InlineNotice(erreur, tone: .error, identifier: "annulation-chargement-erreur", announcesOnAppear: true)
                JoleneButton(L.reessayer, style: .secondary) { Task { await model.charger(mission) } }
                    .accessibilityIdentifier("annulation-recharger")
            }
            if let entree = model.entree {
                if confirmationOuverte, entree == .mission {
                    confirmationMission
                } else {
                    Button { ouvrir(entree) } label: {
                        Text(L.annulerMaParticipation)
                            .font(JoleneFont.button)
                            .foregroundStyle(JoleneColor.rose800)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(Capsule().stroke(JoleneColor.rose800, lineWidth: 2))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.envoiEnCours || model.chargement)
                    .accessibilityIdentifier("annulation-ouvrir")
                }
            }
            issue
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("annulation-section")
        // Relu quand la mission relue change d'attribution (ligne de liste d'abord, détail relu ensuite).
        .task(id: "\(mission.id)|\(mission.record.statut)|\(mission.record.soignantAssigneId ?? "")") {
            model.recus = appareil?.recus
            await model.charger(mission)
        }
        .onChange(of: model.issue) { issue in
            guard case .annulee = issue else { return }
            Task { await relireMission?() }
        }
        .sheet(item: $feuille, onDismiss: apresFermeture) { demande in
            AnnulationSheet(candidatureId: demande.candidatureId, mission: mission, model: model, mediaDemo: mediaDemo,
                            ouvrirSurLeWeb: demandeRenvoi)
        }
    }

    private var routeWeb: JoleneRoute? { AnnulationRules.routeRenvoiWeb(missionId: mission.id) }

    /// Renvoi web demandé par la modale (journal illisible) ; nil sans présentateur : jamais un bouton sans effet.
    private var demandeRenvoi: (() -> Void)? {
        guard routeWeb != nil, presentateurRenvoiWeb != nil else { return nil }
        return { renvoiApresFermeture = true }
    }

    private func apresFermeture() {
        model.effacerIssue()
        guard renvoiApresFermeture else { return }
        renvoiApresFermeture = false
        if let presentateurRenvoiWeb, let routeWeb { presentateurRenvoiWeb.presenter(routeWeb) }
    }

    // MARK: - Confirmation sans candidature

    private var confirmationMission: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            Text(L.titreConfirmationMission)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("annulation-mission-confirmation-titre")
            HStack(spacing: JoleneSpacing.md) {
                JoleneButton(L.nonGarder, style: .secondary) { confirmationOuverte = false }
                    .disabled(model.envoiEnCours)
                    .accessibilityIdentifier("annulation-mission-non")
                JoleneButton(TextesWeb.Annulation.ouiAnnuler, style: .destructive, isLoading: model.envoiEnCours) {
                    Task {
                        await model.annulerMission()
                        confirmationOuverte = false
                    }
                }
                .disabled(model.envoiEnCours)
                .accessibilityIdentifier("annulation-mission-oui")
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("annulation-mission-confirmation")
    }

    // MARK: - Issue (hors de la modale)

    @ViewBuilder private var issue: some View {
        if feuille == nil, let issue = model.issue {
            switch issue {
            case let .annulee(message):
                InlineNotice(message, tone: .success, identifier: "annulation-succes", announcesOnAppear: true)
            case let .erreur(message), let .sessionExpiree(message):
                InlineNotice(message, tone: .error, identifier: "annulation-erreur", announcesOnAppear: true)
            case let .bloquee(message):
                InlineNotice(message, tone: .warning, identifier: "annulation-erreur", announcesOnAppear: true)
                renvoiWeb
            }
        }
    }

    /// Voie de récupération d'un journal illisible : le détail web de la mission (jamais un bouton sans effet).
    @ViewBuilder private var renvoiWeb: some View {
        if let presentateurRenvoiWeb, let route = AnnulationRules.routeRenvoiWeb(missionId: mission.id) {
            JoleneButton(L.ouvrirSurLeWeb, style: .secondary) { presentateurRenvoiWeb.presenter(route) }
                .accessibilityIdentifier("annulation-renvoi-web")
        }
    }

    private func ouvrir(_ entree: AnnulationRules.Entree) {
        model.effacerIssue()
        switch entree {
        case let .candidature(id):
            feuille = DemandeAnnulation(candidatureId: id)
        case .mission:
            confirmationOuverte = true
        }
    }
}

/// Ouverture de la modale d'annulation d'une candidature.
struct DemandeAnnulation: Identifiable, Equatable {
    let candidatureId: String
    var id: String { candidatureId }
}

// MARK: - Sélecteurs démo dans l'environnement

private struct MediaDemoKey: EnvironmentKey {
    static let defaultValue: DemoMediaPicker? = nil
}

extension EnvironmentValues {
    /// Sélecteurs de médias du monde démo (`AppContainer.mediaDemo`), injectés au-dessus des onglets par `MainTabView` ;
    /// nil hors démo (vrais sélecteurs). Lot 1, T7 : justificatif de l'annulation, depuis le détail d'une mission.
    var mediaDemo: DemoMediaPicker? {
        get { self[MediaDemoKey.self] }
        set { self[MediaDemoKey.self] = newValue }
    }
}
