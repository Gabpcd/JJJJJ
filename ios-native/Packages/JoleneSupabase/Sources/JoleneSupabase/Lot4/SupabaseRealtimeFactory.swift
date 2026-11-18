import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « Realtime » (`Gateways.realtime`). Stub non câblé posé par L4-T1 ; la tranche T7a
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.realtime()`.
    static func realtime(client: SupabaseClient) -> RealtimePort { UnwiredRealtimePort() }
}
