import XCTest

/// Exercises the existing Expo Go session. The preceding portrait flow must leave it signed out.
final class NativePilotLandscapeTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "host.exp.Exponent")

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        app.activate()
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            record("ipad-paysage-echec")
        }
    }

    func testLandscapeConsultation() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        require("iPad landscape window") { self.app.frame.width > self.app.frame.height }

        let enterDemo = element("enter-demo")
        require("The preceding portrait flow left the pilot signed out") { self.visible(enterDemo) }
        let demoBanner = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Démo · données fictives")).firstMatch
        require("Synthetic demo data remains explicitly identified") { self.visible(demoBanner) }
        record("ipad-paysage-connexion")
        enterDemo.tap()

        let list = element("missions-list")
        let count = element("mission-count")
        require("The native list displays all 30 demo missions") {
            self.visible(list) && self.visible(count) && count.label.hasPrefix("30 missions")
        }
        record("ipad-paysage-liste")

        let mission = element("mission-card-demo-mission-016")
        var scrolls = 0
        while !fullyVisible(mission, inside: list) && scrolls < 20 {
            // Coordinates are relative to the current landscape list, never portrait device pixels.
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
        record("ipad-paysage-detail")

        let window = app.windows.firstMatch
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let destination = window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: destination)
        require("Native back gesture restores mission 16 without resetting list position") { self.visible(mission) }
        XCTAssertFalse(visible(element("mission-city")), "Returning from detail must preserve list position")
        XCTAssertFalse(visible(title), "The detail must be dismissed by the gesture")
        record("ipad-paysage-retour")

        let signOut = element("sign-out")
        require("The sign-out action is reachable") { self.visible(signOut) }
        signOut.tap()
        let confirmation = app.alerts.firstMatch.buttons["Quitter"]
        require("The native sign-out confirmation is visible") { self.visible(confirmation) }
        confirmation.tap()
        require("The pilot returns to its signed-out screen") { self.visible(enterDemo) }
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

    private func record(_ name: String) {
        let screenshot = XCTAttachment(data: app.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-accessibilite.txt"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
