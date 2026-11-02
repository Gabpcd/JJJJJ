import Foundation
import Combine

/// Modèle de l'onglet Explorer : liste des missions lue via `gateways.missions.listMissions`
/// avec les critères de `filtres` (lot 1, T4a ; état initial = filtres par défaut du profil du
/// lot 0). Les gateways sont obtenues pour l'epoch de la session : si l'identité change pendant
/// la lecture, le résultat est abandonné (plan §4.3).
///
/// Chaque lecture est bornée à `SessionController.resolutionTimeout` (décision 14 du lot 1) : un
/// port muet rend l'erreur réseau générique `SessionController.timeoutMessage`, jamais un
/// chargement sans issue.
///
/// Règles d'état (relecture lot 0) :
/// - une annulation de tâche SwiftUI (`.task` interrompu par un changement d'onglet, retour
///   arrière, pull-to-refresh interrompu) n'est jamais une erreur : l'état reste `.loading`
///   et `.task` relance au prochain affichage ;
/// - un rafraîchissement d'une liste déjà chargée conserve `.loaded` (la liste reste à
///   l'écran) et n'écrase l'état qu'au succès ; un échec est exposé par `refreshError` ;
/// - une erreur `.unauthorized` (session expirée côté serveur) lève `sessionExpired` :
///   l'écran propose une revalidation de session plutôt qu'un simple « Réessayer ».
///
/// Règles des filtres (lot 1) :
/// - changer de critères (`appliquer`, chips, `reinitialiser`) repasse par `.loading` : une liste
///   lue avec d'autres critères n'est jamais présentée sous les nouveaux ; un échec donne `.failed`
///   et « Réessayer » (`load`) relit avec les critères affichés ;
/// - deux lectures qui se chevauchent (chips touchées en rafale) : seule la dernière demandée
///   publie son résultat, une réponse tardive d'anciens critères est ignorée.
@MainActor
public final class MissionsListModel: ObservableObject {
    public enum State: Equatable, Sendable {
        case loading
        case loaded([Mission])
        case failed(String)
    }

    public static let genericFailureMessage = "Les missions n'ont pas pu être chargées. Vérifiez votre connexion puis réessayez."

    @Published public private(set) var state: State = .loading
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var refreshError: String?
    @Published public private(set) var sessionExpired = false
    /// Critères affichés et appliqués à chaque lecture (source unique, `ExplorerFiltres`).
    @Published public private(set) var filtres: ExplorerFiltres

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Numéro de la dernière lecture demandée : seule celle-ci publie son résultat.
    private var derniereDemande = 0

    /// - Parameter filtresInitiaux: critères de la première lecture ; par défaut
    ///   `ExplorerFiltres.initiaux(profile:)`, identiques aux filtres par défaut du lot 0.
    public init(controller: SessionController, snapshot: SessionSnapshot, filtresInitiaux: ExplorerFiltres? = nil) {
        self.controller = controller
        self.snapshot = snapshot
        self.filtres = filtresInitiaux ?? ExplorerFiltres.initiaux(profile: snapshot.profile)
    }

    /// Profil de la session, pour les options et libellés de la feuille de filtres.
    public var profile: SoignantProfile { snapshot.profile }

    public var missions: [Mission] {
        if case let .loaded(missions) = state { return missions }
        return []
    }

    public func mission(id: String) -> Mission? { missions.first { $0.id == id } }

    /// Relit la liste avec les critères courants. Une liste déjà chargée reste affichée pendant
    /// la relecture (pull-to-refresh) ; sinon l'état passe par `.loading`.
    public func load() async {
        let chargee: Bool
        if case .loaded = state { chargee = true } else { chargee = false }
        await lire(conserverListe: chargee)
    }

    /// Applique de nouveaux critères puis relit (`.loading`). Sans effet si les critères sont
    /// ceux d'une liste déjà chargée.
    public func appliquer(_ nouveaux: ExplorerFiltres) async {
        if nouveaux == filtres, case .loaded = state { return }
        filtres = nouveaux
        await lire(conserverListe: false)
    }

    /// Chip rapide (`ExplorerFiltres.chipsRapides`) : bascule le critère puis relit.
    public func basculer(_ chip: ExplorerFiltres.ChipRapide) async {
        await appliquer(filtres.basculer(chip))
    }

    /// « Réinitialiser » du web (`ExplorerFiltres.reinitialises(profile:)`) puis relecture.
    public func reinitialiser() async {
        await appliquer(filtres.reinitialises(profile: snapshot.profile))
    }

    private func lire(conserverListe: Bool) async {
        derniereDemande += 1
        let demande = derniereDemande
        if conserverListe { isRefreshing = true } else { state = .loading; isRefreshing = false }
        refreshError = nil
        defer { if demande == derniereDemande { isRefreshing = false } }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.missions
        let context = snapshot.context
        let criteres = filtres.missionFilters
        do {
            let missions = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.listMissions(context: context, filters: criteres)
            }
            guard await controller.epoch == snapshot.epoch, demande == derniereDemande else { return }
            sessionExpired = false
            state = .loaded(missions)
        } catch {
            guard await controller.epoch == snapshot.epoch, demande == derniereDemande, !Task.isCancelled else { return }
            let message: String
            if let jolene = error as? JoleneError {
                if jolene.kind == .cancelled { return }
                sessionExpired = jolene.kind == .unauthorized
                message = jolene.message
            } else if error is CancellationError {
                return
            } else {
                message = Self.genericFailureMessage
            }
            if conserverListe { refreshError = message } else { state = .failed(message) }
        }
    }
}

/// Détail d'une mission : relu via `gateways.missions.mission(id:context:)` (la valeur de la
/// liste sert d'affichage initial). Mêmes règles d'annulation, d'epoch, de session expirée et
/// de délai (`resolutionTimeout`, lot 1) que `MissionsListModel`.
@MainActor
public final class MissionDetailModel: ObservableObject {
    public static let unavailableMessage = "Cette mission n'est plus disponible."
    public static let genericFailureMessage = "La mission n'a pas pu être chargée. Vérifiez votre connexion puis réessayez."

    @Published public private(set) var mission: Mission?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var sessionExpired = false

    public let missionId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot

    public init(missionId: String, initial: Mission?, controller: SessionController, snapshot: SessionSnapshot) {
        self.missionId = missionId
        self.mission = initial
        self.controller = controller
        self.snapshot = snapshot
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.missions
        let id = missionId
        let context = snapshot.context
        do {
            let fresh = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.mission(id: id, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            sessionExpired = false
            mission = fresh
            errorMessage = fresh == nil ? Self.unavailableMessage : nil
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled else { return }
            if let jolene = error as? JoleneError {
                if jolene.kind == .cancelled { return }
                sessionExpired = jolene.kind == .unauthorized
                if mission == nil { errorMessage = jolene.message }
            } else if error is CancellationError {
                return
            } else if mission == nil {
                errorMessage = Self.genericFailureMessage
            }
        }
    }
}
