import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « litiges » (`Gateways.litiges`), câblée par L4-T8.
    static func litiges(client: SupabaseClient) -> LitigesPort { SupabaseLitigesGateway(client: client) }
}
