import Foundation

/// État du compte démo : en mémoire, perdu au relancement, jamais envoyé.
actor DemoCompteStore {
    private var supprime = false

    func supprimer() { supprime = true }
    func estSupprime() -> Bool { supprime }
}

/// Suppression de compte du monde démo (blueprint lot 1 §2.7) : aucun réseau. La suppression est
/// réellement consignée dans l'acteur puis relue (aucun succès fabriqué) ; un second appel est refusé
/// comme l'edge après une suppression (`403 Compte desactive`). Comme les autres gateways démo, refuse
/// tout contexte qui n'est pas celui du profil fictif.
public struct DemoAccountGateway: AccountPort {
    /// Réponse de l'edge `delete-account` à un compte déjà supprimé (`admin-auth.ts` l.150), verbatim.
    static let compteDesactiveMessage = "Compte desactive"

    private let store = DemoCompteStore()

    public init() {}

    public func deleteAccount(context: MissionReadContext) async throws -> DeleteAccountOutcome {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        guard await !store.estSupprime() else {
            return .refused(code: nil, message: Self.compteDesactiveMessage)
        }
        await store.supprimer()
        // Relecture après mutation : aucun succès fabriqué.
        guard await store.estSupprime() else {
            throw JoleneError(.unknown, CompteSuppression.refusParDefautMessage)
        }
        return .deleted
    }

    /// État relu (preuves des tests démo).
    public func estSupprime() async -> Bool { await store.estSupprime() }
}
