import XCTest
import UIKit
@testable import JoleneDesign

final class JoleneDesignTests: XCTestCase {
    func testHexParsingAcceptsSixAndEightDigits() {
        let rose = JoleneHex.parse("#FF6BBE")
        XCTAssertEqual(rose, JoleneHex(red: 1, green: 107 / 255, blue: 190 / 255, alpha: 1))
        XCTAssertEqual(JoleneHex.parse("ff6bbe"), rose, "La casse et le dièse sont optionnels")
        let translucent = JoleneHex.parse("#2B1B3D80")
        XCTAssertEqual(translucent?.alpha ?? 0, 128 / 255, accuracy: 0.001)
        XCTAssertEqual(translucent?.red ?? 0, 43 / 255, accuracy: 0.001)
    }

    func testHexParsingRejectsInvalidInput() {
        XCTAssertNil(JoleneHex.parse(""))
        XCTAssertNil(JoleneHex.parse("#FFF"))
        XCTAssertNil(JoleneHex.parse("#GG6BBE"))
        XCTAssertNil(JoleneHex.parse("FF6BBE0"))
    }

    func testHSLMatchesDocumentedHexValues() {
        // src/index.css : --jolene-rose 326 100% 71% = #FF6BBE ; --jolene-midnight 268 38% 18% = #2B1B3D.
        let rose = JoleneHSL(326, 100, 71).rgb
        XCTAssertEqual(rose.red * 255, 255, accuracy: 1)
        XCTAssertEqual(rose.green * 255, 107, accuracy: 1)
        XCTAssertEqual(rose.blue * 255, 190, accuracy: 1)
        // Le HEX documenté (#2B1B3D) est un arrondi du HSL CSS : tolérance de 3/255 par canal.
        let midnight = JoleneHSL(268, 38, 18).rgb
        XCTAssertEqual(midnight.red * 255, 43, accuracy: 3)
        XCTAssertEqual(midnight.green * 255, 27, accuracy: 3)
        XCTAssertEqual(midnight.blue * 255, 61, accuracy: 3)
    }

    func testKeyboardMappingFollowsInputMobile() {
        // PROPS_INPUT_EMAIL : inputMode email, autoComplete email, autoCapitalize none, enterKeyHint next.
        let email = JoleneInputTraits.resolve(.email)
        XCTAssertEqual(email.keyboard, .emailAddress)
        XCTAssertEqual(email.contentType, .emailAddress)
        XCTAssertEqual(email.autocapitalization, .none)
        XCTAssertFalse(email.isSecure)
        XCTAssertEqual(email.submitLabel, .next)
        // PROPS_INPUT_OTP : numeric, one-time-code, enterKeyHint go.
        let otp = JoleneInputTraits.resolve(.otp)
        XCTAssertEqual(otp.keyboard, .numberPad)
        XCTAssertEqual(otp.contentType, .oneTimeCode)
        XCTAssertEqual(otp.maxLength, 6)
        XCTAssertEqual(otp.submitLabel, .go)
        XCTAssertEqual(JoleneInputTraits.resolve(.recherche).submitLabel, .search)
        // PROPS_INPUT_MDP : password, current-password, enterKeyHint go.
        let password = JoleneInputTraits.resolve(.motDePasse)
        XCTAssertTrue(password.isSecure)
        XCTAssertEqual(password.contentType, .password)
        XCTAssertEqual(JoleneInputTraits.resolve(.nouveauMotDePasse).contentType, .newPassword)
        // PROPS_INPUT_TELEPHONE / CODE_POSTAL / NOM.
        XCTAssertEqual(JoleneInputTraits.resolve(.telephone).keyboard, .phonePad)
        XCTAssertEqual(JoleneInputTraits.resolve(.codePostal).maxLength, 5)
        XCTAssertEqual(JoleneInputTraits.resolve(.codePostal).contentType, .postalCode)
        XCTAssertEqual(JoleneInputTraits.resolve(.nom).autocapitalization, .words)
        XCTAssertEqual(JoleneInputTraits.resolve(.montant).keyboard, .decimalPad)
        for kind in JoleneInputKind.allCases where kind != .recherche {
            XCTAssertFalse(JoleneInputTraits.resolve(kind).autocorrection, "spellCheck=false pour \(kind)")
        }
    }

    func testOTPDelegateRefusesOverlongReplacementWithoutTruncating() {
        XCTAssertTrue(OTPField.Coordinator.allows(current: "12345", range: NSRange(location: 5, length: 0), replacement: "6"))
        XCTAssertFalse(OTPField.Coordinator.allows(current: "123456", range: NSRange(location: 6, length: 0), replacement: "7"))
        XCTAssertFalse(OTPField.Coordinator.allows(current: "", range: NSRange(location: 0, length: 0), replacement: "1234567"))
        XCTAssertFalse(OTPField.Coordinator.allows(current: "", range: NSRange(location: 0, length: 0), replacement: "12a"))
        XCTAssertTrue(OTPField.Coordinator.allows(current: "123456", range: NSRange(location: 5, length: 1), replacement: ""))
        XCTAssertFalse(OTPField.Coordinator.allows(current: "12", range: NSRange(location: 3, length: 0), replacement: "4"), "Plage hors texte refusée")
    }
}
