import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « parrainage » (`Gateways.parrainage`). Stub non câblé posé par L4-T1 ; la tranche T6
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.parrainage()`.
    static func parrainage(client: SupabaseClient) -> ParrainagePort { UnwiredParrainagePort() }
}
