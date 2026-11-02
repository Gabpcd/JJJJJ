import Foundation
import JoleneCore
import Supabase

/// `RolePort` via la RPC `fn_get_my_role` (jsonb `{role, etablissement_id}`).
/// Comme le pilote : rôle absent ou non textuel => "INCONNU", jamais une exception.
public struct SupabaseRoleGateway: RolePort {
    public static let rpcName = "fn_get_my_role"
    public static let unknownRole = "INCONNU"
    public static let fallbackMessage = "Impossible de vérifier votre espace. Réessayez."

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func currentRole() async throws -> RoleResult {
        do {
            let payload: AnyJSON = try await client.rpc(Self.rpcName).execute().value
            return Self.roleResult(from: payload)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
        }
    }

    static func roleResult(from payload: AnyJSON) -> RoleResult {
        let object = payload.objectValue ?? [:]
        return RoleResult(
            role: object["role"]?.stringValue ?? unknownRole,
            etablissementId: object["etablissement_id"]?.stringValue
        )
    }
}
