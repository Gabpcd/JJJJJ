import Foundation
import JoleneCore
import Supabase

/// `EtabAuditPort` sur Supabase (lot 5, T1 ; D19) : `fn_ecrire_audit_safe` comme
/// `DashboardEtablissement.tsx` l.421-425 — `p_acteur_id` et `p_id_ressource` = utilisateur de la
/// session, `p_type_acteur 'ADMIN_ETABLISSEMENT'`, `p_action 'DONNEES_PERSO_CONSULTATION'` (présente
/// dans `journaux_audit_action_check`, l.70243), `p_type_ressource 'etablissement'`, `p_details {page}`,
/// `p_navigateur jolene-ios/<version>` ; `p_cle_s3` et `p_ip` omis (défaut SQL NULL, envoyés à null par
/// le web).
///
/// Best-effort, contrat du lot 1 (`SupabaseAuditGateway.resultat`) : `{success:false}` → `.nonEnregistre`,
/// jamais une erreur utilisateur. Un contexte incohérent, un uuid invalide ou l'uuid nul sont refusés
/// avant tout appel réseau (CLAUDE.md, « binding uuid cassé »). Aucun doublon des audits déjà écrits par
/// le serveur (validation, contestation, lot).
public struct SupabaseEtabAuditGateway: EtabAuditPort {
    public static let rpc = SupabaseAuditGateway.ecritureRPC
    public static let typeActeur = UserRole.adminEtablissement.rawValue
    public static let action = "DONNEES_PERSO_CONSULTATION"
    public static let typeRessource = "etablissement"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func consultation(page: PageAuditEtab, context: EtablissementReadContext) async throws -> AuditResultat {
        try context.verifier()
        guard let acteur = SupabaseAuditGateway.uuid(context.userId) else {
            throw JoleneError(.contract, SupabaseAuditGateway.ressourceInvalideMessage)
        }
        let params: JSONObject = [
            "p_acteur_id": .string(acteur),
            "p_type_acteur": .string(Self.typeActeur),
            "p_action": .string(Self.action),
            "p_type_ressource": .string(Self.typeRessource),
            "p_id_ressource": .string(acteur),
            "p_details": .object(["page": .string(page.rawValue)]),
            "p_navigateur": .string(SupabaseAuditGateway.navigateur),
        ]
        let reponse = try await RPCResponse.appeler(client, Self.rpc, params: params, fallback: SupabaseAuditGateway.fallbackMessage)
        return try SupabaseAuditGateway.resultat(reponse)
    }
}
