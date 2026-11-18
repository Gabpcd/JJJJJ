import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « swipe » (`Gateways.swipe`). Stub non câblé posé par L4-T1 ; la tranche T3a
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `swipe` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.swipe(client:)`.
    static func swipe() -> SwipePort { UnwiredSwipePort() }
}
