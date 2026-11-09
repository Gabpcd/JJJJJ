import SwiftUI
import JoleneCore
import JoleneDesign

/// Page Présences (blueprint lot 2 §3 T4a) : vue de `PresencesModel` (JoleneCore), port de `PresencesSoignant.tsx`.
/// Les règles d'état (onglet initial, annulation, rafraîchissement, session expirée, epoch, délai, relecture à 60 s),
/// les dérivations (listes, historique, blocs de pointage) et les textes sont testés dans JoleneCore
/// (`PresencesModelTests`, `PresencesAffichageTests`, `LibellesPresencesTests`) ; la vue n'ajoute aucune règle.
///
/// Onglets dans l'ordre du web (À venir, Actives, Aujourd'hui, Historique ; `?tab=` aux valeurs exactes du web, porté
/// par la route de T10 avec `?filtre=a_valider`). Onglet Aujourd'hui : blocs de pointage puis « Présences validées
/// récemment » ; Actives : blocs des missions EN_COURS ; Historique : bandeau « à valider » (`TextesWeb.Presences`,
/// verbatim, texte HARD STOP n°4 de TL en attente de la validation de Gabrielle) quand le lien le demande, puis les
/// lignes. T4b : bandeaux hors ligne (`HorsLigneBandeau`) et sans GPS (`BandeauSansGpsView`) en tête, retour du
/// consentement, services des zones de pointage (`ServicesPointage` : consentement GPS de la page, état du réseau suivi
/// par `Appareil.reseau`, relecture de l'instantané après un pointage enregistré, m1). Exclus : notation (T5a),
/// contestation (T5b).
///
/// Actions des états vides : onglets de l'app (les routes web `/soignant/missions` et `/soignant/planning` sont
/// « Mes missions », `/soignant/recherche-missions` est Explorer, `LinkRouter`).
///
/// Coupe-circuit D-FLAGS `ios_natif_presences_actif` (seconde revue fraîche de T4b, m3 ; fail-open, comme
/// `ios_natif_documents_actif` dans `MesDocumentsScreen`) : lu à l'apparition ; à faux, la page entière (onglets et zones de
/// pointage) devient un renvoi web `/soignant/presences` (`presences-desactive-renvoi`, bouton `presences-desactive-web`
/// seulement avec le présentateur des renvois web de T10 : aucun bouton sans effet). La ligne du consentement du Profil
/// reste native (retrait promis par le texte de consentement, correction 15).
struct PresencesScreen: View {
    @StateObject private var model: PresencesModel
    @StateObject private var consentement: ConsentementGpsModel
    @StateObject private var reseau = EtatReseauModel()
    @ObservedObject private var session: SessionStore
    private let snapshot: SessionSnapshot
    private let ouvrirOnglet: (MainTabView.Tab) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appareil) private var appareil
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    /// Drapeau `ios_natif_presences_actif`, fail-open tant qu'il n'est pas lu.
    @State private var ecranActif = true
    #if DEBUG
    @StateObject private var compteursDemo = CompteursPointageDemo()
    #endif

    init(session: SessionStore, snapshot: SessionSnapshot, parametreOnglet: String? = nil, parametreFiltre: String? = nil,
         ouvrirOnglet: @escaping (MainTabView.Tab) -> Void) {
        self.session = session
        self.snapshot = snapshot
        self.ouvrirOnglet = ouvrirOnglet
        _model = StateObject(wrappedValue: PresencesModel(controller: session.controller, snapshot: snapshot,
                                                          parametreOnglet: parametreOnglet, parametreFiltre: parametreFiltre))
        _consentement = StateObject(wrappedValue: ConsentementGpsModel(controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        Group {
            if ecranActif { page } else { renvoiDesactive }
        }
        .navigationTitle(LibellesWeb.ListePresences.titre)
        .task { ecranActif = await Self.drapeau(session: session, snapshot: snapshot) }
    }

    private static func drapeau(session: SessionStore, snapshot: SessionSnapshot) async -> Bool {
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else { return true }
        return await gateways.flags.ecranActif(.presences)
    }

    /// Renvoi web de la page (drapeau à faux) : texte du lot 0, bouton seulement si un présentateur est injecté.
    private var renvoiDesactive: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                InlineNotice(LibellesPresences.Liste.ecranNonDisponible, tone: .info, identifier: "presences-desactive-renvoi")
                if let presentateurRenvoiWeb, let route = PresencesRenvois.presences {
                    JoleneButton(LibellesPresences.Pointage.voirSurJolene, style: .secondary) { presentateurRenvoiWeb.presenter(route) }
                        .accessibilityIdentifier("presences-desactive-web")
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("presences-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(LibellesPresences.Liste.sousTitre)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                bandeaux
                switch model.state {
                case .loading:
                    chargement
                case let .failed(echec) where model.sessionExpired:
                    // Session expirée côté serveur : textes et règle de l'Accueil (lot 1, `AccueilScreen`).
                    EmptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Session à vérifier",
                               message: echec.message ?? "", identifier: "presences-session-expired",
                               actionTitle: "Vérifier ma session", actionIdentifier: "presences-session-check") {
                        Task { await model.verifierSession(session) }
                    }
                case let .failed(echec):
                    EmptyState(systemImage: "exclamationmark.triangle", title: LibellesPresences.Liste.erreurTitre,
                               message: echec.message ?? "", identifier: "presences-error",
                               actionTitle: LibellesWeb.ListePresences.reessayer, actionIdentifier: "presences-retry") {
                        Task { await model.load() }
                    }
                case .loaded:
                    contenu
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.load() }
        // T4b : le pavé numérique n'a pas de touche Entrée ; un défilement le ferme et découvre le bouton de pointage.
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("presences-screen")
        .background(JoleneColor.lavender.ignoresSafeArea())
        .environment(\.servicesPointage, services)
        // Premier affichage, relance après une tâche annulée, relecture au-delà de 60 s (`staleTime`).
        .task { await model.loadIfStale() }
        .task { await consentement.charger() }
        .task {
            // Suivi du réseau tant que la page est affichée (tâche annulée à sa disparition).
            if let appareil { await reseau.suivre(appareil.reseau) }
        }
        #if DEBUG
        .task { await compteursDemo.relire(session: session, snapshot: snapshot) }
        #endif
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.loadIfStale() } }
        }
    }

    /// Services des zones de pointage ; `recharger` relit l'instantané après un pointage enregistré (m1).
    private var services: ServicesPointage {
        let model = model
        #if DEBUG
        let session = session, snapshot = snapshot, compteurs = compteursDemo
        return ServicesPointage(consentement: consentement, reseau: reseau, recharger: {
            await model.load()
            await compteurs.relire(session: session, snapshot: snapshot)
        }, apresIssue: {
            // Compteurs démo relus à chaque issue, pas seulement après un succès (revue fraîche de T4b, m3).
            await compteurs.relire(session: session, snapshot: snapshot)
        })
        #else
        return ServicesPointage(consentement: consentement, reseau: reseau, recharger: { await model.load() })
        #endif
    }

    // MARK: - Bandeaux (T4b)

    @ViewBuilder private var bandeaux: some View {
        if reseau.horsLigne { HorsLigneBandeau() }
        if consentement.bandeauSansGps { BandeauSansGpsView() }
        if let retour = consentement.retour {
            InlineNotice(LibellesPresences.Pointage.retourConsentement(retour),
                         tone: LibellesPresences.Pointage.tonConsentement(retour).inlineNotice,
                         identifier: "gps-consent-retour", announcesOnAppear: true)
        }
        #if DEBUG
        if let libelle = compteursDemo.libelle {
            HStack {
                Text(verbatim: "Pointages enregistrés (démo)")
                Spacer()
                Text(verbatim: libelle)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityValue(Text(verbatim: String(compteursDemo.lectures)))
                    .accessibilityIdentifier("pointage-demo-scans")
                // Relecture explicite (preuve des XCUITest : une affirmation suit une lecture postérieure à l'action, m3).
                Button { Task { await compteursDemo.relire(session: session, snapshot: snapshot) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(Text(verbatim: "Relire les compteurs (démo)"))
                .accessibilityIdentifier("pointage-demo-relire")
            }
            .font(JoleneFont.caption)
        }
        #endif
    }

    // MARK: - États

    private var chargement: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            SkeletonBlock(size: .lg, width: 260)
            SkeletonCard()
            SkeletonCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presences-loading")
    }

    @ViewBuilder
    private var contenu: some View {
        if let echec = model.echecRafraichissement {
            InlineNotice(echec.message ?? LibellesPresences.Liste.erreurTitre, tone: .error, identifier: "presences-refresh-error",
                         announcesOnAppear: true)
        }
        OngletsPresences(selection: model.onglet, nombreAVenir: model.listes?.missionsAVenir.count ?? 0) { model.choisir($0) }
        switch model.onglet ?? .aujourdhui {
        case .avenir: aVenir
        case .encours: actives
        case .aujourdhui: aujourdhui
        case .historique: historique
        }
    }

    // MARK: - Onglets

    @ViewBuilder private var aVenir: some View {
        let lignes = model.listes?.missionsAVenir ?? []
        if lignes.isEmpty {
            EmptyState(systemImage: "calendar", title: LibellesWeb.ListePresences.videAVenirTitre,
                       message: LibellesPresences.Liste.videAVenirDescription, identifier: "presences-empty-avenir",
                       actionTitle: LibellesWeb.ListePresences.chercherDesMissions,
                       actionIdentifier: "presences-empty-avenir-action") { ouvrirOnglet(.missions) }
        } else {
            ForEach(lignes, id: \.mission.id) { ligne in
                PresenceAVenirRow(ligne: ligne)
            }
        }
    }

    @ViewBuilder private var actives: some View {
        let missions = model.listes?.missionsEnCours ?? []
        if missions.isEmpty {
            EmptyState(systemImage: "waveform.path.ecg", title: LibellesWeb.ListePresences.videActivesTitre,
                       message: LibellesPresences.Liste.videActivesDescription, identifier: "presences-empty-actives",
                       actionTitle: LibellesWeb.ListePresences.trouverUneMission,
                       actionIdentifier: "presences-empty-actives-action") { ouvrirOnglet(.explorer) }
        } else {
            blocs(missions)
        }
    }

    @ViewBuilder private var aujourdhui: some View {
        let missions = model.listes?.missionsAujourdhui ?? []
        if missions.isEmpty {
            EmptyState(systemImage: "calendar", title: LibellesWeb.ListePresences.videAujourdhuiTitre,
                       message: LibellesPresences.Liste.videAujourdhuiDescription, identifier: "presences-empty-aujourdhui",
                       actionTitle: LibellesWeb.ListePresences.voirMonPlanning,
                       actionIdentifier: "presences-empty-aujourdhui-action") { ouvrirOnglet(.missions) }
        } else {
            blocs(missions)
        }
        let validees = model.presencesValidees
        if !validees.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                HStack(spacing: JoleneSpacing.xs) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(JoleneColor.cyan700)
                        .accessibilityHidden(true)
                    Text(LibellesWeb.ListePresences.valideesRecemment)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(validees) { presence in
                    PresenceValideeRow(presence: presence, etablissement: model.instantane?.etablissement(de: presence))
                }
            }
            .padding(.top, JoleneSpacing.lg)
        }
    }

    @ViewBuilder private var historique: some View {
        if model.aValider {
            InlineNotice(TextesWeb.Presences.bandeauAValider, tone: .warning, identifier: "presences-bandeau-a-valider")
        }
        let lignes = model.historique
        if lignes.isEmpty {
            EmptyState(systemImage: "clock.arrow.circlepath", title: LibellesWeb.ListePresences.videHistoriqueTitre,
                       message: LibellesPresences.Liste.videHistoriqueDescription, identifier: "presences-empty-historique",
                       actionTitle: LibellesWeb.ListePresences.trouverUneMission,
                       actionIdentifier: "presences-empty-historique-action") { ouvrirOnglet(.explorer) }
        } else if let instantane = model.instantane {
            ForEach(lignes) { ligne in
                PresenceHistoriqueRow(ligne: ligne, mission: instantane.mission(de: ligne))
            }
        }
    }

    private func blocs(_ missions: [MissionPresenceEnrichie<MissionPresenceLue, EtablissementSummary>]) -> some View {
        ForEach(missions, id: \.mission.id) { mission in
            BlocPointageView(mission: mission, contrat: model.listes?.contrats[mission.mission.id], horloge: model.horloge,
                             session: session, snapshot: snapshot)
        }
    }
}

