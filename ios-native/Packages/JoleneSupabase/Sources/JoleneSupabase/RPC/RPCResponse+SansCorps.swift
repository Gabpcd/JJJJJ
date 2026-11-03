import Foundation
import JoleneCore
import Supabase

/// Issue d'un appel à une RPC `RETURNS void` (`appelerSansCorps`).
public enum IssueAppelSansCorps: Equatable, Sendable {
    /// HTTP 2xx : la RPC a abouti (corps vide, 204, ou `null`).
    case succes
    /// Exception métier déclarée, restituée en refus structuré (`RPCResponse.sqlstate`).
    case refus(RPCResponse)
}

/// RPC sans corps de réponse (blueprint `docs/mobile-swift/LOT3_PLAN.md` correction 16, tranche T1).
/// `fn_upsert_token_push` renvoie `void` : PostgREST répond sans corps JSON (204, ou 200 à corps
/// vide) et `appeler`, qui décode toujours `AnyJSON`, lèverait une erreur de décodage sur ce succès
/// (supabase-swift 2.55.5, `PostgrestBuilder.execute<T: Decodable>`). Cette variante appelle
/// `execute()` → `Void` et garde la même chaîne de traitement des erreurs : `[CODE DU TRAVAIL]` →
/// exceptions métier déclarées → `SupabaseErrorMapping`. Une seule requête, aucun renvoi.
extension RPCResponse {
    static func appelerSansCorps(_ client: SupabaseClient, _ fonction: String, params: JSONObject, fallback: String,
                                 exceptionsMetier: Set<String> = []) async throws -> IssueAppelSansCorps {
        let reponse = try await executer(fallback: fallback, exceptionsMetier: exceptionsMetier) {
            let _: PostgrestResponse<Void> = try await client.rpc(fonction, params: params).execute()
            return AnyJSON.null
        }
        return reponse.estRefus ? .refus(reponse) : .succes
    }
}
