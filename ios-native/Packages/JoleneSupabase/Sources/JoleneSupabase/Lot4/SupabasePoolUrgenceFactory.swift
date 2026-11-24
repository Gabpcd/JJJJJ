import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « pool urgence » (`Gateways.poolUrgence`), câblée par L4-T11.
    static func poolUrgence(client: SupabaseClient) -> PoolUrgencePort { SupabasePoolUrgenceGateway(client: client) }
}
