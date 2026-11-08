import XCTest

/// Socle des tests UI Jolene : helpers repris de
/// `mobile-native/ios-ui-tests/NativePilotUITests/NativePilotTests.swift`
/// (`element`, `visible`, `fullyVisible`, `require`, `scrollTo`, `record`, `attachText`),
/// avec un `tap()` natif pour toute activation (jamais `press(forDuration:)` comme tap) et
/// l'orientation lue dans `JOLENE_UI_ORIENTATION` (portrait | landscape). Les seuls glissements
/// sont `drag(_:fromY:toY:)` (défilement borné de `scrollTo`) et `dragSliderPastMinimum(_:)`
/// (curseur amené à sa borne basse), qui emploient `press(forDuration:thenDragTo:…)` entre deux
/// coordonnées calculées : c'est l'unique API XCUITest de glissement à point de départ contrôlé,
/// et elle n'active rien. Aucune attente arbitraire : toutes passent par `require` (prédicat
/// borné). La preuve est l'assertion ; les captures (`record`) ne sont que des artefacts pour
/// l'humain.
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

    /// Part maximale du délai de `require` décomptée pour UNE évaluation de la condition. Une
    /// évaluation (quelques requêtes d'accessibilité) dure normalement bien moins de 5 s. Au-delà,
    /// quelque chose est bloqué sans que le runner puisse dire quoi : l'observateur (runner saturé)
    /// ou l'app, dont le serveur d'accessibilité répond sur le thread principal, si bien qu'un gel de
    /// l'app allonge l'évaluation exactement comme un runner saturé. Run 42489677193, UI — iphone :
    /// une seule requête « Find the "chip-weekend" Button » a duré 12,5 s (t = 70,4 → 82,9 s), la
    /// capture d'échec 9,5 s et le relancement suivant 10,7 s au lieu de 1,8 s ; le délai de 15 s a
    /// expiré après UNE évaluation, sans qu'aucune n'ait observé l'app après le blocage, alors que
    /// l'arbre d'accessibilité de fin montrait la chip en place (402 × 874, cadre {122.7, 124, 104, 44}).
    static let maximumChargedEvaluation: TimeInterval = 5
    /// Intervalle entre deux évaluations, celui de `XCTNSPredicateExpectation`.
    static let evaluationInterval: TimeInterval = 1
    /// Délai par défaut de `require`.
    static let defaultTimeout: TimeInterval = 15

    /// Attente bornée d'un état de l'app : la condition est évaluée environ chaque seconde jusqu'à
    /// être vraie, pendant `timeout` secondes décomptées sur l'horloge monotone
    /// (`ProcessInfo.systemUptime`). Sans blocage, l'attente équivaut à
    /// `XCTNSPredicateExpectation` sur `timeout`.
    ///
    /// Décompte : une évaluation compte pour sa durée mesurée, plafonnée à
    /// `maximumChargedEvaluation` ; un intervalle compte pour sa durée mesurée (jamais moins que
    /// prévu). L'excédent d'une évaluation au-delà du plafond n'est pas décompté : c'est un blocage
    /// de l'observateur OU du thread principal de l'app, indiscernables côté runner. Ce temps non
    /// décompté n'est donc jamais ignoré :
    /// - borné : cumulé sur l'appel, il ne dépasse pas `timeout`. Au-delà, l'attente échoue aussitôt
    ///   (« observateur ou thread principal de l'app bloqué … »), même si la condition est vraie :
    ///   une évaluation figée plus de `timeout` + `maximumChargedEvaluation` (20 s par défaut) ne
    ///   passe jamais en silence, et un appel dure au plus environ deux fois `timeout`, plus la
    ///   durée de l'évaluation qui franchit le plafond. L'incident ci-dessus (7,5 s non décomptées
    ///   sur 15) reste sous le plafond ;
    /// - tracé : dès qu'il est non nul, attente réussie comprise, une activité XCTest et une pièce
    ///   jointe texte (`<proofPrefix>-attente-bloquee-<fichier>-<ligne>.txt`) donnent chaque
    ///   évaluation bloquée avec sa durée mesurée.
    ///
    /// Évaluation de grâce : si l'évaluation qui épuise le délai était bloquée, une évaluation de
    /// plus est accordée, une seule fois et sous le même plafond, pour que l'état soit constaté
    /// après le blocage. Une évaluation qui ne rend jamais la main n'est interrompue que par le délai
    /// d'exécution du test (`executionTimeAllowance`). Tout échec est rapporté à la ligne de
    /// l'appelant.
    func require(_ description: String, timeout: TimeInterval = JoleneUITestCase.defaultTimeout,
                 file: StaticString = #filePath, line: UInt = #line, condition: () -> Bool) {
        var wait = RequireWait(timeout: timeout, maximumCharged: Self.maximumChargedEvaluation)
        var satisfied = false
        while true {
            let start = ProcessInfo.processInfo.systemUptime
            satisfied = condition()
            let stalled = wait.recordEvaluation(ProcessInfo.processInfo.systemUptime - start)
            if satisfied || wait.stallCapExceeded { break }
            if wait.remaining <= 0 {
                // Délai épuisé : une seule évaluation de plus, si celle qui l'a épuisé était bloquée.
                guard stalled, !wait.graceGranted else { break }
                wait.graceGranted = true
            }
            let pause = wait.remaining > 0 ? min(Self.evaluationInterval, wait.remaining) : Self.evaluationInterval
            let pauseStart = ProcessInfo.processInfo.systemUptime
            pauseBetweenEvaluations(pause)
            wait.pauses += max(pause, ProcessInfo.processInfo.systemUptime - pauseStart)
        }
        if wait.uncharged > 0 {
            let outcome = wait.stallCapExceeded ? "échec, plafond du temps non décompté dépassé"
                : satisfied ? "condition vraie" : "échec, condition fausse au terme du délai"
            traceUncharged(wait, description: description, outcome: outcome, file: file, line: line)
        }
        let s = Self.seconds
        if wait.stallCapExceeded {
            let detail = "\(wait.stalls.count) évaluation(s) bloquée(s) sur \(wait.evaluations), la plus longue "
                + "\(s(wait.longestStall)) ; condition \(satisfied ? "vraie" : "fausse") à la dernière"
            XCTFail("\(description) — observateur ou thread principal de l'app bloqué \(s(wait.uncharged)) non décomptées "
                    + "(plafond \(s(wait.maximumUncharged)) par attente) : \(detail)", file: file, line: line)
        } else if !satisfied {
            let stall = wait.uncharged > 0 ? ", plus \(s(wait.uncharged)) de blocage non décomptées" : ""
            let grace = wait.graceGranted ? ", évaluation de grâce comprise" : ""
            XCTFail("\(description) — condition fausse à chacune des \(wait.evaluations) évaluations sur \(s(timeout)) "
                    + "décomptées\(stall)\(grace)", file: file, line: line)
        }
    }

    /// Mesures d'un appel de `require` : évaluations, blocages, intervalles.
    private struct RequireWait {
        let timeout: TimeInterval
        let maximumCharged: TimeInterval
        /// Plafond du temps non décompté cumulé sur l'appel : le délai lui-même.
        var maximumUncharged: TimeInterval { timeout }
        var evaluations = 0
        /// Évaluations bloquées (au-delà de `maximumCharged`) : rang et durée mesurée.
        var stalls: [(index: Int, duration: TimeInterval)] = []
        var charged: TimeInterval = 0
        var uncharged: TimeInterval = 0
        var pauses: TimeInterval = 0
        var graceGranted = false

        /// Délai restant : `timeout` moins les évaluations décomptées et les intervalles mesurés.
        var remaining: TimeInterval { timeout - charged - pauses }
        var stallCapExceeded: Bool { uncharged > maximumUncharged }
        var longestStall: TimeInterval { stalls.map(\.duration).max() ?? 0 }

        /// Compte une évaluation ; vrai si elle était bloquée.
        mutating func recordEvaluation(_ duration: TimeInterval) -> Bool {
            evaluations += 1
            charged += min(duration, maximumCharged)
            let excess = duration - maximumCharged
            guard excess > 0 else { return false }
            stalls.append((evaluations, duration))
            uncharged += excess
            return true
        }
    }

    /// Consigne le temps non décompté d'un `require`, que l'attente réussisse ou non : activité
    /// XCTest (journal du xcresult) et pièce jointe texte conservée, nommée avec `proofPrefix`.
    private func traceUncharged(_ wait: RequireWait, description: String, outcome: String, file: StaticString, line: UInt) {
        let s = Self.seconds
        let fileName = (String(describing: file) as NSString).lastPathComponent
        let stalls = wait.stalls.map { stall in
            "  évaluation n° \(stall.index) : \(s(stall.duration)) mesurées, \(s(wait.maximumCharged)) décomptées, "
                + "\(s(stall.duration - wait.maximumCharged)) non décomptées"
        }
        let report = [
            "Attente : \(description)",
            "Appelant : \(fileName):\(line)",
            "Issue : \(outcome)",
            "Délai : \(s(wait.timeout)) ; décompté : \(s(wait.charged + wait.pauses)) (évaluations \(s(wait.charged)), "
                + "intervalles mesurés \(s(wait.pauses)))",
            "Temps non décompté : \(s(wait.uncharged)) (plafond \(s(wait.maximumUncharged)) par attente)",
            "Évaluations : \(wait.evaluations), dont \(wait.stalls.count) bloquée(s) au-delà de \(s(wait.maximumCharged)) :",
        ] + stalls + [
            "Évaluation de grâce après blocage : \(wait.graceGranted ? "accordée" : "non")",
            "Origine : observateur (runner) ou thread principal de l'app, indiscernables côté runner.",
        ]
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "\(proofPrefix)-attente-bloquee-\((fileName as NSString).deletingPathExtension)-\(line).txt"
        attachment.lifetime = .keepAlways
        let activity = "Attente « \(description) » : \(s(wait.uncharged)) non décomptées "
            + "(plafond \(s(wait.maximumUncharged))), \(outcome)"
        XCTContext.runActivity(named: activity) { $0.add(attachment) }
    }

    /// Durée en secondes au format français (« 12,5 s »).
    private nonisolated static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1f s", locale: Locale(identifier: "fr_FR"), value)
    }

    /// Laisse tourner la boucle principale entre deux évaluations (XCTest y traite ses
    /// événements), comme `XCTNSPredicateExpectation` entre deux sondages. Un `XCTWaiter` sans
    /// délégué n'enregistre aucun échec : l'attente inversée se termine au bout de `duration`.
    private func pauseBetweenEvaluations(_ duration: TimeInterval) {
        let pause = XCTestExpectation(description: "Intervalle entre deux évaluations")
        pause.isInverted = true
        _ = XCTWaiter().wait(for: [pause], timeout: duration)
    }

    /// Absence prouvée sur une fenêtre bornée (attente inversée, comme le délai du pré-prompt de `DemoPushTests`) :
    /// échoue dès que `condition` devient vraie pendant `duree`. Une lecture instantanée laisserait passer une
    /// présentation encore en cours d'animation (revue B8 de T3b, m8). Jamais un délai fixe sans condition.
    func requireAbsence(_ description: String, pendant duree: TimeInterval = 3, condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let apparition = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        apparition.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [apparition], timeout: duree), .completed, description)
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
    /// Le premier appel du processus de test attend sur `coldTextInputTimeout`, les suivants sur
    /// `defaultTimeout`.
    func focus(_ field: XCUIElement, in container: XCUIElement) {
        let timeout = Self.textInputWarm ? Self.defaultTimeout : Self.coldTextInputTimeout
        require("Le champ à saisir est affiché", timeout: timeout) { self.containerVisible(field) }
        var attempts = 0
        while coveredByKeyboard(field) && attempts < 10 {
            drag(container, fromY: 0.6, toY: 0.3)
            attempts += 1
        }
        require("Le champ à saisir est atteignable hors clavier", timeout: timeout) {
            self.visible(field) && !self.coveredByKeyboard(field)
        }
        field.tap()
        if !hasKeyboardFocus(field) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        }
        require("Le champ a le focus clavier avant la saisie", timeout: timeout) { self.hasKeyboardFocus(field) }
        Self.textInputWarm = true
    }

    /// Délai (donc plafond de temps non décompté) des attentes du PREMIER `focus` du processus de
    /// test : premier champ de saisie interrogé après le premier lancement de l'app sur un
    /// simulateur fraîchement démarré, système de saisie et d'accessibilité à froid. Sur six runs
    /// CI (42489677193 à 42523240142, 18 jobs UI), les requêtes de plus de 5 s du premier test
    /// portent toutes sur le champ `login-email` (6,1 à 10,7 s), dont une de 31 s que XCTest a
    /// lui-même relancée (« Find the "login-email" TextField (retry 1) », run 42523240142,
    /// ipad-landscape) : 29,4 s non décomptées, au-delà du plafond de 15 s. Ces seules attentes
    /// tolèrent 60 s non décomptées, toujours bornées et tracées par `require` ; les `focus`
    /// suivants, et toutes les autres attentes, gardent `defaultTimeout`.
    static let coldTextInputTimeout: TimeInterval = 60
    /// Vrai dès qu'un `focus` a abouti dans ce processus de test (les tests s'y suivent en série).
    private static var textInputWarm = false

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

    /// Glissement entre deux coordonnées du viewport visible (hors clavier) : un glissement, pas une
    /// activation. L'un des deux glissements du socle, avec `dragSliderPastMinimum(_:)`.
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

    /// Amène un curseur (`Slider`) à sa borne basse par un glissement qui part du pouce et finit
    /// AU-DELÀ de l'extrémité gauche de la piste : le contrôle borne lui-même la valeur, quel que
    /// soit l'écart du geste synthétisé. `adjust(toNormalizedSliderPosition: 0)`
    /// vise l'extrémité elle-même, à quelques points près : run 42489677193, UI — ipad-landscape,
    /// son geste (« press, hold, drag, and hold ») part de x = 575,96 et finit à x = 323,25, soit
    /// 7,25 pt dans une piste qui commence à x = 316 et dont le premier pas (5 → 10 km, 19 pas sur
    /// 548 pt) s'arrondit dès 14,4 pt ; le curseur est resté à « Rayon : 10 km » pendant les 15 s
    /// d'attente. La valeur atteinte reste prouvée par l'appelant (libellé ou valeur affichés).
    func dragSliderPastMinimum(_ slider: XCUIElement) {
        require("Le curseur est atteignable") { self.visible(slider) && slider.isEnabled }
        let frame = slider.frame
        let position = min(1, max(0, slider.normalizedSliderPosition))
        // Centre du pouce : la piste utile est réduite d'une demi-largeur de pouce à chaque bout,
        // et le pouce d'un `UISlider` est à peu près aussi large que le contrôle est haut.
        let halfThumb = min(frame.height, frame.width) / 2
        let thumbX = frame.minX + halfThumb + position * (frame.width - 2 * halfThumb)
        // Fin du geste : une cible tactile (44 pt) à gauche de la piste, dans la fenêtre.
        let overshoot: CGFloat = 44
        let endX = max(app.frame.minX + 1, frame.minX - overshoot)
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let y = frame.midY - app.frame.minY
        let start = origin.withOffset(CGVector(dx: thumbX - app.frame.minX, dy: y))
        let end = origin.withOffset(CGVector(dx: endX - app.frame.minX, dy: y))
        // Pression tenue 0,25 s comme `adjust` (au-delà du délai de contenu d'un défilement), puis
        // maintien au point d'arrivée pour que la dernière position soit livrée avant le relâché.
        start.press(forDuration: 0.25, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.25)
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
