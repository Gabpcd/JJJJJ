import SwiftUI
import JoleneCore
import JoleneDesign

/// Feuille du scanner de QR de pointage (port du dialogue web `PointageRotatifSoignant.tsx` l.231-244 : titre et
/// description du web) : caméra réelle ou démo selon `AppContainer`. La remise unique d'un code par ouverture est la
/// règle de `SessionScanQR` (JoleneCore) : le premier code lisible est rendu et la feuille se ferme, les détections
/// suivantes sont ignorées ; un QR illisible affiche « QR non reconnu… » et la caméra continue ; un refus de la caméra
/// ferme la feuille avec « Scan impossible… » (la saisie manuelle reste toujours disponible). Identifiants :
/// `pointage-scanner`, `pointage-scanner-message`, `pointage-scanner-fermer`.
struct ScannerQRSheet: View {
    enum Issue: Equatable {
        case code(String)
        case refus
    }

    let mode: ModeScannerQR
    let rendre: (Issue) -> Void
    let fermer: () -> Void

    @State private var session = SessionScanQR()
    @State private var illisible = false
    @State private var termine = false

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            Text(LibellesWeb.Pointage.scannerTitre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            Text(LibellesWeb.Pointage.scannerDescription)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            scanner
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            if illisible {
                InlineNotice(LibellesWeb.Pointage.qrNonReconnu, tone: .warning, identifier: "pointage-scanner-message",
                             announcesOnAppear: true)
            }
            JoleneButton(LibellesPresences.Pointage.fermer, style: .secondary) { fermer() }
                .accessibilityIdentifier("pointage-scanner-fermer")
            Spacer(minLength: 0)
        }
        .padding(JoleneSpacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pointage-scanner")
        .background(JoleneColor.lavender.ignoresSafeArea())
    }

    @ViewBuilder private var scanner: some View {
        switch mode {
        case .reel:
            QRScannerView { recevoir($0) }
        case let .demo(scenario):
            DemoQRScannerView(scenario: scenario) { recevoir($0) }
        }
    }

    private func recevoir(_ evenement: EvenementScanner) {
        guard !termine else { return }
        switch evenement {
        case let .payload(payload):
            switch session.recevoir(payload) {
            case let .code(code):
                termine = true
                rendre(.code(code))
            case .illisible:
                illisible = true
            case .ignore:
                break
            }
        case .refus, .indisponible:
            termine = true
            rendre(.refus)
        }
    }
}
