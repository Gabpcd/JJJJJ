import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « messagerie » (`Gateways.messagerie`). Stub non câblé posé par L4-T1 ; la tranche T7a
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `messagerie` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.messagerie(client:)`.
    static func messagerie() -> MessageriePort { UnwiredMessageriePort() }
}
