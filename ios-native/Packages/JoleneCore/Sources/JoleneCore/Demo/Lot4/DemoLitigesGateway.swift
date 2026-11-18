import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « litiges » (`Gateways.litiges`). Stub non câblé posé par L4-T1 ; la tranche T8
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `litiges` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.litiges(client:)`.
    static func litiges() -> LitigesPort { UnwiredLitigesPort() }
}
