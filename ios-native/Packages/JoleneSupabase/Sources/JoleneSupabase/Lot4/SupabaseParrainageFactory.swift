import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « parrainage » (`Gateways.parrainage`), câblée par L4-T6.
    static func parrainage(client: SupabaseClient) -> ParrainagePort { SupabaseParrainageGateway(client: client) }
}
