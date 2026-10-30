import XCTest

// Separate control, never selected by a Contracts test method or its runner.
final class UIKitOtpReferenceTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "app.jolene.otp-uikit-reference")

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    func testSixZeros() throws {
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(app.state, .runningForeground, "The runner prepared the distinct UIKit control")
        let title = app.staticTexts["uikit-reference-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "Témoin UIKit · saisie synthétique")
        let fields = app.textFields.matching(identifier: "uikit-reference-otp")
        XCTAssertEqual(fields.count, 1)
        let field = fields.element(boundBy: 0)
        XCTAssertTrue(field.isHittable)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        let before = try capture("before")
        XCTAssertEqual(before["length"] as? Int, 0)
        XCTAssertEqual(before["focused"] as? Bool, true)
        XCTAssertEqual(before["selectionStart"] as? Int, 0)
        XCTAssertEqual(before["selectionEnd"] as? Int, 0)
        XCTAssertTrue(app.frame.contains(field.frame))
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboardTop(), "The whole reference field is above the keyboard")

        // Same original stimulus as Contracts. No second typing, clear, keypad
        // comparison, paste, fallback, waiting for the value or delayed retry.
        field.typeText("000000")
        let actual = field.value as? String
        let after = try capture("after")
        XCTAssertEqual(actual, "000000", "The single original typeText must retain all six exact digits")
        XCTAssertEqual(after["length"] as? Int, 6)
        XCTAssertEqual(after["focused"] as? Bool, true)
        XCTAssertEqual(after["selectionStart"] as? Int, 6)
        XCTAssertEqual(after["selectionEnd"] as? Int, 6)
    }

    func testButtonReleases() throws {
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(app.state, .runningForeground, "The runner prepared the distinct touch control")
        let title = app.staticTexts["uikit-touch-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "Témoin UIKit · relâchement du bouton")
        XCTAssertEqual(app.textFields.count, 0, "No OTP field or preparatory focus gesture")
        let buttons = app.buttons.matching(identifier: "uikit-touch-button")
        XCTAssertEqual(buttons.count, 1)
        let button = buttons.element(boundBy: 0)
        let before = try capture("before", kind: "touch")
        XCTAssertEqual(before["downs"] as? Int, 0)
        XCTAssertEqual(before["upInside"] as? Int, 0)
        XCTAssertEqual(before["cancels"] as? Int, 0)
        // Twelve distinct planned observations, never retries. Each failed
        // original release ends the test before another contact is attempted.
        for index in 1...12 {
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(app.frame.contains(button.frame))
            button.press(forDuration: 0.2)
            let observed = try capture("contact-\(index)", kind: "touch", screen: false)
            guard observed["downs"] as? Int == index,
                  observed["upInside"] as? Int == index,
                  observed["cancels"] as? Int == 0 else {
                _ = try capture("failure-\(index)", kind: "touch")
                XCTFail("Contact \(index) must produce exactly one down and one upInside, without cancellation")
                return
            }
        }
        _ = try capture("after", kind: "touch")
    }

    private func keyboardTop() -> CGFloat {
        let keyboard = app.keyboards.firstMatch.frame
        var top = keyboard.minY
        for accessory in app.descendants(matching: .any).matching(identifier: "SystemInputAssistantView").allElementsBoundByIndex
            + app.toolbars.matching(identifier: "Toolbar").allElementsBoundByIndex {
            let frame = accessory.frame
            if !frame.isEmpty && frame.minY < keyboard.minY
                && frame.minX < keyboard.maxX && frame.maxX > keyboard.minX {
                top = min(top, frame.minY)
            }
        }
        return top
    }

    private func capture(_ stage: String, kind: String = "otp", screen: Bool = true) throws -> [String: Any] {
        let prefix = kind == "touch" ? "uikit-touch" : "uikit-reference"
        if screen {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "\(prefix)-\(stage)-screen"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let ax = XCTAttachment(string: app.debugDescription)
            ax.name = "\(prefix)-\(stage)-accessibility"
            ax.lifetime = .keepAlways
            add(ax)
        }
        let metrics = app.descendants(matching: .any).matching(identifier: "\(prefix)-metrics")
        XCTAssertEqual(metrics.count, 1)
        let json = metrics.element(boundBy: 0).value as? String ?? ""
        let attachment = XCTAttachment(string: json)
        attachment.name = "\(prefix)-\(stage)-metrics.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let value = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(value["schemaVersion"] as? Int, 1)
        XCTAssertEqual(value["source"] as? String, kind == "touch" ? "synthetic-uikit-touch-reference" : "synthetic-uikit-reference")
        XCTAssertEqual(value["bundleId"] as? String, "app.jolene.otp-uikit-reference")
        XCTAssertEqual(value["truncated"] as? Bool, false, "A truncated trace is not complete evidence")
        return value
    }
}
