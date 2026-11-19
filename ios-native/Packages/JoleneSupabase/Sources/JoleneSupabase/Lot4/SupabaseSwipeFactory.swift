import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « swipe » (`Gateways.swipe`), T3a : `SupabaseSwipeGateway` (paquet, ✕ / ⭐, retrait,
    /// quiz). Le ❤️ passe par `Gateways.candidature` (`SupabaseCandidatureGateway`, action `SWIPE_LIKE`).
    static func swipe(client: SupabaseClient) -> SwipePort { SupabaseSwipeGateway(client: client) }
}
