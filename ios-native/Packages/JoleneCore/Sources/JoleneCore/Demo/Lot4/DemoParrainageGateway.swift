import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « parrainage » (`Gateways.parrainage`). Stub non câblé posé par L4-T1 ; la tranche T6
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `parrainage` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.parrainage(client:)`.
    static func parrainage() -> ParrainagePort { UnwiredParrainagePort() }
}
