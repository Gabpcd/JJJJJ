import XCTest

/// Drives the existing Expo Go experience; never launches, reloads or resets Jolene.
final class NativePilotTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "host.exp.Exponent")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var proofPrefix = "ipad-portrait"

    override func setUpWithError() throws {
        continueAfterFailure = false
        // One bounded scenario now includes three distinct demo account journeys.
        executionTimeAllowance = 600
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
        runCaregiverWorkflows()
        signOut()
        runEstablishment()
        runSignup()
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
        runCaregiverWorkflows()
        signOut()
        runEstablishment()
        runSignup()
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
        require("The development menu is closed and Jolene is mounted", timeout: 90) {
            !sdk.exists && self.visible(self.element("login-scroll"))
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
        require("The pilot is signed out") { self.visible(self.element("login-scroll")) }
        let banner = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Démo · données fictives")
        ).firstMatch
        scrollTo(banner, in: element("login-scroll"), downward: false)
        require("Synthetic demo data remains explicitly identified") { self.visible(banner) }
        scrollTo(element("enter-demo"), in: element("login-scroll"))
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

        backGesture()
        require("Native back gesture restores mission 16 without resetting list position") { self.visible(mission) }
        XCTAssertFalse(visible(element("mission-city")), "Returning from detail must preserve list position")
        XCTAssertFalse(visible(title), "The detail must be dismissed by the gesture")
        record(returnProof)
    }

    private func runCaregiverWorkflows() {
        tap("tab-my-missions")
        scrollTo(element("my-missions-empty"), in: element("my-missions-list"))
        tap("tab-explore")
        require("Switching tabs preserves the exploration position") { self.visible(self.element("mission-card-demo-mission-016")) }
        XCTAssertFalse(visible(element("mission-city")), "Switching tabs must not reset exploration")
        tap("mission-card-demo-mission-016")
        scrollTo(element("prepare-application"), in: element("mission-detail-scroll"))
        tap("prepare-application")
        let application = element("application-scroll")
        require("The selected mission opens its application") {
            self.visible(self.element("application-title")) && self.element("application-title").label == "Démonstration · Soins de suite 16"
        }
        scrollTo(text("Dates et horaires à confirmer"), in: application)
        scrollTo(text("Horaires de Paris. Tous les créneaux affichés sont concernés."), in: application)
        scrollTo(element("application-submit"), in: application)
        XCTAssertFalse(element("application-submit").isEnabled, "Planning must be confirmed before submitting")
        scrollTo(element("application-confirm-planning"), in: application, downward: false)
        tap("application-confirm-planning")
        scrollTo(element("application-submit"), in: application)
        require("Confirmed planning enables the synthetic application") { self.element("application-submit").isEnabled }
        tap("application-submit")
        require("Submission returns the saved dossier") { self.element("application-confirmed").exists }
        scrollTo(text("Simulation enregistrée"), in: application, downward: false)
        require("The synthetic application is acknowledged explicitly") { self.visible(self.text("Aucune candidature réelle n’a été envoyée.")) }
        scrollTo(element("application-refresh"), in: application)
        tap("application-refresh")
        scrollTo(text("Simulation enregistrée"), in: application, downward: false)
        require("Refreshing the dossier retains its saved application") { self.visible(self.element("application-confirmed")) }
        record("\(proofPrefix)-candidature-confirmee")
        scrollTo(element("application-my-missions"), in: application)
        tap("application-my-missions")
        let mine = element("my-mission-demo-mission-016")
        scrollTo(mine, in: element("my-missions-list"))
        record("\(proofPrefix)-mes-missions")
        mine.tap()
        scrollTo(text("Simulation enregistrée"), in: element("application-scroll"))
        require("The dossier is read again from My missions") { self.visible(self.element("application-confirmed")) }
        record("\(proofPrefix)-dossier-relu")
        scrollTo(element("application-my-missions"), in: element("application-scroll"))
        tap("application-my-missions")
        require("My missions returns from its dossier to the list root") { self.visible(mine) }
        let myList = element("my-missions-list")
        scrollTo(element("my-missions-tab-passees"), in: myList, downward: false)
        tap("my-missions-tab-passees")
        let cancelled = element("my-mission-demo-history-cancelled")
        scrollTo(cancelled, in: myList)
        XCTAssertTrue(cancelled.label.contains("Annulée par l’établissement"), "A historical accepted application must not mask mission cancellation")
        cancelled.tap()
        require("The cancelled mission opens its historical dossier") {
            self.visible(self.element("application-title")) && self.element("application-title").label == "Démonstration · Mission annulée"
        }
        scrollTo(text("Annulée par l’établissement"), in: element("application-scroll"))
        scrollTo(text("Ce dossier présente l’historique de la mission."), in: element("application-scroll"))
        XCTAssertFalse(text("Cette mission vous est attribuée").exists, "A cancelled mission is not an active assignment")
        XCTAssertFalse(element("application-retry-emails").exists, "Historical failed emails must not offer a new send")
        XCTAssertFalse(element("application-submit").exists, "A cancelled mission must not offer a new application")
        record("\(proofPrefix)-mission-annulee")
        scrollTo(element("application-my-missions"), in: element("application-scroll"))
        tap("application-my-missions")
        require("The historical dossier returns to the history list") { self.visible(cancelled) }
        scrollTo(element("my-missions-tab-candidatures"), in: myList, downward: false)
        tap("my-missions-tab-candidatures")
        scrollTo(mine, in: myList)
        tap("tab-explore")
        require("Exploration retains its own application stack") { self.visible(self.element("application-scroll")) }
        backGesture()
        require("Back dismisses the application to its mission") { self.visible(self.element("mission-detail-scroll")) }
        backGesture()
        require("Back restores the original exploration position") { self.visible(self.element("mission-card-demo-mission-016")) }
        XCTAssertFalse(visible(element("mission-city")), "Completing an application must not reset exploration")

        tap("tab-profile")
        let profile = element("caregiver-profile-scroll")
        let bio = element("profile-bio")
        scrollTo(bio, in: profile)
        let expected = "Simulation native \(proofPrefix)"
        // This fixture is one paragraph. Apple's native triple-tap selects it all;
        // a single long press on an unfocused TextView only opens the keyboard.
        // https://support.apple.com/guide/iphone/iph1a9cae52c/ios
        XCTAssertFalse((bio.value as? String ?? "").contains("\n"))
        bio.tap()
        require("The native keyboard is available for profile editing") { self.app.keyboards.firstMatch.exists }
        bio.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        bio.typeText(XCUIKeyboardKey.delete.rawValue)
        require("The entire previous biography was removed") { bio.value as? String == "" }
        bio.typeText(expected)
        require("The new biography is exact before saving") { bio.value as? String == expected }
        scrollTo(element("save-profile"), in: profile)
        tap("save-profile")
        require("Profile save has an explicit confirmation") { self.element("profile-saved").exists }
        scrollTo(element("profile-saved"), in: profile, downward: false)
        require("The keyboard is dismissed after saving") { !self.app.keyboards.firstMatch.exists }
        tap("tab-explore")
        require("Editing the profile retains the exploration position") { self.visible(self.element("mission-card-demo-mission-016")) }
        tap("tab-profile")
        scrollTo(element("caregiver-profile-title"), in: profile, downward: false)
        drag(profile, fromY: 0.25, toY: 0.8) // User pull-to-refresh, not a hidden data mutation.
        scrollTo(bio, in: profile)
        require("The saved biography is read back after tab return and refresh") {
            // Reading a visible TextView does not require a new activation/hit point.
            // XCTest can fail that hit calculation while its text and frame remain readable.
            guard bio.exists else { return false }
            let frame = bio.frame
            return !frame.isEmpty && self.app.frame.contains(frame)
                && profile.frame.insetBy(dx: -1, dy: -1).contains(frame)
                && bio.value as? String == expected
        }
        record("\(proofPrefix)-profil-relu")
    }

    private func runEstablishment() {
        scrollTo(element("enter-establishment-demo"), in: element("login-scroll"))
        tap("enter-establishment-demo")
        let home = element("establishment-home")
        scrollTo(element("establishment-name"), in: home)
        XCTAssertEqual(element("establishment-name").label, "Clinique des Lilas · Démo")
        record("\(proofPrefix)-etablissement-accueil")
        scrollTo(element("establishment-open-missions"), in: home)
        tap("establishment-open-missions")
        let list = element("establishment-missions-list")
        scrollTo(element("establishment-mission-count"), in: list)
        require("The establishment sees all twelve synthetic missions") { self.element("establishment-mission-count").label == "12 missions sur cette page" }
        scrollTo(element("establishment-status-OUVERTE"), in: list, downward: false)
        tap("establishment-status-OUVERTE")
        scrollTo(element("establishment-mission-count"), in: list)
        require("The open filter displays exactly two establishment missions") { self.element("establishment-mission-count").label == "2 missions sur cette page" }
        record("\(proofPrefix)-etablissement-missions")
        let mission = element("establishment-mission-demo-etab-mission-001")
        scrollTo(mission, in: list)
        mission.tap()
        let detail = element("establishment-mission-detail")
        require("The correct establishment mission is shown") {
            self.visible(self.element("establishment-mission-detail-title")) && self.element("establishment-mission-detail-title").label == "Médecine — mission fictive 1"
        }
        scrollTo(textContaining("2 créneaux"), in: detail)
        scrollTo(text("Planning prévisionnel"), in: detail)
        let slotTimes = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{2}:[0-9]{2} — [0-9]{2}:[0-9]{2}"))
        XCTAssertEqual(slotTimes.count, 2, "The detail must render both exact synthetic time slots")
        scrollTo(slotTimes.element(boundBy: 0), in: detail)
        scrollTo(slotTimes.element(boundBy: 1), in: detail)
        scrollTo(text("Horaires de Paris."), in: detail)
        XCTAssertFalse(element("establishment-planning-incomplete").exists, "Both persisted synthetic slots must be rendered")
        record("\(proofPrefix)-etablissement-planning")
        backGesture()
        require("The establishment back gesture preserves the selected card") { self.visible(mission) }
        record("\(proofPrefix)-etablissement-retour")
        scrollTo(element("establishment-mission-count"), in: list, downward: false)
        XCTAssertEqual(element("establishment-mission-count").label, "2 missions sur cette page", "The selected status survives the detail return")
        tap("tab-establishment-profile")
        let profile = element("establishment-profile")
        scrollTo(text("Vos droits dans l’établissement"), in: profile)
        scrollTo(text("Consulter l’établissement"), in: profile)
        require("The declared membership role is visible") { self.visible(self.text("Propriétaire")) }
        scrollTo(text("Autorisé"), in: profile)
        require("The read permission is visible") { self.visible(self.text("Autorisé")) }
        record("\(proofPrefix)-etablissement-acces")
        signOut()
    }

    private func runSignup() {
        scrollTo(element("enter-onboarding-demo"), in: element("login-scroll"))
        tap("enter-onboarding-demo")
        let form = element("account-scroll")
        require("The registration form explicitly uses fictitious data") {
            self.visible(self.element("account-environment")) && self.element("account-environment").label == "Démo · formulaire fictif, aucune donnée envoyée"
        }
        scrollTo(element("onboarding-formation"), in: form)
        tap("onboarding-formation")
        let cycles = app.scrollViews.containing(.button, identifier: "onboarding-formation-MEDECINE_DES").firstMatch
        scrollTo(element("onboarding-formation-MEDECINE_DES"), in: cycles)
        require("Medicine offers its third cycle") { self.visible(self.element("onboarding-formation-MEDECINE_DES")) }
        XCTAssertFalse(element("onboarding-formation-KINE").exists, "Medicine must not offer a physiotherapy degree")
        scrollTo(element("onboarding-formation-MEDECINE_DFASM"), in: cycles, downward: false)
        tap("onboarding-formation-MEDECINE_DFASM")
        scrollTo(element("onboarding-study-year"), in: form)
        scrollTo(element("onboarding-formation"), in: form, downward: false)
        tap("onboarding-formation")
        scrollTo(element("onboarding-formation-MEDECINE_DES"), in: cycles)
        tap("onboarding-formation-MEDECINE_DES")
        scrollTo(element("onboarding-internat-notice"), in: form)
        XCTAssertTrue(element("onboarding-internat-notice").label.contains("Votre droit au remplacement n’est pas validé à cette étape."))
        XCTAssertFalse(element("onboarding-study-year").exists, "Internship is not a first/second cycle year")
        XCTAssertFalse(text("Choisir le profil aide-soignant").exists, "Choosing internship must not imply an aide-soignant equivalence")
        record("\(proofPrefix)-inscription-internat")
        scrollTo(element("onboarding-save"), in: form)
        tap("onboarding-save")
        let saved = text("Brouillon de démonstration conservé en mémoire.")
        require("The registration draft remains on the same screen") { saved.exists && self.element("onboarding-save").exists }
        scrollTo(saved, in: form, downward: false)
        scrollTo(element("onboarding-complete"), in: form)
        tap("onboarding-complete")
        scrollTo(element("mission-count"), in: element("missions-list"))
        assertMissionCount(0)
        scrollTo(element("missions-empty"), in: element("missions-list"))
        XCTAssertFalse(element("mission-card-demo-mission-016").exists, "A declared medical profile must not receive IDE demo missions")
        record("\(proofPrefix)-inscription-terminee")
        signOut()
    }

    private func backGesture() {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
    }

    private func drag(_ container: XCUIElement, fromY: CGFloat, toY: CGFloat) {
        container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
            .press(forDuration: 0.05, thenDragTo: container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY)))
    }

    private func scrollTo(_ target: XCUIElement, in container: XCUIElement, downward: Bool = true) {
        require("The expected scroll container is visible") { self.visible(container) }
        var scrolls = 0
        while !fullyVisible(target, inside: container) && scrolls < 20 {
            drag(container, fromY: downward ? 0.8 : 0.25, toY: downward ? 0.25 : 0.8)
            scrolls += 1
        }
        require("The requested control is fully visible after bounded scrolling") { self.fullyVisible(target, inside: container) }
    }

    private func tap(_ identifier: String) {
        let target = element(identifier)
        require("Control \(identifier) is reachable") { self.visible(target) && target.isEnabled }
        target.tap()
    }

    private func text(_ label: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch }
    private func textContaining(_ label: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch }

    private func signOut() {
        let action = element("sign-out")
        require("The sign-out action is reachable") { self.visible(action) }
        action.tap()
        let confirmation = app.alerts.firstMatch.buttons["Quitter"]
        require("The native sign-out confirmation is visible") { self.visible(confirmation) }
        confirmation.tap()
        assertSignedOutDemo()
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
