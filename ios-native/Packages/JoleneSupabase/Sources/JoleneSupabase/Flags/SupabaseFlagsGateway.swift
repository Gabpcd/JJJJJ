import Foundation
import JoleneCore
import Supabase

/// `FlagsPort` via `fn_param_bool(p_cle, p_defaut)` (même motif `client.rpc(name, params:)` que
/// `SupabaseRoleGateway`). Appelé avec la session : la fonction n'est pas accordée à `anon`.
///
/// Ne lève jamais : erreur réseau, droits refusés, fonction introuvable ou réponse non booléenne
/// rendent `defaut` — `true` pour les écrans natifs (décision 15, fail-open). Aucun renvoi.
public struct SupabaseFlagsGateway: FlagsPort {
    public static let rpcName = "fn_param_bool"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func ecranActif(cle: String, defaut: Bool) async -> Bool {
        let cle = cle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cle.isEmpty else { return defaut }
        do {
            let params: JSONObject = ["p_cle": .string(cle), "p_defaut": .bool(defaut)]
            let valeur: AnyJSON = try await client.rpc(Self.rpcName, params: params).execute().value
            return valeur.boolValue ?? defaut
        } catch {
            return defaut
        }
    }
}
