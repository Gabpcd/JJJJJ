import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « évaluations reçues » (`Gateways.evaluationsRecues`), câblée par L4-T9.
    static func evaluationsRecues(client: SupabaseClient) -> EvaluationsPort { SupabaseEvaluationsGateway(client: client) }
}
