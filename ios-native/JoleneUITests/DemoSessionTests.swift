import XCTest

/// Session durcie en démo (lot 1, T9) : biométrie « Non disponible sur cet appareil » (port démo
/// `.unavailable`, interrupteur grisé, aucun `XCTSkip`) et drapeaux d'écran natif
/// (`-JOLENE_FLAG_<cle> false`, DEBUG, lu par `DemoFlagsGateway`) qui remplacent l'onglet coupé par
/// l'écran de renvoi web. Aucune requête réseau.
/// Identifiants : `profile-securite`, `securite-screen`, `biometrie-toggle`, `biometrie-indisponible`,
/// `renvoi-web-<ecran>` (+ `-message`, `-ouvrir`), `logout-button`.
final class DemoSessionTests: JoleneUITestCase {
    static let messageRenvoi = "Cet écran est momentanément indisponible dans l'application. Retrouvez-le sur jolene.app."

    func testBiometrieNonDisponibleEnDemoInterrupteurGrise() throws {
        launchDemo()
        signInDemo()
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil est affiché") { self.containerVisible(self.element("profile-list")) }
        let ouvrir = element("profile-securite")
        if !visible(ouvrir) { scrollTo(ouvrir, in: element("profile-list")) }
        tap("profile-securite")

        let ecran = element("securite-screen")
        require("L'écran Sécurité est affiché") { self.containerVisible(ecran) }
        let interrupteur = element("biometrie-toggle")
        require("L'interrupteur biométrique est affiché") { interrupteur.exists }
        let indisponible = element("biometrie-indisponible")
        require("La biométrie est déclarée indisponible") { indisponible.exists }
        XCTAssertEqual(indisponible.label, "Non disponible sur cet appareil")
        XCTAssertFalse(interrupteur.isEnabled, "Interrupteur grisé en démonstration")
        XCTAssertNotEqual(interrupteur.value as? String, "1", "Le verrou n'est pas annoncé comme actif")
        record("\(proofPrefix)-securite-demo")

        let back = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(back) }
        back.tap()
        require("Le profil est de retour, session intacte") { self.containerVisible(self.element("profile-list")) }
        XCTAssertTrue(tabBarExists)
    }

    func testDrapeauMissionsCoupeAfficheLeRenvoiWebEtLaisseLesAutresOnglets() throws {
        launchDemo(extraArguments: ["-JOLENE_FLAG_ios_natif_missions_actif", "false"])
        signInDemo()
        require("L'Accueil reste natif") { self.containerVisible(self.element("accueil-screen")) }
        XCTAssertFalse(element("renvoi-web-accueil").exists)

        tabButton("tab-missions", label: "Mes missions").tap()
        let renvoi = element("renvoi-web-missions")
        require("Mes missions affiche le renvoi web") { self.containerVisible(renvoi) }
        XCTAssertEqual(element("renvoi-web-missions-message").label, Self.messageRenvoi)
        XCTAssertTrue(element("renvoi-web-missions-ouvrir").exists, "Une sortie vers jolene.app est proposée")
        record("\(proofPrefix)-renvoi-web-missions")

        tabButton("tab-explorer", label: "Explorer").tap()
        require("Explorer reste natif") { self.containerVisible(self.element("missions-list")) }
        XCTAssertFalse(element("renvoi-web-explorer").exists)
    }

    func testDrapeauxParDefautAucunRenvoiWeb() throws {
        launchDemo()
        signInDemo()
        require("L'Accueil est natif") { self.containerVisible(self.element("accueil-screen")) }
        XCTAssertEqual(elements(withPrefix: "renvoi-web-").count, 0, "Accueil : aucun drapeau coupé (fail-open)")
        tabButton("tab-revenus", label: "Revenus").tap()
        // Le titre de navigation est posé par l'écran natif comme par le renvoi : il prouve que
        // l'onglet est rendu avant de constater l'absence de renvoi.
        require("L'onglet Revenus est affiché") { self.app.navigationBars["Revenus"].exists }
        XCTAssertEqual(elements(withPrefix: "renvoi-web-").count, 0, "Revenus : aucun renvoi (fail-open)")
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil natif est affiché") { self.containerVisible(self.element("profile-list")) }
        XCTAssertEqual(elements(withPrefix: "renvoi-web-").count, 0, "Profil : aucun renvoi (fail-open)")
        record("\(proofPrefix)-drapeaux-par-defaut")
    }

    func testProfilCoupeGardeLaDeconnexion() throws {
        launchDemo(extraArguments: ["-JOLENE_FLAG_ios_natif_profil_actif", "false"])
        signInDemo()
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil affiche le renvoi web") { self.containerVisible(self.element("renvoi-web-profil")) }
        XCTAssertFalse(element("profile-list").exists, "L'écran natif coupé n'est pas monté")
        XCTAssertEqual(element("renvoi-web-profil-message").label, Self.messageRenvoi)
        record("\(proofPrefix)-renvoi-web-profil")

        tap("logout-button")
        require("La déconnexion reste possible depuis le renvoi") { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(tabBarExists)
        XCTAssertFalse(element("login-error").exists, "Une déconnexion volontaire n'affiche aucun message")
    }

    // MARK: Étapes

    private func signInDemo() {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.visible(scroll) }
        let email = element("login-email")
        focus(email, in: scroll)
        email.typeText(Self.demoEmail)
        let password = element("login-password")
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.demoPassword)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) { scrollTo(submit, in: scroll) }
        submit.tap()
        require("La session est prête : la barre d'onglets est affichée", timeout: 30) { self.tabBarExists }
    }
}
