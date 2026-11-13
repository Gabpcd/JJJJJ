import SwiftUI
import JoleneCore
import JoleneDesign

/// Variante démo du scanner (blueprint lot 2 §2.2, §2.8) : aucune caméra, aucune permission système ; rend le scénario
/// `-JOLENE_DEMO_QR` (DEBUG) comme l'aurait rendu `QRScannerView` : deux détections du même payload (preuve « une seule
/// remise par session »), un payload illisible, ou un refus de la caméra. Posée par `AppContainer` en mode démo
/// seulement ; la caméra réelle n'est pas pilotable en XCUITest et se prouve sur appareil (P8), le décodage du QR rotatif
/// au niveau 1 (Vision, `PayloadQRTests`).
///
/// DEBUG (seconde revue fraîche de T4b, MJ1) : la lecture part sur une action explicite, le bouton
/// `pointage-scanner-demo-lire` ; la feuille reste présentée jusque-là, quel que soit le scénario. Les XCUITest attendent
/// donc un état stable (feuille ouverte) avant de toucher, sans course avec une fermeture automatique. Release (monde démo
/// sans tests) : lecture rendue une fois la présentation de la feuille terminée.
struct DemoQRScannerView: View {
    let scenario: ScenarioQRDemo
    let surEvenement: @MainActor (EvenementScanner) -> Void

    var body: some View {
        VStack(spacing: JoleneSpacing.md) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 96))
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityHidden(true)
            #if DEBUG
            // Texte DEBUG (absent en Release, jamais vu par un utilisateur), inventorié dans DECISIONS_LOT2.md.
            Button { lire() } label: {
                Text(verbatim: "Simuler la lecture du QR (démo)")
                    .font(JoleneFont.button)
                    .padding(.horizontal, JoleneSpacing.md)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(JoleneColor.rose700)
            .accessibilityIdentifier("pointage-scanner-demo-lire")
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JoleneColor.cloud)
        #if !DEBUG
        .task {
            // Laisse la feuille finir sa présentation avant de rendre la lecture (une fermeture pendant
            // l'animation d'ouverture serait ignorée par SwiftUI). Délai de l'app démo, jamais d'un test.
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            lire()
        }
        #endif
    }

    /// Rend le scénario : un refus de la caméra, ou les détections du payload, dans l'ordre.
    private func lire() {
        switch scenario {
        case .refus:
            surEvenement(.refus)
        case .lecture:
            for detection in scenario.detections { surEvenement(.payload(detection)) }
        }
    }
}