/// Barre des quatre onglets (`TabsList` du web, l.519-524) : une ligne quand elle tient, sinon deux colonnes comme le
/// web sur mobile (`grid-cols-2`). Un onglet choisi porte le trait « sélectionné » ; le compteur d'« À venir » est
/// vocalisé comme l'`aria-label` du web (« 2 missions à venir »).
private struct OngletsPresences: View {
    let selection: PointageRules.OngletPresences?
    let nombreAVenir: Int
    let choisir: (PointageRules.OngletPresences) -> Void

    private static let ordre: [PointageRules.OngletPresences] = [.avenir, .encours, .aujourdhui, .historique]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: JoleneSpacing.xs) {
                ForEach(Self.ordre, id: \.self) { bouton($0) }
            }
            Grid(horizontalSpacing: JoleneSpacing.xs, verticalSpacing: JoleneSpacing.xs) {
                GridRow { bouton(.avenir); bouton(.encours) }
                GridRow { bouton(.aujourdhui); bouton(.historique) }
            }
        }
    }

    private func bouton(_ onglet: PointageRules.OngletPresences) -> some View {
        let choisi = onglet == selection
        let compteur = onglet == .avenir && nombreAVenir > 0 ? nombreAVenir : nil
        return Button { choisir(onglet) } label: {
            HStack(spacing: JoleneSpacing.xs) {
                Image(systemName: Self.symbole(onglet))
                    .accessibilityHidden(true)
                Text(Self.titre(onglet))
                    .lineLimit(1)
                    .fixedSize()
                if let compteur {
                    Text(String(compteur))
                        .font(JoleneFont.caption.weight(.semibold))
                        .padding(.horizontal, JoleneSpacing.xs)
                        .background(Capsule().fill(JoleneColor.mauve100))
                }
            }
            .font(JoleneFont.callout.weight(.semibold))
            .foregroundStyle(choisi ? JoleneColor.midnight : JoleneColor.bubblegum)
            .padding(.horizontal, JoleneSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: JoleneRadius.field).fill(choisi ? JoleneColor.cloud : JoleneColor.lavender))
            .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field)
                .strokeBorder(choisi ? JoleneColor.rose700 : JoleneColor.rose100, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.titre(onglet))
        .accessibilityValue(compteur.map(LibellesPresences.Liste.badgeAVenir) ?? "")
        .accessibilityAddTraits(choisi ? .isSelected : [])
        .accessibilityIdentifier("presences-tab-" + Self.suffixe(onglet))
    }

    private static func titre(_ onglet: PointageRules.OngletPresences) -> String {
        switch onglet {
        case .avenir: return LibellesWeb.ListePresences.ongletAVenir
        case .encours: return LibellesWeb.ListePresences.ongletActives
        case .aujourdhui: return LibellesWeb.ListePresences.ongletAujourdhui
        case .historique: return LibellesWeb.ListePresences.ongletHistorique
        }
    }

    /// Identifiants du blueprint (`presences-tab-avenir`, `-actives`, `-aujourdhui`, `-historique`).
    private static func suffixe(_ onglet: PointageRules.OngletPresences) -> String {
        onglet == .encours ? "actives" : onglet.rawValue
    }

    /// Icônes du web (`CalendarDays`, `Activity`, `Clock`, `History`).
    private static func symbole(_ onglet: PointageRules.OngletPresences) -> String {
        switch onglet {
        case .avenir: return "calendar"
        case .encours: return "waveform.path.ecg"
        case .aujourdhui: return "clock"
        case .historique: return "clock.arrow.circlepath"
        }
    }
}

#if DEBUG
/// Scans appliqués par le monde démo et, parmi eux, ceux qui portent une position (preuve « une seule fois » et « aucune
/// coordonnée » des XCUITest) ; nil hors démo. Aucune coordonnée n'est affichée. DEBUG seulement. `lectures` compte les
/// relectures (valeur d'accessibilité) : un XCUITest exige une lecture postérieure à son action avant d'affirmer (m3).
@MainActor
final class CompteursPointageDemo: ObservableObject {
    @Published private(set) var libelle: String?
    @Published private(set) var lectures = 0

    func relire(session: SessionStore, snapshot: SessionSnapshot) async {
        guard let gateways = await session.controller.gateways(for: snapshot.epoch),
              let demo = gateways.pointage as? DemoPointageGateway else { return }
        let scans = await demo.metadonneesRecues
        let avecPosition = scans.filter { $0.latitude != nil || $0.longitude != nil || $0.precisionGpsM != nil }.count
        libelle = "\(scans.count) scan · \(avecPosition) avec position"
        lectures += 1
    }
}
#endif
