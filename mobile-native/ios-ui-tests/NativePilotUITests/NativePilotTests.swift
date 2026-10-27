import XCTest

/// Drives the prepared Expo Go experience without launching, reopening or resetting it.
final class NativePilotTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "host.exp.Exponent")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var proofPrefix = "ipad-portrait"
    private var backgroundStates: [UInt] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Each selected consultation, Documents or Contracts scenario has its own bounded budget.
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


    // Each Contracts scenario starts in a fresh demo runtime with the explicit
    // EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO=1 flag. No provider is contacted.
    func testContractsIphonePortrait() throws { runContracts(prefix: "iphone-portrait", landscape: false) }
    func testContractsIpadPortrait() throws { runContracts(prefix: "ipad-portrait", landscape: false) }
    func testContractsIpadLandscape() throws { runContracts(prefix: "ipad-paysage", landscape: true) }

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
        scrollTo(element("contract-demo-code"), in: detail)
        XCTAssertTrue(element("contract-demo-code").label.contains("000000"))
        XCTAssertTrue(element("contract-demo-code").label.contains("Aucun SMS envoyé"))
        record("\(prefix)-contrats-otp-simule")
        scrollTo(element("contract-otp"), in: detail)
        tap("contract-otp")
        dismissFirstKeyboardIntroductionIfPresent()
        typeContractCode()
        XCTAssertEqual(element("contract-otp").value as? String, "000000", "The six typed digits are exact before any further action")
        XCUIDevice.shared.press(.home)
        require("Contracts actually entered background") {
            self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended
        }
        app.activate()
        require("The contract is reread after resume") { self.element("contract-original").exists && !self.app.keyboards.firstMatch.exists }
        scrollTo(element("contract-request-otp"), in: detail)
        XCTAssertFalse(element("contract-request-otp").isEnabled, "Consent must be reset after backgrounding")
        scrollTo(element("contract-otp"), in: detail)
        XCTAssertTrue((element("contract-otp").value as? String).map { $0.isEmpty || $0 == "6 chiffres" } ?? false,
                      "The previously typed code must not survive resume")
        record("\(prefix)-contrats-reprise")
        scrollTo(element("contract-consent"), in: detail, downward: false)
        tap("contract-consent")
        scrollTo(element("contract-otp"), in: detail)
        tap("contract-otp")
        typeContractCode()
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
        scrollTo(element("contract-demo-code"), in: detail)
        XCTAssertTrue(element("contract-demo-code").label.contains("000000"))
        XCTAssertTrue(element("contract-demo-code").label.contains("Aucun SMS envoyé"))
        scrollTo(element("contract-otp"), in: detail)
        tap("contract-otp")
        typeContractCode()
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

    private func typeContractCode() {
        let input = element("contract-otp")
        let detail = element("contract-detail-scroll")
        require("The native keyboard is available for the signature code") {
            self.app.keyboards.firstMatch.exists
        }
        require("The focused code field stays fully above the keyboard without another scroll") {
            self.fullyVisible(input, inside: detail) && input.frame.maxY <= self.keyboardTopIncludingAccessory()
        }
        input.typeText("000000")
    }

    private func prepareExpoGo() {
        // simctl already launched the fixed local experience. Activation attaches
        // XCTest to this running process and waits until it can receive events;
        // it does not reopen the URL or terminate/relaunch the application.
        require("The prepared Expo Go process is already running") {
            self.app.state == .runningForeground
        }
        app.activate()
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
        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 1, dy: 0))
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
