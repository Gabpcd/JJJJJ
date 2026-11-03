import XCTest

/// Socle des tests UI Jolene : helpers repris de
/// `mobile-native/ios-ui-tests/NativePilotUITests/NativePilotTests.swift`
/// (`element`, `visible`, `fullyVisible`, `require`, `scrollTo`, `record`, `attachText`),
/// avec un `tap()` natif pour toute activation (jamais `press(forDuration:)` comme tap) et
/// l'orientation lue dans `JOLENE_UI_ORIENTATION` (portrait | landscape). Le seul glissement
/// est `drag(_:fromY:toY:)` (défilement borné de `scrollTo`), qui emploie
/// `press(forDuration:thenDragTo:)` entre deux coordonnées calculées hors clavier : c'est
/// l'unique API XCUITest de glissement à point de départ contrôlé, et elle n'active rien.
/// Aucune attente arbitraire : toutes passent par `require` (prédicat borné). La preuve est
/// l'assertion ; les captures (`record`) ne sont que des artefacts pour l'humain.
@MainActor
class JoleneUITestCase: XCTestCase {
    // Lus depuis les crochets XCTest (nonisolés) qui tournent sur le thread principal ;
    // aucune autre file n'y accède. XCUIApplication est Sendable, son init est main actor.
    nonisolated let app: XCUIApplication = MainActor.assumeIsolated { XCUIApplication() }
    nonisolated(unsafe) var proofPrefix = "iphone-portrait"

    static let demoEmail = "demonstration@example.invalid"
    /// Mot de passe de démonstration : valeur fictive, acceptée uniquement par le monde démo.
    static let demoPassword = "demonstration"

    nonisolated var requestedOrientation: UIDeviceOrientation {
        let raw = (ProcessInfo.processInfo.environment["JOLENE_UI_ORIENTATION"] ?? "portrait").lowercased()
        return raw == "landscape" ? .landscapeLeft : .portrait
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 600
        let landscape = requestedOrientation != .portrait
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        proofPrefix = "\(isPad ? "ipad" : "iphone")-\(landscape ? "paysage" : "portrait")"
    }

    /// Sur échec : capture, dump d'accessibilité et état du processus, sans envoyer `self` au main actor.
    override func tearDownWithError() throws {
        guard (testRun?.totalFailureCount ?? 0) > 0 else { return }
        let prefix = proofPrefix
        let application = app
        let (png, dump, state) = MainActor.assumeIsolated {
            (XCUIScreen.main.screenshot().pngRepresentation, application.debugDescription, application.state.rawValue)
        }
        let screenshot = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        screenshot.name = "\(prefix)-echec"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachText(dump, name: "\(prefix)-echec-accessibilite.txt")
        attachText("État de l'app : \(state)", name: "\(prefix)-process-state.txt")
    }

    // MARK: Lancement

    /// Lance l'app en mode démonstration et applique l'orientation demandée.
    func launchDemo(extraArguments: [String] = [], environment: [String: String] = [:]) {
        app.launchArguments = ["-JOLENE_MODE", "demo"] + extraArguments
        app.launchEnvironment = environment
        app.launch()
        applyOrientation()
    }

    func applyOrientation() {
        XCUIDevice.shared.orientation = requestedOrientation
        let landscape = requestedOrientation != .portrait
        require("La fenêtre est en \(landscape ? "paysage" : "portrait")") {
            landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width
        }
    }

