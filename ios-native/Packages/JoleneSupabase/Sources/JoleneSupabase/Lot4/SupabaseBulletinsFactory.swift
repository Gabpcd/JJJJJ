import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « copies des bulletins » (`Gateways.bulletins`). Stub non câblé posé par L4-T1 ; la tranche T10
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.bulletins()`.
    static func bulletins(client: SupabaseClient) -> BulletinsPort { UnwiredBulletinsPort() }
}
