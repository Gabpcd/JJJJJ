import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « pool urgence » (`Gateways.poolUrgence`). Stub non câblé posé par L4-T1 ; la tranche T11
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.poolUrgence()`.
    static func poolUrgence(client: SupabaseClient) -> PoolUrgencePort { UnwiredPoolUrgencePort() }
}