    // MARK: Requêtes d'éléments

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func elements(withPrefix prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    func textContaining(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    func visible(_ element: XCUIElement) -> Bool {
        element.exists && element.isHittable && !element.frame.isEmpty && app.frame.intersects(element.frame)
    }

    func fullyVisible(_ element: XCUIElement, inside container: XCUIElement) -> Bool {
        visible(element) && container.frame.insetBy(dx: -1, dy: -1).contains(element.frame)
    }

    /// Visibilité d'un conteneur (liste, défilement) sans `isHittable` : sur iPad (iOS 26.2),
    /// l'atteignabilité d'une `List` SwiftUI échoue (« Activation point invalid and no suggested
    /// hit points based on element frame ») alors que ses cellules restent atteignables.
    /// L'atteignabilité est exigée sur chaque contrôle activé, jamais sur son conteneur.
    func containerVisible(_ element: XCUIElement) -> Bool {
        element.exists && !element.frame.isEmpty && app.frame.intersects(element.frame)
    }

    func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    func coveredByKeyboard(_ element: XCUIElement) -> Bool {
        let keyboard = app.keyboards.firstMatch
        return keyboard.exists && element.frame.maxY > keyboard.frame.minY
    }

    /// Prédicat borné. Sur un simulateur CI chargé, un instantané d'accessibilité peut rester bloqué
    /// une quinzaine de secondes puis échouer (« Find … (retry 1) », runs 41556230233 : iPhone et iPad,
    /// classes Mes missions, Compte, Explorer) : une seule évaluation consomme alors tout le délai. Une
    /// dernière évaluation, après le délai, tranche ; la condition reste exigée (aucune attente ajoutée
    /// quand elle est vraie, aucune quand elle est fausse au-delà de cette évaluation).
    func require(_ description: String, timeout: TimeInterval = 15, condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let resultat = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if resultat != .completed, condition() { return }
        XCTAssertEqual(resultat, .completed, description)
    }

    // MARK: Actions

    /// Un `tap()` natif, jamais `press(forDuration:)` pour activer : la navigation attendue est vérifiée ensuite.
    func tap(_ identifier: String) {
        let target = element(identifier)
        require("Le contrôle \(identifier) est atteignable") { self.visible(target) && target.isEnabled }
        target.tap()
    }

    /// Donne le focus clavier à un champ avant `typeText`. Un champ recouvert par le clavier
    /// (iPad paysage : le clavier ouvert pour l'email couvre la moitié basse) est d'abord remonté
    /// dans la zone visible hors clavier, puis touché ; le focus est ensuite exigé, car
    /// `typeText` sans focus échoue (« Neither element nor any descendant has keyboard focus »).
    func focus(_ field: XCUIElement, in container: XCUIElement) {
        require("Le champ à saisir est affiché") { self.containerVisible(field) }
        var attempts = 0
        while coveredByKeyboard(field) && attempts < 10 {
            drag(container, fromY: 0.6, toY: 0.3)
            attempts += 1
        }
        require("Le champ à saisir est atteignable hors clavier") { self.visible(field) && !self.coveredByKeyboard(field) }
        field.tap()
        if !hasKeyboardFocus(field) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        }
        require("Le champ a le focus clavier avant la saisie") { self.hasKeyboardFocus(field) }
    }

    // MARK: Barre d'onglets

    /// Symboles SF des cinq onglets de `MainTabView`. UIKit expose un bouton d'onglet avec,
    /// pour identifiant, le nom de l'image de son `Label` (`house`, `magnifyingglass`…) ; le
    /// `.accessibilityIdentifier("tab-*")` SwiftUI est porté par le contenu de l'onglet, pas
    /// par son bouton (vérifié sur les dumps iPhone iOS 18.6 et iPad iOS 18.6).
    static let tabSymbols: [String: String] = [
        "tab-accueil": "house", "tab-explorer": "magnifyingglass", "tab-missions": "list.clipboard",
        "tab-revenus": "banknote", "tab-profil": "person",
    ]

    /// Boutons d'onglet : dans l'élément `TabBar` (barre basse, iPhone) ou, sur iPadOS 18 et
    /// suivants où la barre d'onglets est rendue en haut de l'écran sans aucun élément `TabBar`,
    /// les boutons libres dont l'identifiant est l'un des cinq symboles (ou `tab-*`).
    var tabButtons: XCUIElementQuery {
        let bar = app.tabBars.firstMatch
        if bar.exists { return bar.buttons }
        let identifiers = Array(Self.tabSymbols.keys) + Array(Self.tabSymbols.values)
        return app.buttons.matching(NSPredicate(format: "identifier IN %@", identifiers))
    }

    /// Libellés distincts des onglets présents, dans l'ordre d'affichage. Sur iPad chaque
    /// bouton apparaît deux fois (imbriqué) dans l'arbre d'accessibilité : on compte les
    /// libellés, pas les nœuds.
    var tabLabels: [String] {
        var seen = Set<String>()
        return tabButtons.allElementsBoundByIndex.map(\.label).filter { seen.insert($0).inserted }
    }

    /// Vrai dès qu'au moins un onglet est exposé (barre basse ou barre haute).
    var tabBarExists: Bool { !tabLabels.isEmpty }

    /// Description de la barre pour les pièces jointes : l'élément `TabBar` s'il existe,
    /// sinon la requête des boutons d'onglet.
    var tabBarDescription: String {
        let bar = app.tabBars.firstMatch
        return bar.exists ? bar.debugDescription : tabButtons.debugDescription
    }

    /// Onglet de la barre : l'identifiant `tab-*`, puis le symbole SF correspondant, puis le
    /// libellé en dernier repli.
    func tabButton(_ identifier: String, label: String) -> XCUIElement {
        let buttons = tabButtons
        let byIdentifier = buttons.matching(identifier: identifier).firstMatch
        if byIdentifier.exists { return byIdentifier }
        if let symbol = Self.tabSymbols[identifier] {
            let bySymbol = buttons.matching(identifier: symbol).firstMatch
            if bySymbol.exists { return bySymbol }
        }
        return buttons[label]
    }

    /// Glissement entre deux coordonnées du viewport visible (hors clavier). Seul emploi de
    /// `press(forDuration:thenDragTo:)` du socle : un glissement, pas une activation.
    func drag(_ container: XCUIElement, fromY: CGFloat, toY: CGFloat) {
        var viewport = container.frame.intersection(app.frame)
        if app.keyboards.firstMatch.exists {
            let bottom = min(viewport.maxY, app.keyboards.firstMatch.frame.minY)
            viewport.size.height = max(0, bottom - viewport.minY)
        }
        XCTAssertFalse(viewport.isNull || viewport.isEmpty, "Un défilement exige un viewport visible hors clavier")
        guard !viewport.isNull && !viewport.isEmpty else { return }
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let x = viewport.midX - app.frame.minX
        let top = viewport.minY - app.frame.minY
        let start = origin.withOffset(CGVector(dx: x, dy: top + viewport.height * fromY))
        let end = origin.withOffset(CGVector(dx: x, dy: top + viewport.height * toY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func scrollTo(_ target: XCUIElement, in container: XCUIElement, downward: Bool = true) {
        require("Le conteneur de défilement attendu est visible") { self.containerVisible(container) }
        var scrolls = 0
        while !fullyVisible(target, inside: container) && scrolls < 20 {
            var forward = downward
            var distance: CGFloat = 0.55
            if target.exists && !target.frame.isEmpty {
                let frame = target.frame
                let viewport = container.frame
                if frame.minY < viewport.minY { forward = false } else if frame.maxY > viewport.maxY { forward = true }
                distance = min(0.55, max(0.08, (viewport.height - frame.height) * 0.4 / viewport.height))
            }
            drag(container, fromY: 0.5 + (forward ? distance : -distance) / 2,
                 toY: 0.5 - (forward ? distance : -distance) / 2)
            scrolls += 1
        }
        require("Le contrôle demandé est entièrement visible après un défilement borné") {
            self.fullyVisible(target, inside: container)
        }
    }

    /// L'onglet « Mes missions » (`tab-missions`) garde son libellé entier et visible dans la
    /// barre, sur chaque largeur d'écran : ni tronqué, ni hors cadre.
    func assertMissionsTabLabelFits() {
        let tab = tabButton("tab-missions", label: "Mes missions")
        require("L'onglet Mes missions est visible") { self.visible(tab) }
        XCTAssertEqual(tab.label, "Mes missions", "Le libellé de l'onglet doit rester « Mes missions »")
        let bar = app.tabBars.firstMatch
        // Barre basse : l'onglet tient dans la barre. Barre haute iPad (aucun élément `TabBar`) :
        // l'onglet tient dans la fenêtre, qui est alors la seule borne connue.
        let container = bar.exists ? bar.frame : app.frame
        XCTAssertTrue(container.insetBy(dx: -1, dy: -1).contains(tab.frame), "L'onglet doit tenir dans la barre")
        XCTAssertGreaterThan(tab.frame.width, 44, "L'onglet doit garder une zone tactile d'au moins 44 pt")
        if bar.exists {
            let labelText = bar.staticTexts["Mes missions"]
            if labelText.exists {
                XCTAssertTrue(bar.frame.insetBy(dx: -1, dy: -1).contains(labelText.frame), "Le libellé ne doit pas déborder de la barre")
            }
        }
    }

    // MARK: Preuves

    nonisolated func attachText(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func record(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachText(app.debugDescription, name: "\(name)-accessibilite.txt")
    }
}
