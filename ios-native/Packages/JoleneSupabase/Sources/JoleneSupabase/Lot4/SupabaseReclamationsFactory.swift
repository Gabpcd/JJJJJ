import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « réclamations » (`Gateways.reclamations`). Stub non câblé posé par L4-T1 ; la tranche T8
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.reclamations()`.
    static func reclamations(client: SupabaseClient) -> ReclamationsPort { UnwiredReclamationsPort() }
}
