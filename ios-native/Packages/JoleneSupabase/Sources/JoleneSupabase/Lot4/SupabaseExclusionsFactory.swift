import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « exclusions » (`Gateways.exclusions`), câblée par L4-T11.
    static func exclusions(client: SupabaseClient) -> ExclusionsPort { SupabaseExclusionsGateway(client: client) }
}
