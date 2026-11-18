import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « Realtime » (`Gateways.realtime`). Stub non câblé posé par L4-T1 ; la tranche T7a
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `realtime` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.realtime(client:)`.
    static func realtime() -> RealtimePort { UnwiredRealtimePort() }
}
