import XCTest

/// Socle des tests UI Jolene : helpers repris de
/// `mobile-native/ios-ui-tests/NativePilotUITests/NativePilotTests.swift`
/// (`element`, `visible`, `fullyVisible`, `require`, `scrollTo`, `record`, `attachText`),
/// avec un `tap()` natif pour toute activation (jamais `press(forDuration:)` comme tap) et
/// l'orientation lue dans `JOLENE_UI_ORIENTATION` (portrait | landscape). Les seuls glissements
/// sont `drag(_:fromY:toY:)` (défilement borné de `scrollTo`) et `dragSliderPastMinimum(_:)`
/// (curseur amené à sa borne basse), qui emploient `press(forDuration:thenDragTo:…)` entre deux
/// coordonnées calculées : c'est l'unique API XCUITest de glissement à point de départ contrôlé,
/// et elle n'active rien. Le défilement tient le doigt immobile à l'arrivée : aucun élan après le geste, sauf le
/// glissement de secours de `scrollTo` après deux glissements restés sans effet (feuille à crans), suivi d'une attente
/// de l'arrêt du mouvement ; le premier de chaque appel est consigné. Aucune attente arbitraire : toutes passent par `require` (prédicat
/// borné, délai fonctionnel et budget de blocage distincts) ou, pour décider de rejouer un geste perdu, par
/// `attendreSansEchec` (même décompte, mêmes budgets et même trace, sans échec sur condition fausse ; chaque rejeu est
/// consigné par `consignerRejeu`). `require` ne borne que l'évaluation
/// de conditions : les actions (`tap`, `typeText`, glissements) n'y passent pas et restent
/// soumises aux seuls délais propres à XCTest. La preuve est l'assertion ; les captures
/// (`record`) ne sont que des artefacts pour l'humain.
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
        // Garde de repos (`GardeRepos.swift`) : posée une fois par processus du lanceur, remise à zéro à chaque test.
        GardeRepos.debutDeTest(name)
    }

    /// Fin du budget de blocage à froid (`coldStallBudget`), quelle que soit l'issue du test ; puis,
    /// sur échec : capture, dump d'accessibilité et état du processus, sans envoyer `self` au main actor.
    override func tearDownWithError() throws {
        MainActor.assumeIsolated { JoleneUITestCase.coldStart = false }
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

    /// Élément présent, à l'écran et atteignable. `isHittable` n'est demandé qu'APRÈS avoir vérifié qu'une part réelle
    /// du cadre (au moins 1 pt sur 1 pt) est dans la fenêtre : sur une ligne de liste SwiftUI sortie de l'écran, XCTest
    /// ÉCHOUE au lieu de répondre faux (« Failed to determine hittability … Activation point invalid and no suggested
    /// hit points based on element frame », runs 43276693380 et 43296247455, iPad paysage, `DemoPreferencesTests`,
    /// interrupteur `prefs-sms-alertes` en haut d'un écran défilé vers le bas). Même règle qu'avant, ordre inversé.
    func visible(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let cadre = element.frame
        let part = app.frame.intersection(cadre)
        guard !cadre.isEmpty, !part.isNull, part.width >= 1, part.height >= 1 else { return false }
        return element.isHittable
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

    /// Élément recouvert, même en partie, par une barre de navigation ATTEIGNABLE : celle de l'écran
    /// au premier plan ; la barre d'un écran recouvert par une feuille ne l'est pas et n'est pas
    /// comptée (`PasDeDefilement.recouvertParUneBarre`).
    func coveredByNavigationBar(_ element: XCUIElement) -> Bool {
        let barres = app.navigationBars.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }.map(\.frame)
        return PasDeDefilement.recouvertParUneBarre(element.frame, barres: barres)
    }

    /// Part maximale du délai de `require` décomptée pour UNE évaluation de la condition. Une
    /// évaluation (quelques requêtes d'accessibilité) dure normalement bien moins de 5 s. Au-delà,
    /// quelque chose est bloqué sans que le runner puisse dire quoi : l'observateur (runner saturé)
    /// ou l'app, dont le serveur d'accessibilité répond sur le thread principal, si bien qu'un gel de
    /// l'app allonge l'évaluation exactement comme un runner saturé. Run 42489677193, UI — iphone :
    /// une seule requête « Find the "chip-weekend" Button » a duré 12,5 s (t = 70,4 → 82,9 s), la
    /// capture d'échec 9,5 s et le relancement suivant 10,7 s au lieu de 1,8 s ; le délai de 15 s
    /// d'alors (`XCTNSPredicateExpectation`) a expiré après UNE évaluation, sans qu'aucune n'ait
    /// observé l'app après le blocage, alors que l'arbre d'accessibilité de fin montrait la chip en
    /// place (402 × 874, cadre {122.7, 124, 104, 44}).
    static let maximumChargedEvaluation: TimeInterval = 5
    /// Intervalle entre deux évaluations, celui de `XCTNSPredicateExpectation`.
    static let evaluationInterval: TimeInterval = 1
    /// Délai fonctionnel par défaut de `require` : temps décompté accordé à la condition.
    static let defaultTimeout: TimeInterval = 15
    /// Budget de blocage par défaut de `require` : temps non décompté toléré sur un appel, quel que
    /// soit son délai fonctionnel. L'incident ci-dessus (7,5 s non décomptées) reste dessous.
    static let defaultStallBudget: TimeInterval = 15
    /// Budget de blocage « à froid », réservé au PREMIER test du processus de test : premier
    /// lancement de l'app sur un simulateur fraîchement démarré, systèmes de saisie et
    /// d'accessibilité à froid. Constats CI : sur six runs (42489677193 à 42523240142, 18 jobs UI),
    /// les requêtes de plus de 5 s du premier test portent sur le champ `login-email` (6,1 à
    /// 10,7 s), et le pire cas est une évaluation de 34,4 s, dont une requête de 31 s que XCTest a
    /// lui-même relancée (« Find the "login-email" TextField (retry 1) », run 42523240142,
    /// ipad-landscape : 29,4 s non décomptées, au-delà de 15 s) ; sur la tête be551b66, l'attente
    /// « La session démo est prête » (DemoAccueilTests) a bloqué à froid sur 3 des 9 jobs UI
    /// (évaluations de 5,8 à 6,5 s). 60 s couvrent ce pire cas observé (34,4 s) avec une marge. Le budget ne vaut
    /// que pour ce test : `coldStart` tombe dans son `tearDown`, et chaque `require` qui l'emploie
    /// le trace (activité XCTest « Budget de blocage à froid … »). Les tests suivants, y compris
    /// leurs `focus` et leurs attentes de session, gardent `defaultStallBudget`.
    static let coldStallBudget: TimeInterval = 60
    /// Vrai jusqu'au `tearDown` du premier test du processus de test (les tests s'y suivent en
    /// série, `-parallel-testing-enabled NO`), quelle que soit son issue.
    private static var coldStart = true

    /// Attente bornée d'un état de l'app : la condition est évaluée environ chaque seconde jusqu'à
    /// être vraie. Deux bornes distinctes, mesurées sur l'horloge monotone
    /// (`ProcessInfo.systemUptime`) :
    /// - délai fonctionnel `timeout` : temps DÉCOMPTÉ (chaque évaluation pour sa durée mesurée,
    ///   plafonnée à `maximumChargedEvaluation` ; chaque intervalle pour sa durée mesurée) au terme
    ///   duquel une condition encore fausse fait échouer l'attente. Sans blocage, l'attente équivaut
    ///   à `XCTNSPredicateExpectation` sur `timeout` ;
    /// - budget de blocage `stallBudget` (`defaultStallBudget`, 15 s, indépendant de `timeout`) :
    ///   temps NON décompté toléré sur l'appel, c'est-à-dire l'excédent des évaluations bloquées
    ///   au-delà du plafond, blocage de l'observateur OU du thread principal de l'app,
    ///   indiscernables côté runner. Au-delà du budget, l'attente échoue aussitôt (« observateur ou
    ///   thread principal de l'app bloqué … »), même si la condition est vraie. Dans le premier test
    ///   du processus seulement, le budget est porté à `coldStallBudget` (60 s), et chaque appel
    ///   concerné le trace par une activité XCTest.
    /// Un appel dure donc au plus environ `timeout` + budget de blocage, plus la durée de
    /// l'évaluation qui franchit l'une des deux bornes. Évaluation de grâce : si l'évaluation qui
    /// épuise le délai était bloquée, une seule évaluation de plus est accordée, sous le même
    /// budget, pour que l'état soit constaté après le blocage. Règles exactes et tests :
    /// `RequireWait` (fichier partagé avec JoleneCoreTests, `RequireWaitTests`).
    ///
    /// Tout temps non décompté est tracé, attente réussie comprise : activité XCTest et pièce jointe
    /// texte `<proofPrefix>-attente-bloquee-<fichier>-<ligne>.txt` (chaque évaluation bloquée, sa
    /// durée mesurée, le budget appliqué), que le résumé CI (`ios-swift-ci.yml`) relève dans sa
    /// section « Attentes bloquées absorbées », avec une annotation par appelant.
    ///
    /// Une évaluation qui ne rend jamais la main n'est pas interrompue par `require`, qui ne mesure
    /// qu'à son retour : les délais propres à XCTest pour les requêtes d'accessibilité passent
    /// avant (XCTest relance puis abandonne lui-même une requête sans réponse, avec son propre
    /// échec) ; à défaut, seul `executionTimeAllowance` borne le test, et seulement si xcodebuild
    /// tourne avec `-test-timeouts-enabled YES` (cas de la CI). Quand XCTest interrompt ainsi le
    /// test, la trace du temps non décompté de cet appel est perdue : elle n'est écrite qu'au
    /// retour de la boucle. Tout autre échec est rapporté à la ligne de l'appelant.
    func require(_ description: String, timeout: TimeInterval = JoleneUITestCase.defaultTimeout,
                 stallBudget: TimeInterval = JoleneUITestCase.defaultStallBudget,
                 file: StaticString = #filePath, line: UInt = #line, condition: () -> Bool) {
        attendre(description, timeout: timeout, stallBudget: stallBudget, conditionFausseEchoue: true,
                 file: file, line: line, condition: condition)
    }

    /// Attente bornée SANS échec sur condition fausse : même décompte, mêmes budgets de blocage (normal et à froid), même
    /// trace (`traceUncharged`) que `require`, mais une condition encore fausse au terme du délai rend `false` au lieu
    /// d'échouer. Un budget de blocage dépassé échoue toujours, comme dans `require` : un gel n'est jamais absorbé par un
    /// rejeu de geste (revue B8 de la vague 5, 5ᵉ tour, M1). Réservée au choix de rejouer un geste perdu
    /// (`toucherSeConnecter`, `toucherEtRejouerSiPerdu`, `dragSliderPastMinimum`) ; la preuve passe ensuite par `require`
    /// ou par l'assertion de l'appelant.
    func attendreSansEchec(_ description: String, timeout: TimeInterval,
                           stallBudget: TimeInterval = JoleneUITestCase.defaultStallBudget,
                           file: StaticString = #filePath, line: UInt = #line, condition: () -> Bool) -> Bool {
        attendre(description, timeout: timeout, stallBudget: stallBudget, conditionFausseEchoue: false,
                 file: file, line: line, condition: condition)
    }

    /// Corps commun de `require` et `attendreSansEchec` : vrai si la condition est constatée vraie.
    @discardableResult
    private func attendre(_ description: String, timeout: TimeInterval, stallBudget: TimeInterval,
                          conditionFausseEchoue: Bool, file: StaticString, line: UInt,
                          condition: () -> Bool) -> Bool {
        let s = Self.seconds
        let cold = Self.coldStart && Self.coldStallBudget > stallBudget
        let budget = cold ? Self.coldStallBudget : stallBudget
        if cold {
            XCTContext.runActivity(named: "Budget de blocage à froid \(s(budget)) au lieu de \(s(stallBudget)) "
                                   + "(premier test du processus) : « \(description) »") { _ in }
        }
        let wait = RequireWait.run(
            timeout: timeout, stallBudget: budget, maximumCharged: Self.maximumChargedEvaluation,
            interval: Self.evaluationInterval,
            now: { ProcessInfo.processInfo.systemUptime },
            evaluate: condition,
            pause: { self.pauseBetweenEvaluations($0) })
        if wait.needsTrace {
            traceUncharged(wait, description: description, cold: cold, normalBudget: stallBudget,
                           conditionFausseEchoue: conditionFausseEchoue, file: file, line: line)
        }
        let budgetLabel = "budget de blocage \(s(budget))\(cold ? " à froid" : "")"
        switch wait.outcome {
        case .satisfied:
            return true
        case .stallBudgetExceeded:
            let detail = "\(wait.stalls.count) évaluation(s) bloquée(s) sur \(wait.evaluations), la plus longue "
                + "\(s(wait.longestStall)) ; condition \(wait.lastEvaluation ? "vraie" : "fausse") à la dernière"
            XCTFail("\(description) — observateur ou thread principal de l'app bloqué \(s(wait.uncharged)) non décomptées "
                    + "(\(budgetLabel)) : \(detail)", file: file, line: line)
        case .conditionFalse:
            guard conditionFausseEchoue else { return false }
            let stall = wait.needsTrace ? ", plus \(s(wait.uncharged)) de blocage non décomptées (\(budgetLabel))" : ""
            let grace = wait.graceGranted ? ", évaluation de grâce comprise" : ""
            XCTFail("\(description) — condition fausse à chacune des \(wait.evaluations) évaluations sur \(s(timeout)) "
                    + "décomptées\(stall)\(grace)", file: file, line: line)
        }
        return false
    }

    /// Consigne le temps non décompté d'un `require`, que l'attente réussisse ou non : activité
    /// XCTest (journal du xcresult) et pièce jointe texte conservée, nommée avec `proofPrefix`. Le
    /// résumé CI lit les lignes « Appelant », « Issue », « Temps non décompté » et « Budget de
    /// blocage » : en changer le libellé, c'est changer `ios-swift-ci.yml`.
    private func traceUncharged(_ wait: RequireWait, description: String, cold: Bool, normalBudget: TimeInterval,
                                conditionFausseEchoue: Bool = true, file: StaticString, line: UInt) {
        let s = Self.seconds
        let fileName = (String(describing: file) as NSString).lastPathComponent
        let outcome: String
        switch wait.outcome {
        case .satisfied: outcome = "condition vraie"
        case .conditionFalse: outcome = conditionFausseEchoue
            ? "échec, condition fausse au terme du délai"
            : "condition fausse au terme du délai, sans échec (l'appelant décide de la suite)"
        case .stallBudgetExceeded: outcome = "échec, budget de blocage dépassé"
        }
        let budget = cold
            ? "\(s(wait.stallBudget)) à froid — premier test du processus, budget normal \(s(normalBudget))"
            : s(wait.stallBudget)
        let stalls = wait.stalls.map { stall in
            "  évaluation n° \(stall.index) (début à +\(s(stall.start))) : \(s(stall.duration)) mesurées, "
                + "\(s(wait.maximumCharged)) décomptées, \(s(stall.duration - wait.maximumCharged)) non décomptées"
        }
        let report = [
            "Attente : \(description)",
            "Appelant : \(fileName):\(line)",
            "Issue : \(outcome)",
            "Délai fonctionnel : \(s(wait.timeout)) ; décompté : \(s(wait.charged + wait.pauses)) "
                + "(évaluations \(s(wait.charged)), intervalles mesurés \(s(wait.pauses)))",
            "Temps non décompté : \(s(wait.uncharged))",
            "Budget de blocage : \(budget)",
            "Évaluations : \(wait.evaluations), dont \(wait.stalls.count) bloquée(s) au-delà de \(s(wait.maximumCharged)) :",
        ] + stalls + [
            "Évaluation de grâce après blocage : \(wait.graceGranted ? "accordée" : "non")",
            "Origine : observateur (runner) ou thread principal de l'app, indiscernables côté runner.",
        ]
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "\(proofPrefix)-attente-bloquee-\((fileName as NSString).deletingPathExtension)-\(line).txt"
        attachment.lifetime = .keepAlways
        let activity = "Attente « \(description) » : \(s(wait.uncharged)) non décomptées "
            + "(budget de blocage \(s(wait.stallBudget))\(cold ? " à froid" : "")), \(outcome)"
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

    /// Consigne le rejeu d'un geste resté sans effet : pièce jointe au format du relevé « Attentes bloquées absorbées »
    /// d'`ios-swift-ci.yml` (lignes « Attente », « Appelant », « Issue », annotation par appelant), visible même dans un
    /// job vert, comme `DemoPointageUITestCase.basculer` (revue B8 de la vague 5, 5ᵉ tour, M2). Des rejeux récurrents au
    /// même appelant signaleraient un défaut « il faut toucher deux fois » à instruire, pas un simple geste perdu. La ligne
    /// « Nature : geste rejoué » fait annoncer la trace comme un rejeu, sans temps non décompté ni budget (revue B8 de la
    /// vague 5, 6ᵉ tour, m3).
    func consignerRejeu(_ attente: String, issue: String, file: StaticString, line: UInt) {
        let fichier = (String(describing: file) as NSString).lastPathComponent
        let rapport = ["Attente : \(attente)", "Appelant : \(fichier):\(line)", "Nature : geste rejoué", "Issue : \(issue)"]
            .joined(separator: "\n")
        XCTContext.runActivity(named: "Geste rejoué — « \(attente) » : \(issue)") { _ in }
        attachText(rapport, name: "\(proofPrefix)-attente-bloquee-\((fichier as NSString).deletingPathExtension)-\(line).txt")
    }

    /// Consigne un geste resté sans effet que le socle n'a PAS rejoué : toucher reçu (état relu changé) sans effet dans la
    /// fenêtre, ou témoin du rejeu illisible (`toucherOnglet`). Même format que `consignerRejeu`, ligne « Nature : geste
    /// non rejoué », annoncée à part par le relevé d'`ios-swift-ci.yml` : un rejeu désactivé ne passe pas inaperçu dans un
    /// job vert (revue B8 de #1203, M1 et m5).
    func consignerNonRejeu(_ attente: String, issue: String, file: StaticString, line: UInt) {
        let fichier = (String(describing: file) as NSString).lastPathComponent
        let rapport = ["Attente : \(attente)", "Appelant : \(fichier):\(line)", "Nature : geste non rejoué", "Issue : \(issue)"]
            .joined(separator: "\n")
        XCTContext.runActivity(named: "Geste non rejoué — « \(attente) » : \(issue)") { _ in }
        attachText(rapport, name: "\(proofPrefix)-attente-bloquee-\((fichier as NSString).deletingPathExtension)-\(line).txt")
    }

    /// Consigne un témoin d'onglet ambigu (plus d'un onglet lu « Selected ») : un seul toucher, aucun rejeu. Attendu sur
    /// iPad dans l'espace établissement sous iPadOS 26.2 (`exigerTemoinOnglet`), où chaque toucher d'onglet en produit
    /// un ; réservé aux formats iPad (hors iPad, `consignerNonRejeu` garde l'avertissement). Ligne « Nature : témoin ambigu », comptée à part par le relevé d'`ios-swift-ci.yml`, qui regroupe ces traces
    /// en une ligne et une annotation par test : elles ne masquent plus les autres annotations (revue B8 de #1203, m2).
    func consignerTemoinAmbigu(_ attente: String, issue: String, file: StaticString, line: UInt) {
        let fichier = (String(describing: file) as NSString).lastPathComponent
        let rapport = ["Attente : \(attente)", "Appelant : \(fichier):\(line)", "Nature : témoin ambigu", "Issue : \(issue)"]
            .joined(separator: "\n")
        XCTContext.runActivity(named: "Témoin d'onglet ambigu — « \(attente) » : \(issue)") { _ in }
        attachText(rapport, name: "\(proofPrefix)-attente-bloquee-\((fichier as NSString).deletingPathExtension)-\(line).txt")
    }

    // MARK: Actions

    /// Touche « Se connecter » puis exige la session (`sessionPrete`) sur `timeout` décomptées au total. Un toucher resté
    /// sans aucun effet est rejoué une seule fois, et consigné (`consignerRejeu`) : écran de connexion inchangé, bouton
    /// toujours actif (il se désactive dès l'envoi, `LoginScreen.canSubmit`), aucune erreur affichée. Run 43962293492,
    /// UI — ipad-landscape, `DemoPushTests.testPrePromptDeuxiemeSessionPuisActiver` : toucher synthétisé sur le bouton
    /// entièrement visible, 5 s après le dernier défilement, puis 30 s sans envoi ni erreur (capture d'échec : mot de
    /// passe saisi, focus clavier toujours sur le champ). Un toucher qui a bien envoyé le formulaire n'est jamais rejoué :
    /// le bouton est alors désactivé, ou l'écran a changé. La première fenêtre (8 s) passe par `attendreSansEchec` :
    /// blocages décomptés, budgetés et tracés comme dans `require`. La preuve reste le `require` final, sur le reste du
    /// délai (revue B8 de la vague 5, 5ᵉ tour, m1 : 30 s au total, pas 38). Le budget de blocage vaut pour chaque
    /// attente, comme partout ailleurs : 15 s pour la première fenêtre, 15 s pour le `require` final (60 s chacune à
    /// froid, premier test du processus). Un gel réel dépasse le budget de l'une des deux et fait échouer le test ; un
    /// blocage absorbé de part et d'autre peut cumuler jusqu'à deux budgets (revue B8 de la vague 5, 6ᵉ tour, m2).
    func toucherSeConnecter(_ submit: XCUIElement, _ description: String, timeout: TimeInterval = 30,
                            file: StaticString = #filePath, line: UInt = #line, sessionPrete: () -> Bool) {
        let fenetre = min(8, timeout / 2)
        submit.tap()
        if !attendreSansEchec("\(description) (premier toucher)", timeout: fenetre, file: file, line: line,
                              condition: sessionPrete),
           submit.exists, submit.isEnabled, visible(submit), !element("login-error").exists {
            consignerRejeu(description, issue: "« Se connecter » touché sans effet en \(Self.seconds(fenetre)) "
                           + "(bouton actif, aucune erreur) : un seul nouveau toucher", file: file, line: line)
            submit.tap()
        }
        require(description, timeout: timeout - fenetre, file: file, line: line, condition: sessionPrete)
    }

    /// Fenêtre de constat d'un toucher avant de décider d'un rejeu (`toucherEtRejouerSiPerdu`). Les témoins d'un toucher
    /// reçu (onglet sélectionné, case cochée, étoile désactivée pendant l'appel) apparaissent sans attendre le réseau.
    static let fenetreToucher: TimeInterval = 5

    /// Socle générique du rejeu d'un toucher perdu, sur le modèle de `toucherSeConnecter` et de
    /// `DemoPreferencesTests.prefsBasculer`. Série 45799922589 (main `f599cab3`), UI lot 1 — ipad-landscape : tentative 1,
    /// `DemoFavorisTests.swift:33`, étoile touchée puis 15 s sans sauvegarde ; tentative 2, `DemoFiltresTests.swift:95`,
    /// onglet Profil touché puis 15 s sans hub. Verts sur les autres formats et à la tentative suivante : toucher
    /// synthétisé perdu, pas un défaut de l'app.
    ///
    /// Le geste `toucher` est fait une fois. Si `effet` n'est pas constaté sur `fenetre` (`attendreSansEchec` : blocages
    /// décomptés, budgetés et tracés comme dans `require`), le geste est rejoué UNE seule fois, et seulement si
    /// `rienNAChange` relit l'état d'avant le toucher : aucun écran intermédiaire, contrôle toujours actif, aucune
    /// erreur. Un toucher reçu, même lent, n'est donc jamais rejoué. Chaque rejeu est consigné (`consignerRejeu`, relevé
    /// « Geste rejoué » de la CI) ; un effet absent sans rejeu permis l'est aussi (`consignerNonRejeu`). Rien n'est prouvé ici :
    /// l'appelant exige l'effet ensuite (`require`), avec le message d'avant ; une double bascule y échouerait. Réservé
    /// aux gestes dont l'état relu prouve l'absence d'effet (onglets, cases, chips, étoiles) : jamais un envoi, un
    /// paiement, une signature ou une candidature sans relecture qui prouve que rien n'est parti.
    func toucherEtRejouerSiPerdu(_ attente: String, fenetre: TimeInterval = JoleneUITestCase.fenetreToucher,
                                 file: StaticString = #filePath, line: UInt = #line,
                                 toucher: () -> Void, rienNAChange: () -> Bool, effet: () -> Bool) {
        toucher()
        if attendreSansEchec("\(attente) (premier toucher)", timeout: fenetre, file: file, line: line, condition: effet) {
            return
        }
        guard rienNAChange() else {
            consignerNonRejeu(attente, issue: "effet absent en \(Self.seconds(fenetre)), mais état relu changé ou contrôle "
                              + "inactif : aucun rejeu", file: file, line: line)
            return
        }
        consignerRejeu(attente, issue: "toucher sans effet en \(Self.seconds(fenetre)), état relu inchangé : "
                       + "un seul nouveau toucher", file: file, line: line)
        toucher()
    }

    /// Touche `cible`, puis exige `effet` sous `description`, sur `timeout` décomptées au total, comme un `require` posé
    /// juste après le toucher (même message d'échec ; revue B8 de la vague 5, 5ᵉ tour, m1 : le délai n'est pas allongé).
    /// Un toucher perdu est rejoué une fois (`toucherEtRejouerSiPerdu`) : seulement si `cible` est encore atteignable et
    /// que `rienNAChange` relit l'état d'avant le toucher.
    func toucherPuisExiger(_ cible: XCUIElement, _ description: String,
                           timeout: TimeInterval = JoleneUITestCase.defaultTimeout,
                           fenetre: TimeInterval = JoleneUITestCase.fenetreToucher,
                           file: StaticString = #filePath, line: UInt = #line,
                           rienNAChange: () -> Bool, effet: () -> Bool) {
        let premiere = min(fenetre, timeout / 2)
        toucherEtRejouerSiPerdu(description, fenetre: premiere, file: file, line: line,
                                toucher: { cible.tap() },
                                rienNAChange: { self.visible(cible) && rienNAChange() },
                                effet: effet)
        require(description, timeout: timeout - premiere, file: file, line: line, condition: effet)
    }

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
    /// Délais et budget de blocage par défaut de `require` : le premier champ interrogé à froid
    /// (`login-email`, premier test du processus) relève du budget à froid de `require`
    /// (`coldStallBudget`), pas d'un délai propre à `focus`.
    /// Un champ recouvert par la barre de navigation translucide de l'écran (iPad paysage, run
    /// 42579729412 : `profil-ville-recherche` à y = 104…145 sous la barre 32…140, touché sur la bande
    /// visible de 4 pt, puis sous la barre, sans jamais recevoir le focus) est d'abord redescendu
    /// sous la barre, par glissements bornés.
    func focus(_ field: XCUIElement, in container: XCUIElement) {
        require("Le champ à saisir est affiché") { self.containerVisible(field) }
        var attempts = 0
        while attempts < 10 {
            if coveredByKeyboard(field) {
                // Un pavé sans touche Entrée qui recouvre le champ est fermé par « OK », jamais par un glissement
                // (`fermerLePaveNumerique`, « Gel iPhone CI — 16/11/2026 ») ; un autre clavier reste ouvert.
                if app.buttons.matching(identifier: "clavier-ok").firstMatch.exists {
                    fermerLePaveNumerique()
                } else {
                    drag(container, fromY: 0.6, toY: 0.3)
                }
            } else if coveredByNavigationBar(field) {
                drag(container, fromY: 0.4, toY: 0.6)
            } else {
                break
            }
            attempts += 1
        }
        require("Le champ à saisir est atteignable hors clavier") { self.visible(field) && !self.coveredByKeyboard(field) }
        field.tap()
        if !hasKeyboardFocus(field) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        }
        require("Le champ a le focus clavier avant la saisie") { self.hasKeyboardFocus(field) }
    }

    /// Ferme un pavé sans touche Entrée (numérique, décimal, téléphonique) par son bouton « OK » (`clavier-ok`,
    /// `BoutonClavierOK` de JoleneDesign), puis attend la disparition du clavier : à appeler AVANT tout défilement. Au run
    /// 43889328109 (iPhone 17, iOS 26.2), un glissement qui fermait le pavé (`.scrollDismissesKeyboard(.immediately)`) a
    /// gelé le serveur de rendu du simulateur, puis tous les éclats suivants (DECISIONS_LOT2, « Gel iPhone CI —
    /// 16/11/2026 »). Sans clavier ouvert, rien à faire. Un seul « OK » est exigé : la barre suit le focus du champ, deux
    /// champs numériques d'un même écran n'empilent jamais deux boutons.
    func fermerLePaveNumerique() {
        guard app.keyboards.firstMatch.exists else { return }
        let boutons = app.buttons.matching(identifier: "clavier-ok")
        let ok = boutons.firstMatch
        require("Le bouton OK est affiché au-dessus du pavé") { self.visible(ok) }
        XCTAssertEqual(boutons.count, 1, "un seul bouton OK au-dessus du pavé")
        XCTAssertEqual(ok.label, "OK", "libellé d'interface standard")
        ok.tap()
        require("Le pavé est fermé par OK, sans défilement") { !self.app.keyboards.firstMatch.exists }
    }

    // MARK: Barre d'onglets

    /// Symboles SF des cinq onglets de `MainTabView`. UIKit expose un bouton d'onglet avec,
    /// pour identifiant, le nom de l'image de son `Label` (`house`, `magnifyingglass`…) ; le
    /// `.accessibilityIdentifier("tab-*")` SwiftUI est porté par le contenu de l'onglet, pas
    /// par son bouton (vérifié sur les dumps iPhone iOS 18.6 et iPad iOS 18.6).
    static let tabSymbols: [String: String] = [
        "tab-accueil": "house", "tab-explorer": "magnifyingglass", "tab-missions": "list.clipboard",
        "tab-revenus": "banknote", "tab-profil": "person",
        // Lot 5 (T2a) : onglets de l'espace établissement (`EtablissementTabView`, D13).
        "tab-etab-accueil": "house", "tab-etab-missions": "list.clipboard", "tab-etab-presences": "checkmark.seal",
        "tab-etab-messages": "bubble.left.and.bubble.right", "tab-etab-compte": "person.crop.circle",
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
    /// L'onglet est d'abord amené dans la page affichée de la barre haute de l'iPad (`amenerOngletDansLaPage`).
    func tabButton(_ identifier: String, label: String) -> XCUIElement {
        amenerOngletDansLaPage(identifier, label: label)
        return boutonOnglet(identifier, label: label)
    }

    private func boutonOnglet(_ identifier: String, label: String) -> XCUIElement {
        let buttons = tabButtons
        let byIdentifier = buttons.matching(identifier: identifier).firstMatch
        if byIdentifier.exists { return byIdentifier }
        if let symbol = Self.tabSymbols[identifier] {
            let bySymbol = buttons.matching(identifier: symbol).firstMatch
            if bySymbol.exists { return bySymbol }
        }
        return buttons[label]
    }

    /// Touche un onglet de la barre (`tabButton`). Un toucher perdu est rejoué UNE fois (`toucherEtRejouerSiPerdu`) :
    /// seulement si l'onglet sélectionné avant le toucher est lisible, n'est pas l'onglet visé, et reste le même 5 s plus
    /// tard, barres de navigation inchangées et onglet visé toujours atteignable (`lireBarreOnglets`). La sélection change
    /// dès que le toucher est reçu, avant tout chargement du contenu : un onglet reçu n'est jamais retouché (un second
    /// toucher le ramènerait à sa racine). Onglet visé déjà lu sélectionné (lecture juste ou non), sélection illisible, ou
    /// ambiguë (plus d'un onglet lu « Selected ») : un seul toucher, jamais de rejeu ; une sélection illisible est
    /// consignée (`consignerNonRejeu`), une sélection ambiguë aussi hors iPad, et à part sur iPad, où elle est attendue
    /// (`consignerTemoinAmbigu`, regroupée par test au relevé), pour qu'un rejeu désactivé se voie au relevé de la CI, et
    /// `exigerTemoinOnglet` prouve sur chaque format que le témoin est lisible (revue B8 de #1203, M1).
    /// Cas laissé armé (revue B8 de #1203, delta court, m1) : sur l'iPad, espace établissement, la page de la barre peut
    /// masquer l'onglet courant (ouvrir Compte depuis Accueil fait passer en page 2) ; un seul onglet est alors lu
    /// « Selected », et ce peut être l'onglet lu en trop par iPadOS (Présences), pas l'onglet courant. Le rejeu reste
    /// possible, sans danger : l'effet est lu sur l'onglet VISÉ, et l'instantané doit être identique à celui d'avant.
    /// Rien n'est exigé ici, pas même la sélection : l'appelant exige le contenu de l'onglet, avec son message et
    /// son délai d'avant. Ce délai ne court qu'après la fenêtre, donc au plus 5 s plus tard, et seulement quand la
    /// sélection n'a pas été constatée.
    func toucherOnglet(_ identifier: String, label: String, file: StaticString = #filePath, line: UInt = #line) {
        let onglet = tabButton(identifier, label: label)
        let symbole = Self.tabSymbols[identifier]
        let avant = lireBarreOnglets()
        guard let selection = avant.selection else {
            consignerNonRejeu("Le témoin du rejeu d'onglet est lisible avant le toucher de \(label)",
                              issue: "aucun bouton d'onglet lu « Selected » (\(avant.onglets.count) lu(s)) : un seul toucher, "
                                  + "rejeu d'onglet désactivé", file: file, line: line)
            onglet.tap()
            return
        }
        // Plus d'un onglet lu « Selected » (iPadOS 26.2, iPad portrait et paysage, espace établissement : un onglet reste
        // lu sélectionné quel que soit l'onglet courant, runs 45967481048 et 45995190132) : témoin ambigu, aucun rejeu.
        let selectionnes = avant.libellesSelectionnes
        guard selectionnes.count == 1 else {
            let attente = "Témoin d'onglet ambigu avant le toucher de \(label)"
            let issue = "\(selectionnes.count) onglets lus « Selected » (\(selectionnes.sorted().joined(separator: ", "))) : "
                + "un seul toucher, rejeu d'onglet désactivé"
            // Attendu sur iPad seulement : ailleurs, un rejeu désactivé reste un avertissement « Geste non rejoué »
            // (revue B8 de #1205, m1).
            if proofPrefix.hasPrefix("ipad-") {
                consignerTemoinAmbigu(attente, issue: issue, file: file, line: line)
            } else {
                consignerNonRejeu(attente, issue: issue, file: file, line: line)
            }
            onglet.tap()
            return
        }
        // Onglet visé déjà lu « Selected », que la lecture soit juste ou non : un seul toucher, jamais de rejeu.
        guard !avant.estSelectionne(identifier, symbole: symbole, label: label) else {
            onglet.tap()
            return
        }
        toucherEtRejouerSiPerdu("L'onglet \(label) est lu « Selected » (avant le toucher : \(selection.label))",
                                file: file, line: line,
                                toucher: { onglet.tap() },
                                rienNAChange: { self.lireBarreOnglets() == avant && self.visible(onglet) },
                                effet: { self.lireBarreOnglets().estSelectionne(identifier, symbole: symbole, label: label) })
    }

    /// Ramène à sa racine un onglet souvent déjà COURANT, pile chargée (écran du test empilé sur le hub). Run 45995190132,
    /// UI lot 1 — ipad-landscape, `DemoLitigesTests.swift:239` : Profil touché, onglet déjà sélectionné (jamais rejoué,
    /// par conception), puis 15 s sans la liste du profil. Cause NON établie, deux hypothèses : toucher de `nav-messages`
    /// par l'ancien repli « premier bouton de la barre », ou toucher de l'onglet perdu avec une lecture fausse de
    /// `litiges-screen`. Un retour seulement perdu est exclu : l'ancien code ne touchait le retour qu'après avoir lu
    /// `litiges-screen`, puis exigeait son retrait (`548b1b685`) ; il aurait échoué sur ce retrait, ou rendu la racine
    /// si l'onglet avait dépilé l'écran, jamais sur « La liste du profil est affichée » (revue B8 de #1203, n° 5). À
    /// trancher par l'arbre d'accessibilité d'échec du xcresult de ce job.
    ///
    /// 1. Toucher de l'onglet (`toucherOnglet`), puis 3 s (`attendreSansEchec`) pour la racine : `racine` affichée, aucun
    ///    écran de `empiles`. Qu'un toucher sur l'onglet courant ramène sa pile à la racine ou non, les deux sont normaux.
    /// 2. Sinon, tant qu'un écran de `empiles` est lu (le plus haut d'abord), retour par le SEUL bouton retour du système
    ///    (`BackButton`), puis 5 s pour que cet écran disparaisse. Juste avant le toucher, UN instantané doit montrer
    ///    l'écran empilé encore présent et `BackButton` dans une barre de navigation (`lireRetourSysteme`) : jamais un
    ///    autre bouton de la barre (`nav-messages`, seul bouton de la racine du Profil, déjà touché à la place du retour,
    ///    `DemoMessagerieTests.retour`). Un retour vers la racine est idempotent : resté sans effet (même écran toujours
    ///    lu), il est rejoué UNE fois au plus par appel, et consigné (`consignerRejeu`) juste avant le geste, jamais pour
    ///    un rejeu abandonné (écran retiré pendant la lecture, échec net) ; encore sans effet, l'écran est
    ///    exigé retiré (`require`, échec net). Bouton retour du système absent : échec net.
    /// 3. Ni racine ni écran connu : aucun geste (revue B8 de #1203, M1 : un retour à l'aveugle dépilerait un écran inconnu
    ///    ou un autre onglet, et masquerait le défaut). Consigné (`consignerNonRejeu`), avec les barres de navigation lues ;
    ///    l'appelant exige ensuite la racine, avec son message d'avant, et échoue s'il le faut : rien n'est masqué.
    func revenirALaRacine(_ identifier: String, label: String, racine: String, empiles: [String],
                          file: StaticString = #filePath, line: UInt = #line) {
        toucherOnglet(identifier, label: label, file: file, line: line)
        let empile = { empiles.first { self.element($0).exists } }
        let aLaRacine = { empile() == nil && self.containerVisible(self.element(racine)) }
        if attendreSansEchec("L'onglet \(label) revient à sa racine", timeout: 3, file: file, line: line, condition: aLaRacine) {
            return
        }
        var precedent: String?
        var rejoue = false
        for _ in 0...(2 * empiles.count) {
            guard let ecran = empile() else { break }
            let rejeu = ecran == precedent
            if rejeu && rejoue {
                require("L'écran \(ecran) est retiré", file: file, line: line) { !self.element(ecran).exists }
                continue
            }
            // Bouton lu une fois par tour, sur un instantané où l'écran empilé est encore présent.
            var lu = RetourSystemeLu()
            _ = attendreSansEchec("Le bouton retour du système est lu sur \(ecran)", timeout: 5, file: file, line: line) {
                lu = self.lireRetourSysteme(sur: ecran)
                return lu.lisible && (!lu.ecranPresent || lu.boutonPresent)
            }
            guard lu.lisible else {
                XCTFail("Le bouton retour du système est lu sur \(ecran) — instantané de l'app illisible pendant 5 s : "
                        + "aucun retour à l'aveugle", file: file, line: line)
                return
            }
            guard lu.ecranPresent else {
                precedent = nil // écran retiré de lui-même pendant la lecture : aucun retour à faire pour lui
                continue
            }
            guard lu.boutonPresent else {
                XCTFail("Le bouton retour du système (BackButton) est disponible sur \(ecran) — absent de l'instantané "
                        + "pendant 5 s : aucun autre bouton de la barre n'est touché", file: file, line: line)
                return
            }
            // Rejeu consigné seulement ici, juste avant le geste : écran retiré pendant la lecture ou échec net plus
            // haut, aucun rejeu n'est compté (revue B8 de #1203, n° 5, m1).
            if rejeu {
                rejoue = true
                consignerRejeu("L'écran \(ecran) est retiré par le retour", issue: "retour sans effet en 5 s (écran "
                               + "toujours lu) : un seul nouveau retour", file: file, line: line)
            }
            app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch.tap()
            precedent = ecran
            _ = attendreSansEchec("L'écran \(ecran) est retiré par le retour", timeout: 5, file: file, line: line) {
                !self.element(ecran).exists
            }
        }
        guard !aLaRacine(), empile() == nil else { return }
        let barres = lireBarreOnglets().barresDeNavigation.map { "« \($0) »" }.joined(separator: ", ")
        consignerNonRejeu("L'onglet \(label) revient à sa racine",
                          issue: "\(racine) absent et aucun écran connu lu (\(empiles.joined(separator: ", "))) ; barres "
                              + "de navigation lues : \(barres.isEmpty ? "aucune" : barres) : aucun geste", file: file, line: line)
    }

    /// Sur UN instantané : l'écran `ecran` est présent, et une barre de navigation porte le bouton retour du système
    /// (identifiant `BackButton`, actif, cadre dans la fenêtre). Aucun autre bouton n'est jamais retenu comme retour.
    func lireRetourSysteme(sur ecran: String) -> RetourSystemeLu {
        var lu = RetourSystemeLu()
        guard let racine = try? app.snapshot() else { return lu }
        lu.lisible = true
        let fenetre = racine.frame
        func parcourir(_ element: XCUIElementSnapshot, dansUneBarre: Bool) {
            if element.identifier == ecran { lu.ecranPresent = true }
            let barre = dansUneBarre || element.elementType == .navigationBar
            if barre, element.elementType == .button, element.identifier == "BackButton", element.isEnabled,
               !element.frame.isEmpty, fenetre.intersects(element.frame) {
                lu.boutonPresent = true
            }
            element.children.forEach { parcourir($0, dansUneBarre: barre) }
        }
        parcourir(racine, dansUneBarre: false)
        return lu
    }

    /// Boutons d'onglet (dans l'élément `TabBar`, ou identifiés par l'un des symboles de `tabSymbols` dans la barre haute
    /// de l'iPad), avec leur état `Selected`, et identifiants des barres de navigation, lus dans UN instantané de l'app,
    /// comme `lirePageDeLaBarre`. Instantané impossible : rien de lisible, donc aucun rejeu.
    func lireBarreOnglets() -> EtatBarreOnglets {
        var etat = EtatBarreOnglets()
        guard let racine = try? app.snapshot() else { return etat }
        let symboles = Set(Self.tabSymbols.keys).union(Self.tabSymbols.values)
        func parcourir(_ element: XCUIElementSnapshot, dansLaBarre: Bool) {
            let barre = dansLaBarre || element.elementType == .tabBar
            if element.elementType == .navigationBar { etat.barresDeNavigation.append(element.identifier) }
            if element.elementType == .button, barre || symboles.contains(element.identifier) {
                etat.onglets.append(BoutonOngletLu(identifiant: element.identifier, label: element.label,
                                                   selectionne: element.isSelected))
            }
            element.children.forEach { parcourir($0, dansLaBarre: barre) }
        }
        parcourir(racine, dansLaBarre: false)
        return etat
    }

    /// Preuve, sur le format courant, que le témoin de `toucherOnglet` est lisible (revue B8 de #1203, M1) : l'onglet
    /// courant est lu « Selected », aucun autre onglet ne l'est, et chaque onglet de `presents` est exposé dans
    /// l'instantané. Sans cette preuve, un témoin illisible désactiverait le rejeu d'onglet sans aucun échec. La lecture
    /// est jointe en texte (`<préfixe>-temoin-onglet-<identifiant>.txt`).
    ///
    /// `espaceEtablissement` : seule exception à l'exclusivité, l'espace établissement sur iPad, en portrait ET en
    /// paysage. Runs 45967481048 (portrait) et 45995190132 (paysage), iPadOS 26.2, `TabView` standard sans trait posé
    /// par l'app : « Présences » y reste lu « Selected » quel que soit l'onglet courant, alors qu'à l'écran seul l'onglet
    /// courant est en surbrillance. Anomalie d'accessibilité ATTRIBUÉE à iPadOS, par élimination, sans reproduction sur
    /// un `TabView` minimal ; témoin : côté soignant, sur le même simulateur, l'exclusivité passe
    /// (`DemoConsultationTests`). Là seulement, des onglets lus en trop sont tolérés s'ils forment un ensemble STABLE :
    /// déduit de la première lecture du test (jamais codé en dur), il doit se retrouver, onglet courant mis à part, à
    /// chaque lecture suivante. La règle dépend donc de l'ordre : une première lecture faite sur l'onglet lu en trop
    /// apprendrait un ensemble vide et ferait échouer la suite (faux rouge, jamais faux vert) ; aucun test actuel ne la
    /// fait. L'onglet courant reste exigé « Selected ». L'ensemble est consigné au relevé de la CI (« Témoin d'onglet
    /// ambigu »). `toucherOnglet` ne rejoue jamais quand plus d'un onglet est lu « Selected ».
    func exigerTemoinOnglet(_ identifier: String, label: String, presents: [(String, String)] = [],
                            espaceEtablissement: Bool = false,
                            file: StaticString = #filePath, line: UInt = #line) {
        let symbole = Self.tabSymbols[identifier]
        var lu = EtatBarreOnglets()
        _ = attendreSansEchec("Le témoin du rejeu d'onglet lit « \(label) » sélectionné", timeout: 5, file: file, line: line) {
            lu = self.lireBarreOnglets()
            return lu.estSelectionne(identifier, symbole: symbole, label: label)
        }
        let lecture = lu.onglets.map { "\($0.label) [\($0.identifiant)]\($0.selectionne ? " Selected" : "")" }
            .joined(separator: ", ")
        attachText("Onglet courant : \(label) (\(identifier))\nBoutons d'onglet lus : \(lecture)",
                   name: "\(proofPrefix)-temoin-onglet-\(identifier).txt")
        XCTAssertTrue(lu.estSelectionne(identifier, symbole: symbole, label: label),
                      "témoin du rejeu d'onglet illisible sur ce format : « \(label) » n'est pas lu sélectionné (\(lecture))",
                      file: file, line: line)
        let enTrop = Set(lu.onglets.filter { $0.selectionne && !$0.designe(identifier, symbole: symbole, label: label) }
            .map(\.label))
        if espaceEtablissement && proofPrefix.hasPrefix("ipad-") {
            if let ensemble = ongletsLusEnTrop {
                XCTAssertEqual(enTrop, ensemble.subtracting([label]),
                               "témoin d'onglet ambigu instable : onglets lus « Selected » en plus de « \(label) » différents de "
                                   + "la première lecture du test (\(ensemble.sorted().joined(separator: ", "))) (\(lecture))",
                               file: file, line: line)
            } else {
                ongletsLusEnTrop = enTrop
                if !enTrop.isEmpty {
                    let orientation = proofPrefix == "ipad-portrait" ? "portrait" : "paysage"
                    consignerTemoinAmbigu("Témoin d'onglet ambigu (iPad \(orientation), établissement) : "
                                              + enTrop.sorted().joined(separator: ", "),
                                          issue: "lu(s) « Selected » en plus de l'onglet courant \(label), anomalie attribuée à "
                                              + "iPadOS : toléré tant que l'ensemble reste stable dans le test ; aucun rejeu "
                                              + "d'onglet tant que plus d'un onglet est lu « Selected »",
                                          file: file, line: line)
                }
            }
        } else {
            XCTAssertTrue(enTrop.isEmpty, "un autre onglet que « \(label) » est lu sélectionné (\(lecture))", file: file, line: line)
        }
        for (autre, libelle) in presents {
            let symboleAutre = Self.tabSymbols[autre]
            XCTAssertTrue(lu.onglets.contains { $0.designe(autre, symbole: symboleAutre, label: libelle) },
                          "l'onglet « \(libelle) » n'est pas exposé au témoin (\(lecture))", file: file, line: line)
        }
    }

    /// Onglets lus « Selected » en plus de l'onglet courant à la première lecture du test (`exigerTemoinOnglet`, espace
    /// établissement sur iPad, portrait et paysage) : chaque test a sa propre instance, donc son propre ensemble.
    private var ongletsLusEnTrop: Set<String>?

    static let pageSuivante = "Page suivante"
    static let pagePrecedente = "Page précédente"

    /// Barre d'onglets haute de l'iPad (iPadOS 18 et suivants) trop large pour la fenêtre : le système n'en montre qu'une
    /// page et ajoute « Page suivante » / « Page précédente ». Les cinq libellés de l'espace établissement (D13 :
    /// 509 pt) dépassent la largeur que la barre reçoit en iPad portrait (820 pt), contrairement à ceux du soignant
    /// (495 pt) : « Compte » reste caché derrière « Page suivante », et le toucher de son bouton ne sélectionne rien
    /// (runs 44398503180 sous iOS 26.2 et local sous iOS 18.6). Comme un utilisateur, on tourne la page avant de toucher
    /// l'onglet : il est caché derrière l'un des deux boutons, ou absent de la page affichée (la seconde page commence à
    /// « Missions », sans « Accueil »). Chaque décision est lue dans UN instantané (`lirePageDeLaBarre`) : pendant
    /// l'animation, « Page suivante » disparaît, et lire son cadre par une requête échouait (« Failed to get matching
    /// snapshot »). Sans pagination (iPhone, iPad paysage, espace soignant), rien n'est lu ni touché.
    private func amenerOngletDansLaPage(_ identifier: String, label: String) {
        guard !app.tabBars.firstMatch.exists else { return }
        let suivante = app.buttons.matching(NSPredicate(format: "label == %@", Self.pageSuivante)).firstMatch
        let precedente = app.buttons.matching(NSPredicate(format: "label == %@", Self.pagePrecedente)).firstMatch
        guard suivante.exists || precedente.exists else { return }
        // Onglet absent de la page affichée : une seule direction de recherche (jamais d'aller-retour), d'abord l'arrière.
        var recherche: XCUIElement?
        for _ in 0..<4 {
            guard let page = lirePageDeLaBarre(identifier, label: label), !page.ongletDansLaPage else { return }
            let bouton: XCUIElement
            if let onglet = page.onglet {
                if let cadre = page.suivante, onglet.maxX > cadre.minX + 1 {
                    bouton = suivante
                } else if let cadre = page.precedente, onglet.minX < cadre.maxX - 1 {
                    bouton = precedente
                } else {
                    return
                }
            } else {
                if recherche == nil { recherche = page.precedente != nil ? precedente : (page.suivante != nil ? suivante : nil) }
                guard let sens = recherche else { return }
                bouton = sens
            }
            guard bouton.exists else { return }
            bouton.tap()
            _ = attendreSansEchec("L'onglet \(label) entre dans la page affichée de la barre", timeout: 3) {
                self.lirePageDeLaBarre(identifier, label: label)?.ongletDansLaPage ?? false
            }
        }
    }

    /// Cadres de l'onglet et des deux boutons de page, lus dans un même instantané de l'app.
    private func lirePageDeLaBarre(_ identifier: String, label: String) -> PageDeBarreOnglets? {
        guard let racine = try? app.snapshot() else { return nil }
        let symbole = Self.tabSymbols[identifier]
        let symboles = Set(Self.tabSymbols.keys).union(Self.tabSymbols.values)
        var page = PageDeBarreOnglets()
        func parcourir(_ element: XCUIElementSnapshot) {
            if element.elementType == .button {
                if element.label == Self.pageSuivante {
                    page.suivante = page.suivante ?? element.frame
                } else if element.label == Self.pagePrecedente {
                    page.precedente = page.precedente ?? element.frame
                } else if page.onglet == nil, element.identifier == identifier || element.identifier == symbole
                            || (element.label == label && symboles.contains(element.identifier)) {
                    page.onglet = element.frame
                }
            }
            element.children.forEach(parcourir)
        }
        parcourir(racine)
        return page
    }

    /// Glissement entre deux coordonnées du viewport visible (hors clavier) : un glissement, pas une
    /// activation. L'un des deux glissements du socle, avec `dragSliderPastMinimum(_:)`.
    /// `avecElan` : relâché en vitesse, sans tenue à l'arrivée. Réservé à `scrollTo`, après des glissements sans élan
    /// restés sans effet (`PasDeDefilement.elanRequis`).
    func drag(_ container: XCUIElement, fromY: CGFloat, toY: CGFloat, avecElan: Bool = false) {
        var viewport = container.frame.intersection(app.frame)
        if app.keyboards.firstMatch.exists {
            let bottom = min(viewport.maxY, app.keyboards.firstMatch.frame.minY)
            viewport.size.height = max(0, bottom - viewport.minY)
        }
        XCTAssertFalse(viewport.isNull || viewport.isEmpty, "Un défilement exige un viewport visible hors clavier")
        guard !viewport.isNull && !viewport.isEmpty else { return }
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        // Jamais un départ sur un curseur, qui capterait le geste (`PasDeDefilement.abscisseDeGlissement`,
        // run 42593592247) : le milieu du viewport, sinon un couloir latéral.
        let curseurs = app.sliders.allElementsBoundByIndex.filter { $0.exists }.map { $0.frame }
        let x = PasDeDefilement.abscisseDeGlissement(viewport: viewport, departY: viewport.minY + viewport.height * fromY,
                                                     obstacles: curseurs) - app.frame.minX
        let top = viewport.minY - app.frame.minY
        let start = origin.withOffset(CGVector(dx: x, dy: top + viewport.height * fromY))
        let end = origin.withOffset(CGVector(dx: x, dy: top + viewport.height * toY))
        // Doigt tenu immobile 0,3 s à l'arrivée avant le relâché : vitesse de relâché nulle, donc aucun élan. Sans
        // cette tenue, le défilement continuait sur sa lancée et l'action suivante (toucher, curseur, lecture de
        // l'atteignabilité) tombait sur une liste en mouvement : le toucher arrêtait le défilement au lieu d'activer
        // le contrôle (runs 42664161349 et 43276693380 : interrupteur de complétion, « Se connecter » de
        // l'inscription, curseur du rayon, « Activation point invalid » d'un interrupteur des préférences).
        // Avec élan (`avecElan`) : aucun maintien, le relâché garde sa vitesse ; `scrollTo` attend ensuite l'arrêt.
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: avecElan ? .fast : .default,
                    thenHoldForDuration: avecElan ? 0 : 0.3)
    }

    /// Amène un curseur (`Slider`) à sa borne basse par un glissement qui part du pouce et finit
    /// AU-DELÀ de l'extrémité gauche de la piste : le contrôle borne lui-même la valeur, quel que
    /// soit l'écart du geste synthétisé. `adjust(toNormalizedSliderPosition: 0)`
    /// vise l'extrémité elle-même, à quelques points près : run 42489677193, UI — ipad-landscape,
    /// son geste (« press, hold, drag, and hold ») part de x = 575,96 et finit à x = 323,25, soit
    /// 7,25 pt dans une piste qui commence à x = 316 et dont le premier pas (5 → 10 km, 19 pas sur
    /// 548 pt) s'arrondit dès 14,4 pt ; le curseur est resté à « Rayon : 10 km » pendant les 15 s
    /// d'attente. La valeur atteinte reste prouvée par l'appelant (libellé ou valeur affichés).
    /// Un glissement synthétisé peut aussi s'interrompre avant la borne : run 43962293492, UI — ipad-portrait,
    /// `DemoExplorerTests.testEtatVideGardeActualiserACoteDeLActionSecondaire`, curseur parti de 50 km et resté à
    /// « Rayon : 15 km » pendant les 15 s d'attente. Le geste est alors rejoué depuis la nouvelle position du pouce,
    /// trois glissements au plus, tant que le curseur n'est pas à sa borne basse ; chaque reprise est consignée
    /// (`consignerRejeu`) et chaque constat passe par `attendreSansEchec` (blocages décomptés et budgetés).
    func dragSliderPastMinimum(_ slider: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        require("Le curseur est atteignable", file: file, line: line) { self.visible(slider) && slider.isEnabled }
        let attente = "Le curseur \(slider.identifier) est à sa borne basse"
        for essai in 1...3 {
            glisserAuDelaDuMinimum(slider)
            if attendreSansEchec(attente, timeout: 2, file: file, line: line,
                                 condition: { slider.normalizedSliderPosition < 0.005 }) { return }
            guard essai < 3 else { return } // la valeur atteinte reste exigée par l'appelant
            consignerRejeu(attente, issue: "glissement \(essai)/3 arrêté avant la borne basse (valeur « "
                           + "\((slider.value as? String) ?? "?") ») : glissement rejoué depuis le pouce", file: file, line: line)
        }
    }

    /// Amène un curseur à pas entiers (`Slider(step: 1)`) DANS la plage `cible`, et rend la valeur réellement atteinte,
    /// une fois stabilisée. Une valeur exacte n'est jamais visée : sous iOS 26.2, `adjust(toNormalizedSliderPosition:)`
    /// n'est pas fidèle à la position demandée. Run 45626727902 (main `be5b0d49`, UI lot 1),
    /// `DemoPoolUrgenceTests.testActiverRayonPuisAccepterEtChoixDeContrat`, visée 15 km sur 5-50 km :
    /// - iPhone : positions 0,222 → 0,289 → 0,133 → 0,267 → 0,156 → 0,311, valeurs lues 12 → 22 → 9 → 20 → 8 ;
    /// - iPad portrait : 17 → 12 → 18 → 11 → 14.
    /// Une position plus basse a donné une valeur plus haute, et la correction de l'écart a oscillé sans converger. Aucun
    /// réglage de position ne peut donc garantir une valeur exacte.
    ///
    /// Ici, le premier geste vise le centre de la plage. Si la valeur lue en sort, au plus trois reprises suivent, avec
    /// une correction amortie (moitié de l'écart au centre), chacune consignée (`consignerRejeu`). XCUITest n'offre pas
    /// `increment` pour un curseur sur iOS.
    ///
    /// La valeur rendue est lue après stabilisation : trois lectures identiques à 0,5 s d'intervalle, curseur actif. Le
    /// curseur est désactivé pendant l'envoi (`PoolUrgenceScreen`) et la relecture de l'état peut le recaler. L'appelant
    /// exige la plage, puis la relecture EXACTE de la valeur rendue.
    func reglerCurseur(_ slider: XCUIElement, dansLaPlage cible: ClosedRange<Int>, minimum: Int, maximum: Int,
                       file: StaticString = #filePath, line: UInt = #line) -> Int? {
        require("Le curseur est atteignable", file: file, line: line) { self.visible(slider) && slider.isEnabled }
        let plage = CGFloat(maximum - minimum)
        let centre = CGFloat(cible.lowerBound + cible.upperBound) / 2
        var position = (centre - CGFloat(minimum)) / plage
        let attente = "Le curseur \(slider.identifier) est entre \(cible.lowerBound) et \(cible.upperBound)"
        for geste in 1...4 {
            slider.adjust(toNormalizedSliderPosition: min(1, max(0, position)))
            guard let lue = valeurStable(slider), !cible.contains(lue), geste < 4 else { break }
            position += (centre - CGFloat(lue)) / plage / 2
            consignerRejeu(attente, issue: "valeur lue \(lue) après le geste \(geste)/4 : position visée corrigée à "
                           + String(format: "%.3f", position) + " (demi-écart au centre)", file: file, line: line)
        }
        return valeurStable(slider)
    }

    /// Valeur entière du curseur une fois stable : trois lectures identiques à 0,5 s d'intervalle, curseur actif, 10 s au
    /// plus ; sinon la dernière lecture (nil si illisible).
    private func valeurStable(_ slider: XCUIElement) -> Int? {
        var derniere = valeurEntiere(slider)
        var identiques = 1
        let limite = Date().addingTimeInterval(10)
        while identiques < 3 && Date() < limite {
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "lecture du curseur")], timeout: 0.5)
            let lue = valeurEntiere(slider)
            identiques = (lue == derniere && slider.isEnabled) ? identiques + 1 : 1
            derniere = lue
        }
        return derniere
    }

    /// Premier nombre entier de la valeur d'accessibilité d'un élément (« 14 km » → 14), nil s'il n'y en a pas.
    func valeurEntiere(_ element: XCUIElement) -> Int? {
        guard let texte = element.value as? String else { return nil }
        let chiffres = texte.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
        return Int(chiffres)
    }

    /// Un glissement du pouce du curseur jusqu'au-delà de l'extrémité gauche de sa piste (`dragSliderPastMinimum`).
    private func glisserAuDelaDuMinimum(_ slider: XCUIElement) {
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

    /// Bas des barres de navigation qui recouvrent le haut de `container` : sous iOS 26, les barres sont translucides
    /// et le défilement passe sous elles. Un élément qui s'y trouve peut être déclaré atteignable par XCUITest, mais un
    /// toucher à cet endroit atteint la barre, qui ramène le défilement en haut (run 42559541711, iPad paysage,
    /// `DemoContratsTests.testContratSigneCertificatEtPartageDuFichierOriginal` : « Télécharger le contrat » sous la
    /// barre, aucune feuille de partage). Seules comptent les barres qui commencent dans la moitié haute du conteneur :
    /// la barre d'une page restée derrière une feuille commence au-dessus de la feuille et n'en masque rien.
    func basDesBarresDeNavigation(sur container: XCUIElement) -> CGFloat? {
        let cadre = container.frame
        var bas: CGFloat?
        for barre in app.navigationBars.allElementsBoundByIndex where barre.exists {
            let f = barre.frame
            guard !f.isEmpty, f.minY >= cadre.minY - 1, f.minY < cadre.midY,
                  f.maxX > cadre.minX, f.minX < cadre.maxX else { continue }
            bas = max(bas ?? f.maxY, f.maxY)
        }
        return bas
    }

    /// Entièrement visible dans `container` ET hors des barres de navigation qui en recouvrent le haut.
    func visibleSousLesBarres(_ target: XCUIElement, inside container: XCUIElement) -> Bool {
        guard fullyVisible(target, inside: container) else { return false }
        guard let bas = basDesBarresDeNavigation(sur: container) else { return true }
        return target.frame.minY >= bas - 1
    }

    func scrollTo(_ target: XCUIElement, in container: XCUIElement, downward: Bool = true,
                  file: StaticString = #filePath, line: UInt = #line) {
        require("Le conteneur de défilement attendu est visible") { self.containerVisible(container) }
        var scrolls = 0
        // Glissements sans élan de suite qui n'ont déplacé ni la cible ni le conteneur (`PasDeDefilement.sansEffet`).
        var sansEffet = 0
        var elanConsigne = false
        // 40 pas au plus, glissements avec élan compris : sans élan (`drag`), un pas défile au plus 55 % du conteneur ;
        // la boucle s'arrête dès que la cible est entièrement visible.
        while !visibleSousLesBarres(target, inside: container) && scrolls < 40 {
            // Direction et amplitude : `PasDeDefilement` (testé par `PasDeDefilementTests`), calculées sur la partie du
            // conteneur hors des barres de navigation qui en recouvrent le haut (fusion des lots 2 et 3 : les deux lots
            // avaient corrigé le même défaut, chacun de son côté). Une cible déjà dans ce cadre revient vers le centre
            // d'un pas court, jamais dans la direction de recherche `downward` (lot 3, run 42579729412 : vingt
            // glissements en alternance) ; une cible sous la barre translucide est ramenée vers le bas au lieu d'être
            // poussée plus haut à chaque glissement (lot 2, run 42559541711, iPad paysage,
            // `DemoPointageTests.testHorsLigneDesactiveLePointageSansAucunEnvoi`).
            let conteneurAvant = container.frame
            var cadreUtile = conteneurAvant
            if let bas = basDesBarresDeNavigation(sur: container), bas > cadreUtile.minY {
                cadreUtile = CGRect(x: cadreUtile.minX, y: bas, width: cadreUtile.width, height: max(0, cadreUtile.maxY - bas))
            }
            let cibleAvant = target.exists ? target.frame : nil
            let pas = PasDeDefilement.suivant(cible: cibleAvant, conteneur: cadreUtile, versLaSuiteParDefaut: downward)
            if PasDeDefilement.elanRequis(glissementsSansEffet: sansEffet, versLaSuite: pas.versLaSuite) {
                // Feuille à crans dont le contenu est en haut (run 44797977486, UI — ipad-portrait, récapitulatif
                // d'acceptation) : le glissement tenu à l'arrivée étire la feuille, qui revient à son cran ; quarante
                // glissements identiques n'y ont rien déplacé. Un glissement relâché en vitesse la fait passer au cran
                // suivant, ou fait défiler son contenu. Le premier est consigné, et l'arrêt du mouvement attendu avant
                // toute relecture : aucune action ne tombe sur un contenu en mouvement.
                if !elanConsigne {
                    consignerRejeu("Le contrôle demandé est entièrement visible après un défilement borné",
                                   issue: "\(sansEffet) glissements de suite sans effet sur \(container.identifier) : "
                                       + "glissement avec élan", file: file, line: line)
                    elanConsigne = true
                }
                let elan = PasDeDefilement.amplitudeRecherche
                drag(container, fromY: 0.5 + elan / 2, toY: 0.5 - elan / 2, avecElan: true)
                var dernierCadre: CGRect?
                _ = attendreSansEchec("Le défilement avec élan est arrêté", timeout: 5, file: file, line: line) {
                    let cadre = target.exists ? target.frame : .null
                    defer { dernierCadre = cadre }
                    return dernierCadre.map { $0 == cadre || PasDeDefilement.memeCadre($0, cadre) } ?? false
                }
                scrolls += 1
                // Les deux pas suivants repartent sans élan, que l'élan ait agi ou non : un élan sur trois pas au plus,
                // soit au moins 27 glissements sans élan sur les 40 pas (40 avant ce secours).
                sansEffet = 0
                continue
            }
            let distance = pas.versLaSuite ? pas.amplitude : -pas.amplitude
            drag(container, fromY: 0.5 + distance / 2, toY: 0.5 - distance / 2)
            scrolls += 1
            let effetNul = PasDeDefilement.sansEffet(cibleAvant: cibleAvant, cibleApres: target.exists ? target.frame : nil,
                                                     conteneurAvant: conteneurAvant, conteneurApres: container.frame)
            sansEffet = effetNul ? sansEffet + 1 : 0
        }
        require("Le contrôle demandé est entièrement visible après un défilement borné") {
            self.visibleSousLesBarres(target, inside: container)
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

/// Boutons d'onglet et barres de navigation, lus dans un même instantané (`lireBarreOnglets`) : témoin d'un toucher
/// d'onglet resté sans effet (`toucherOnglet`), prouvé lisible par `exigerTemoinOnglet`.
struct EtatBarreOnglets: Equatable {
    /// Boutons d'onglet dans l'ordre de l'arbre (deux nœuds par onglet sur iPad).
    var onglets: [BoutonOngletLu] = []
    var barresDeNavigation: [String] = []

    /// Premier bouton d'onglet lu « Selected », de libellé non vide.
    var selection: BoutonOngletLu? { onglets.first { $0.selectionne && !$0.label.isEmpty } }

    /// Libellés distincts des onglets lus « Selected » (deux nœuds par onglet sur iPad) : plus d'un, témoin ambigu.
    var libellesSelectionnes: Set<String> { Set(onglets.filter { $0.selectionne && !$0.label.isEmpty }.map(\.label)) }

    /// L'onglet désigné (règle de `BoutonOngletLu.designe`) est lu « Selected », seul ou non.
    func estSelectionne(_ identifier: String, symbole: String?, label: String) -> Bool {
        onglets.contains { $0.selectionne && $0.designe(identifier, symbole: symbole, label: label) }
    }
}

/// Bouton d'onglet lu : identifiant (`tab-*` ou symbole SF), libellé et état « Selected ».
struct BoutonOngletLu: Equatable {
    let identifiant: String
    let label: String
    let selectionne: Bool

    /// Même règle que `boutonOnglet` : l'identifiant `tab-*`, puis son symbole SF (`tabSymbols`), puis le libellé.
    func designe(_ identifier: String, symbole: String?, label attendu: String) -> Bool {
        identifiant == identifier || (symbole != nil && identifiant == symbole) || label == attendu
    }
}

/// Écran empilé et bouton retour du système (`BackButton`), lus dans un même instantané (`lireRetourSysteme`).
struct RetourSystemeLu {
    /// Instantané obtenu : sans lui, rien n'est lu, et aucun retour n'est fait.
    var lisible = false
    var ecranPresent = false
    var boutonPresent = false
}

/// Page affichée de la barre d'onglets haute de l'iPad : cadres lus dans un même instantané (`lirePageDeLaBarre`).
struct PageDeBarreOnglets {
    var onglet: CGRect?
    var suivante: CGRect?
    var precedente: CGRect?

    /// L'onglet est présent et n'est recouvert par aucun des deux boutons de page.
    var ongletDansLaPage: Bool {
        guard let onglet else { return false }
        if let suivante, onglet.maxX > suivante.minX + 1 { return false }
        if let precedente, onglet.minX < precedente.maxX - 1 { return false }
        return true
    }
}
