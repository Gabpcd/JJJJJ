import Foundation
import JoleneCore
import Supabase

/// `AuditPort` comme le web (décision 5) :
/// - connexion / déconnexion : `fn_audit_connexion(p_action)` (`AuthContext.tsx` l.186-191 et
///   l.205-207 ; IP et User-Agent lus côté serveur dans `request.headers`) ;
/// - activité : `fn_maj_activite_soignant()` (`AuthContext.tsx` l.194-198) ;
/// - assignation : `fn_ecrire_audit_safe` (`DetailMissionSoignant.tsx` l.824-836) avec
///   `p_acteur_id` = utilisateur de la session (le serveur l'impose de toute façon),
///   `p_type_acteur` SOIGNANT et `p_navigateur` `jolene-ios/<version>`.
///
/// Best-effort : `{success:false}` (exception avalée par la fonction, « Non authentifié »
/// compris : `fn_ecrire_audit_safe` l.31815 puis l.31831-31833) n'est pas une erreur et rend
/// `.nonEnregistre` ; rien n'est renvoyé automatiquement, et le texte SQL d'un échec n'est
/// jamais conservé. Les erreurs encore levées (transport, contrat) sont avalées par l'appelant
/// (`AuditPort`).
/// Jamais d'uuid nul ni invalide dans `p_id_ressource` (CLAUDE.md, « binding uuid cassé ») :
/// l'audit est refusé avant tout appel réseau.
public struct SupabaseAuditGateway: AuditPort {
    public static let connexionRPC = "fn_audit_connexion"
    public static let activiteRPC = "fn_maj_activite_soignant"
    public static let ecritureRPC = "fn_ecrire_audit_safe"
    public static let typeActeur = UserRole.soignant.rawValue
    public static let navigateur = JoleneSupabase.clientInfo
    public static let fallbackMessage = "Le journal d'audit n'a pas pu être écrit."
    public static let ressourceInvalideMessage = "Audit refusé : identifiant de ressource invalide."

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func connexion() async throws -> AuditResultat {
        try await session(action: "CONNEXION")
    }

    public func deconnexion() async throws -> AuditResultat {
        try await session(action: "DECONNEXION")
    }

    public func activite() async throws -> AuditResultat {
        let reponse = try await RPCResponse.appeler(client, Self.activiteRPC, fallback: Self.fallbackMessage)
        return try Self.resultat(reponse)
    }

    public func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                       context: MissionReadContext) async throws -> AuditResultat {
        try MissionQuery.validate(context: context)
        let type = typeRessource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty, let acteur = Self.uuid(context.userId), let ressource = Self.uuid(idRessource) else {
            throw JoleneError(.contract, Self.ressourceInvalideMessage)
        }
        // `p_cle_s3` et `p_ip` sont omis : leur défaut SQL (NULL) s'applique, comme le web les envoie à null.
        var params: JSONObject = [
            "p_acteur_id": .string(acteur),
            "p_type_acteur": .string(Self.typeActeur),
            "p_action": .string(action.rawValue),
            "p_type_ressource": .string(type),
            "p_id_ressource": .string(ressource),
            "p_navigateur": .string(Self.navigateur),
        ]
        if !details.isEmpty {
            params["p_details"] = .object(details.mapValues { .string($0) })
        }
        let reponse = try await RPCResponse.appeler(client, Self.ecritureRPC, params: params, fallback: Self.fallbackMessage)
        return try Self.resultat(reponse)
    }

    // MARK: - Interne

    private func session(action: String) async throws -> AuditResultat {
        let reponse = try await RPCResponse.appeler(client, Self.connexionRPC, params: ["p_action": .string(action)],
                                                    fallback: Self.fallbackMessage)
        return try Self.resultat(reponse)
    }

    /// `{success:false}` → non enregistré, quel que soit le message joint (pas une erreur, jamais
    /// « session expirée ») ; `{success:true}` → enregistré ; `{error}` seul → erreur levée ;
    /// toute autre forme → refus de contrat (jamais un succès supposé).
    static func resultat(_ reponse: RPCResponse) throws -> AuditResultat {
        if reponse.success == false { return .nonEnregistre }
        try reponse.leverSiErreur(fallback: fallbackMessage)
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return .enregistre
    }

    /// Uuid canonique en minuscules ; nil pour une valeur vide, invalide ou l'uuid nul.
    static func uuid(_ valeur: String) -> String? {
        guard let uuid = UUID(uuidString: valeur.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let canonique = uuid.uuidString.lowercased()
        return canonique == "00000000-0000-0000-0000-000000000000" ? nil : canonique
    }
}
