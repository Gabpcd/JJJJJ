import SwiftUI
import JoleneCore
import JoleneDesign

/// Accueil de l'espace établissement (lot 5, T4 ; `LOT5_PLAN.md` §3 T4) : vue de `EtabAccueilModel` (JoleneCore),
/// liste d'actions prioritaires sans graphique, bouton « Publier une mission », planning des 31 prochains jours.
/// Règles d'état, ordre et filtrage des actions, textes et formats sont testés dans JoleneCore
/// (`EtabAccueilModelTests`, `PrioriteActionsTests`, `EtabDashboardDecodingTests`) ; la vue n'ajoute aucune logique.
///
/// Les actions sont dérivées de l'instantané de session **courant** (`snapshot`, re-filtré à epoch constant après une
/// relecture des permissions). Chaque action, le bouton Publier et chaque ligne du planning mènent à un chemin web
/// résolu par la table des liens de l'espace (`PrioriteActions.presentation`) : onglet natif (`ouvrir`), écran livré,
/// sinon renvoi web par le présentateur `.safari` (D16) — jamais un écran provisoire.
///
/// Identifiants : `etab-accueil-screen`, `etab-accueil-nom`, `etab-accueil-role`, `etab-accueil-loading`,
/// `etab-accueil-error` / `-retry`, `etab-accueil-session-expired` / `-session-check`, `etab-accueil-refresh-error`,
/// `etab-accueil-partiel`, `etab-accueil-actions`, `etab-action-<cle>` (+ `-cta`), `etab-accueil-aucune-action`,
/// `etab-accueil-note-web`, `etab-accueil-publier`, `etab-accueil-planning` (+ `-compteur`, `-vide`, `-erreur`,
/// `-retry`, `-a-confirmer`), `etab-prochaine-<occurrence>`.
struct EtabAccueilScreen: View {
    @StateObject private var model: EtabAccueilModel
    @ObservedObject private var session: SessionStore
    private let snapshot: EtablissementSessionSnapshot
    private let ouvrir: (CibleEtablissement) -> Void
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @Environment(\.openURL) private var openURL

