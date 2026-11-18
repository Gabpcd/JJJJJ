import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « swipe » (`Gateways.swipe`). Stub non câblé posé par L4-T1 ; la tranche T3a
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.swipe()`.
    static func swipe(client: SupabaseClient) -> SwipePort { UnwiredSwipePort() }
}
