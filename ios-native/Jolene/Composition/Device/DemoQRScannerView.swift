import SwiftUI
import JoleneCore
import JoleneDesign

/// Variante démo du scanner (blueprint lot 2 §2.2, §2.8) : aucune caméra, aucune permission système ; rend le scénario
/// `-JOLENE_DEMO_QR` (DEBUG) comme l'aurait rendu `QRScannerView` : deux détections du même payload (preuve « une seule
/// remise par session »), un payload illisible, ou un refus de la caméra. Posée par `AppContainer` en mode démo
/// seulement ; la caméra réelle n'est pas pilotable en XCUITest et se prouve sur appareil (P8), le décodage du QR rotatif
/// au niveau 1 (Vision, `PayloadQRTests`).
struct DemoQRScannerView: View {
    let scenario: ScenarioQRDemo
    let surEvenement: @MainActor (EvenementScanner) -> Void

    var body: some View {
        Image(systemName: "qrcode.viewfinder")
            .font(.system(size: 96))
            .foregroundStyle(JoleneColor.bubblegum)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(JoleneColor.cloud)
            .accessibilityHidden(true)
            .task {
                // Laisse la feuille finir sa présentation avant de rendre la lecture (une fermeture pendant
                // l'animation d'ouverture serait ignorée par SwiftUI). Délai de l'app démo, jamais d'un test.
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                switch scenario {
                case .refus:
                    surEvenement(.refus)
                case .lecture:
                    for detection in scenario.detections { surEvenement(.payload(detection)) }
                }
            }
    }
}
