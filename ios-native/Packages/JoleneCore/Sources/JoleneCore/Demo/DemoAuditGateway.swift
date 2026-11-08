import Foundation

/// Journal d'audit du monde démo : en mémoire, perdu au relancement, jamais envoyé.
actor DemoAuditJournal {
    private var entries: [String] = []

    func record(_ entry: String) { entries.append(entry) }
    func all() -> [String] { entries }
}

/// Audit démo : chaque écriture est réellement consignée dans le journal en mémoire du jeu de
/// ports (aucun succès fabriqué, aucun réseau). Comme les autres gateways démo, refuse tout
/// contexte qui n'est pas celui du profil fictif.
public struct DemoAuditGateway: AuditPort {
    private let store = DemoAuditJournal()

    public init() {}

    public func connexion() async throws -> AuditResultat { await consigner("CONNEXION") }
    public func deconnexion() async throws -> AuditResultat { await consigner("DECONNEXION") }
    public func activite() async throws -> AuditResultat { await consigner("ACTIVITE") }

    public func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                       context: MissionReadContext) async throws -> AuditResultat {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
        let type = typeRessource.trimmingCharacters(in: .whitespacesAndNewlines)
        let ressource = idRessource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty, !ressource.isEmpty else {
            throw JoleneError(.contract, "Audit refusé : identifiant de ressource invalide.")
        }
        return await consigner("\(action.rawValue) \(type) \(ressource)")
    }

    /// Entrées consignées, dans l'ordre (preuves des tests démo).
    public func journal() async -> [String] { await store.all() }

    private func consigner(_ entry: String) async -> AuditResultat {
        await store.record(entry)
        return .enregistre
    }
}
