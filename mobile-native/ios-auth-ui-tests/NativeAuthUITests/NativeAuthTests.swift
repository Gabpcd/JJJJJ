import XCTest
import UIKit

/// Real Auth TEST only. No account creation, profile save, API request, token
/// injection or business mutation is made by this driver. The tested app uses its
/// ordinary login fields and its ordinary SecureStore-backed session controller.
final class NativeAuthTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "app.jolene.nativepilot")
    private var phases: [String] = []
    private var keyboardIntroductionChecked = false
    private struct Actor: Decodable { let alias: String; let userId: String; let email: String; let password: String }
    private struct Cohort: Decodable { let schemaVersion: Int; let purpose: String; let projectRef: String; let actors: [Actor] }
    private enum CheckError: Error { case failed }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 540
    }

    override func tearDown() {
        UIPasteboard.general.items = []
        // No hierarchy, screenshot, activity text or credential is attached here.
        // XCTest's own automatic attachments remain in the private xcresult only.
        let safe: [String: Any] = ["schemaVersion": 1, "phases": phases]
        if let bytes = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]) {
            let proof = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
            proof.name = "native-auth-proof-v1.json"; proof.lifetime = .keepAlways; add(proof)
        }
        app.terminate()
        super.tearDown()
    }

    func testStagingAuthIsolation() throws {
        // Supplied only to the XCTest runner through an ephemeral 0600 xctestrun
        // generated after build-for-testing. Never supplied to Expo or compiled in.
        guard let privateJSON = ProcessInfo.processInfo.environment["JOLENE_AUTH_COHORT_JSON"],
              let bytes = privateJSON.data(using: .utf8), bytes.count <= 8192,
              let cohort = try? JSONDecoder().decode(Cohort.self, from: bytes),
              cohort.schemaVersion == 1, cohort.purpose == "native-auth-staging-v1",
              cohort.projectRef == "mejpriaetwgtcstbgfid", cohort.actors.count == 2,
              cohort.actors.map({ $0.alias }) == ["A", "B"],
              Set(cohort.actors.map({ $0.email })).count == 2 else {
            XCTFail("Private TEST cohort is missing or invalid"); return
        }
        try prepareCompiledClient()
        let format = ProcessInfo.processInfo.environment["JOLENE_AUTH_FORMAT"] ?? ""
        try check("Reviewed device format") { ["iphone", "ipad-portrait", "ipad-landscape"].contains(format) }
        XCUIDevice.shared.orientation = format == "ipad-landscape" ? .landscapeLeft : .portrait
        try signedOut()
        phases.append("initial_signed_out")
        for index in 0..<2 {
            let actor = cohort.actors[index], other = cohort.actors[1 - index]
            try login(actor)
            try admitted(actor, excluding: other)
            phases.append("\(actor.alias)_login")
            try record("auth-\(actor.alias)-login")
            try restartProcess()
            try admitted(actor, excluding: other)
            phases.append("\(actor.alias)_process_restart")
            try record("auth-\(actor.alias)-restart")
            let leave = element("sign-out")
            try check("Native sign-out control is available") { self.visible(leave) }
            leave.tap()
            let alert = app.alerts["Se déconnecter ?"]
            try check("Sign-out confirmation") { self.visible(alert.buttons["Quitter"]) }
            alert.buttons["Quitter"].tap()
            try signedOut()
            phases.append("\(actor.alias)_logout")
            try restartProcess()
            try signedOut()
            try check("Both prior identities remain absent after local logout and process restart") {
                !self.app.staticTexts[actor.email].exists && !self.app.staticTexts[other.email].exists
            }
            phases.append("\(actor.alias)_logout_process_restart")
        }
    }

    private func login(_ actor: Actor) throws {
        let email = element("login-email"), password = element("login-password")
        try scrollTo(email)
        try paste(actor.email, into: email, secure: false)
        try scrollTo(password)
        try paste(actor.password, into: password, secure: true)
        let signIn = element("sign-in")
        try scrollTo(signIn)
        try check("The normal sign-in button is enabled") { self.visible(signIn) && signIn.isEnabled }
        signIn.tap() // Exactly one submission; failures never retry the credentials.
    }

    private func paste(_ value: String, into field: XCUIElement, secure: Bool) throws {
        UIPasteboard.general.setItems([["public.utf8-plain-text": value]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(30)])
        defer { UIPasteboard.general.items = [] }
        field.tap()
        if !keyboardIntroductionChecked {
            keyboardIntroductionChecked = true
            try dismissFirstKeyboardIntroductionIfPresent()
        }
        field.press(forDuration: 1.0)
        let paste = app.buttons.matching(NSPredicate(format: "label IN %@", ["Paste", "Coller"])).firstMatch
        try check("Native Paste control is available") { self.visible(paste) }
        paste.tap()
        // iOS may ask whether Jolene can paste from the UI-test runner. Authorize
        // this one explicit action only; do not change system-wide privacy settings.
        let allow = app.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Paste", "Autoriser le collage"])).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        try check("The field received the private value without revealing it") {
            guard let actual = field.value as? String else { return false }
            return secure ? !actual.isEmpty : actual == value
        }
    }

    private func admitted(_ actor: Actor, excluding other: Actor) throws {
        try check("Authenticated TEST identity is admitted only to incomplete onboarding", timeout: 90) {
            self.element("account-scroll").exists && self.app.staticTexts[actor.email].exists
                && self.developerOverlaysAbsent()
                && !self.app.staticTexts[other.email].exists
                && self.app.staticTexts["Reprendre mon inscription"].exists
                && self.element("onboarding-start").exists && !self.element("onboarding-save").exists
                && !self.element("onboarding-complete").exists && !self.element("login-email").exists
                && !self.element("missions-list").exists && !self.element("tab-profile").exists
                && !self.element("tab-establishment-home").exists && !self.element("tab-contracts").exists
                && !self.element("enter-demo").exists
                && self.element("account-environment").label == "Environnement TEST · votre compte de test"
        }
    }

    private func signedOut() throws {
        try check("The application shows its TEST login, without a demonstration bypass", timeout: 90) {
            self.element("login-scroll").exists && self.element("login-email").exists
                && self.developerOverlaysAbsent()
                && self.element("login-password").exists && !self.element("account-scroll").exists
                && !self.element("enter-demo").exists && self.app.staticTexts["Environnement TEST"].exists
        }
        try check("No credential is retained in the login fields") {
            let email = self.element("login-email").value as? String ?? ""
            let password = self.element("login-password").value as? String ?? ""
            return (email.isEmpty || email == "vous@exemple.fr") && password.isEmpty
        }
    }

    private func restartProcess() throws {
        app.terminate()
        try check("Jolene process actually stopped") { self.app.state == .notRunning }
        // Exactly four planned restarts, after admission and after logout for A/B.
        // These are persistence assertions, never retries after a failed phase.
        // The local bundle address is public; no session or credentials are
        // injected on restart. SecureStore must restore the ordinary session.
        app.launchArguments = ["-RCT_jsLocation", "127.0.0.1:8090"]
        app.launch() // Same project; no reinstall, storage reset or new login.
        try check("Jolene process returned to foreground") { self.app.state == .runningForeground }
    }

    private func dismissFirstKeyboardIntroductionIfPresent() throws {
        // The bounded keyboard tutorial check belongs to the first Jolene input.
        let introduction = app.otherElements["UIContinuousPathIntroductionView"]
        if introduction.waitForExistence(timeout: 3) {
            let proceed = introduction.buttons["Continue"]
            try check("Initial keyboard tutorial Continue") { self.visible(proceed) }
            proceed.tap()
            try check("Initial keyboard tutorial closed") { !introduction.exists }
        }
    }

    private func prepareCompiledClient() throws {
        // The runner has already launched the compiled source client once. Require its
        // foreground process before the single activation that attaches XCTest
        // and waits for event readiness. Never open its URL or relaunch here.
        try check("Prepared Jolene process is already running") { self.app.state == .runningForeground }
        app.activate()
        XCUIDevice.shared.orientation = .portrait
        try check("Jolene TEST login is mounted without a developer menu", timeout: 120) {
            self.app.state == .runningForeground && self.developerOverlaysAbsent()
                && self.visible(self.element("login-scroll"))
        }
    }

    private func developerOverlaysAbsent() -> Bool {
        let proceed = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Continue|Continuer")).firstMatch
        return !proceed.exists && !app.staticTexts["SDK version: 57.0.0"].exists
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func record(_ name: String) throws {
        // Only called after authenticated onboarding assertions. The synthetic
        // @example.invalid email is permitted; no login field/token is on screen.
        try check("Only the admitted onboarding screen may be captured publicly") {
            self.app.state == .runningForeground && self.app.keyboards.count == 0
                && self.app.alerts.count == 0
                && XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count == 0
                && self.visible(self.element("account-environment"))
                && !self.element("login-email").exists && !self.element("login-password").exists
        }
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
    private func visible(_ element: XCUIElement) -> Bool { element.exists && element.isHittable }
    private func scrollTo(_ field: XCUIElement) throws {
        for _ in 0..<8 { if visible(field) { return }; element("login-scroll").swipeUp() }
        try check("Required login control is reachable") { self.visible(field) }
    }
    private func check(_ message: String, timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            XCTFail(message); throw CheckError.failed
        }
    }
}
