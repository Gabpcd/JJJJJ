import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « litiges » (`Gateways.litiges`). Stub non câblé posé par L4-T1 ; la tranche T8
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.litiges()`.
    static func litiges(client: SupabaseClient) -> LitigesPort { UnwiredLitigesPort() }
}
