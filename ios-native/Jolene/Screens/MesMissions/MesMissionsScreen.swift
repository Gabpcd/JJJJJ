import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet « Mes missions » (lot 1, T5) : vue de `MesMissionsModel` (JoleneCore), port de
/// `MissionsSoignant.tsx` — Candidatures · À venir · Passées. Les règles d'état (onglet relu à la
/// sélection, relecture sans démontage, session expirée, epoch, délai, « Charger plus ») sont testées
/// dans `MesMissionsModelTests`, les textes et lignes dans `MesMissionsPresentationTests` ; la vue
/// n'ajoute aucune logique ni aucun calcul de montant.
///
/// À venir : bouton « Ajouter au calendrier » (`calendrier-{id}`, décision 18) quand l'ajout est
/// injecté (`CalendarWriter`) et que le planning est complet ; issue sous les onglets
/// (`missions-calendrier-issue`). Passées : note « net estimé » du web, verbatim. États vides : renvoi
/// vers Explorer (la recherche de missions ne vit qu'à cet onglet, comme sur le web).
/// Exclus (HARD STOP n°4, comme l'Accueil) : `BandeauAlerte48h` ; les heures de la semaine ne sont pas lues.
struct MesMissionsScreen: View {
    @StateObject private var model: MesMissionsModel
    @ObservedObject private var session: SessionStore
    private let snapshot: SessionSnapshot
    private let ouvrirOnglet: (MainTabView.Tab) -> Void
    @Environment(\.ajoutCalendrierMission) private var calendrier
    @State private var issueCalendrier: AjoutCalendrierIssue?

    init(session: SessionStore, snapshot: SessionSnapshot, onglet: MesMissionsOnglet = .aVenir,
         ouvrirOnglet: @escaping (MainTabView.Tab) -> Void) {
        self.session = session
        self.snapshot = snapshot
        self.ouvrirOnglet = ouvrirOnglet
        _model = StateObject(wrappedValue: MesMissionsModel(controller: session.controller, snapshot: snapshot, onglet: onglet))
    }