    init(session: SessionStore, snapshot: EtablissementSessionSnapshot, ouvrir: @escaping (CibleEtablissement) -> Void) {
        self.session = session
        self.snapshot = snapshot
        self.ouvrir = ouvrir
        _model = StateObject(wrappedValue: EtabAccueilModel(controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                entete
                switch model.state {
                case .loading:
                    chargement
                case let .failed(message) where model.sessionExpired:
                    EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Session à vérifier", message: message,
                               identifier: "etab-accueil-session-expired", actionTitle: "Vérifier ma session",
                               actionIdentifier: "etab-accueil-session-check") { Task { await model.verifierSession(session) } }
                case let .failed(message):
                    EmptyState(systemImage: "wifi.exclamationmark", title: "Impossible de charger le tableau de bord",
                               message: message, identifier: "etab-accueil-error", actionTitle: EtabAccueilPresentation.reessayer,
                               actionIdentifier: "etab-accueil-retry") { Task { await model.load() } }
                case let .loaded(tableau):
                    contenu(tableau)
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.load() }
        .accessibilityIdentifier("etab-accueil-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Accueil")
        .task { await model.loadIfStale() }
    }

    // MARK: - États

    private var entete: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(snapshot.etablissement.nom)
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("etab-accueil-nom")
            Text(snapshot.context.roleEtab.libelle)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("etab-accueil-role")
        }
    }

    private var chargement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            SkeletonBlock(size: .lg, width: 220)
            SkeletonCard()
            SkeletonCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-accueil-loading")
    }

    @ViewBuilder
    private func contenu(_ tableau: EtabDashboardSnapshot) -> some View {
        if let refreshError = model.refreshError {
            InlineNotice(refreshError, tone: .error, identifier: "etab-accueil-refresh-error", announcesOnAppear: true)
        }
        if tableau.lecturePartielle {
            InlineNotice(EtabAccueilPresentation.lecturePartielle, tone: .warning, identifier: "etab-accueil-partiel")
        }
        actions(PrioriteActions.liste(profil: snapshot.etablissement, stats: tableau.stats,
                                      permissions: snapshot.context.permissions))
        if snapshot.context.permissions.missions {
            JoleneButton(EtabAccueilPresentation.publier) { aller(PrioriteActions.Chemins.publier) }
                .accessibilityIdentifier("etab-accueil-publier")
        }
        planning(tableau.planning)
    }

    // MARK: - Actions prioritaires

    private func actions(_ actions: [ActionPrioritaire]) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            SectionHeader(EtabAccueilPresentation.titreActions, identifier: "etab-accueil-actions")
            if actions.isEmpty {
                Text(EtabAccueilPresentation.aucuneAction)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("etab-accueil-aucune-action")
            }
            ForEach(actions) { action in
                ligne(action)
            }
            if actions.contains(where: { estRenvoiWeb($0.chemin) }) {
                Text(EtabAccueilPresentation.noteRenvoiWeb)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("etab-accueil-note-web")
            }
        }
    }

    private func ligne(_ action: ActionPrioritaire) -> some View {
        let web = estRenvoiWeb(action.chemin)
        return VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(action.titre)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = action.detail {
                Text(detail)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { aller(action.chemin) } label: {
                Label(action.cta, systemImage: web ? "safari" : "arrow.right")
                    .font(JoleneFont.button)
                    .foregroundStyle(JoleneColor.rose700)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(Capsule().strokeBorder(JoleneColor.rose700, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(web ? "Ouvre jolene.app" : "Ouvre l'écran dans l'application")
            .accessibilityIdentifier("etab-action-\(action.cle.rawValue)-cta")
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(action.urgente ? JoleneColor.rose100 : JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-action-\(action.cle.rawValue)")
    }

    // MARK: - Planning à venir

    private func planning(_ planning: EtabPlanningAVenir?) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            SectionHeader(EtabAccueilPresentation.titrePlanning, identifier: "etab-accueil-planning")
            if let planning {
                Text(EtabAccueilPresentation.compteurPlanning(planning))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("etab-accueil-planning-compteur")
                if !planning.missionsSansPlanning.isEmpty {
                    aConfirmer(planning.missionsSansPlanning)
                }
                if planning.occurrences.isEmpty, planning.missionsSansPlanning.isEmpty {
                    Text(EtabAccueilPresentation.planningVide)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityIdentifier("etab-accueil-planning-vide")
                }
                ForEach(planning.occurrences.prefix(EtabAccueilPresentation.occurrencesAffichees)) { occurrence in
                    Button { aller(PrioriteActions.Chemins.mission(occurrence.missionId)) } label: {
                        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(occurrence.intitule)
                                    .font(JoleneFont.callout.weight(.semibold))
                                    .foregroundStyle(JoleneColor.midnight)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(EtabAccueilPresentation.statut(occurrence.statut))
                                    .font(JoleneFont.caption)
                                    .foregroundStyle(JoleneColor.rose800)
                            }
                            Text(EtabAccueilPresentation.horaire(occurrence))
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.bubblegum)
                        }
                        .padding(JoleneSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(JoleneColor.cloud)
                        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                        .contentShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Ouvre la mission")
                    .accessibilityIdentifier("etab-prochaine-\(occurrence.id)")
                }
            } else {
                InlineNotice(EtabAccueilPresentation.planningErreur, tone: .error, identifier: "etab-accueil-planning-erreur")
                JoleneButton(EtabAccueilPresentation.reessayer, style: .secondary) { Task { await model.load() } }
                    .accessibilityIdentifier("etab-accueil-planning-retry")
            }
        }
    }

    private func aConfirmer(_ missions: [EtabMissionPlanifiee]) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            InlineNotice(EtabAccueilPresentation.sansPlanningDetail, title: EtabAccueilPresentation.sansPlanningTitre, tone: .warning)
            ForEach(missions) { mission in
                Button { aller(PrioriteActions.Chemins.mission(mission.id)) } label: {
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                        Text(mission.intitule)
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(JoleneColor.midnight)
                        Text(EtabAccueilPresentation.periodePrevue(mission))
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                    }
                    .padding(JoleneSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JoleneColor.butter100)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    .contentShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("etab-accueil-a-confirmer-\(mission.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-accueil-planning-a-confirmer")
    }

    // MARK: - Navigation

    private func estRenvoiWeb(_ chemin: String) -> Bool {
        if case .renvoiWeb? = PrioriteActions.presentation(chemin: chemin) { return true }
        return false
    }

    /// Chemin résolu par la table des liens de l'espace : onglet ou écran livré, sinon Safari (présentateur `.safari`
    /// du coordinateur ; à défaut, la racine `https://jolene.app`, hors lien universel, comme `RenvoiWebEtabScreen`).
    private func aller(_ chemin: String) {
        switch PrioriteActions.presentation(chemin: chemin) {
        case let .naviguer(cible)?:
            ouvrir(cible)
        case let .renvoiWeb(url)?:
            if let presentateurRenvoiWeb {
                presentateurRenvoiWeb.presenter(.etablissement(url))
            } else {
                openURL(BlockingScreen.siteURL)
            }
        case nil:
            break
        }
    }
}
