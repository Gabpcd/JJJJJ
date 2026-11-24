import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « copies des bulletins » (`Gateways.bulletins`), câblée par L4-T10.
    static func bulletins(client: SupabaseClient) -> BulletinsPort { SupabaseBulletinsGateway(client: client) }
}
