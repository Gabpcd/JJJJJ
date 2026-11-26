#if DEBUG
import XCTest
@testable import JoleneCore

/// Argument DEBUG de la recette de la garde de repos XCUITest : posé seulement en démo, avec la valeur « 1 ».
final class SondeAnimationOuverteTests: XCTestCase {
    func testActiveSeulementEnDemoAvecUn() {
        XCTAssertEqual(SondeAnimationOuverte.argument, "-JOLENE_UITEST_ANIMATION_OUVERTE", "argument lu par DemoGardeReposTests")
        XCTAssertTrue(SondeAnimationOuverte.active(arguments: ["-JOLENE_MODE", "demo", "-JOLENE_UITEST_ANIMATION_OUVERTE", "1"], demo: true))
        XCTAssertFalse(SondeAnimationOuverte.active(arguments: ["-JOLENE_UITEST_ANIMATION_OUVERTE", "1"], demo: false), "hors démo : rien")
        XCTAssertFalse(SondeAnimationOuverte.active(arguments: ["-JOLENE_UITEST_ANIMATION_OUVERTE", "0"], demo: true))
        XCTAssertFalse(SondeAnimationOuverte.active(arguments: ["-JOLENE_UITEST_ANIMATION_OUVERTE"], demo: true), "valeur absente")
        XCTAssertFalse(SondeAnimationOuverte.active(arguments: ["-JOLENE_MODE", "demo"], demo: true))
    }
}
#endif
