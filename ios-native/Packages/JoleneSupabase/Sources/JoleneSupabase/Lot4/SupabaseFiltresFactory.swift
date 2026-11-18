import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « recherches sauvegardées » (`Gateways.filtres`), câblée par L4-T4.
    static func filtres(client: SupabaseClient) -> FiltresSauvegardesPort { SupabaseFiltresGateway(client: client) }
}
