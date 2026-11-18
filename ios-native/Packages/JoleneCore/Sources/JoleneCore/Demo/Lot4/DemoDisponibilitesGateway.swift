import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « disponibilités » (`Gateways.disponibilites`). Stub non câblé posé par L4-T1 ; la tranche T5
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `disponibilites` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.disponibilites(client:)`.
    static func disponibilites() -> DisponibilitesPort { UnwiredDisponibilitesPort() }
}
