import XCTest
@testable import JoleneCore
#if os(macOS)
import CoreImage
#endif

/// Règle native du QR de pointage (lot 2, décision Q3) : plus stricte que l'extraction de
/// chiffres du web (`PointageRotatifSoignant.tsx` l.186), un payload n'est un code que s'il vaut
/// exactement six chiffres ASCII après suppression des espaces de bord. Pas de golden : la règle
/// diverge volontairement du web (un jeton du système ① ou un QR étranger ne produit jamais un code).
final class PayloadQRTests: XCTestCase {
    func testSixChiffresExactsSeulement() {
        XCTAssertEqual(PayloadQR.codePointage(depuis: "123456"), "123456")
        XCTAssertEqual(PayloadQR.codePointage(depuis: " 123456\n"), "123456")
        XCTAssertEqual(PayloadQR.codePointage(depuis: "\t000000 "), "000000")
        XCTAssertNil(PayloadQR.codePointage(depuis: "12345"))
        XCTAssertNil(PayloadQR.codePointage(depuis: "1234567"))
        XCTAssertNil(PayloadQR.codePointage(depuis: "abc123def456"), "six chiffres épars : acceptés par le web, refusés en natif")
        XCTAssertNil(PayloadQR.codePointage(depuis: "123 456"))
        XCTAssertNil(PayloadQR.codePointage(depuis: ""))
        XCTAssertNil(PayloadQR.codePointage(depuis: "١٢٣٤٥٦"), "chiffres arabes-indiens : jamais un code")
        XCTAssertNil(PayloadQR.codePointage(depuis: "１２３４５６"), "chiffres pleine chasse : jamais un code")
        XCTAssertNil(PayloadQR.codePointage(depuis: "+12345"))
        XCTAssertNil(PayloadQR.codePointage(depuis: "https://jolene.app/pointage?code=123456"))
    }

    func testPayloadAbsent() {
        XCTAssertNil(PayloadQR.codePointage(depuis: nil))
    }

    #if os(macOS)
    /// P2 niveau 1 : un QR de niveau M encodant le code rotatif, rendu puis relu, redonne le code.
    /// Décodeur `CIDetector` en rendu logiciel (aucun GPU, aucun réseau) : la lecture sur
    /// appareil passe par `AVCaptureMetadataOutput` (niveau 5, recette T12). Limité à `swift test`
    /// macOS : la détection Vision/CoreImage n'est pas garantie sur le simulateur iOS.
    func testQRNiveauMRenduPuisReluDonneLeCode() throws {
        let filtre = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filtre.setValue(Data("123456".utf8), forKey: "inputMessage")
        filtre.setValue("M", forKey: "inputCorrectionLevel")
        let qr = try XCTUnwrap(filtre.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let marge: CGFloat = 48
        let fond = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: qr.extent.insetBy(dx: -marge, dy: -marge))
        let image = qr.composited(over: fond)
        let contexte = CIContext(options: [.useSoftwareRenderer: true])
        let rendu = try XCTUnwrap(contexte.createCGImage(image, from: image.extent))
        let detecteur = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: contexte,
                                                 options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let messages = detecteur.features(in: CIImage(cgImage: rendu)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(messages, ["123456"])
        XCTAssertEqual(PayloadQR.codePointage(depuis: messages.first), "123456")
    }
    #endif
}
