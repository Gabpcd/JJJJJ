import XCTest
import SwiftUI
import UIKit
import CoreImage
@testable import JoleneDesign

/// Lot 5 (T7) : plein écran du code de pointage (`FullScreenCodeView`). Côté du QR au plus grand que l'écran permet
/// (70 % du petit côté, portrait comme paysage) et QR rendu à ce côté relu par `CIDetector` en la valeur brute du code
/// (D4 : QR du `code_pointage_actif`, jamais un autre jeton). Le parcours visible est couvert par `DemoEtabPointageTests`
/// (XCUITest démo, QR décodé sur la capture du plein écran).
/// Lot 5 (T8) : rangée d'étoiles saisissable (`StarRating`), note de l'établissement à la validation d'une présence.
final class JoleneDesignLot5Tests: XCTestCase {
    func testEtoilesSaisissablesPleinesJusquALaNoteChoisie() {
        XCTAssertEqual(StarRating.starCount, 5)
        XCTAssertEqual(StarRating.minimumTarget, 44, "cible tactile de 44 pt par étoile")
        XCTAssertEqual((1...5).map { StarRating.isFilled($0, value: 0) }, [false, false, false, false, false], "aucune note choisie")
        XCTAssertEqual((1...5).map { StarRating.isFilled($0, value: 4) }, [true, true, true, true, false])
        XCTAssertEqual((1...5).map { StarRating.isFilled($0, value: 9) }, [true, true, true, true, true], "valeur bornée à 5")
        XCTAssertFalse(StarRating.isFilled(0, value: 5))
        XCTAssertEqual([-3, 0, 3, 5, 12].map(StarRating.clamped), [0, 0, 3, 5, 5])
    }


    func testCoteDuQRAuPlusGrandEnPortraitCommeEnPaysage() {
        XCTAssertEqual(FullScreenCodeView.proportionQR, 0.7)
        XCTAssertEqual(FullScreenCodeView.coteQR(pour: CGSize(width: 390, height: 844)), 273, "iPhone portrait")
        XCTAssertEqual(FullScreenCodeView.coteQR(pour: CGSize(width: 844, height: 390)), 273, "iPhone paysage : même côté")
        XCTAssertEqual(FullScreenCodeView.coteQR(pour: CGSize(width: 1180, height: 820)), 574, "iPad paysage")
        XCTAssertEqual(FullScreenCodeView.coteQR(pour: .zero), 0)
        XCTAssertEqual(FullScreenCodeView.coteQR(pour: CGSize(width: CGFloat.infinity, height: .nan)), 0)
    }

    func testQRDuPleinEcranRelitLaValeurBrute() throws {
        let detecteur = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                 options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for code in ["123456", "100002", "000000"] {
            let image = try XCTUnwrap(QRCodeImage.cgImage(for: code), code)
            let lus = detecteur.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(lus, [code], "le QR encode la valeur relue telle quelle (six chiffres, sans espace)")
        }
    }
}
