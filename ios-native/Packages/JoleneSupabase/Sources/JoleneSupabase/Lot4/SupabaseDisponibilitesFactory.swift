import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « disponibilités » (`Gateways.disponibilites`). Stub non câblé posé par L4-T1 ; la tranche T5
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.disponibilites()`.
    static func disponibilites(client: SupabaseClient) -> DisponibilitesPort { UnwiredDisponibilitesPort() }
}