    var body: some View {
        VStack(spacing: 0) {
            selecteurOnglets
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                    switch model.onglet {
                    case .candidatures:
                        contenu(model.candidatures, onglet: .candidatures) { candidatures in
                            ForEach(candidatures.compactMap { MesMissionsPresentation.ligne(candidature: $0, maintenant: model.horloge.now()) }) {
                                lienMission($0)
                            }
                        }
                    case .aVenir:
                        contenu(model.aVenir, onglet: .aVenir) { missions in
                            if let issue = issueCalendrier {
                                InlineNotice(issue.message, tone: issue.succes ? .success : .error, identifier: "missions-calendrier-issue",
                                             announcesOnAppear: true)
                            }
                            ForEach(missions) { mission in
                                HStack(spacing: JoleneSpacing.sm) {
                                    lienMission(MesMissionsPresentation.ligneAVenir(mission, maintenant: model.horloge.now()))
                                    boutonCalendrier(mission)
                                }
                            }
                        }
                    case .passees:
                        contenu(model.passees, onglet: .passees) { missions in
                            ForEach(missions) { mission in
                                lienMission(MesMissionsPresentation.lignePassee(mission, finance: model.finances[mission.id]))
                            }
                            Text(AccueilPresentation.noteNetEstime)
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.bubblegum)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("missions-note-net-estime")
                        }
                    }
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.charger() }
            .accessibilityIdentifier("mes-missions-scroll")
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mes-missions-screen")
        .navigationTitle("Mes missions")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MissionRoute.self) { route in
            MissionDetailScreen(route: route, initial: model.mission(id: route.id), session: session, snapshot: snapshot)
        }
        // Chaque apparition relit l'onglet affiché (liste conservée pendant la relecture), comme le web
        // qui relit à chaque montage : une candidature posée ailleurs y figure au retour.
        .task { await model.charger() }
    }

    // MARK: - Onglets

    private var selecteurOnglets: some View {
        HStack(spacing: 0) {
            ForEach(MesMissionsOnglet.allCases) { onglet in
                let actif = model.onglet == onglet
                Button {
                    Task { await model.selectionner(onglet) }
                } label: {
                    VStack(spacing: JoleneSpacing.xs) {
                        Text(onglet.titre)
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(actif ? JoleneColor.rose700 : JoleneColor.bubblegum)
                            .lineLimit(1)
                        Capsule()
                            .fill(actif ? JoleneColor.rose700 : Color.clear)
                            .frame(height: 2)
                    }
                    .padding(.top, JoleneSpacing.sm)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(onglet.titre)
                .accessibilityAddTraits(actif ? [.isSelected] : [])
                .accessibilityIdentifier(onglet.identifiant)
            }
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, JoleneSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(JoleneColor.cloud)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("missions-tabs")
    }

    // MARK: - États

    /// États d'une liste d'onglet : chargement, erreur (ou session à vérifier), vide, liste avec ses
    /// encarts (relecture échouée, « Charger plus » et son échec).
    @ViewBuilder
    private func contenu<Element, Lignes: View>(_ liste: MesMissionsModel.Liste<Element>, onglet: MesMissionsOnglet,
                                                @ViewBuilder lignes: ([Element]) -> Lignes) -> some View
        where Element: Equatable & Sendable & Identifiable, Element.ID == String {
        switch liste.contenu {
        case .chargement:
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                Text(MesMissionsPresentation.chargement(onglet))
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                SkeletonCard()
                SkeletonCard()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mes-missions-loading")
        case let .echec(message) where model.sessionExpired:
            EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Session à vérifier", message: message,
                       identifier: "mes-missions-session-expired", actionTitle: "Vérifier ma session",
                       actionIdentifier: "mes-missions-session-check") { Task { await model.verifierSession(session) } }
        case let .echec(message):
            EmptyState(systemImage: "wifi.exclamationmark", title: MesMissionsPresentation.titreErreur, message: message,
                       identifier: "mes-missions-error", actionTitle: "Réessayer",
                       actionIdentifier: "mes-missions-retry") { Task { await model.charger() } }
        case let .chargee(elements) where elements.isEmpty:
            erreurRafraichissement(liste)
            let vide = MesMissionsPresentation.etatVide(onglet)
            EmptyState(systemImage: onglet == .passees ? "clock.arrow.circlepath" : "briefcase", title: vide.titre,
                       message: vide.message, identifier: "missions-empty-\(onglet.rawValue)", actionTitle: vide.action,
                       actionIdentifier: "missions-empty-action-\(onglet.rawValue)") { ouvrirOnglet(.explorer) }
        case let .chargee(elements):
            erreurRafraichissement(liste)
            lignes(elements)
            if liste.aSuivre {
                JoleneButton(MesMissionsPresentation.chargerPlus, style: .secondary, isLoading: liste.chargementSuite) {
                    Task { await model.chargerPlus() }
                }
                .disabled(liste.chargementSuite)
                .accessibilityIdentifier("missions-load-more")
            }
            if let erreur = liste.erreurSuite {
                InlineNotice(erreur, tone: .error, identifier: "missions-load-more-error", announcesOnAppear: true)
            }
        }
    }

    @ViewBuilder
    private func erreurRafraichissement<Element>(_ liste: MesMissionsModel.Liste<Element>) -> some View
        where Element: Equatable & Sendable & Identifiable, Element.ID == String {
        if let erreur = liste.erreurRafraichissement {
            InlineNotice(erreur, tone: .error, identifier: "mes-missions-refresh-error", announcesOnAppear: true)
        }
    }

    // MARK: - Lignes

    private func lienMission(_ ligne: MesMissionsPresentation.Ligne) -> some View {
        NavigationLink(value: MissionRoute(id: ligne.id)) {
            MesMissionLigneVue(ligne: ligne)
                .padding(JoleneSpacing.md)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ligne.texteAccessible)
        .accessibilityHint("Ouvre le détail de la mission")
        .accessibilityIdentifier("mes-mission-\(ligne.id)")
    }

    /// Affiché seulement si l'ajout au calendrier est injecté et que le planning est complet.
    @ViewBuilder
    private func boutonCalendrier(_ mission: Mission) -> some View {
        if let calendrier, !CalendrierMission.evenements(pour: mission).isEmpty {
            Button {
                Task { issueCalendrier = await calendrier.ajouterAuCalendrier(mission) }
            } label: {
                Image(systemName: "calendar.badge.plus")
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.rose700)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter au calendrier")
            .accessibilityIdentifier("calendrier-\(mission.id)")
        }
    }
}
