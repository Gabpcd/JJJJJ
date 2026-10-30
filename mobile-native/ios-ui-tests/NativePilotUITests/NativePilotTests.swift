import XCTest

/// Drives the prepared CI experience without launching, reopening or resetting it.
final class NativePilotTests: XCTestCase {
    private let targetBundle = ProcessInfo.processInfo.environment["JOLENE_TEST_APP_ID"] ?? "host.exp.Exponent"
    private let homeIcon = ProcessInfo.processInfo.environment["JOLENE_TEST_HOME_ICON"] ?? "Expo Go"
    private lazy var app = XCUIApplication(bundleIdentifier: targetBundle)
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var proofPrefix = "ipad-portrait"
    private var backgroundStates: [UInt] = []
    private var dismissedDebuggerMigrationBanner = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ["host.exp.Exponent", "app.jolene.nativepilot"].contains(targetBundle),
              !homeIcon.isEmpty, homeIcon.count <= 100, !homeIcon.contains("$("),
              !homeIcon.contains("\n"), !homeIcon.contains("\r"),
              targetBundle != "host.exp.Exponent" || homeIcon == "Expo Go" else {
            XCTFail("The runner must identify the prepared app and its Home icon explicitly")
            return
        }
        // Each selected consultation, Documents, Contracts or Presence scenario has its own bounded budget.
        executionTimeAllowance = 600
    }

    override func tearDownWithError() throws {
        // hasSucceeded is still false during teardown; count only failures already recorded.
        if (testRun?.totalFailureCount ?? 0) > 0 {
            attachText("Expo state: \(app.state.rawValue); SpringBoard state: \(springboard.state.rawValue)",
                       name: "\(proofPrefix)-process-state.txt")
            attachText("States before and after Home: \(backgroundStates)",
                       name: "\(proofPrefix)-background-states.txt")
            record("\(proofPrefix)-echec")
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "\(proofPrefix)-echec-ecran-systeme"
            screen.lifetime = .keepAlways
            add(screen)
            attachText(springboard.debugDescription, name: "\(proofPrefix)-echec-springboard.txt")
        }
    }

    /// The runner launches a fresh Expo Go; XCTest activates its prepared experience.
    func testPortraitConsultation() throws {
        runPortraitConsultation(prefix: "ipad-portrait", deviceName: "iPad")
    }

    /// Uses the identical portrait assertions on a separate fresh iPhone simulator.
    func testIphoneConsultation() throws {
        runPortraitConsultation(prefix: "iphone-portrait", deviceName: "iPhone")
    }

    private func runPortraitConsultation(prefix: String, deviceName: String) {
        // Both roles plus signup share one test; individual screen deadlines stay at 15s.
        executionTimeAllowance = 900
        proofPrefix = prefix
        prepareExpoGo()
        XCUIDevice.shared.orientation = .portrait
        require("\(deviceName) portrait window") { self.app.frame.height > self.app.frame.width }
        assertSignedOutDemo()
        record("\(prefix)-connexion")
        tap("enter-demo")
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
        dismissFirstKeyboardIntroductionIfPresent()
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
        backgroundStates = [app.state.rawValue]
        XCUIDevice.shared.press(.home)
        require("The pilot actually entered the background") {
            let state = self.app.state
            if self.backgroundStates.last != state.rawValue && self.backgroundStates.count < 16 {
                self.backgroundStates.append(state.rawValue)
            }
            return state == .runningBackground || state == .runningBackgroundSuspended
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
        executionTimeAllowance = 900
        proofPrefix = "ipad-paysage"
        app.activate()
        XCUIDevice.shared.orientation = .landscapeLeft
        require("iPad landscape window") { self.app.frame.width > self.app.frame.height }
        assertSignedOutDemo()
        record("ipad-paysage-connexion")
        tap("enter-demo")
        assertMissionCount(30)
        record("ipad-paysage-liste")
        openMissionAndReturn(detailProof: "ipad-paysage-detail", returnProof: "ipad-paysage-retour")
        runCaregiverWorkflows()
        signOut()
        runEstablishment()
        runSignup()
    }


    // Dedicated synthetic attendance runtime. The manual code, not the previously
    // opened detail, selects the mission. No physical QR or GPS claim is made.
    func testPresenceIphonePortrait() throws { runPresence(prefix: "iphone-portrait", landscape: false) }
    func testPresenceIpadPortrait() throws { runPresence(prefix: "ipad-portrait", landscape: false) }
    func testPresenceIpadLandscape() throws { runPresence(prefix: "ipad-paysage", landscape: true) }

    private func runPresence(prefix: String, landscape: Bool) {
        proofPrefix = prefix
        prepareExpoGo()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        require("Presence starts in the requested orientation") {
            landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width
        }
        assertSignedOutDemo()
        tap("enter-demo")
        assertMissionCount(30)
        tap("tab-presence")
        let list = element("presence-list-scroll")
        let detail = element("presence-detail-scroll")
        let scan = element("presence-scan-scroll")
        require("The synthetic presence list is displayed") {
            self.visible(list) && self.element("presence-demo-notice").exists
        }
        scrollTo(element("presence-mission-demo-presence-a"), in: list)
        XCTAssertTrue(element("presence-mission-demo-presence-a").label.contains("Mission A fictive"))
        record("\(prefix)-presences-liste")
        tap("presence-mission-demo-presence-a")
        require("The chosen detail is mission A") { self.element("presence-detail-title").label == "Mission A fictive" }
        scrollTo(element("presence-scan-count"), in: detail)
        XCTAssertEqual(element("presence-scan-count").label, "0")
        XCTAssertEqual(element("presence-state-label").label, "Aucune présence ouverte")
        record("\(prefix)-presences-mission-avant")
        scrollTo(element("presence-detail-open-scan"), in: detail)
        tap("presence-detail-open-scan")
        require("Manual attendance entry is mounted") { self.visible(scan) }
        XCTAssertFalse(element("presence-open-camera").exists)
        XCTAssertFalse(element("presence-gps-choice").exists)
        enterPresenceCode("000000", in: scan)
        require("A synthetic authentication refusal is explicit") { self.element("presence-rejected").exists }
        scrollTo(element("presence-rejected"), in: scan, downward: false)
        XCTAssertTrue(textContaining("La connexion a été refusée avant l’enregistrement du pointage").exists)
        XCTAssertFalse(element("presence-pending").exists)
        XCTAssertFalse(element("presence-confirmed").exists)
        record("\(prefix)-presences-auth-refusee")
        scrollTo(element("presence-code-input"), in: scan)
        XCTAssertTrue(element("presence-code-input").isEnabled, "A definitive refusal must not leave an uncertain journal")
        enterPresenceCode("654321", in: scan)
        require("The first synthetic write has an explicitly uncertain result") { self.element("presence-unconfirmed").exists }
        scrollTo(element("presence-unconfirmed"), in: scan, downward: false)
        XCTAssertTrue(textContaining("Démonstration d’une réponse perdue").exists)
        record("\(prefix)-presences-confirmation-incertaine")
        scrollTo(element("presence-submit"), in: scan)
        XCTAssertFalse(element("presence-submit").isEnabled, "The pending receipt must forbid a second scan")

        tap("tab-explore")
        require("The separate missions tab is usable") { self.visible(self.element("missions-list")) }
        tap("tab-presence")
        require("Tab return retains the attendance route") { self.visible(scan) }
        XCUIDevice.shared.press(.home)
        require("Presence actually entered background") {
            self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended
        }
        app.activate()
        require("Presence resumes and rereads its pending receipt") { self.visible(scan) && self.element("presence-pending").exists }
        scrollTo(element("presence-pending"), in: scan, downward: false)
        XCTAssertFalse(element("presence-confirmed").exists, "Resume must not manufacture a successful scan")
        XCTAssertTrue(textContaining("Ne saisissez pas de nouveau code").exists)
        XCTAssertFalse(element("presence-code-input").isEnabled)
        XCTAssertFalse(element("presence-submit").isEnabled)
        record("\(prefix)-presences-reprise")
        scrollTo(element("presence-reconcile"), in: scan)
        tap("presence-reconcile")
        require("Read-only reconciliation confirms the existing synthetic arrival") { self.element("presence-confirmed").exists }
        scrollTo(element("presence-actual-mission"), in: scan, downward: false)
        XCTAssertEqual(element("presence-actual-mission").label, "Mission B fictive", "The result must identify B despite opening A")
        XCTAssertTrue(text("Simulation enregistrée").exists)
        scrollTo(element("presence-confirmed-time"), in: scan)
        XCTAssertTrue(text("Arrivée").exists)
        XCTAssertEqual(element("presence-confirmed-time").label, "27 octobre 2026 à 11:00")
        XCTAssertFalse(element("presence-pending").exists)
        record("\(prefix)-presences-arrivee-relue")
        scrollTo(element("presence-open-actual-mission"), in: scan)
        tap("presence-open-actual-mission")
        require("The result opens B, not the original A screen") { self.element("presence-detail-title").label == "Mission B fictive" }
        scrollTo(element("presence-scan-count"), in: detail)
        XCTAssertEqual(element("presence-state-label").label, "Présence ouverte")
        XCTAssertEqual(element("presence-scan-count").label, "1", "Reconciliation and resume must not create another proof")
        record("\(prefix)-presences-ouverte")
        scrollTo(element("presence-detail-open-scan"), in: detail)
        tap("presence-detail-open-scan")
        enterPresenceCode("654321", in: scan)
        require("The previous code is refused after rotation") { self.element("presence-rejected").exists }
        scrollTo(element("presence-rejected"), in: scan, downward: false)
        XCTAssertTrue(textContaining("Ce code fictif est invalide ou a déjà été renouvelé").exists)
        XCTAssertFalse(element("presence-confirmed").exists)
        XCTAssertFalse(element("presence-pending").exists)
        record("\(prefix)-presences-code-obsolete")
        enterPresenceCode("100001", in: scan)
        require("The renewed code confirms the synthetic departure") { self.element("presence-confirmed").exists }
        scrollTo(element("presence-actual-mission"), in: scan, downward: false)
        XCTAssertEqual(element("presence-actual-mission").label, "Mission B fictive")
        scrollTo(element("presence-confirmed-time"), in: scan)
        XCTAssertTrue(text("Départ").exists)
        XCTAssertEqual(element("presence-confirmed-time").label, "27 octobre 2026 à 11:03")
        record("\(prefix)-presences-depart-relu")
        scrollTo(element("presence-open-actual-mission"), in: scan)
        tap("presence-open-actual-mission")
        require("Departure links to the same mission B") { self.element("presence-detail-title").label == "Mission B fictive" }
        scrollTo(element("presence-scan-count"), in: detail)
        XCTAssertEqual(element("presence-state-label").label, "Aucune présence ouverte")
        XCTAssertEqual(element("presence-scan-count").label, "2")
        scrollTo(element("presence-effective-demo-presence-effective-1"), in: detail)
        XCTAssertTrue(text("27 octobre 2026 à 11:00").exists)
        XCTAssertTrue(text("27 octobre 2026 à 11:03").exists)
        XCTAssertFalse(text("Pas encore enregistré").exists)
        record("\(prefix)-presences-cloturee")
        signOut()
        XCTAssertFalse(scan.exists)
        XCTAssertFalse(detail.exists)

        // The establishment has its own identity. It reads the shared synthetic
        // mission world, never a fabricated UI-only counter or a real server.
        scrollTo(element("enter-establishment-demo"), in: element("login-scroll"))
        tap("enter-establishment-demo")
        tap("tab-presence")
        require("Establishment presence list is mounted") { self.visible(list) }
        XCTAssertFalse(element("presence-open-scan").exists)
        scrollTo(element("presence-mission-demo-presence-a"), in: list)
        tap("presence-mission-demo-presence-a")
        require("The unrelated mission A remains readable") { self.element("presence-detail-title").label == "Mission A fictive" }
        scrollTo(element("presence-scan-count"), in: detail)
        XCTAssertEqual(element("presence-scan-count").label, "0", "Opening A must not attach B's pointages to A")
        scrollTo(element("presence-establishment-code"), in: detail)
        XCTAssertEqual(element("presence-establishment-code").label, "Code de pointage 1 2 3 4 5 6")
        scrollTo(element("presence-establishment-qr"), in: detail)
        require("The establishment QR is visible") { self.visible(self.element("presence-establishment-qr")) }
        record("\(prefix)-presences-code-initial")
        backGesture()
        require("Return from A restores the establishment list") { self.visible(list) }
        scrollTo(element("presence-mission-demo-presence-b"), in: list)
        tap("presence-mission-demo-presence-b")
        require("The establishment reads its mission B") { self.element("presence-detail-title").label == "Mission B fictive" }
        scrollTo(element("presence-scan-count"), in: detail)
        XCTAssertEqual(element("presence-scan-count").label, "2")
        scrollTo(element("presence-establishment-code"), in: detail)
        XCTAssertEqual(element("presence-establishment-code").label, "Code de pointage 1 0 0 0 0 2")
        XCTAssertTrue(text("Code fictif relu en mémoire.").exists)
        XCTAssertFalse(element("presence-detail-open-scan").exists)
        scrollTo(element("presence-establishment-qr"), in: detail)
        require("The renewed establishment QR is visible") { self.visible(self.element("presence-establishment-qr")) }
        record("\(prefix)-presences-code-renouvele")
        backGesture()
        require("The native back gesture returns to the same establishment list position") {
            self.visible(list) && self.visible(self.element("presence-mission-demo-presence-b"))
        }
        XCTAssertTrue(element("presence-mission-demo-presence-b").label.contains("En cours"))
        record("\(prefix)-presences-retour-etablissement")
        signOut()
        XCTAssertFalse(element("presence-establishment-code").exists)
        XCTAssertFalse(list.exists)
    }

    private func enterPresenceCode(_ code: String, in scan: XCUIElement) {
        scrollTo(element("presence-code-input"), in: scan)
        require("The journal allows a new explicit manual scan") { self.element("presence-code-input").isEnabled }
        tap("presence-code-input")
        element("presence-code-input").typeText(code)
        XCTAssertEqual(element("presence-code-input").value as? String, code)
        // iOS interactive dismissal follows a downward drag; an upward scroll
        // does not promise to close its number pad. Use the visible Done action
        // already provided by this TextInput's returnKeyType, on both devices.
        let done = app.toolbars.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Done", "Terminé"))
        require("The native number pad exposes one reachable Done action") {
            done.count == 1 && self.visible(done.firstMatch) && done.firstMatch.isEnabled
        }
        done.firstMatch.tap()
        require("The native keyboard is dismissed before confirmation") { !self.app.keyboards.firstMatch.exists }
        XCTAssertEqual(element("presence-code-input").value as? String, code, "Done must preserve the six digits without submitting them")
        scrollTo(element("presence-submit"), in: scan)
        tap("presence-submit")
    }

    // Each Contracts scenario starts in a fresh demo runtime with the explicit
    // EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO=1 flag. No provider is contacted.
    func testContractsIphonePortrait() throws { runContracts(prefix: "iphone-portrait", landscape: false) }
    func testContractsIpadPortrait() throws { runContracts(prefix: "ipad-portrait", landscape: false) }
    func testContractsIpadLandscape() throws { runContracts(prefix: "ipad-paysage", landscape: true) }

    // app.state is retained as a diagnostic: iPad may report both apps foreground
    // while SpringBoard is visibly showing its full Home screen.
    private func springboardShowsHome() -> Bool {
        let home = springboard.otherElements.matching(identifier: "Home screen icons").firstMatch
        guard home.exists, !home.frame.isEmpty, !springboard.frame.isEmpty,
              springboard.frame.insetBy(dx: -1, dy: -1).contains(home.frame),
              home.frame.width >= springboard.frame.width - 2,
              home.frame.height >= springboard.frame.height - 2 else { return false }
        return springboard.descendants(matching: .icon).matching(identifier: homeIcon)
            .allElementsBoundByIndex.contains { icon in
                icon.exists && icon.isHittable && !icon.frame.isEmpty && home.frame.contains(icon.frame)
            }
    }

    private func contractsHomeRoundTrip(prefix: String, detail: XCUIElement) -> Bool {
        let proofID = UUID().uuidString
        var markers: [[String: Any]] = []
        var homePresses = 0
        var activations = 0
        func mark(_ stage: String, _ observations: [String: Any] = [:]) {
            var marker = observations
            marker["stage"] = stage
            marker["atMs"] = Int64(Date().timeIntervalSince1970 * 1000)
            marker["expoState"] = app.state.rawValue
            marker["springboardState"] = springboard.state.rawValue
            markers.append(marker)
        }
        defer {
            let proof: [String: Any] = ["schemaVersion": 1, "id": proofID, "prefix": prefix,
                "homePresses": homePresses, "activations": activations, "markers": markers]
            if let bytes = try? JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys]),
               let json = String(data: bytes, encoding: .utf8) {
                attachText(json, name: "\(prefix)-contrats-home-oracle.json")
            } else { XCTFail("Home proof could not be recorded") }
        }
        let alreadyHome = springboardShowsHome()
        XCTAssertFalse(alreadyHome, "Home must not be visible before the one Home press")
        guard !alreadyHome else { return false }
        guard element("contract-otp").value as? String == "000000" else {
            XCTFail("The six typed digits must still be present immediately before Home"); return false
        }
        mark("armed", ["homeVisible": false, "codeLength": 6])
        homePresses += 1
        XCUIDevice.shared.press(.home)
        require("The one Home press shows SpringBoard Home icons") { self.springboardShowsHome() }
        guard springboardShowsHome() else { return false }
        mark("home-visible", ["homeVisible": true])
        let homeCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        homeCapture.name = "\(prefix)-contrats-home"
        homeCapture.lifetime = .keepAlways
        add(homeCapture)
        attachText(springboard.debugDescription, name: "\(prefix)-contrats-home-accessibilite.txt")
        mark("activate")
        activations += 1
        app.activate()
        require("The contract is reread after resume") { self.element("contract-original").exists && !self.app.keyboards.firstMatch.exists }
        scrollTo(element("contract-request-otp"), in: detail)
        let consentEnabled = element("contract-request-otp").isEnabled
        XCTAssertFalse(consentEnabled, "Consent must be reset after backgrounding")
        scrollTo(element("contract-otp"), in: detail)
        let cleared = (element("contract-otp").value as? String).map { $0.isEmpty || $0 == "6 chiffres" } ?? false
        XCTAssertTrue(cleared, "The previously typed code must not survive resume")
        let homeVisible = springboardShowsHome()
        let originalVisible = element("contract-original").exists
        XCTAssertFalse(homeVisible, "The contract must replace Home after the one activation")
        mark("resumed", ["homeVisible": homeVisible, "codeLength": cleared ? 0 : -1,
                         "consentEnabled": consentEnabled, "originalVisible": originalVisible])
        return cleared && !consentEnabled && originalVisible && !homeVisible
    }

    private func runContracts(prefix: String, landscape: Bool) {
        proofPrefix = prefix
        prepareExpoGo()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        require("Contracts starts in the requested orientation") {
            landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width
        }
        assertSignedOutDemo()
        tap("enter-demo")
        assertMissionCount(30)
        tap("tab-contracts")
        require("One synthetic contract is listed") {
            self.visible(self.element("contracts-list")) && self.element("contracts-count").label.hasPrefix("1 contrat")
        }
        XCTAssertTrue(text("Démo · données fictives").exists)
        record("\(prefix)-contrats-liste")
        tap("contract-card-00000000-0000-4000-8000-000000000021")
        let detail = element("contract-detail-scroll")
        require("The synthetic contract is explicitly identified") { self.visible(self.element("contract-demo-notice")) }
        XCTAssertTrue(element("contract-number").label.contains("DEMO-CONTRAT-001"))
        scrollTo(element("contract-original-end"), in: detail)
        XCTAssertTrue(element("contract-original-end").label.contains("DOCUMENT FICTIF — AUCUN ENGAGEMENT RÉEL"))
        XCTAssertTrue(element("contract-original-end").label.contains("Dernière ligne : l’employeur fictif dit 'oui'."))
        record("\(prefix)-contrats-original")
        scrollTo(element("contract-request-otp"), in: detail)
        XCTAssertFalse(element("contract-request-otp").isEnabled, "Reading does not accept the contract")
        scrollTo(element("contract-consent"), in: detail, downward: false)
        tap("contract-consent")
        scrollTo(element("contract-request-otp"), in: detail)
        tap("contract-request-otp")
        require("The single caregiver code request rendered its synthetic response before scrolling") {
            self.element("contract-demo-code").exists
        }
        scrollTo(element("contract-demo-code"), in: detail)
        XCTAssertTrue(element("contract-demo-code").label.contains("000000"))
        XCTAssertTrue(element("contract-demo-code").label.contains("Aucun SMS envoyé"))
        record("\(prefix)-contrats-otp-simule")
        scrollTo(element("contract-otp"), in: detail)
        tap("contract-otp")
        dismissFirstKeyboardIntroductionIfPresent()
        guard typeContractCode() else { return }
        XCTAssertEqual(element("contract-otp").value as? String, "000000", "The six typed digits are exact before any further action")
        guard contractsHomeRoundTrip(prefix: prefix, detail: detail) else { return }
        record("\(prefix)-contrats-reprise")
        scrollTo(element("contract-consent"), in: detail, downward: false)
        tap("contract-consent")
        scrollTo(element("contract-otp"), in: detail)
        tap("contract-otp")
        guard typeContractCode() else { return }
        XCTAssertEqual(element("contract-otp").value as? String, "000000", "The six typed digits are exact before any further action")
        // Dragging the native ScrollView dismisses the numeric keyboard if needed.
        scrollTo(element("contract-sign"), in: detail)
        XCTAssertEqual(element("contract-otp").value as? String, "000000", "Scrolling to the signature preserves all six typed digits")
        tap("contract-sign")
        scrollTo(element("contract-result-unconfirmed"), in: detail, downward: false)
        XCTAssertTrue(element("contract-result-message").label.contains("Simulation"))
        XCTAssertFalse(element("contract-sign").isEnabled, "An uncertain response must not offer a second signature")
        record("\(prefix)-contrats-signature-incertaine")
        scrollTo(element("contract-reconcile"), in: detail)
        tap("contract-reconcile")
        require("Signature reread completed") { self.element("contract-status").label == "Signé par le soignant" }
        scrollTo(element("contract-signature-soignant"), in: detail, downward: false)
        XCTAssertTrue(element("contract-signature-soignant").label.contains("Soignant : Signé"))
        XCTAssertFalse(element("contract-consent").exists)
        XCTAssertFalse(element("contract-sign").exists)
        record("\(prefix)-contrats-signature-relue")
        backGesture()
        require("Native back returns to the contract list") { self.visible(self.element("contracts-list")) }
        XCTAssertTrue(element("contract-card-00000000-0000-4000-8000-000000000021").label.contains("Signé par le soignant"))
        signOut()

        scrollTo(element("enter-contracts-readonly-demo"), in: element("login-scroll"))
        tap("enter-contracts-readonly-demo")
        tap("tab-contracts")
        require("Read-only establishment can list its synthetic contract") {
            self.visible(self.element("contract-card-00000000-0000-4000-8000-000000000021"))
        }
        tap("contract-card-00000000-0000-4000-8000-000000000021")
        scrollTo(element("contract-original-end"), in: detail)
        XCTAssertTrue(element("contract-original-end").label.contains("Dernière ligne"))
        scrollTo(element("contract-read-only"), in: detail)
        XCTAssertFalse(element("contract-consent").exists)
        XCTAssertFalse(element("contract-request-otp").exists)
        XCTAssertFalse(element("contract-sign").exists)
        record("\(prefix)-contrats-lecture-seule")
        signOut()
        XCTAssertFalse(element("contract-original").exists)
        XCTAssertFalse(element("contract-detail-scroll").exists)

        scrollTo(element("enter-establishment-demo"), in: element("login-scroll"))
        tap("enter-establishment-demo")
        tap("tab-contracts")
        require("Authorized establishment sees the first party signature") {
            self.element("contract-card-00000000-0000-4000-8000-000000000021").label.contains("Signé par le soignant")
        }
        tap("contract-card-00000000-0000-4000-8000-000000000021")
        scrollTo(element("contract-original-end"), in: detail)
        XCTAssertTrue(element("contract-original-end").label.contains("Dernière ligne"))
        scrollTo(element("contract-request-otp"), in: detail)
        XCTAssertFalse(element("contract-request-otp").isEnabled)
        scrollTo(element("contract-consent"), in: detail, downward: false)
        tap("contract-consent")
        scrollTo(element("contract-request-otp"), in: detail)
        tap("contract-request-otp")
        require("The single establishment code request rendered its synthetic response before scrolling") {
            self.element("contract-demo-code").exists
        }
        scrollTo(element("contract-demo-code"), in: detail)
        XCTAssertTrue(element("contract-demo-code").label.contains("000000"))
        XCTAssertTrue(element("contract-demo-code").label.contains("Aucun SMS envoyé"))
        scrollTo(element("contract-otp"), in: detail)
        tap("contract-otp")
        guard typeContractCode() else { return }
        XCTAssertEqual(element("contract-otp").value as? String, "000000", "The six typed digits are exact before any further action")
        scrollTo(element("contract-sign"), in: detail)
        XCTAssertEqual(element("contract-otp").value as? String, "000000", "Scrolling to the signature preserves all six typed digits")
        tap("contract-sign")
        scrollTo(element("contract-result-unconfirmed"), in: detail, downward: false)
        XCTAssertFalse(element("contract-sign").isEnabled)
        scrollTo(element("contract-reconcile"), in: detail)
        tap("contract-reconcile")
        require("Both synthetic signatures are reread") { self.element("contract-status").label == "Signé par les deux parties" }
        scrollTo(element("contract-signature-soignant"), in: detail, downward: false)
        XCTAssertTrue(element("contract-signature-soignant").label.contains("Soignant : Signé"))
        XCTAssertTrue(element("contract-signature-etablissement").label.contains("Établissement : Signé"))
        XCTAssertFalse(element("contract-consent").exists)
        XCTAssertFalse(element("contract-sign").exists)
        record("\(prefix)-contrats-deux-signatures")
        backGesture()
        require("List retains both signatures") {
            self.visible(self.element("contracts-list")) && self.element("contract-card-00000000-0000-4000-8000-000000000021").label.contains("Signé par les deux parties")
        }
        signOut()
        XCTAssertFalse(element("contract-original").exists)
    }

    // Selected independently by the Documents CI jobs. Each orientation receives a fresh
    // simulator/runtime; no hidden reset, existing 1091 journey, or personal file is required.
    func testDocumentsIphonePortrait() throws {
        runDocuments(prefix: "iphone-portrait", landscape: false)
    }

    func testDocumentsIpadPortrait() throws {
        runDocuments(prefix: "ipad-portrait", landscape: false)
    }

    func testDocumentsIpadLandscape() throws {
        runDocuments(prefix: "ipad-paysage", landscape: true)
    }

    private func runDocuments(prefix: String, landscape: Bool) {
        proofPrefix = prefix
        prepareExpoGo()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        require("Documents starts in the requested orientation") {
            landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width
        }
        assertSignedOutDemo()
        tap("enter-demo")
        assertMissionCount(30)
        tap("tab-profile")
        scrollTo(element("profile-documents"), in: element("caregiver-profile-scroll"))
        tap("profile-documents")

        let documents = element("documents-scroll")
        require("The native document dossier is loaded") { self.visible(self.element("documents-title")) }
        XCTAssertTrue(text("Démo · données fictives").exists)
        scrollTo(element("document-status-DIPLOME"), in: documents)
        XCTAssertEqual(element("document-status-DIPLOME").label, "Vérifié")
        XCTAssertFalse(element("document-view-DIPLOME").exists, "The synthetic demo must not pretend to open an original")
        record("\(prefix)-documents-statuts")
        scrollTo(element("document-status-CARTE_IDENTITE"), in: documents)
        XCTAssertEqual(element("document-status-CARTE_IDENTITE").label, "Rejeté")
        scrollTo(element("document-status-RIB"), in: documents)
        XCTAssertEqual(element("document-status-RIB").label, "En attente de vérification")
        scrollTo(element("document-review-CARTE_IDENTITE"), in: documents, downward: false)
        tap("document-review-CARTE_IDENTITE")
        let reviewAlert = app.alerts["Demander une revue humaine ?"]
        require("Human review needs an explicit native confirmation") { reviewAlert.exists && reviewAlert.buttons["Demander la revue"].isHittable }
        reviewAlert.buttons["Demander la revue"].tap()
        scrollTo(element("document-status-CARTE_IDENTITE"), in: documents)
        require("A requested review is pending, never verified automatically") {
            self.element("document-status-CARTE_IDENTITE").label == "En cours de vérification"
        }
        scrollTo(textContaining("Demande reçue — en attente d’attribution"), in: documents)
        XCTAssertTrue(textContaining("pour la revue humaine.").exists)
        record("\(prefix)-documents-revue-humaine")

        // The first synthetic selection is deliberately cancelled: the old record remains.
        scrollTo(element("document-replace-DIPLOME"), in: documents, downward: false)
        tap("document-replace-DIPLOME")
        let upload = element("document-upload-scroll")
        require("Replacement opens the native upload sheet") { self.element("document-upload-title").exists && self.element("document-upload-title").label == "Remplacer le justificatif" }
        scrollTo(element("document-pick-file"), in: upload)
        tap("document-pick-file")
        scrollTo(text("remplacement-annule-demo.png"), in: upload)
        XCTAssertTrue(visible(text("remplacement-annule-demo.png")))
        scrollTo(element("document-upload-cancel"), in: upload)
        tap("document-upload-cancel")
        require("Cancelling closes the sheet without an upload") { !self.element("document-upload-title").exists }
        scrollTo(text("Simulation — DIPLOME"), in: documents, downward: false)
        XCTAssertTrue(visible(text("Simulation — DIPLOME")))
        record("\(prefix)-documents-remplacement-annule")

        scrollTo(element("document-replace-DIPLOME"), in: documents)
        tap("document-replace-DIPLOME")
        scrollTo(element("document-pick-file"), in: upload)
        tap("document-pick-file")
        scrollTo(text("diplome-remplace-demo.png"), in: upload)
        XCTAssertTrue(visible(text("diplome-remplace-demo.png")))
        let label = element("document-upload-label")
        scrollTo(label, in: upload)
        label.tap()
        dismissFirstKeyboardIntroductionIfPresent()
        label.typeText("Simulation diplome remplace")
        XCTAssertEqual(label.value as? String, "Simulation diplome remplace")
        drag(upload, fromY: 0.8, toY: 0.25)
        require("A user scroll dismisses the upload keyboard") { !self.app.keyboards.firstMatch.exists }
        scrollTo(element("document-upload-submit"), in: upload)
        tap("document-upload-submit")
        require("The confirmed replacement closes the sheet") { !self.element("document-upload-title").exists }
        scrollTo(element("document-status-DIPLOME"), in: documents)
        require("The replacement receives its separate synthetic verification") { self.element("document-status-DIPLOME").label == "Vérifié" }
        scrollTo(text("Simulation diplome remplace"), in: documents, downward: false)
        XCTAssertTrue(visible(text("Simulation diplome remplace")))
        XCTAssertFalse(text("Simulation — DIPLOME").exists, "The cancelled original label must be replaced only after explicit submit")
        record("\(prefix)-documents-remplacement-confirme")

        // The next injected in-memory commit loses its response. No retry may send the file again.
        scrollTo(element("document-add-RCP_ASSURANCE"), in: documents)
        tap("document-add-RCP_ASSURANCE")
        scrollTo(element("document-pick-file"), in: upload)
        tap("document-pick-file")
        scrollTo(text("rcp-incertaine-demo.png"), in: upload)
        XCTAssertTrue(visible(text("rcp-incertaine-demo.png")))
        scrollTo(element("document-upload-submit"), in: upload)
        tap("document-upload-submit")
        require("The uncertain response is explicitly displayed") { self.textContaining("Simulation : réponse interrompue").exists }
        scrollTo(textContaining("Simulation : réponse interrompue"), in: upload)
        scrollTo(element("document-upload-submit"), in: upload)
        XCTAssertFalse(element("document-upload-submit").isEnabled, "An uncertain upload must not be sent twice")
        record("\(prefix)-documents-envoi-incertain")
        scrollTo(element("document-upload-cancel"), in: upload)
        tap("document-upload-cancel")
        require("The blocked upload sheet closes without another write") { !self.element("document-upload-title").exists }
        scrollTo(element("documents-refresh"), in: documents, downward: false)
        tap("documents-refresh")
        scrollTo(element("documents-reconcile"), in: documents)
        tap("documents-reconcile")
        require("Reconciliation finds the committed synthetic file without resending") {
            self.text("Simulation : enregistrement fictif retrouvé, sans renvoi du fichier.").exists
                && !self.element("documents-reconcile").exists
        }
        scrollTo(element("document-status-RCP_ASSURANCE"), in: documents)
        XCTAssertEqual(element("document-status-RCP_ASSURANCE").label, "En attente de vérification",
                       "Readback must not manufacture a successful verification")
        record("\(prefix)-documents-envoi-reconcilie")

        scrollTo(element("document-delete-RCP_ASSURANCE"), in: documents)
        tap("document-delete-RCP_ASSURANCE")
        let deleteAlert = app.alerts["Supprimer ce document ?"]
        require("Archiving needs explicit native confirmation") { deleteAlert.exists && deleteAlert.buttons["Supprimer"].isHittable }
        deleteAlert.buttons["Supprimer"].tap()
        scrollTo(element("document-add-RCP_ASSURANCE"), in: documents)
        XCTAssertTrue(visible(element("document-add-RCP_ASSURANCE")))
        XCTAssertFalse(element("document-status-RCP_ASSURANCE").exists)
        record("\(prefix)-documents-retrait-confirme")

        // A second failure boundary: no registration occurred, so readback can close
        // the local receipt while keeping the prior proof and never resending bytes.
        scrollTo(element("document-replace-RIB"), in: documents)
        tap("document-replace-RIB")
        scrollTo(element("document-pick-file"), in: upload)
        tap("document-pick-file")
        scrollTo(text("rib-avant-enregistrement-demo.png"), in: upload)
        XCTAssertTrue(visible(text("rib-avant-enregistrement-demo.png")))
        scrollTo(element("document-upload-submit"), in: upload)
        tap("document-upload-submit")
        require("Pre-registration interruption is explicit") { self.textContaining("Simulation : interruption avant").exists }
        scrollTo(element("document-upload-submit"), in: upload)
        XCTAssertFalse(element("document-upload-submit").isEnabled)
        scrollTo(element("document-upload-cancel"), in: upload)
        tap("document-upload-cancel")
        scrollTo(element("documents-reconcile"), in: documents, downward: false)
        tap("documents-reconcile")
        require("An unregistered receipt is closed without claiming upload success") {
            self.textContaining("cet envoi sans enregistrement est clos").exists && !self.element("documents-reconcile").exists
        }
        scrollTo(element("document-status-RIB"), in: documents)
        XCTAssertEqual(element("document-status-RIB").label, "En attente de vérification")
        scrollTo(text("Simulation — RIB"), in: documents, downward: false)
        XCTAssertTrue(visible(text("Simulation — RIB")))
        scrollTo(element("document-replace-RIB"), in: documents)
        XCTAssertTrue(element("document-replace-RIB").isEnabled)
        record("\(prefix)-documents-envoi-sans-enregistrement")

        backGesture()
        require("The native back gesture returns to the caregiver profile") { self.visible(self.element("caregiver-profile-scroll")) }
        tap("tab-explore")
        require("The separate exploration tab is usable") { self.visible(self.element("missions-list")) }
        tap("tab-profile")
        scrollTo(element("profile-documents"), in: element("caregiver-profile-scroll"), downward: false)
        tap("profile-documents")
        require("The dossier reloads after a native navigation return") { self.visible(documents) }
        XCUIDevice.shared.press(.home)
        require("Documents actually enters the background") { self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended }
        app.activate()
        require("Documents returns to the same native screen") { self.visible(documents) }
        scrollTo(element("document-status-DIPLOME"), in: documents)
        XCTAssertEqual(element("document-status-DIPLOME").label, "Vérifié")
        scrollTo(text("Simulation diplome remplace"), in: documents, downward: false)
        XCTAssertTrue(visible(text("Simulation diplome remplace")))
        scrollTo(element("document-status-CARTE_IDENTITE"), in: documents)
        XCTAssertEqual(element("document-status-CARTE_IDENTITE").label, "En cours de vérification")
        scrollTo(element("document-add-RCP_ASSURANCE"), in: documents)
        XCTAssertTrue(visible(element("document-add-RCP_ASSURANCE")))
        XCTAssertFalse(element("document-status-RCP_ASSURANCE").exists)
        record("\(prefix)-documents-reprise")
        backGesture()
        signOut()
    }

    private func keyboardTopIncludingAccessory() -> CGFloat {
        let keyboardFrame = app.keyboards.firstMatch.frame
        var top = keyboardFrame.minY
        let assistant = app.otherElements["SystemInputAssistantView"].firstMatch
        if assistant.exists { top = min(top, assistant.frame.minY) }
        // iPhone exposes the Done accessory as Toolbar, not the iPad assistant.
        // Navigation headers are NavigationBar elements. The system accessory
        // can be separated from the keys by a gap, so do not require adjacency.
        for toolbar in app.toolbars.matching(identifier: "Toolbar").allElementsBoundByIndex {
            let frame = toolbar.frame
            if !frame.isEmpty && frame.minY < keyboardFrame.minY
                && frame.minX < keyboardFrame.maxX && frame.maxX > keyboardFrame.minX {
                top = min(top, frame.minY)
            }
        }
        return top
    }

    private func typeContractCode() -> Bool {
        let input = element("contract-otp")
        let detail = element("contract-detail-scroll")
        require("The native keyboard is available for the signature code") {
            self.app.keyboards.firstMatch.exists
        }
        require("The focused code field stays fully above the keyboard without another scroll") {
            self.fullyVisible(input, inside: detail) && input.frame.maxY <= self.keyboardTopIncludingAccessory()
        }
        input.typeText("000000")
        let originalValue = input.value as? String
        guard originalValue == "000000" else {
            // Record the original failure BEFORE the comparison. Continuing is
            // enabled only for this one report, then immediately restored.
            do {
                let previous = continueAfterFailure
                continueAfterFailure = true
                defer { continueAfterFailure = previous }
                XCTAssertEqual(originalValue, "000000", "The six typed digits are exact before any further action")
            }
            diagnoseContractKeypadAfterTypingFailure(input, originalValue: originalValue)
            XCTFail("Original typeText(000000) did not produce six exact digits. The keypad comparison is diagnostic only; the contract scenario stops without signing.")
            return false
        }
        return true
    }

    // This is reached only after the original, unchanged six-character typing
    // operation has already failed its value check. It can never rescue the test.
    private func diagnoseContractKeypadAfterTypingFailure(_ input: XCUIElement, originalValue: String?) {
        let name = "\(proofPrefix)-diagnostic-otp-input-comparison"
        var markers: [[String: Any]] = []
        var deleteTapAttempts = 0
        var zeroTapAttempts = 0
        func mark(_ stage: String, value: String? = nil) {
            var marker: [String: Any] = ["stage": stage, "atMs": Int64(Date().timeIntervalSince1970 * 1000)]
            if let value { marker["value"] = value }
            markers.append(marker)
        }
        mark("original-typeText-failed", value: originalValue ?? "<unavailable>")
        record("\(name)-before")
        defer {
            mark("comparison-finished", value: input.exists ? (input.value as? String ?? "<unavailable>") : "<absent>")
            record("\(name)-after")
            let proof: [String: Any] = ["schemaVersion": 1, "diagnosticOnly": true,
                "originalTypingPassed": false, "deleteTapAttempts": deleteTapAttempts,
                "zeroTapAttempts": zeroTapAttempts, "markers": markers]
            if let data = try? JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                attachText(json, name: "\(name).json")
            }
        }
        // A single observed zero is the only admitted comparison case. No clear(),
        // paste, re-focus, keyboard toggle, repeated deletion or delayed retry.
        let keyboard = app.keyboards.firstMatch
        guard originalValue == "0", input.exists, input.isEnabled,
              input.value as? String == "0", keyboard.exists else {
            mark("comparison-skipped-preconditions"); return
        }
        let zeros = keyboard.keys.matching(NSPredicate(format: "label == %@", "0"))
        let deletes = keyboard.keys.matching(NSPredicate(format: "label == %@ OR label == %@", "Delete", "delete"))
        guard zeros.count == 1, deletes.count == 1,
              visible(zeros.firstMatch), visible(deletes.firstMatch),
              zeros.firstMatch.isEnabled, deletes.firstMatch.isEnabled,
              keyboard.frame.contains(zeros.firstMatch.frame), keyboard.frame.contains(deletes.firstMatch.frame) else {
            mark("comparison-skipped-keys"); return
        }
        mark("delete-tap")
        deleteTapAttempts += 1
        deletes.firstMatch.tap()
        let afterDelete = input.value as? String
        mark("after-delete", value: afterDelete ?? "<unavailable>")
        guard afterDelete == "" || afterDelete == "6 chiffres" else {
            mark("comparison-stopped-delete-not-empty"); return
        }
        for index in 1...6 {
            guard keyboard.exists, zeros.count == 1, visible(zeros.firstMatch),
                  zeros.firstMatch.isEnabled, keyboard.frame.contains(zeros.firstMatch.frame) else {
                mark("comparison-stopped-key-unavailable"); return
            }
            mark("visible-zero-tap-\(index)")
            zeroTapAttempts += 1
            zeros.firstMatch.tap()
        }
    }

    private func prepareExpoGo() {
        // simctl already launched the fixed local experience. Observe that same
        // foreground process: activate() unnecessarily asks SpringBoard to open
        // it again and can time out before any test interaction (iPad CI).
        require("The prepared pilot process is already running") {
            self.app.state == .runningForeground
        }
        XCUIDevice.shared.orientation = .portrait
        let continueButton = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "Continue|Continuer")
        ).firstMatch
        let sdk = app.staticTexts["SDK version: 57.0.0"]
        // The runner supplies temporary Expo host preferences at launch. This
        // checks their effect; it makes no claim to test Expo's own onboarding.
        require("Jolene is mounted without the Expo tutorial or developer menu", timeout: 120) {
            self.app.state == .runningForeground
                && !continueButton.exists && !sdk.exists
                && self.visible(self.element("login-scroll"))
        }
    }

    private func dismissFirstKeyboardIntroductionIfPresent() {
        // The startup URL argument does not use Expo Home's text field. Handle the
        // same identified system tutorial at the first Jolene input instead.
        // This retains the existing single, bounded startup check per scenario.
        let keyboardIntroduction = app.otherElements["UIContinuousPathIntroductionView"]
        if keyboardIntroduction.waitForExistence(timeout: 3) {
            let keyboardContinue = keyboardIntroduction.buttons["Continue"]
            require("The keyboard tutorial exposes Continue") { self.visible(keyboardContinue) }
            keyboardContinue.tap()
            require("The keyboard tutorial is dismissed") { !keyboardIntroduction.exists }
        }
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
        // Select All is an explicit native editing action. A synthesized triple
        // tap selected only "Profil" on iPhone 17, so do not infer selection size.
        bio.tap()
        require("The native keyboard is available for profile editing") { self.app.keyboards.firstMatch.exists }
        // Focusing the field must keep it visible for the user. A coordinate on
        // an obscured TextView can hit a key instead of opening its editing menu.
        require("The focused biography stays above the native keyboard without another scroll") {
            self.fullyVisible(bio, inside: profile) && bio.frame.maxY <= self.keyboardTopIncludingAccessory()
        }
        // Place the insertion point after the short fixture, in the TextView's
        // empty lower area; holding there opens the editing menu without selecting a word.
        let insertion = bio.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.85))
        insertion.tap()
        insertion.press(forDuration: 1.0)
        // The native text editing menu exposes this action as MenuItem (iPad AX).
        let selectAll = app.menuItems.matching(NSPredicate(format: "label IN %@", ["Select All", "Tout sélectionner"])).firstMatch
        require("The native Select All editing action is available") { self.visible(selectAll) }
        selectAll.tap()
        bio.typeText(XCUIKeyboardKey.delete.rawValue)
        require("The entire previous biography was removed") { bio.value as? String == "" }
        bio.typeText(expected)
        require("The new biography is exact before saving") { bio.value as? String == expected }
        scrollTo(element("save-profile"), in: profile)
        XCTAssertEqual(bio.value as? String, expected, "Scrolling to Save preserves the edited biography")
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
        // React Native can expose both the parent Text and its untagged native
        // child with the same label. Count the two tagged rows, not that duplicate.
        let slotTimes = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "establishment-slot-time-"))
        XCTAssertEqual(slotTimes.count, 2, "The detail must render both exact synthetic time slots")
        for index in 0..<2 {
            let slot = element("establishment-slot-time-\(index)")
            scrollTo(slot, in: detail)
            // Fixture is 08–16 UTC on relative future dates: Paris is UTC+1 or
            // UTC+2, including when the two slots straddle a DST transition.
            XCTAssertTrue(["09:00 — 17:00", "10:00 — 18:00"].contains(slot.label),
                          "Each synthetic slot renders its complete eight-hour Paris interval")
        }
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
        let role = element("establishment-membership-role")
        scrollTo(role, in: profile)
        require("The declared membership role is visible") { self.visible(role) && role.label == "Propriétaire" }
        let readPermission = element("establishment-permission-lecture")
        scrollTo(readPermission, in: profile)
        require("The establishment read permission is visible and authorized") {
            self.visible(self.text("Consulter l’établissement")) && self.visible(readPermission) && readPermission.label == "Autorisé"
        }
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
        require("The cycle sheet finished its native presentation") { self.visible(self.element("onboarding-formation-presented")) }
        let cycles = element("onboarding-formation-choices")
        scrollTo(element("onboarding-formation-MEDECINE_DES"), in: cycles)
        require("Medicine offers its third cycle") { self.visible(self.element("onboarding-formation-MEDECINE_DES")) }
        XCTAssertFalse(element("onboarding-formation-KINE").exists, "Medicine must not offer a physiotherapy degree")
        scrollTo(element("onboarding-formation-MEDECINE_DFASM"), in: cycles, downward: false)
        tap("onboarding-formation-MEDECINE_DFASM")
        scrollTo(element("onboarding-study-year"), in: form)
        scrollTo(element("onboarding-formation"), in: form, downward: false)
        tap("onboarding-formation")
        require("The cycle sheet can be presented again") { self.visible(self.element("onboarding-formation-presented")) }
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
        // An edge gesture starts at the same physical inset on every device width.
        // A 1% inset moves from 4 pt on iPhone to almost 12 pt on landscape iPad.
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 1, dy: 0))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let startPoint = start.screenPoint
        let endPoint = end.screenPoint
        let proofID = UUID().uuidString
        let startedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        let stateBefore = app.state.rawValue
        defer {
            let proof: [String: Any] = ["schemaVersion": 1, "id": proofID,
                "startedAtMs": startedAtMs, "finishedAtMs": Int64(Date().timeIntervalSince1970 * 1000),
                "start": ["x": startPoint.x, "y": startPoint.y], "end": ["x": endPoint.x, "y": endPoint.y],
                "velocityPreset": "original-default", "velocityPixelsPerSecond": 500,
                "initialHoldSeconds": 0.05, "finalHoldSeconds": 0,
                "appStateBefore": stateBefore, "appStateAfter": app.state.rawValue]
            if let data = try? JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                attachText(json, name: "\(proofPrefix)-edge-back-\(proofID).json")
            } else { XCTFail("The single edge gesture's diagnostic could not be recorded") }
        }
        // Preserve the original failing gesture while measuring its transition.
        // A faster swipe must not silently replace this regression condition.
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func drag(_ container: XCUIElement, fromY: CGFloat, toY: CGFloat) {
        // A ScrollView retains its full frame while iOS adds keyboard insets.
        // Start the user's gesture in the unobscured viewport, never on a key.
        var viewport = container.frame.intersection(app.frame)
        if app.keyboards.firstMatch.exists {
            let bottom = min(viewport.maxY, keyboardTopIncludingAccessory())
            viewport.size.height = max(0, bottom - viewport.minY)
        }
        XCTAssertFalse(viewport.isNull || viewport.isEmpty, "A scroll gesture requires a visible viewport outside the keyboard")
        guard !viewport.isNull && !viewport.isEmpty else { return }
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let x = viewport.midX - app.frame.minX
        let top = viewport.minY - app.frame.minY
        let start = origin.withOffset(CGVector(dx: x, dy: top + viewport.height * fromY))
        let end = origin.withOffset(CGVector(dx: x, dy: top + viewport.height * toY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func scrollTo(_ target: XCUIElement, in container: XCUIElement, downward: Bool = true) {
        require("The expected scroll container is visible") { self.visible(container) }
        var scrolls = 0
        while !fullyVisible(target, inside: container) && scrolls < 20 {
            var forward = downward
            var distance: CGFloat = 0.55
            if target.exists && !target.frame.isEmpty {
                let frame = target.frame
                let viewport = container.frame
                // A large paragraph can be skipped by a fixed half-screen drag.
                // Follow its actual frame, including reversing an overshoot,
                // and use less than the available space around that paragraph.
                if frame.minY < viewport.minY { forward = false }
                else if frame.maxY > viewport.maxY { forward = true }
                distance = min(0.55, max(0.08, (viewport.height - frame.height) * 0.4 / viewport.height))
            }
            drag(container, fromY: 0.5 + (forward ? distance : -distance) / 2,
                 toY: 0.5 - (forward ? distance : -distance) / 2)
            scrolls += 1
        }
        require("The requested control is fully visible after bounded scrolling") { self.fullyVisible(target, inside: container) }
    }

    private func tap(_ identifier: String) {
        let target = element(identifier)
        if identifier.hasPrefix("tab-") && !visible(target) {
            dismissDebuggerMigrationBannerIfPresent()
        }
        require("Control \(identifier) is reachable") { self.visible(target) && target.isEnabled }
        // One ordinary 200 ms contact. A system touch cancellation still fails
        // the unchanged navigation assertion; there is no retry or press-on-cancel.
        target.press(forDuration: 0.2)
    }

    private func dismissDebuggerMigrationBannerIfPresent() {
        // RN 0.86's one-time Debug migration notice can cover the tab bar. Its
        // grouped accessibility node does not expose the close icon separately.
        // Close only this identified tooling notice, using its visible X. Keep
        // the before/after evidence and Metro warnings; never suppress LogBox.
        let banners = app.otherElements.matching(NSPredicate(
            format: "label == %@", "!, Open debugger to view warnings."
        ))
        guard banners.count == 1, visible(banners.firstMatch) else { return }
        guard !dismissedDebuggerMigrationBanner else {
            XCTFail("The one-time Debug migration notice unexpectedly reappeared")
            return
        }
        let banner = banners.firstMatch
        let frame = banner.frame
        guard frame.width >= 250, (44...52).contains(frame.height),
              frame.minY > app.frame.midY, app.frame.contains(frame) else {
            XCTFail("The identified Debug migration notice has an unexpected layout")
            return
        }
        record("\(proofPrefix)-debugger-migration-before")
        dismissedDebuggerMigrationBanner = true
        // Locked RN LogBoxNotification: 12pt right padding + half the 20pt X.
        banner.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -22, dy: 0)).tap()
        require("The Debug migration notice is closed before reaching the actual tab") {
            !banners.firstMatch.exists
        }
        record("\(proofPrefix)-debugger-migration-after")
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
