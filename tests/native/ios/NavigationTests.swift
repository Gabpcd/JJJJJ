import XCTest
import UIKit

// Reprise des gestes et pièces XCTest de recette/2026-09-23-fluidite/natif/
// NavigationTests.swift ; contrat API et textes issus du banc Android du SHA livré.
final class NavigationTests: XCTestCase {
  let app = XCUIApplication(bundleIdentifier: "app.jolene.recette")
  let password = "Recette-Native!2026"
  var tablet: Bool { UIDevice.current.userInterfaceIdiom == .pad }
  var navigation: XCUIElement { app.otherElements[tablet ? "Menu principal, navigation" : "Navigation mobile, navigation"] }

  override func setUpWithError() throws {
    continueAfterFailure = false
    app.launchArguments += ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    orient(landscape: false)
  }

  override func tearDownWithError() throws {
    preuve("etat-final-meme-en-echec")
    app.terminate()
  }

  func preuve(_ name: String) {
    let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    image.name = name; image.lifetime = .keepAlways; add(image)
    let tree = XCTAttachment(string: app.debugDescription)
    tree.name = name + "-accessibilite"; tree.lifetime = .keepAlways; add(tree)
  }

  func visible(_ element: XCUIElement, timeout: TimeInterval = 20) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout), app.debugDescription)
  }

  func reachable(_ element: XCUIElement) -> XCUIElement {
    visible(element)
    for _ in 0..<6 {
      if element.isHittable { return element }
      app.swipeUp()
    }
    XCTAssertTrue(element.isHittable, app.debugDescription)
    return element
  }

  func later(timeout: TimeInterval = 0) {
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let alert = system.alerts.firstMatch
    if alert.exists {
      let notification = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "notification")).firstMatch
      XCTAssertTrue(notification.exists, "Alerte native inattendue : " + alert.debugDescription)
      let refuse = alert.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Ne pas autoriser", "Don't Allow")).firstMatch
      XCTAssertTrue(refuse.exists && refuse.isHittable, alert.debugDescription)
      preuve("permission-notifications-refusee")
      refuse.tap()
    }
    // Le pré-prompt natif arrive 5 s après checkPermissions à partir de la
    // deuxième session (DemandePermissionPush.tsx). Ne fermer que ce dialogue.
    let prompt = app.otherElements.matching(NSPredicate(
      format: "label == %@ OR label == %@",
      "Recevoir les alertes missions ?, web dialog",
      "Recevoir les notifications de votre établissement ?, web dialog"
    )).firstMatch
    if prompt.exists || (timeout > 0 && prompt.waitForExistence(timeout: timeout)) {
      let button = prompt.buttons["Plus tard"]
      visible(button)
      XCTAssertTrue(button.isHittable, prompt.debugDescription)
      preuve("prepermission-notifications-plus-tard")
      button.tap()
      let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: prompt)
      XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed, app.debugDescription)
    }
  }

  func closeKeyboardIfDone() {
    guard app.keyboards.firstMatch.exists else { return }
    let done = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Terminé", "Done")).firstMatch
    if done.exists && done.isHittable { done.tap() }
  }

  func nav(_ name: String) {
    later()
    visible(navigation)
    let mapping = ["Explorer": "Trouver une mission", "Profil": "Mon compte", "Menu": "Mon compte", "Publier": "Publier une mission", "Messages": "Messagerie"]
    let label = tablet ? (mapping[name] ?? name) : name
    let button = navigation.buttons[label]
    if tablet && ["Explorer", "Mes missions"].contains(name) && !button.exists {
      navigationButton(navigation.buttons["Missions"]).tap()
    }
    navigationButton(button).tap()
    later()
    XCTAssertFalse(app.staticTexts["Une erreur inattendue est survenue"].exists)
  }

  func navigationButton(_ button: XCUIElement) -> XCUIElement {
    later()
    visible(button)
    if tablet {
      for _ in 0..<6 { later(); if button.isHittable { break }; navigation.swipeDown() }
      for _ in 0..<12 { later(); if button.isHittable { break }; navigation.swipeUp() }
    }
    later()
    XCTAssertTrue(button.isHittable, app.debugDescription)
    return button
  }

  // Sur iPad, le header de sidebar possède aussi « Se déconnecter ». Viser
  // le bouton du compte, à droite de la navigation, conserve le geste testé.
  func accountButton(_ name: String) -> XCUIElement {
    if !tablet { return app.buttons[name] }
    let loaded = NSPredicate { _, _ in
      self.app.buttons.matching(identifier: name).allElementsBoundByIndex.filter {
        $0.frame.minX >= self.navigation.frame.maxX
      }.count == 1
    }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: app)], timeout: 20), .completed, app.debugDescription)
    let candidates = app.buttons.matching(identifier: name).allElementsBoundByIndex.filter { $0.frame.minX >= navigation.frame.maxX }
    XCTAssertEqual(candidates.count, 1, app.debugDescription)
    return candidates.first ?? app.buttons[name].firstMatch
  }

  func contentText(_ name: String) {
    let predicate = NSPredicate { _, _ in
      self.app.staticTexts.matching(identifier: name).allElementsBoundByIndex.contains {
        $0.exists && (!self.tablet || $0.frame.minX >= self.navigation.frame.maxX)
      }
    }
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 20), .completed, app.debugDescription)
  }

  func credentials(_ role: String) {
    let email = app.textFields["Email"]
    visible(email); email.tap(); email.typeText("native-ios-\(role)@example.invalid")
    let secret = app.secureTextFields["Mot de passe"]
    visible(secret); secret.tap(); secret.typeText(password)
    visible(app.keyboards.firstMatch)
    preuve(role + "-clavier-auth")
    closeKeyboardIfDone()
  }

  func signup(_ role: String) {
    let etab = role == "etab"
    reachable(app.buttons[etab ? "Créer un compte établissement" : "Créer un compte soignant"]).tap()
    credentials(role)
    if etab {
      let name = app.textFields["Nom de l’établissement"]
      reachable(name).tap(); name.typeText("Résidence Camille — simulation")
      closeKeyboardIfDone()
    } else {
      let profession = app.otherElements.matching(NSPredicate(format: "label == %@ AND value BEGINSWITH %@", "Profession", "Choisir")).firstMatch
      reachable(profession).tap()
      let label = "Infirmier(ère) Diplômé(e) d'État (IDE)"
      if app.pickerWheels.firstMatch.waitForExistence(timeout: 3) {
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: label)
        if app.buttons["Terminé"].exists { app.buttons["Terminé"].tap() }
        else if app.buttons["Done"].exists { app.buttons["Done"].tap() }
      } else { reachable(app.buttons[label]).tap() }
    }
    reachable(app.switches.matching(NSPredicate(format: "label CONTAINS %@", "CGU")).firstMatch).tap()
    if etab {
      reachable(app.switches.matching(NSPredicate(format: "label CONTAINS %@", "conditions générales de vente")).firstMatch).tap()
    }
    reachable(app.buttons["Créer mon compte"]).tap()
    later(timeout: 7)
    visible(navigation, timeout: 30)
  }

  func fiveTabs(_ role: String, phase: String, orientation: String) {
    let etab = role == "etab"
    let names = etab ? ["Accueil", "Missions", "Publier", "Messages", "Menu"] : ["Accueil", "Mes missions", "Revenus", "Profil", "Explorer"]
    for name in names {
      nav(name)
      if etab {
        switch name {
        case "Accueil":
          contentText("Préparez votre première mission")
          contentText("À compléter avant publication")
          XCTAssertFalse(app.staticTexts["Paiements à jour"].exists)
        case "Missions": contentText("Publiez votre première mission")
        case "Publier": visible(app.textFields.matching(NSPredicate(format: "label CONTAINS %@", "Intitulé")).firstMatch)
        case "Messages": contentText("Aucune conversation")
        default:
          visible(accountButton("Se déconnecter"))
          visible(accountButton("Supprimer mon compte"))
        }
      } else {
        switch name {
        case "Explorer": visible(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Mission IDE à Résidence Camille")).firstMatch)
        case "Accueil": contentText("Explorez les missions librement. Votre profil sera demandé lorsque vous souhaiterez candidater.")
        case "Profil": contentText("Mon compte")
        case "Revenus": contentText("💰 Revenus")
        default: contentText("Mes missions")
        }
      }
      preuve("\(role)-\(phase)-\(orientation)-\(name)")
    }
  }

  func orient(landscape: Bool) {
    later()
    // Un simulateur neuf est déjà en portrait. Changer l'orientation avant
    // le lancement peut expirer sans interface pour confirmer la rotation.
    if (app.frame.width > app.frame.height) != landscape {
      XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
    }
    let dimensions = NSPredicate { _, _ in
      let size = self.app.frame.size
      return size.width > 0 && size.height > 0 && (landscape ? size.width > size.height : size.height > size.width)
    }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: dimensions, object: app)], timeout: 20), .completed, "Orientation demandée non appliquée")
  }

  func orientations(_ role: String, phase: String) {
    orient(landscape: false)
    fiveTabs(role, phase: phase, orientation: "portrait")
    let portraitSize = XCUIScreen.main.screenshot().image.size
    XCTAssertGreaterThan(portraitSize.height, portraitSize.width, "Orientation portrait non appliquée")
    if tablet {
      orient(landscape: true)
      fiveTabs(role, phase: phase, orientation: "paysage")
      let size = XCUIScreen.main.screenshot().image.size
      XCTAssertGreaterThan(size.width, size.height, "Orientation iPad paysage non appliquée")
      orient(landscape: false)
    }
  }

  func logout(_ role: String) {
    nav(role == "etab" ? "Menu" : "Profil")
    reachable(accountButton("Se déconnecter")).tap()
    visible(app.buttons["Se connecter"])
  }

  func testVersion107Build24DeuxRolesNavigationEtReprise() throws {
    for role in ["soignant", "etab"] {
      signup(role)
      orientations(role, phase: "inscription")
      // Redémarrage complet de l'app : la session doit subsister sans resaisie.
      app.terminate(); app.launch()
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
      later(timeout: 7)
      visible(navigation, timeout: 30)
      nav(role == "etab" ? "Publier" : "Mes missions")
      preuve(role + "-session-apres-relancement")
      logout(role)
      credentials(role)
      reachable(app.buttons["Se connecter"]).tap()
      later(timeout: 7)
      visible(navigation, timeout: 30)
      orientations(role, phase: "reconnexion")
      logout(role)
    }
  }
}
