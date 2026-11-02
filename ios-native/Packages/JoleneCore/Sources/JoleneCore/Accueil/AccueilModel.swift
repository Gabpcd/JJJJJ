import Foundation
import Combine

/// Modèle de l'onglet Accueil (lot 1, T3) : tableau de bord lu par `gateways.dashboard` pour
/// l'epoch de la session, borné à `SessionController.resolutionTimeout` (décision 14). Mêmes
/// règles d'état que `MissionsListModel` :
/// - une annulation de tâche SwiftUI n'est jamais une erreur (l'état reste `.loading`) ;
/// - un rafraîchissement conserve le tableau affiché et n'expose qu'un `refreshError` ;
/// - `.unauthorized` lève `sessionExpired` (revalidation de session plutôt que « Réessayer ») ;
/// - une réponse reçue pour un epoch périmé est abandonnée.
/// Relecture à l'apparition au-delà de `delaiRelecture` (web : `staleTime: 60_000`) et par
/// pull-to-refresh. Lecture seule : aucune mutation n'est faite depuis l'Accueil au lot 1 T3.
@MainActor
public final class AccueilModel: ObservableObject {
    public enum State: Equatable, Sendable {
        case loading
        case loaded(DashboardSnapshot)
        case failed(String)
    }

    public static let genericFailureMessage = "Votre tableau de bord n'a pas pu être chargé. Vérifiez votre connexion puis réessayez."
    /// Au-delà, une nouvelle apparition de l'onglet relit le tableau de bord.
    public static let delaiRelecture: TimeInterval = 60

    @Published public private(set) var state: State = .loading
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var refreshError: String?
    @Published public private(set) var sessionExpired = false
    /// Instant (horloge des gateways) du dernier chargement réussi.
    public private(set) var chargeLe: Date?
    /// Horloge des gateways de la session (démo : horloge fixée) : décompte des propositions.
    public private(set) var horloge: any ClockPort = SystemClock()

    private let controller: SessionController
    private let snapshot: SessionSnapshot

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public var tableau: DashboardSnapshot? {
        if case let .loaded(tableau) = state { return tableau }
        return nil
    }

    /// Mission relue par le tableau de bord (valeur initiale du détail), si elle l'a été.
    public func mission(id: String) -> Mission? { tableau?.mission(id: id) }

    public func load() async {
        let refreshing: Bool
        if case .loaded = state { refreshing = true } else { refreshing = false }
        if refreshing { isRefreshing = true } else { state = .loading }
        refreshError = nil
        defer { isRefreshing = false }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        horloge = gateways.clock
        let port = gateways.dashboard
        let context = snapshot.context
        do {
            let tableau = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.dashboard(context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            sessionExpired = false
            chargeLe = gateways.clock.now()
            state = .loaded(tableau)
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

    /// Apparition de l'onglet : premier chargement (ou relance après une tâche annulée), ou
    /// relecture si le dernier chargement date de plus de `delaiRelecture`. Après un échec, seule
    /// l'action « Réessayer » relance (jamais de boucle à l'apparition).
    public func loadIfStale() async {
        switch state {
        case .loading:
            await load()
        case .failed:
            return
        case .loaded:
            guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
            guard let chargeLe, gateways.clock.now().timeIntervalSince(chargeLe) <= Self.delaiRelecture else {
                await load()
                return
            }
        }
    }
}
