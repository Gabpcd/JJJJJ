import XCTest

/// Drives the existing Expo Go experience; never launches, reloads or resets Jolene.
final class NativePilotTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "host.exp.Exponent")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var proofPrefix = "ipad-portrait"

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
    }

    override func tearDownWithError() throws {
        // hasSucceeded is still false during teardown; count only failures already recorded.
        if (testRun?.totalFailureCount ?? 0) > 0 {
            record("\(proofPrefix)-echec")
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "\(proofPrefix)-echec-ecran-systeme"
            screen.lifetime = .keepAlways
            add(screen)
            attachText(springboard.debugDescription, name: "\(proofPrefix)-echec-springboard.txt")
        }
    }

    /// The runner opens the prepared exp:// URL before this test on a fresh iPad simulator.
    func testPortraitConsultation() throws {
        runPortraitConsultation(prefix: "ipad-portrait", deviceName: "iPad")
    }

    /// Uses the identical portrait assertions on a separate fresh iPhone simulator.
    func testIphoneConsultation() throws {
        runPortraitConsultation(prefix: "iphone-portrait", deviceName: "iPhone")
    }

    private func runPortraitConsultation(prefix: String, deviceName: String) {
        proofPrefix = prefix
        prepareExpoGo()
        XCUIDevice.shared.orientation = .portrait
        require("\(deviceName) portrait window") { self.app.frame.height > self.app.frame.width }
        assertSignedOutDemo()
        record("\(prefix)-connexion")
        element("enter-demo").tap()
        assertMissionCount(30)

        element("contract-filter-LIBERAL").tap()
        assertMissionCount(10)
        element("contract-filter-CDD").tap()
        assertMissionCount(20)
        element("contract-filter-TOUS").tap()
        assertMissionCount(30)

        let city = element("mission-city")
        require("The native city input is reachable") { self.visible(city) }
        city.tap()
        // Return invokes the TextInput search action, including its keyboard dismissal.
        city.typeText("VilleIntrouvable\n")
        require("An unmatched city displays the empty state after keyboard dismissal") {
            self.visible(self.element("missions-empty")) && !self.app.keyboards.firstMatch.exists
        }
        let reset = element("reset-filters")
        require("The empty state offers a reachable reset action") { self.visible(reset) }
        reset.tap()
        assertMissionCount(30)
        XCTAssertTrue((city.value as? String).map { $0.isEmpty || $0 == "Rechercher une ville" } ?? false,
                      "Reset must clear the city input")
        record("\(prefix)-missions")

        openMissionAndReturn(detailProof: "\(prefix)-detail", returnProof: "\(prefix)-retour")
        XCUIDevice.shared.press(.home)
        require("The pilot actually entered the background") {
            self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended
        }
        app.activate()
        require("Foreground resume preserves the selected list position") {
            self.visible(self.element("mission-card-demo-mission-016"))
        }
        XCTAssertFalse(visible(city), "Foreground resume must not reset the list to its filters")
        signOut()
    }

    /// Runs separately after portrait, using the same signed-out experience without preparation/reset.
    func testLandscapeConsultation() throws {
        proofPrefix = "ipad-paysage"
        app.activate()
        XCUIDevice.shared.orientation = .landscapeLeft
        require("iPad landscape window") { self.app.frame.width > self.app.frame.height }
        assertSignedOutDemo()
        record("ipad-paysage-connexion")
        element("enter-demo").tap()
        assertMissionCount(30)
        record("ipad-paysage-liste")
        openMissionAndReturn(detailProof: "ipad-paysage-detail", returnProof: "ipad-paysage-retour")
        signOut()
    }

    private func prepareExpoGo() {
        // A system URL confirmation may be in SpringBoard, outside Expo's accessibility tree.
        let open = springboard.alerts.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "Open|Ouvrir")
        ).firstMatch
        if open.waitForExistence(timeout: 5) {
            require("The system Expo URL confirmation is hittable") { open.isHittable }
            open.tap()
            require("The system URL confirmation disappeared") { !open.exists }
        }
        app.activate()
        XCUIDevice.shared.orientation = .portrait

        // A fresh Expo Go install must present this sheet. The SDK label behind it is not proof
        // of dismissal. Native Button.tap() resolves its actual control rather than screen pixels.
        let continueButton = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "Continue|Continuer")
        ).firstMatch
        require("The fresh Expo Go tutorial is visible", timeout: 120) { self.visible(continueButton) }
        continueButton.tap()
        require("The Expo tutorial disappeared after one native tap") { !continueButton.exists }

        let sdk = app.staticTexts["SDK version: 57.0.0"]
        require("Expo SDK 57 development menu is visible") { self.visible(sdk) }
        let toolsLabel = app.staticTexts["Tools button"]
        var scrolls = 0
        while toolsSwitch(alongside: toolsLabel) == nil && scrolls < 6 {
            // Expo renders Text(title) and an unlabeled Toggle in the same row. The Text does
            // not handle taps, so locate the real switch by row geometry, then use switch.tap().
            let menu = app.scrollViews.containing(.staticText, identifier: "Tools button").firstMatch
            require("Expo menu is scrollable to its Tools button row") { self.visible(menu) }
            menu.swipeUp()
            scrolls += 1
        }
        guard let tools = toolsSwitch(alongside: toolsLabel) else {
            XCTFail("No hittable native Tools button switch on the matching row")
            return
        }
        let initial = tools.value as? String
        XCTAssertTrue(initial == "0" || initial == "1", "Expo Tools switch must expose a 0/1 state")
        if initial == "1" {
            tools.tap()
        }
        require("Expo floating Tools button is disabled") {
            self.toolsSwitch(alongside: toolsLabel)?.value as? String == "0"
        }
        let close = app.buttons.matching(identifier: "xmark").firstMatch
        require("The Expo menu close button is reachable") { self.visible(close) }
        close.tap()
        require("The development menu is closed and Jolene is visible", timeout: 90) {
            !sdk.exists && self.visible(self.element("enter-demo"))
        }
    }

    private func toolsSwitch(alongside label: XCUIElement) -> XCUIElement? {
        guard visible(label) else { return nil }
        let labelFrame = label.frame
        return app.switches.allElementsBoundByIndex.filter { candidate in
            guard self.visible(candidate) else { return false }
            let frame = candidate.frame
            return frame.minX >= labelFrame.maxX - 2
                && abs(frame.midY - labelFrame.midY) <= max(frame.height, labelFrame.height) / 2
        }.min { $0.frame.width < $1.frame.width }
        // SwiftUI can expose both the row switch and its child; use the narrow actual control.
    }

    private func assertSignedOutDemo() {
        require("The pilot is signed out") { self.visible(self.element("enter-demo")) }
        let banner = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Démo · données fictives")
        ).firstMatch
        require("Synthetic demo data remains explicitly identified") { self.visible(banner) }
    }

    private func assertMissionCount(_ count: Int) {
        require("The native list displays \(count) demo missions") {
            let label = self.element("mission-count")
            return self.visible(self.element("missions-list")) && self.visible(label)
                && label.label.hasPrefix("\(count) missions")
        }
    }

    private func openMissionAndReturn(detailProof: String, returnProof: String) {
        let list = element("missions-list")
        let mission = element("mission-card-demo-mission-016")
        var scrolls = 0
        while !fullyVisible(mission, inside: list) && scrolls < 20 {
            // Coordinates follow the actual native view's current orientation.
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end)
            scrolls += 1
        }
        require("Mission 16 is visible after a bounded scroll") { self.fullyVisible(mission, inside: list) }
        XCTAssertFalse(visible(element("mission-city")), "The list must remain scrolled away from its search field")
        mission.tap()
        let title = element("mission-detail-title")
        require("The selected mission detail is rendered") {
            self.visible(title) && title.label == "Démonstration · Soins de suite 16"
        }
        record(detailProof)

        let window = app.windows.firstMatch
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let destination = window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: destination)
        require("Native back gesture restores mission 16 without resetting list position") { self.visible(mission) }
        XCTAssertFalse(visible(element("mission-city")), "Returning from detail must preserve list position")
        XCTAssertFalse(visible(title), "The detail must be dismissed by the gesture")
        record(returnProof)
    }

    private func signOut() {
        let action = element("sign-out")
        require("The sign-out action is reachable") { self.visible(action) }
        action.tap()
        let confirmation = app.alerts.firstMatch.buttons["Quitter"]
        require("The native sign-out confirmation is visible") { self.visible(confirmation) }
        confirmation.tap()
        require("The pilot returns to its signed-out screen") { self.visible(self.element("enter-demo")) }
        XCTAssertFalse(element("missions-list").exists, "No authenticated mission list may remain after sign-out")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func visible(_ element: XCUIElement) -> Bool {
        element.exists && element.isHittable && !element.frame.isEmpty && app.frame.intersects(element.frame)
    }

    private func fullyVisible(_ element: XCUIElement, inside container: XCUIElement) -> Bool {
        visible(element) && container.frame.insetBy(dx: -1, dy: -1).contains(element.frame)
    }

    private func require(_ description: String, timeout: TimeInterval = 15, condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, description)
    }

    private func attachText(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func record(_ name: String) {
        // Preserve the whole native screen and its orientation metadata without transforming pixels.
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachText(app.debugDescription, name: "\(name)-accessibilite.txt")
    }
}
