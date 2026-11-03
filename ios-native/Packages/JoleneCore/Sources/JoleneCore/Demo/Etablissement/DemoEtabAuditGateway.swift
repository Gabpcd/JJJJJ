import Foundation

/// Audit de consultation démo (D19) : chaque écriture est consignée dans le journal en mémoire du jeu
/// de ports (aucun succès fabriqué, aucun réseau), perdu au relancement. Refuse un contexte
/// incohérent, puis tout autre utilisateur que le compte fictif.
public struct DemoEtabAuditGateway: EtabAuditPort {
    /// Action écrite par le web (`DashboardEtablissement.tsx` l.422), présente dans
    /// `journaux_audit_action_check`.
    public static let action = "DONNEES_PERSO_CONSULTATION"

    private let store = DemoAuditJournal()

    public init() {}

    public func consultation(page: PageAuditEtab, context: EtablissementReadContext) async throws -> AuditResultat {
        try DemoEtablissementWorld.verifier(context)
        await store.record("\(Self.action) etablissement \(context.userId) \(page.rawValue)")
        return .enregistre
    }

    /// Entrées consignées, dans l'ordre (preuves des tests démo).
    public func journal() async -> [String] { await store.all() }
}
