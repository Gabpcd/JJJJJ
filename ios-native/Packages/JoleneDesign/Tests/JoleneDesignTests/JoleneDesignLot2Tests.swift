import XCTest
import SwiftUI
import UIKit
@testable import JoleneDesign

/// Lot 2 (T7) : `StatusBadge`. Partie calculable vérifiée sans XCUITest (tons, contrastes) ; le corps est évalué dans un
/// `UIHostingController` comme les composants du lot 1. Le parcours visible est couvert par `DemoDocumentsTests`.
final class JoleneDesignLot2Tests: XCTestCase {
    func testStatusBadgeReprendLesTonsVerifiesDesEncarts() {
        XCTAssertEqual(StatusBadge.Tone.allCases.count, 5)
        XCTAssertEqual(StatusBadge.Tone.success.noticeTone, .success)
        XCTAssertEqual(StatusBadge.Tone.warning.noticeTone, .warning)
        XCTAssertEqual(StatusBadge.Tone.error.noticeTone, .error)
        XCTAssertEqual(StatusBadge.Tone.info.noticeTone, .info)
        XCTAssertNil(StatusBadge.Tone.neutral.noticeTone)
        for tone in StatusBadge.Tone.allCases {
            if let notice = tone.noticeTone {
                XCTAssertEqual(tone.backgroundHSL, notice.backgroundHSL)
                XCTAssertEqual(tone.inkHSL, notice.inkHSL)
                XCTAssertEqual(tone.systemImage, notice.systemImage, "le ton est porté par l'icône, jamais par la couleur seule")
            }
        }
        XCTAssertEqual(StatusBadge.Tone.neutral.systemImage, "minus.circle")
        XCTAssertEqual(StatusBadge.textInkHSL, JoleneColor.midnightHSL)
    }

    func testStatusBadgeTexteEtIconeContrastentEnClairEtEnSombre() {
        for tone in StatusBadge.Tone.allCases {
            let fond = tone.backgroundHSL
            XCTAssertGreaterThanOrEqual(StatusBadge.textInkHSL.light.rgb.contrastRatio(with: fond.light.rgb), 4.5, "\(tone) clair")
            XCTAssertGreaterThanOrEqual(StatusBadge.textInkHSL.dark.rgb.contrastRatio(with: fond.dark.rgb), 4.5, "\(tone) sombre")
            XCTAssertGreaterThanOrEqual(tone.inkHSL.light.rgb.contrastRatio(with: fond.light.rgb), 3, "\(tone) : icône claire")
            XCTAssertGreaterThanOrEqual(tone.inkHSL.dark.rgb.contrastRatio(with: fond.dark.rgb), 3, "\(tone) : icône sombre")
        }
    }

    @MainActor
    func testStatusBadgeSeRendA390Points() {
        for (tone, enCours) in [(StatusBadge.Tone.success, false), (.warning, true), (.neutral, false)] {
            let hote = UIHostingController(rootView: StatusBadge("Vérifié ✅", tone: tone, isInProgress: enCours, identifier: "badge",
                                                                 progressIdentifier: "badge-progression"))
            let taille = hote.sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
            XCTAssertGreaterThan(taille.width, 0)
            XCTAssertGreaterThan(taille.height, 0)
            XCTAssertLessThanOrEqual(taille.width, 390)
        }
    }
}
