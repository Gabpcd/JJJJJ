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
    /// Rollback prouvé (`RPCResponse.rollbackProuve`) : SQLSTATE, ou code PostgREST émis avant toute transaction ou
    /// après son annulation. Rien n'est écrit. Refus définitif (message de `SupabaseErrorMapping`), jamais un
    /// incertain ; aucun renvoi.
    case refusDefinitif(code: String, erreur: JoleneError)
    /// Aucune preuve : réseau, annulation, passerelle (corps HTML → `HTTPError` ; corps `{"message"}` sans `code`
    /// → `PostgrestError(code: nil)` dans supabase-swift 2.55.5), `PGRST001` (connexion à la base cassée en cours de
    /// session, COMMIT compris), tout autre code. La requête a pu être appliquée : réconciliation par relecture,
    /// jamais un renvoi.
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

    /// Vrai seulement pour une réponse PostgREST décodée dont le `code` prouve que rien n'a été validé
    /// (revue fraîche de T1, seconde passe ; correction 10 amendée dans `DECISIONS_LOT2.md`) :
    /// - un SQLSTATE (`RecuScan.sqlstateValide` : cinq caractères `[0-9A-Z]`, le prédicat de `RecuScan.refuser`) :
    ///   PostgreSQL a levé une erreur, la transaction est annulée ;
    /// - un code PostgREST de `codePostgRESTSansTransaction`.
    /// Tout autre code (`PGRST001`, `PGRSTX00`, code texte d'une passerelle) n'est pas une preuve.
    static func rollbackProuve(_ echec: (any Error)?) -> Bool {
        guard let postgrest = echec as? PostgrestError, let code = postgrest.code else { return false }
        return RecuScan.sqlstateValide(code) || codePostgRESTSansTransaction(code)
    }

    /// Codes PostgREST émis avant toute transaction ou après son annulation : connexion jamais obtenue (`PGRST000`),
    /// cache de schéma indisponible (`PGRST002`), délai d'attente du pool (`PGRST003`), requête (`PGRST1xx`, dont
    /// `PGRST116` et `PGRST124` qui annulent la transaction), cache de schéma (`PGRST2xx`), JWT (`PGRST3xx`).
    /// Exclus : `PGRST001` (connexion cassée en cours de session, COMMIT compris) et, parmi les `PGRST1xx`, ceux que
    /// PostgREST produit aussi en construisant la réponse APRÈS le COMMIT : `PGRST103` (plage 416), `PGRST111` et
    /// `PGRST112` (en-têtes et statut posés par la fonction).
    static func codePostgRESTSansTransaction(_ code: String) -> Bool {
        if ["PGRST000", "PGRST002", "PGRST003"].contains(code) { return true }
        if ["PGRST103", "PGRST111", "PGRST112"].contains(code) { return false }
        let scalaires = Array(code.unicodeScalars)
        guard scalaires.count == 8, code.hasPrefix("PGRST"), ("1"..."3").contains(scalaires[5]) else { return false }
        return scalaires[6...].allSatisfy { ("0"..."9").contains($0) }
    }
}
