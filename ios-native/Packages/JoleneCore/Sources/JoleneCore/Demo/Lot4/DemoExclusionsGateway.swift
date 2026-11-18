import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « exclusions » (`Gateways.exclusions`). Stub non câblé posé par L4-T1 ; la tranche T11
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `exclusions` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.exclusions(client:)`.
    static func exclusions() -> ExclusionsPort { UnwiredExclusionsPort() }
}
