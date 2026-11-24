import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « réclamations » (`Gateways.reclamations`), câblée par L4-T8.
    static func reclamations(client: SupabaseClient) -> ReclamationsPort { SupabaseReclamationsGateway(client: client) }
}
