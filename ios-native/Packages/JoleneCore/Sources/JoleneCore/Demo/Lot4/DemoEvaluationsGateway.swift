import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « évaluations reçues » (`Gateways.evaluationsRecues`). Stub non câblé posé par L4-T1 ; la tranche T9
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `evaluationsRecues` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.evaluationsRecues(client:)`.
    static func evaluationsRecues() -> EvaluationsPort { UnwiredEvaluationsPort() }
}
