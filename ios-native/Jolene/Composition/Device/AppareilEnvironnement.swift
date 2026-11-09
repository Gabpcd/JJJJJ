import SwiftUI
import JoleneCore

/// Scanner de QR choisi par `AppContainer` : la caméra réelle (`QRScannerView`) ou sa variante démo (`DemoQRScannerView`,
/// scénario `-JOLENE_DEMO_QR`). Une vue, pas un port (blueprint lot 2 §2.2) : le modèle ne reçoit qu'un code.
enum ModeScannerQR: Equatable, Sendable {
    case reel
    case demo(ScenarioQRDemo)
}

private struct AppareilKey: EnvironmentKey {
    static let defaultValue: Appareil? = nil
}

extension EnvironmentValues {
    /// Capacités d'appareil (`Appareil` : position, réseau, identifiant terminal, reçus) d'`AppContainer`, injectées
    /// au-dessus des onglets par `MainTabView` (lot 2 T4b) ; nil hors session.
    var appareil: Appareil? {
        get { self[AppareilKey.self] }
        set { self[AppareilKey.self] = newValue }
    }
}
