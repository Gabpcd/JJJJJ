import XCTest
final class NavigationTests: XCTestCase {
  let app = XCUIApplication(bundleIdentifier: "app.jolene.recette")
  func preuve(_ nom: String) {
    let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = nom; image.lifetime = .keepAlways; add(image)
    let arbre = XCTAttachment(string: app.debugDescription); arbre.name = nom + "-accessibilite"; arbre.lifetime = .keepAlways; add(arbre)
    print("NATIVE_" + nom + "\n" + app.debugDescription)
  }
  func testInscriptionEtNavigation() throws {
    continueAfterFailure = false
    app.launchArguments += ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
    app.launch()
    if app.buttons["Créer un compte soignant"].waitForExistence(timeout: 12) { app.buttons["Créer un compte soignant"].tap() }
    let email = app.textFields["Email"]
    XCTAssertTrue(email.waitForExistence(timeout: 15), app.debugDescription)
    email.tap(); email.typeText("recette-ios-fluidite@example.invalid")
    let mdp = app.secureTextFields["Mot de passe"]
    mdp.tap(); mdp.typeText("Recette-Solide!2026")
    preuve("clavier-inscription")
    let profession = app.otherElements.matching(NSPredicate(format: "label == %@ AND value BEGINSWITH %@", "Profession", "Choisir")).firstMatch
    XCTAssertTrue(profession.exists, app.debugDescription)
    profession.tap()
    preuve("selecteur-profession")
    if app.pickerWheels.firstMatch.waitForExistence(timeout: 3) {
      app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "Infirmier(ère) Diplômé(e) d'État (IDE)")
      if app.buttons["Terminé"].exists { app.buttons["Terminé"].tap() }
      else if app.buttons["Done"].exists { app.buttons["Done"].tap() }
    } else {
      app.buttons["Infirmier(ère) Diplômé(e) d'État (IDE)"].tap()
    }
    let cgu = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "J’accepte les CGU")).firstMatch
    XCTAssertTrue(cgu.exists, app.debugDescription); cgu.tap()
    app.buttons["Créer mon compte"].tap()
    XCTAssertTrue(app.buttons["Explorer"].waitForExistence(timeout: 20), app.debugDescription)
    preuve("compte-soignant-cree")
  }
  func appPrete() {
    continueAfterFailure = false
    app.launchArguments += ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
    app.launch()
  }
  func onglet(_ nom: String) {
    if app.buttons["Plus tard"].waitForExistence(timeout: 2) { app.buttons["Plus tard"].tap() }
    let nav = app.otherElements["Navigation mobile, navigation"]
    XCTAssertTrue(nav.waitForExistence(timeout: 15), app.debugDescription)
    let bouton = nav.buttons[nom]
    XCTAssertTrue(bouton.exists, app.debugDescription)
    bouton.tap()
    if app.buttons["Plus tard"].waitForExistence(timeout: 2) { app.buttons["Plus tard"].tap() }
    XCTAssertTrue(nav.waitForExistence(timeout: 10), app.debugDescription)
  }
  func boutonVisible(_ nom: String) -> XCUIElement {
    let bouton = app.buttons[nom].firstMatch
    for _ in 0..<7 {
      if bouton.exists && bouton.isHittable { return bouton }
      app.swipeUp()
    }
    return bouton
  }
  func testSoignantCinqOngletsEtParrainage() throws {
    appPrete()
    XCTAssertTrue(app.buttons["Explorer"].waitForExistence(timeout: 20), app.debugDescription)
    for nom in ["Accueil", "Mes missions", "Revenus", "Profil", "Explorer"] {
      onglet(nom)
      preuve("soignant-onglet-" + nom)
    }
    onglet("Profil")
    let parrainage = boutonVisible("Parrainage")
    XCTAssertTrue(parrainage.isHittable, app.debugDescription); parrainage.tap()
    XCTAssertTrue(app.staticTexts["Votre lien de parrainage n’est pas encore disponible"].waitForExistence(timeout: 15), app.debugDescription)
    preuve("soignant-parrainage")

  }

  func testEtablissementCinqOngletsEtPreparation() throws {
    appPrete()
    onglet("Profil")
    let deconnexion = boutonVisible("Se déconnecter")
    XCTAssertTrue(deconnexion.isHittable, app.debugDescription); deconnexion.tap()
    let creer = app.buttons["Créer un compte établissement"]
    XCTAssertTrue(creer.waitForExistence(timeout: 15), app.debugDescription); creer.tap()
    let email = app.textFields["Email"]
    XCTAssertTrue(email.waitForExistence(timeout: 15), app.debugDescription)
    email.tap(); email.typeText("recette-ios-etablissement@example.invalid")
    let mdp = app.secureTextFields["Mot de passe"]
    mdp.tap(); mdp.typeText("Recette-Solide!2026")
    XCTAssertTrue(app.keyboards.firstMatch.exists, app.debugDescription)
    preuve("etablissement-inscription-clavier")
    let nom = app.textFields["Nom de l’établissement"]
    nom.tap(); nom.typeText("Résidence Camille — simulation")
    let cgu = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "J’accepte les CGU")).firstMatch
    cgu.tap()
    app.switches.matching(NSPredicate(format: "label CONTAINS %@", "conditions générales de vente")).firstMatch.tap()
    app.buttons["Créer mon compte"].tap()
    XCTAssertTrue(app.buttons["Publier"].waitForExistence(timeout: 20), app.debugDescription)
    preuve("etablissement-compte-cree")
    for rubrique in ["Missions", "Publier", "Messages", "Menu", "Accueil"] {
      onglet(rubrique)
      preuve("etablissement-onglet-" + rubrique)
    }
    onglet("Publier")
    let intitule = app.textFields.matching(NSPredicate(format: "label CONTAINS %@", "Intitulé")).firstMatch
    XCTAssertTrue(intitule.waitForExistence(timeout: 15), app.debugDescription)
    intitule.tap(); intitule.typeText("Préparation native — simulation")
    preuve("etablissement-formulaire-mission-clavier")
  }

  func testExplorerMisAJour() throws {
    appPrete()
    if app.buttons["Menu"].waitForExistence(timeout: 12) {
      onglet("Menu")
      let quitter = boutonVisible("Se déconnecter")
      XCTAssertTrue(quitter.isHittable, app.debugDescription); quitter.tap()
      let email = app.textFields["Email"]
      XCTAssertTrue(email.waitForExistence(timeout: 15), app.debugDescription)
      email.tap(); email.typeText("recette-ios-fluidite@example.invalid")
      let mdp = app.secureTextFields["Mot de passe"]
      mdp.tap(); mdp.typeText("Recette-Solide!2026")
      app.buttons["Se connecter"].tap()
    }
    XCTAssertTrue(app.buttons["Explorer"].waitForExistence(timeout: 20), app.debugDescription)
    onglet("Explorer")
    let carte = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Mission IDE à Résidence Camille")).firstMatch
    XCTAssertTrue(carte.waitForExistence(timeout: 15), app.debugDescription)
    XCTAssertFalse(carte.label.contains("score 0"), carte.label)
    XCTAssertFalse(app.staticTexts["0/100"].exists, app.debugDescription)
    preuve("soignant-explorer-sans-score-fictif")
    carte.tap()
    XCTAssertTrue(app.staticTexts["Remplacement infirmier de jour — simulation"].waitForExistence(timeout: 10), app.debugDescription)
    preuve("soignant-detail-swipe")
    app.buttons["Fermer"].firstMatch.tap()
    XCTAssertTrue(carte.waitForExistence(timeout: 10), app.debugDescription)
  }

}
