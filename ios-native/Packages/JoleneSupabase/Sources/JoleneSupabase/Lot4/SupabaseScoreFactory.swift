import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « score » (`Gateways.score`), câblée par L4-T9.
    static func score(client: SupabaseClient) -> ScorePort { SupabaseScoreGateway(client: client) }
}
