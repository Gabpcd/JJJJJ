import Foundation

extension DemoLot4 {
    /// Fabrique démo du port « recherches sauvegardées » (`Gateways.filtres`). Stub non câblé posé par L4-T1 ; la tranche T4
    /// remplace ce corps par sa gateway démo (ce fichier seulement) et retire `filtres` de
    /// `DemoWorldTests.portsEnAttenteLot4`, dans la même PR que `SupabaseLot4.filtres(client:)`.
    static func filtres() -> FiltresSauvegardesPort { UnwiredFiltresSauvegardesPort() }
}
