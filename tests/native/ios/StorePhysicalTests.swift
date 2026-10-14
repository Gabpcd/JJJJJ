import XCTest

// Test physique de l’application DÉJÀ installée. Aucun produit app.jolene
// ne doit être construit par le scheme ou présent dans son Build Products.
// Apple : XCUIApplication.init(bundleIdentifier:) lance alors l’app existante.
// Ce test ne valide que l’ouverture et la reprise de l’écran initial.
// Il ne connecte personne, ne touche aucun bouton et ne gère aucune permission.
final class StorePhysicalTests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "app.jolene")
  // Le pré-prompt push peut apparaître 5 s après l'hydratation du layout.
  // Six secondes consécutives de contenu prêt empêchent un succès prématuré.
  private let minimumStableObservation: TimeInterval = 6
  // Le DOM fournit les aria-label sans suffixe ; certains runtimes XCTest
  // ajoutent le rôle à ces mêmes labels. Autoriser seulement ces variantes.
  private let navigationLabels = [
    "Navigation mobile", "Navigation mobile, navigation",
    "Menu principal", "Menu principal, navigation"
  ]

  private enum Screen: String {
    // Le dashboard peut être exploré en mode invité : sa présence ne prouve
    // aucune session authentifiée ni identité vérifiée.
    case publicLanding, authentication, soignantDashboard, etablissementDashboard
  }

  // Uniquement du vocabulaire statique déjà public. Ne jamais exporter
  // debugDescription, label/value d’un élément dynamique, email, OTP ou champ.
  private let publicMarkers = [
    "Connexion", "Connexion, heading", "Se connecter", "Créer un compte soignant",
    "Créer un compte établissement", "Créez votre compte.", "Créez votre compte., heading",
    "Créer mon compte", "Inscription Soignant", "Inscription Soignant, heading",
    "Inscription Établissement", "Inscription Établissement, heading",
    "Le remplacement santé, enfin simple.", "Le remplacement santé, enfin simple., heading",
    "🩺 Je suis soignant", "🏥 Je suis un établissement",
    "Accueil", "Explorer", "Mes missions", "Revenus", "Profil",
    "Missions", "Publier", "Messages", "Menu", "Trouver une mission", "Publier une mission",
    "Missions pour toi", "Missions pour toi, heading", "Dernières missions", "Dernières missions, heading",
    "Statistiques détaillées",
    "Publiez votre première mission", "Publiez votre première mission, heading",
    "Préparez votre première mission", "Préparez votre première mission, heading",
    "Décrivez votre besoin et publiez votre mission. Les soignants pourront ensuite candidater.",
    "Décrivez votre besoin, puis complétez votre établissement avant de publier.",
    "Une erreur inattendue est survenue", "Une erreur est survenue",
    "Impossible de charger ton tableau de bord", "Impossible de vérifier votre établissement",
    "Ton tableau de bord met plus de temps que prévu", "Le tableau de bord met plus de temps que prévu",
    "Certaines données n'ont pas pu être chargées.", "Cette section n'a pas pu se charger.",
    "Pas de connexion internet", "Chargement en cours",
    "Recevoir les alertes missions ?", "Recevoir les notifications de votre établissement ?",
    "Recevoir les notifications Jolene ?"
  ]

  private let errorMarkers = [
    "Une erreur inattendue est survenue", "Une erreur est survenue",
    "Impossible de charger ton tableau de bord", "Impossible de vérifier votre établissement",
    "Ton tableau de bord met plus de temps que prévu", "Le tableau de bord met plus de temps que prévu",
    "Certaines données n'ont pas pu être chargées.", "Cette section n'a pas pu se charger.",
    "Pas de connexion internet"
  ]

  private let pushPromptMarkers = [
    "Recevoir les alertes missions ?", "Recevoir les notifications de votre établissement ?",
    "Recevoir les notifications Jolene ?"
  ]

  override func setUpWithError() throws {
    continueAfterFailure = false
    // Aucun argument ou variable n’est injecté dans Jolene. Son backend,
    // son binaire store et son éventuel contenu OTA restent ceux installés.
  }

  private func exactPublicText(_ text: String) -> Bool {
    let predicate = NSPredicate(format: "label == %@", text)
    // WKWebView n'expose pas toujours un heading comme staticText : son type
    // peut être otherElement. Garder une égalité exacte sur le label public,
    // sans exporter l'arbre ni élargir la reconnaissance aux textes arbitraires.
    return app.descendants(matching: .any).matching(predicate).firstMatch.exists
  }

  private func navigation(_ label: String) -> XCUIElement? {
    let element = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    return element.exists ? element : nil
  }

  private func hasSoignantNavigation() -> Bool {
    navigationLabels.contains { label in
      guard let nav = navigation(label) else { return false }
      return nav.buttons["Mes missions"].exists
        && (nav.buttons["Explorer"].exists || nav.buttons["Trouver une mission"].exists)
    }
  }

  private func publicHeading(_ text: String) -> Bool {
    exactPublicText(text) || exactPublicText(text + ", heading")
  }

  // Ces identifiants de blocage sont statiques. Ne jamais joindre le texte
  // d'une alerte, qui peut contenir une identité, un message, un email ou un OTP.
  private func blockingConditions() -> [String] {
    var blockers: [String] = []
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    if springboard.alerts.firstMatch.exists || app.alerts.firstMatch.exists {
      blockers.append("native-alert")
    }
    // WKWebView expose notamment « ..., web dialog » et « ..., web alert ».
    // Rechercher le rôle sans lire/exporter le label dynamique du conteneur.
    let blockedWebRole = NSPredicate(format: "label MATCHES[c] %@", "(?s).*[, ](web )?(alert|alertdialog|dialog)$")
    if app.dialogs.firstMatch.exists || app.descendants(matching: .any).matching(blockedWebRole).firstMatch.exists {
      blockers.append("web-dialog-or-alert")
    }
    if pushPromptMarkers.contains(where: publicHeading) {
      blockers.append("push-prepermission-dialog")
    }
    if errorMarkers.contains(where: publicHeading) {
      blockers.append("known-error-or-offline-state")
    }
    return blockers
  }

  private func isLoading() -> Bool {
    if app.progressIndicators.firstMatch.exists { return true }
    let loading = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Chargement en cours", "Chargement en cours,")
    return app.descendants(matching: .any).matching(loading).firstMatch.exists
  }

  private func recognisedScreen() -> Screen? {
    guard app.state == .runningForeground else { return nil }
    guard !isLoading() else { return nil }
    // La nav reste montée pendant le Suspense de LayoutApp et pendant le
    // chargement/échec dashboard. Exiger également du contenu propre à la
    // branche prête des dashboards 1.0.7, jamais un prénom ou une statistique.
    let soignantContentReady = publicHeading("Missions pour toi")
    let etablissementContentReady = (
      publicHeading("Dernières missions") && exactPublicText("Statistiques détaillées")
    ) || (
      publicHeading("Publiez votre première mission")
      && exactPublicText("Décrivez votre besoin et publiez votre mission. Les soignants pourront ensuite candidater.")
    ) || (
      publicHeading("Préparez votre première mission")
      && exactPublicText("Décrivez votre besoin, puis complétez votre établissement avant de publier.")
    )
    for label in navigationLabels {
      guard let nav = navigation(label) else { continue }
      if soignantContentReady && nav.buttons["Explorer"].exists && nav.buttons["Mes missions"].exists { return .soignantDashboard }
      if soignantContentReady && nav.buttons["Trouver une mission"].exists && nav.buttons["Mes missions"].exists { return .soignantDashboard }
      if etablissementContentReady && nav.buttons["Publier"].exists && nav.buttons["Messages"].exists { return .etablissementDashboard }
      if etablissementContentReady && nav.buttons["Publier une mission"].exists && nav.buttons["Missions"].exists { return .etablissementDashboard }
    }
    let authHeading = [
      "Connexion", "Connexion, heading", "Créez votre compte.", "Créez votre compte., heading",
      "Inscription Soignant", "Inscription Soignant, heading",
      "Inscription Établissement", "Inscription Établissement, heading"
    ].contains(where: exactPublicText)
    if authHeading && (app.buttons["Se connecter"].exists || app.buttons["Créer mon compte"].exists) {
      return .authentication
    }
    if (exactPublicText("Le remplacement santé, enfin simple.")
        || exactPublicText("Le remplacement santé, enfin simple., heading"))
        && app.buttons["Se connecter"].exists { return .publicLanding }
    return nil
  }

  private func report(_ stage: String, screen: Screen?, stableFor: TimeInterval = 0, blockers: [String] = [], didScroll: Bool = false) throws {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    // Diagnostic seulement : aucun label brut ne quitte ce bloc et aucun
    // résultat ne participe à recognisedScreen() ou aux assertions du test.
    let marker = "Missions pour toi"
    let markerQuery = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", marker))
    var markerDiagnostics: [[String: Any]] = []
    for index in 0..<min(markerQuery.count, 8) {
      let element = markerQuery.element(boundBy: index)
      guard element.exists else { continue }
      let label = element.label
      let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalized = label.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        .filter { !$0.isEmpty }.joined(separator: " ")
      markerDiagnostics.append([
        "elementType": element.elementType.rawValue,
        "labelLength": label.utf16.count,
        "labelTrimEquals": trimmed == marker,
        "labelTrimEqualsHeading": trimmed == marker + ", heading",
        "textNormalizedEquals": normalized == marker
      ])
    }
    let snapshot: [String: Any] = [
      "schema": "jolene-physical-public-markers/v2",
      "bundleUnderTest": "app.jolene",
      "stage": stage,
      "screen": screen?.rawValue ?? "unrecognised",
      "foreground": app.state == .runningForeground,
      "systemAlertPresent": springboard.alerts.firstMatch.exists,
      "blockingConditions": blockers,
      "loadingPresent": isLoading(),
      "minimumStableObservationSeconds": minimumStableObservation,
      "observedStableSeconds": stableFor,
      "didScroll": didScroll,
      "observedPublicMarkers": publicMarkers.filter { exactPublicText($0) },
      "observedNavigationLabels": navigationLabels.filter { navigation($0) != nil },
      "markerDiagnostics": markerDiagnostics,
      "limitation": didScroll
        ? "Contenu du dashboard recherché après un seul défilement. Un succès exige son marqueur prêt et la navigation stables 6 s ; il ne valide pas tout le premier écran ni documents, caméra, GPS, push, PSC ou finance."
        : "Ouverture/reprise seulement ; aucune validation documents, caméra, GPS, push, PSC ou financière."
    ]
    let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
    attachment.name = stage + "-marqueurs-publics"
    attachment.lifetime = .keepAlways
    add(attachment)

    // Par défaut aucune capture. Même en opt-in, jamais de capture d’un
    // compte connecté ou d’un formulaire pouvant contenir un email/OTP.
    if ProcessInfo.processInfo.environment["JOLENE_PHYSICAL_CAPTURE_SCREENSHOTS"] == "1",
       screen == .publicLanding,
       !didScroll,
       stableFor >= minimumStableObservation,
       blockers.isEmpty,
       !app.textFields.firstMatch.exists,
       !app.secureTextFields.firstMatch.exists,
       !app.alerts.firstMatch.exists,
       !springboard.alerts.firstMatch.exists {
      let image = XCTAttachment(screenshot: app.screenshot())
      image.name = stage + "-accueil-public"
      image.lifetime = .keepAlways
      add(image)
    }
  }

  private func openAndObserve(_ stage: String) throws -> Screen {
    app.launch()
    let foreground = app.wait(for: .runningForeground, timeout: 30)
    if !foreground {
      try report(stage, screen: nil)
      XCTFail("Jolene n’atteint pas le premier plan. Aucun contenu privé exporté.")
      throw ObservationError.unrecognised
    }
    let observationStart = Date()
    let deadline = observationStart.addingTimeInterval(45)
    var didScroll = false
    var stableScreen: Screen?
    var stableSince: Date?
    repeat {
      let blockers = blockingConditions()
      if !blockers.isEmpty {
        try report(stage, screen: nil, blockers: blockers, didScroll: didScroll)
        XCTFail("Ouverture non validée : alerte, dialogue, erreur ou absence de connexion observée. Aucune permission traitée ni donnée privée exportée ; consulter les catégories statiques jointes.")
        throw ObservationError.unrecognised
      }
      if let screen = recognisedScreen() {
        if screen != stableScreen {
          stableScreen = screen
          stableSince = Date()
        }
        let stableFor = stableSince.map { Date().timeIntervalSince($0) } ?? 0
        if stableFor >= minimumStableObservation {
          // Un nouveau snapshot peut révéler un dialogue apparu pendant les
          // requêtes UI précédentes ; le dernier contrôle doit aussi passer.
          let finalBlockers = blockingConditions()
          if finalBlockers.isEmpty && !isLoading() && recognisedScreen() == screen {
            try report(stage, screen: screen, stableFor: stableFor, didScroll: didScroll)
            return screen
          }
          if !finalBlockers.isEmpty {
            try report(stage, screen: nil, blockers: finalBlockers, didScroll: didScroll)
            XCTFail("Ouverture non validée : un dialogue ou une erreur apparaît pendant l’observation stable. Aucun dialogue traité.")
            throw ObservationError.unrecognised
          }
          stableScreen = nil
          stableSince = nil
        }
      } else {
        stableScreen = nil
        stableSince = nil
        // WKWebView peut omettre de son arbre les headings hors viewport.
        // Un seul geste de lecture, après 5 s, jamais sur une alerte ou un
        // chargement. La nav ne vaut toujours pas preuve du contenu : après
        // ce geste, « Missions pour toi » et la nav doivent rester prêts 6 s.
        if !didScroll,
           Date().timeIntervalSince(observationStart) >= 5,
           app.state == .runningForeground,
           !isLoading(),
           blockingConditions().isEmpty,
           hasSoignantNavigation(),
           app.webViews.firstMatch.exists,
           app.webViews.firstMatch.isHittable {
          didScroll = true
          app.webViews.firstMatch.swipeUp()
        }
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    } while Date() < deadline
    try report(stage, screen: nil, didScroll: didScroll)
    XCTFail("Écran initial non reconnu : état connecté, authentification ou accueil public attendu. Aucun login ni dialogue système traité ; lire uniquement les marqueurs publics joints.")
    throw ObservationError.unrecognised
  }

  private enum ObservationError: Error { case unrecognised }

  func testInstalledStoreOpeningAndRelaunch() throws {
    let first = try openAndObserve("ouverture")
    app.terminate()
    let second = try openAndObserve("relancement")
    XCTAssertEqual(second.rawValue, first.rawValue, "L’état initial attendu change après relancement ; ce constat ne valide aucun autre parcours.")
    // Laisser l’app à son écran initial, sans se déconnecter ni effacer de données.
  }
}
