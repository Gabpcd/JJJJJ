import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « recherches sauvegardées » (`Gateways.filtres`). Stub non câblé posé par L4-T1 ; la tranche T4
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.filtres()`.
    static func filtres(client: SupabaseClient) -> FiltresSauvegardesPort { UnwiredFiltresSauvegardesPort() }
}
