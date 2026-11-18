import Foundation

/// Confirmation de présence depuis le détail de mission (lot 1, T6c) : un seul appel `PresencePort.confirmerPresence`
/// à la fois, aucun renvoi automatique, succès annoncé seulement quand la gateway a relu `presence_confirmee_le`.
///
/// La RPC n'est pas idempotente (chaque appel réécrit l'instant et notifie l'établissement). Revue B8 (M1) :
/// - `enCours` est posé avant le premier `await` : un double toucher n'envoie qu'un appel ;
/// - la date relue par la gateway (relecture serveur de `missions.presence_confirmee_le`) est gardée : le bloc passe à
///   « confirmée » sans attendre la relecture de la mission par l'écran, même si celle-ci échoue, et le bouton ne
///   redevient jamais actif après un succès.
/// Mêmes gardes d'epoch que `MissionDetailModel`.
@MainActor
public final class ConfirmationPresenceModel: ObservableObject {
    public enum Issue: Equatable, Sendable {
        /// Relue confirmée : notice `TextesWeb.ConfirmationPresence.confirmation`.
        case confirmee
        /// Refus serveur verbatim, sinon le repli web « Confirmation impossible. » (toute autre erreur, comme le web).
        case refus(String)
    }

    @Published public private(set) var enCours = false
    @Published public private(set) var issue: Issue?
    @Published public private(set) var maintenant: Date?
    /// `presence_confirmee_le` relu par la gateway après un succès (jamais posé localement).
    @Published public private(set) var presenceRelue: String?

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

    /// Bloc de la mission relue par l'écran, complétée par la date relue par la gateway quand la mission ne la porte pas
    /// encore (relecture de la mission en retard ou en échec).
    public func bloc(_ mission: MissionRecord) -> PresenceRules.Bloc {
        guard let maintenant else { return .masque }
        var relue = mission
        if (relue.presenceConfirmeeLe ?? "").isEmpty, let presenceRelue { relue.presenceConfirmeeLe = presenceRelue }
        return PresenceRules.bloc(relue, userId: snapshot.context.userId, maintenant: maintenant)
    }

    /// Rend `true` quand l'écran doit relire la mission (confirmation relue, ou refus : l'état a pu changer).
    public func confirmer() async -> Bool {
        guard !enCours, presenceRelue == nil else { return false }
        enCours = true
        defer { enCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.presence
        let id = missionId
        let context = snapshot.context
        issue = nil
        do {
            let outcome = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.confirmerPresence(missionId: id, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            switch outcome {
            case let .confirmee(presenceConfirmeeLe):
                presenceRelue = presenceConfirmeeLe
                issue = .confirmee
            case let .refusee(message):
                issue = .refus(PresenceRules.messageRefus(message))
            }
            return true
        } catch {
            guard await controller.epoch == snapshot.epoch else { return false }
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled { return false }
            // Revue B8 (m3) : `error || data?.error` du web → repli pour toute erreur sans message serveur.
            issue = .refus(TextesWeb.ConfirmationPresence.repliRefus)
            return true
        }
    }
}
