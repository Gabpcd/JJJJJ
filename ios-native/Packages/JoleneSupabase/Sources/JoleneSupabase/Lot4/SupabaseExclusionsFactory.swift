import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « exclusions » (`Gateways.exclusions`). Stub non câblé posé par L4-T1 ; la tranche T11
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.exclusions()`.
    static func exclusions(client: SupabaseClient) -> ExclusionsPort { UnwiredExclusionsPort() }
}
