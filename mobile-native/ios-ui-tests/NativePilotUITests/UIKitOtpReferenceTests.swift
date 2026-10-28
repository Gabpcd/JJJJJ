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
        app.activate()
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

    private func capture(_ stage: String) throws -> [String: Any] {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "uikit-reference-\(stage)-screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = "uikit-reference-\(stage)-accessibility"
        ax.lifetime = .keepAlways
        add(ax)
        let metrics = app.descendants(matching: .any).matching(identifier: "uikit-reference-metrics")
        XCTAssertEqual(metrics.count, 1)
        let json = metrics.element(boundBy: 0).value as? String ?? ""
        let attachment = XCTAttachment(string: json)
        attachment.name = "uikit-reference-\(stage)-metrics.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let value = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(value["schemaVersion"] as? Int, 1)
        XCTAssertEqual(value["source"] as? String, "synthetic-uikit-reference")
        XCTAssertEqual(value["bundleId"] as? String, "app.jolene.otp-uikit-reference")
        XCTAssertEqual(value["truncated"] as? Bool, false, "A truncated trace is not complete evidence")
        return value
    }
}
