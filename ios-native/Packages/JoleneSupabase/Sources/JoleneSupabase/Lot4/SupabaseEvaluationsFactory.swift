import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « évaluations reçues » (`Gateways.evaluationsRecues`). Stub non câblé posé par L4-T1 ; la tranche T9
    /// remplace ce corps par sa gateway (ce fichier seulement), dans la même PR que `DemoLot4.evaluationsRecues()`.
    static func evaluationsRecues(client: SupabaseClient) -> EvaluationsPort { UnwiredEvaluationsPort() }
}
