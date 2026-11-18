import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « score » (`Gateways.score`). Stub non câblé posé par L4-T1 ; la tranche T9
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `score` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.score(client:)`.
    static func score() -> ScorePort { UnwiredScorePort() }
}
