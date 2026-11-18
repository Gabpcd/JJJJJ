import Foundation

/// Confirmation de présence depuis le détail de mission (lot 1, T6c) : un seul appel `PresencePort.confirmerPresence`
/// à la fois (bouton désactivé pendant l'appel : la RPC n'est pas idempotente), aucun renvoi automatique, succès
/// annoncé seulement quand la gateway a relu `presence_confirmee_le` ; l'écran relit ensuite la mission, dont l'état
/// masque le bouton. Mêmes gardes d'epoch que `MissionDetailModel`.
@MainActor
public final class ConfirmationPresenceModel: ObservableObject {
    public enum Issue: Equatable, Sendable {
        /// Relue confirmée : notice `TextesWeb.ConfirmationPresence.confirmation`.
        case confirmee
        /// Refus serveur verbatim (ou repli web), ou message `JoleneError`.
        case refus(String)
    }

    @Published public private(set) var enCours = false
    @Published public private(set) var issue: Issue?
    @Published public private(set) var maintenant: Date?

    public let missionId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot

    public init(missionId: String, controller: SessionController, snapshot: SessionSnapshot) {
        self.missionId = missionId
        self.controller = controller
        self.snapshot = snapshot
    }

    /// Horloge des gateways de la session (démo : horloge fixée).
    public func charger() async {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        maintenant = gateways.clock.now()
    }

    public func bloc(_ mission: MissionRecord) -> PresenceRules.Bloc {
        guard let maintenant else { return .masque }
        return PresenceRules.bloc(mission, userId: snapshot.context.userId, maintenant: maintenant)
    }

    /// Rend `true` quand l'écran doit relire la mission (confirmation relue, ou refus : l'état a pu changer).
    public func confirmer() async -> Bool {
        guard !enCours, let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.presence
        let id = missionId
        let context = snapshot.context
        enCours = true
        issue = nil
        defer { enCours = false }
        do {
            let outcome = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.confirmerPresence(missionId: id, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            switch outcome {
            case .confirmee: issue = .confirmee
            case let .refusee(message): issue = .refus(PresenceRules.messageRefus(message))
            }
            return true
        } catch {
            guard await controller.epoch == snapshot.epoch else { return false }
            if let jolene = error as? JoleneError {
                guard jolene.kind != .cancelled else { return false }
                issue = .refus(jolene.message)
            } else if error is CancellationError {
                return false
            } else {
                issue = .refus(TextesWeb.ConfirmationPresence.repliRefus)
            }
            return true
        }
    }
}
