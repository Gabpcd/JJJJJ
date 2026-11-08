import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet Explorer : vue de `MissionsListModel` (JoleneCore). Les règles d'état (annulation
/// de tâche ignorée, rafraîchissement sans démontage de la liste, session expirée, filtres,
/// chips, dernière demande gagnante, délai) sont testées dans `MissionsModelsTests` et
/// `ExplorerModelsTests` ; la vue n'ajoute aucune logique.
///
/// Lot 1 (T4a) : chips rapides au-dessus de la liste (`explorer-chips`, `chip-*`), bouton
/// « Filtres » avec le nombre de critères actifs (`explorer-filtres-ouvrir`) ouvrant
/// `FiltresSheet`, état vide avec l'action secondaire du web (`missions-empty-action`) ET
/// « Actualiser » (`missions-refresh`, toujours présent), tirer pour actualiser sur l'état vide
/// comme sur la liste (`usePullToRefresh(recharger)` couvre toute la page web).
///
/// Feuille de filtres : présentée par `.sheet(item:)` depuis `ExplorerFeuilleFiltres` (JoleneCore),
/// une présentation neuve à chaque appui sur « Filtres ». « Afficher les missions » ne fait
/// qu'enregistrer les critères ; ils sont appliqués dans `onDismiss`, une fois la feuille fermée,
/// pour que la liste et le badge ne soient pas reconstruits pendant la transition de fermeture
/// (feuille qui ne se rouvrait plus, run CI 42526135547). « Fermer » n'applique rien.
struct MissionRoute: Hashable {
    let id: String
}

struct MissionsListScreen: View {
    @StateObject private var model: MissionsListModel
    @ObservedObject private var session: SessionStore
    @State private var feuilleFiltres = ExplorerFeuilleFiltres()
    private let controller: SessionController
    private let snapshot: SessionSnapshot

    init(session: SessionStore, snapshot: SessionSnapshot) {
        self.session = session
        self.controller = session.controller
        self.snapshot = snapshot
        _model = StateObject(wrappedValue: MissionsListModel(controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        VStack(spacing: 0) {
            chipsRapides
            contenu
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle("Explorer")
        // Titre en ligne : la rangée de chips (défilement horizontal) précède la liste, un grand
        // titre ne se replierait pas au défilement de la liste.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { boutonFiltres }
        }
        .sheet(item: $feuilleFiltres.ouverture, onDismiss: {
            // Après la transition de fermeture : rien n'est relu tant que la feuille se ferme.
            guard let nouveaux = feuilleFiltres.cloturer() else { return }
            Task { await model.appliquer(nouveaux) }
        }) { ouverture in
            FiltresSheet(filtres: ouverture.filtres, profile: model.profile) { feuilleFiltres.enregistrer($0) }
        }
        .navigationDestination(for: MissionRoute.self) { route in
            MissionDetailScreen(route: route, initial: model.mission(id: route.id), session: session, snapshot: snapshot)
        }
        // Une tâche annulée (changement d'onglet, retour) laisse l'état à .loading : relance ici.
        .task { if case .loading = model.state { await model.load() } }
    }

    // MARK: Filtres

    private var chipsRapides: some View {
        FilterChipRow(identifier: "explorer-chips") {
            ForEach(ExplorerFiltres.chipsRapides) { chip in
                FilterChip(chip.titre, isSelected: model.filtres.estActif(chip), identifier: chip.identifiant) {
                    Task { await model.basculer(chip) }
                }
            }
        }
        .padding(.vertical, JoleneSpacing.xs)
    }

    private var boutonFiltres: some View {
        let actifs = model.filtres.nombreFiltresActifs
        return Button {
            feuilleFiltres.ouvrir(avec: model.filtres)
        } label: {
            HStack(spacing: JoleneSpacing.xs) {
                Image(systemName: "slider.horizontal.3")
                if actifs > 0 {
                    Text("\(actifs)")
                        .font(JoleneFont.caption.weight(.bold))
                        .foregroundStyle(JoleneColor.rose800)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(JoleneColor.rose100))
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .tint(JoleneColor.rose700)
        .accessibilityLabel("Filtres")
        .accessibilityValue(ExplorerFiltres.libelleFiltresActifs(actifs))
        .accessibilityIdentifier("explorer-filtres-ouvrir")
    }

    // MARK: États

    @ViewBuilder private var contenu: some View {
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
            etatVide
        case let .loaded(missions):
            missionList(missions)
        }
    }

    /// État vide : action secondaire du web (effacer d'abord les chips, sinon élargir le rayon)
    /// puis « Actualiser », toujours présent — le message promet l'apparition des nouvelles
    /// missions, il faut donc pouvoir relire avec les mêmes critères (revue T4a). Défilable pour
    /// « tirer pour actualiser », comme la liste ; boutons désactivés pendant la relecture.
    private var etatVide: some View {
        GeometryReader { geometrie in
            ScrollView {
                VStack(spacing: JoleneSpacing.md) {
                    if let refreshError = model.refreshError {
                        Text(refreshError)
                            .font(JoleneFont.callout)
                            .foregroundStyle(JoleneColor.rose700)
                            .multilineTextAlignment(.center)
                            .padding(JoleneSpacing.md)
                            .frame(maxWidth: .infinity)
                            .background(JoleneColor.rose100)
                            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                            .padding(.horizontal, JoleneSpacing.lg)
                            .accessibilityIdentifier("missions-refresh-error")
                    }
                    etatVideContenu
                        .disabled(model.isRefreshing)
                }
                .frame(maxWidth: .infinity, minHeight: geometrie.size.height)
            }
            .refreshable { await model.load() }
            .accessibilityIdentifier("missions-empty-scroll")
        }
    }

    @ViewBuilder private var etatVideContenu: some View {
        let message = "Aucune mission ne correspond à vos critères pour le moment. Les nouvelles missions apparaîtront ici dès leur publication."
        if let action = model.filtres.actionEtatVide {
            EmptyState(systemImage: "magnifyingglass", title: "Aucune mission trouvée", message: message,
                       identifier: "missions-empty",
                       actionTitle: action.titre, actionIdentifier: "missions-empty-action",
                       action: { Task { await model.appliquer(model.filtres.appliquant(action)) } },
                       secondaryActionTitle: "Actualiser", secondaryActionIdentifier: "missions-refresh",
                       secondaryAction: { Task { await model.load() } })
        } else {
            EmptyState(systemImage: "magnifyingglass", title: "Aucune mission trouvée", message: message,
                       identifier: "missions-empty", actionTitle: "Actualiser", actionIdentifier: "missions-refresh") {
                Task { await model.load() }
            }
        }
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
                HStack(spacing: JoleneSpacing.sm) {
                    Text(ExplorerFiltres.libelleCompteur(missions.count))
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityIdentifier("missions-count")
                    // Le rayon n'est annoncé que s'il s'applique (position du soignant connue).
                    if ExplorerFiltres.rayonApplicable(profile: model.profile) {
                        Text("dans un rayon de \(MissionPresentation.nombreJavaScript(model.filtres.rayonKm)) km")
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .accessibilityIdentifier("missions-rayon")
                    }
                }
                .textCase(nil)
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
