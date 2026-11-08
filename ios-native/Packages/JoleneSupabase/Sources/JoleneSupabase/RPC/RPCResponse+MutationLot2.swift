import Foundation
import JoleneCore
import Supabase

/// Issue d'une mutation non idempotente du lot 2 (blueprint `docs/mobile-swift/LOT2_PLAN.md` correction 10 et
/// §2.4 ; revue fraîche de T1). `RPCResponse.appeler(…, exceptionsMetier:)` (extension partagée avec le lot 3,
/// inchangée) traduit par `SupabaseErrorMapping` une exception non déclarée ET une réponse de passerelle en un
/// même `JoleneError(.unknown, fallback)` ; or la première prouve un rollback et la seconde non. Ce classement,
/// local au lot 2, relit l'erreur brute du SDK avant traduction.
enum IssueMutation: Equatable, Sendable {
    /// Réponse HTTP 200 (succès ou refus jsonb), exception déclarée restituée en refus (`exceptionsMetier`) ou
    /// `[CODE DU TRAVAIL]` : l'appelant lit `estRefus`, `sqlstate`, `erreur`.
    case reponse(RPCResponse)
    /// PostgREST a répondu avec un `code` (SQLSTATE ou `PGRST…`) : transaction annulée ou jamais ouverte, rien n'est
    /// écrit. Refus définitif (message de `SupabaseErrorMapping`), jamais un incertain ; aucun renvoi.
    case refusDefinitif(code: String, erreur: JoleneError)
    /// Aucune preuve : réseau, annulation, passerelle (corps HTML → `HTTPError` ; corps `{"message"}` sans `code`
    /// → `PostgrestError(code: nil)` dans supabase-swift 2.55.5). La requête a pu être appliquée : réconciliation par
    /// relecture, jamais un renvoi.
    case incertain(JoleneError)
}

extension RPCResponse {
    /// Une seule requête POST (le SDK ne rejoue jamais un `rpc`, correction 19), classée par `IssueMutation`.
    static func appelerMutation(_ client: SupabaseClient, _ fonction: String, params: JSONObject, fallback: String,
                                exceptionsMetier: Set<String>) async -> IssueMutation {
        await executerMutation(fallback: fallback, exceptionsMetier: exceptionsMetier) {
            try await client.rpc(fonction, params: params).execute().value
        }
    }

    static func executerMutation(fallback: String, exceptionsMetier: Set<String>,
                                 _ requete: () async throws -> AnyJSON) async -> IssueMutation {
        var echecBrut: (any Error)?
        do {
            let reponse = try await executer(fallback: fallback, exceptionsMetier: exceptionsMetier) {
                do {
                    return try await requete()
                } catch {
                    echecBrut = error
                    throw error
                }
            }
            return .reponse(reponse)
        } catch {
            let traduite = SupabaseErrorMapping.map(error, fallback: fallback)
            if rollbackProuve(echecBrut), let code = (echecBrut as? PostgrestError)?.code {
                return .refusDefinitif(code: code, erreur: traduite)
            }
            return .incertain(traduite)
        }
    }

    /// Vrai seulement pour une réponse PostgREST décodée portant un `code` non vide.
    static func rollbackProuve(_ echec: (any Error)?) -> Bool {
        guard let postgrest = echec as? PostgrestError, let code = postgrest.code else { return false }
        return !code.isEmpty
    }
}
