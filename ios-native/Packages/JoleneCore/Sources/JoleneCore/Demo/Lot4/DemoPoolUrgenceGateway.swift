import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « pool urgence » (`Gateways.poolUrgence`). Stub non câblé posé par L4-T1 ; la tranche T11
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `poolUrgence` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.poolUrgence(client:)`.
    static func poolUrgence() -> PoolUrgencePort { UnwiredPoolUrgencePort() }
}
