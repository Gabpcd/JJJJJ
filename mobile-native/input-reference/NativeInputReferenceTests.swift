import XCTest
final class NativeInputReferenceTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "host.exp.Exponent")
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 180 }
    func testFields() throws {
        app.activate()
        XCTAssertTrue(app.staticTexts["rn-input-reference-title"].waitForExistence(timeout: 20))
        var observed: [String: String] = [:]
        for variant in ["controlled-styled", "uncontrolled-styled", "controlled-basic"] {
            let field = app.textFields[variant]
            XCTAssertTrue(field.exists && field.isHittable)
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.frame.contains(field.frame))
            XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY)
            XCTAssertTrue(["", "6 chiffres"].contains(field.value as? String ?? "missing"))
            capture("input-reference-\(variant)-before")
            field.typeText("000000")
            observed[variant] = field.value as? String ?? "missing"
            capture("input-reference-\(variant)-after")
            let button = app.buttons["\(variant)-snapshot"]
            XCTAssertTrue(button.isHittable)
            button.tap()
            let metric = app.staticTexts["\(variant)-metrics"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "not-read"), object: metric)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            let attachment = XCTAttachment(string: metric.label)
            attachment.name = "\(variant)-metrics"; attachment.lifetime = .keepAlways; add(attachment)
        }
        let json = try JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys])
        let attachment = XCTAttachment(string: String(data: json, encoding: .utf8)!)
        attachment.name = "observed-values"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(observed, ["controlled-styled":"000000", "uncontrolled-styled":"000000", "controlled-basic":"000000"])
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = "\(name)-accessibility"; ax.lifetime = .keepAlways; add(ax)
    }
}
