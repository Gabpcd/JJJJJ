import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « disponibilités » (`Gateways.disponibilites`), câblée par L4-T5.
    static func disponibilites(client: SupabaseClient) -> DisponibilitesPort { SupabaseDisponibilitesGateway(client: client) }
}
