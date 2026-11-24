import Foundation
import Combine

/// « Contacter le soignant » depuis le détail d'une mission de l'établissement (lot 5, T11), port du bouton de
/// `src/pages/DetailMission.tsx` (l.1081-1089) et de `useOuvrirConversation` (`src/hooks/useOuvrirConversation.ts`
/// l.25-53, sans résolution d'établissement) : `fn_obtenir_conversation(p_autre_id := soignant assigné,
/// p_mission_id)` par `MessageriePort.conversationPourSoignant`, puis ouverture du fil
/// (`/etablissement/messagerie?conv=<id>`, destination `EtabDestination.conversation`).
///
/// Règles : un appel à la fois ; borné à `SessionController.resolutionTimeout` ; tout refus (relation refusée,
/// interlocuteur invalide, réponse vide) → « Impossible d'ouvrir la conversation. », comme le web (`DECISIONS_LOT4.md`
/// précision 14 e) ; session expirée → message de session, jamais pour un refus de relation ; annulation sans message ;
/// réponse d'un epoch périmé ignorée. Le serveur reste juge de la relation (aucune règle d'accès ici).
@MainActor
public final class ContactSoignantModel: ObservableObject {
    @Published public private(set) var enCours = false
    @Published public private(set) var erreur: String?

    private let controller: SessionController
    private let snapshot: EtablissementSessionSnapshot

    public init(controller: SessionController, snapshot: EtablissementSessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    /// Identifiant de la conversation de la mission, `nil` en cas d'échec (message affiché).
    public func ouvrir(missionId: String, soignantId: String) async -> String? {
        guard !enCours, let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        enCours = true
        defer { enCours = false }
        erreur = nil
        let port = gateways.messagerie
        let etab = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.conversationPourSoignant(missionId: missionId, soignantId: soignantId, etab: etab)
            }
            guard await courant() else { return nil }
            switch issue {
            case let .conversation(id): return id
            case .indisponible: erreur = MessagerieTextes.ouvertureImpossible
            }
        } catch {
            guard await courant(), !(error is CancellationError) else { return nil }
            if let jolene = error as? JoleneError, jolene.kind == .cancelled { return nil }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized {
                erreur = jolene.message
            } else {
                erreur = MessagerieTextes.ouvertureImpossible
            }
        }
        return nil
    }

    private func courant() async -> Bool { await controller.epoch == snapshot.epoch }
}
