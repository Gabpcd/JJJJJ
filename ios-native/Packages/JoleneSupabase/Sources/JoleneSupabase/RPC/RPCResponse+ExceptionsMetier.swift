import Foundation
import JoleneCore
import Supabase

/// Exceptions métier restituées (blueprint `docs/mobile-swift/LOT3_PLAN.md` §2.1 et §2.4,
/// correction 12, tranche T1 ; même forme et même ordre que le blueprint du lot 2 §2.4).
///
/// Plusieurs RPC signalent un refus utilisateur par `RAISE EXCEPTION` (HTTP 4xx/5xx PostgREST),
/// jamais en jsonb HTTP 200 : `fn_demarrer_inscription` (22023 messages utilisateur, 23505 dont le
/// message est le code de réservation `ACCOUNT_*`), `fn_enregistrer_parcours_inscription` (22023,
/// P0002), `fn_upsert_token_push` (22023). `SupabaseErrorMapping` les réduirait au message
/// générique (`map(postgrestCode:)`), comme `[CODE DU TRAVAIL]` au lot 1. L'appelant déclare les
/// SQLSTATE métier de SA RPC (jamais une interception globale) ; ils sont restitués en
/// `{success:false, ok:false, code:"SQLSTATE_<code>", error:<PostgrestError.message brut>}` — ni
/// `details` ni `hint`. Ordre : `[CODE DU TRAVAIL]` → exceptions métier → `SupabaseErrorMapping`
/// (inchangé) ; une exception hors ensemble garde le comportement du lot 1 (42501 → session
/// expirée, PGRST202 → contrat, autre → `fallback`). Exception déclarée dont le message commence
/// par « permission denied for » (GRANT manquant, incident #835) : `.contract`, jamais restituée
/// (blueprint du lot 2 §2.4 et liste de tests de son T1). Une seule requête, aucun renvoi.
extension RPCResponse {
    /// Préfixe du `code` d'un refus restitué depuis une exception PostgREST.
    public static let prefixeSQLState = "SQLSTATE_"

    /// Début du message PostgreSQL d'un privilège manquant sur un objet (`42501`, GRANT absent).
    public static let prefixePrivilegeManquant = "permission denied for"

    /// Vrai pour « permission denied for function|table|… » (sensible à la casse, comme PostgreSQL).
    public static func estPrivilegeManquant(_ message: String) -> Bool {
        message.hasPrefix(prefixePrivilegeManquant)
    }

    /// SQLSTATE d'un refus restitué par `exceptionsMetier` ; nil pour toute autre réponse.
    public var sqlstate: String? {
        guard estRefus, let code, code.hasPrefix(Self.prefixeSQLState) else { return nil }
        let valeur = String(code.dropFirst(Self.prefixeSQLState.count))
        return valeur.isEmpty ? nil : valeur
    }

    /// Refus structuré équivalent à l'exception déclarée : message mot pour mot.
    static func refusMetier(sqlstate: String, message: String) -> RPCResponse {
        RPCResponse(.object([
            "success": .bool(false),
            "ok": .bool(false),
            "code": .string(prefixeSQLState + sqlstate),
            "error": .string(message),
        ]))
    }

    /// Appel RPC sans paramètre ; `exceptionsMetier` = SQLSTATE restitués pour cette RPC.
    static func appeler(_ client: SupabaseClient, _ fonction: String, fallback: String,
                        exceptionsMetier: Set<String>) async throws -> RPCResponse {
        try await executer(fallback: fallback, exceptionsMetier: exceptionsMetier) {
            try await client.rpc(fonction).execute().value
        }
    }

    /// Appel RPC à paramètres nommés ; `exceptionsMetier` = SQLSTATE restitués pour cette RPC.
    static func appeler(_ client: SupabaseClient, _ fonction: String, params: JSONObject, fallback: String,
                        exceptionsMetier: Set<String>) async throws -> RPCResponse {
        try await executer(fallback: fallback, exceptionsMetier: exceptionsMetier) {
            try await client.rpc(fonction, params: params).execute().value
        }
    }

    /// Restitue les exceptions déclarées en corps de refus, puis délègue à `executer(fallback:_:)`
    /// (lot 1) : l'interception `[CODE DU TRAVAIL]` et `SupabaseErrorMapping` restent les seuls
    /// traitements de tout le reste. Un privilège manquant déclaré (`estPrivilegeManquant`) est une
    /// erreur de contrat : la version de l'app ne correspond plus aux GRANT du backend.
    static func executer(fallback: String, exceptionsMetier: Set<String>,
                         _ requete: () async throws -> AnyJSON) async throws -> RPCResponse {
        try await executer(fallback: fallback) {
            do {
                return try await requete()
            } catch let postgrest as PostgrestError
                        where !estRefusCodeDuTravail(postgrest.message) && exceptionsMetier.contains(postgrest.code ?? "") {
                if estPrivilegeManquant(postgrest.message) {
                    throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
                }
                return refusMetier(sqlstate: postgrest.code ?? "", message: postgrest.message).raw
            }
        }
    }
}
