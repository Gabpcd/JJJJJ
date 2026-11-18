import Foundation

/// Dépôt des justificatifs d'annulation du monde démo (lot 1, T7, `LOT1_PLAN.md` §2.7 : « justificatif : reçu Keychain
/// écrit, envoi en mémoire »). Aucun réseau : l'objet est gardé en mémoire pour la session, sous le chemin du reçu, avec
/// les contrôles du bucket `justificatifs` (premier segment = utilisateur, `upsert: false` : un chemin déjà déposé est un
/// 409, rendu incertain comme sur Supabase, puis relu présent). Refuse tout contexte qui n'est pas celui du profil fictif.
public actor DemoJustificatifStorage: JustificatifStoragePort {
    private var objets: [String: Int] = [:]

    public init() {}

    public func deposer(chemin: String, octets: Data, mime: MimeDocument, context: MissionReadContext) async throws -> IssueDepotJustificatif {
        try Self.verifier(context)
        guard chemin.hasPrefix(context.userId + "/"), !chemin.contains(".."),
              (1...RecuJustificatif.tailleMaxOctets).contains(octets.count) else { return .refuse(statut: 403) }
        guard objets[chemin] == nil else { return .incertain }
        objets[chemin] = octets.count
        return .depose
    }

    public func existe(chemin: String, context: MissionReadContext) async throws -> Bool {
        try Self.verifier(context)
        return objets[chemin] != nil
    }

    /// Chemins déposés pendant la session (relecture des tests).
    public func chemins() -> [String] { objets.keys.sorted() }

    private static func verifier(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}
