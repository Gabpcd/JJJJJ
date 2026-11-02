import Foundation
import Combine

/// Modèle de l'onglet Explorer : liste des missions lue via `gateways.missions.listMissions`
/// avec les filtres par défaut du profil. Les gateways sont obtenues pour l'epoch de la
/// session : si l'identité change pendant la lecture, le résultat est abandonné (plan §4.3).
///
/// Règles d'état (relecture lot 0) :
/// - une annulation de tâche SwiftUI (`.task` interrompu par un changement d'onglet, retour
///   arrière, pull-to-refresh interrompu) n'est jamais une erreur : l'état reste `.loading`
///   et `.task` relance au prochain affichage ;
/// - un rafraîchissement d'une liste déjà chargée conserve `.loaded` (la liste reste à
///   l'écran) et n'écrase l'état qu'au succès ; un échec est exposé par `refreshError` ;
/// - une erreur `.unauthorized` (session expirée côté serveur) lève `sessionExpired` :
///   l'écran propose une revalidation de session plutôt qu'un simple « Réessayer ».
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

    private let controller: SessionController
    private let snapshot: SessionSnapshot

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public var missions: [Mission] {
        if case let .loaded(missions) = state { return missions }
        return []
    }

    public func mission(id: String) -> Mission? { missions.first { $0.id == id } }

    public func load() async {
        let refreshing: Bool
        if case .loaded = state { refreshing = true } else { refreshing = false }
        if refreshing { isRefreshing = true } else { state = .loading }
        refreshError = nil
        defer { isRefreshing = false }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        do {
            let missions = try await gateways.missions.listMissions(
                context: snapshot.context, filters: MissionBusiness.defaultFilters(profile: snapshot.profile)
            )
            guard await controller.epoch == snapshot.epoch else { return }
            sessionExpired = false
            state = .loaded(missions)
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled else { return }
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
            if refreshing { refreshError = message } else { state = .failed(message) }
        }
    }
}

/// Détail d'une mission : relu via `gateways.missions.mission(id:context:)` (la valeur de la
/// liste sert d'affichage initial). Mêmes règles d'annulation, d'epoch et de session expirée
/// que `MissionsListModel`.
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
        do {
            let fresh = try await gateways.missions.mission(id: missionId, context: snapshot.context)
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
