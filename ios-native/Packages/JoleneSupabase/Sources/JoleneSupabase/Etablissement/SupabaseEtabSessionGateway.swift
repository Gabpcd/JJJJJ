import Foundation
import JoleneCore
import Supabase

/// `EtabSessionPort` sur Supabase (lot 5, T1 ; §2.2, D2) :
/// - `fn_mes_permissions_etab(p_etablissement_id)` : corps exact `{"p_etablissement_id":null}` pour le
///   périmètre serveur (`mon_etablissement_id()`, celui de toutes les RPC du lot), ou un uuid canonique ;
///   réponse décodée fail-closed (`PermissionsEtabResult`), sans interprétation ;
/// - `fn_mon_etablissement_complet()` : sous-ensemble `EtablissementProfil` seulement — identifiants
///   Stripe, IBAN, RIB, SIRET, commissions et notes ne sont jamais décodés (correction 4, D15).
///
/// Aucune des deux ne lève d'exception côté serveur (listes blanches vides) : un 42501 reste « session
/// expirée » (lot 0). `{error}` en HTTP 200 → message serveur verbatim (« Etablissement introuvable ») ;
/// une forme inattendue → refus de contrat, jamais un succès supposé.
public struct SupabaseEtabSessionGateway: EtabSessionPort {
    public static let permissionsRPC = "fn_mes_permissions_etab"
    public static let profilRPC = "fn_mon_etablissement_complet"
    public static let fallbackPermissions = "Impossible de vérifier les droits de votre établissement. Réessayez."
    public static let fallbackProfil = "Impossible de charger votre établissement. Réessayez."

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func permissions(etablissementId: String?) async throws -> PermissionsEtabResult {
        let parametre: AnyJSON
        if let etablissementId {
            // Un identifiant explicite doit être un uuid valide (jamais l'uuid nul) : refusé avant réseau.
            guard let uuid = SupabaseAuditGateway.uuid(etablissementId) else {
                throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
            }
            parametre = .string(uuid)
        } else {
            parametre = .null
        }
        let reponse = try await RPCResponse.appeler(
            client, Self.permissionsRPC, params: ["p_etablissement_id": parametre], fallback: Self.fallbackPermissions,
            interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.permissionsRPC))
        try reponse.leverSiErreur(fallback: Self.fallbackPermissions)
        guard reponse.raw.objectValue != nil, reponse.success != nil else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return try Self.decoder(PermissionsEtabResult.self, reponse)
    }

    public func profil() async throws -> EtablissementProfil {
        let reponse = try await RPCResponse.appeler(
            client, Self.profilRPC, fallback: Self.fallbackProfil,
            interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.profilRPC))
        try reponse.leverSiErreur(fallback: Self.fallbackProfil)
        guard reponse.raw.objectValue != nil, !reponse.estRefus else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return try Self.decoder(EtablissementProfil.self, reponse)
    }

    /// Décodage tolérant du corps par le modèle de `JoleneCore` ; échec (clé exigée absente) → contrat.
    static func decoder<T: Decodable>(_ type: T.Type, _ reponse: RPCResponse) throws -> T {
        do {
            let donnees = try JSONEncoder().encode(reponse.raw)
            return try JSONDecoder().decode(T.self, from: donnees)
        } catch {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
    }
}
