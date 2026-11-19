import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « messagerie » (`Gateways.messagerie`). Stub non câblé posé par L4-T1 ; la tranche T7a
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.messagerie()`.
    static func messagerie(client: SupabaseClient) -> MessageriePort { UnwiredMessageriePort() }
}
