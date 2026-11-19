import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « copies des bulletins » (`Gateways.bulletins`). Stub non câblé posé par L4-T1 ; la tranche T10
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `bulletins` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.bulletins(client:)`.
    static func bulletins() -> BulletinsPort { UnwiredBulletinsPort() }
}
