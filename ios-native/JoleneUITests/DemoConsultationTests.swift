import XCTest

/// Scénario démo du lot 0 (plan §11 jours 4-5) : connexion, cinq onglets, Explorer à
/// 30 missions, ouverture et retour d'une mission, preuve « 0 requête », déconnexion.
final class DemoConsultationTests: JoleneUITestCase {
    func testDemoConsultation() throws {
        launchDemo()
        assertSignedOut()
        record("\(proofPrefix)-connexion")

        signInDemo()
        assertFiveTabs()
        record("\(proofPrefix)-accueil")

        openExplorer()
        openFirstMissionAndReturn()

        assertNoNetworkRequest()
        signOut()
    }

    // MARK: Étapes

    private func assertSignedOut() {
        require("L'écran de connexion est affiché") { self.visible(self.element("login-scroll")) }
        require("La démo est explicitement identifiée") { self.visible(self.element("login-demo-banner")) }
        let submit = element("login-submit")
        require("Le bouton de connexion existe") { submit.exists }
        XCTAssertFalse(submit.isEnabled, "Le bouton reste désactivé tant que les champs sont vides")
        XCTAssertFalse(element("missions-list").exists, "Aucune liste de missions avant connexion")
    }

    private func signInDemo() {
        let scroll = element("login-scroll")
        let email = element("login-email")
        focus(email, in: scroll)
        email.typeText(Self.demoEmail)
        let password = element("login-password")
        // Retour sur l'email : `submitLabel(.next)` + `onSubmit { focusedField = .password }`
        // donnent le focus au mot de passe sans toucher l'écran. Sur iPad paysage (iOS 26.2),
        // un tap sur le champ ne prend pas le focus clavier alors qu'il n'est pas recouvert.
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.demoPassword)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé une fois les deux champs remplis") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) {
            scrollTo(submit, in: element("login-scroll"))
        }
        submit.tap()
        require("La session est prête : la barre d'onglets est affichée", timeout: 30) {
            self.tabBarExists && self.containerVisible(self.element("accueil-screen"))
        }
        XCTAssertFalse(element("login-error").exists, "Aucune erreur de connexion en démo")
    }

    private func assertFiveTabs() {
        let expected: [(String, String)] = [("tab-accueil", "Accueil"), ("tab-explorer", "Explorer"),
                                            ("tab-missions", "Mes missions"), ("tab-revenus", "Revenus"), ("tab-profil", "Profil")]
        XCTAssertEqual(tabLabels.count, 5, "La barre expose exactement cinq onglets : \(tabLabels)")
        for (identifier, label) in expected {
            let tab = tabButton(identifier, label: label)
            require("L'onglet \(label) est visible") { self.visible(tab) }
            XCTAssertEqual(tab.label, label)
        }
        assertMissionsTabLabelFits()
        attachText(tabBarDescription, name: "\(proofPrefix)-onglets.txt")

        tabButton("tab-missions", label: "Mes missions").tap()
        // Lot 1, T5 : l'écran natif remplace l'état « Disponible au lot 1 » (`placeholder-missions`).
        require("Mes missions affiche ses missions à venir", timeout: 30) {
            self.containerVisible(self.element("mes-missions-screen")) && self.element("mes-mission-demo-assignee-001").exists
        }
        XCTAssertFalse(element("placeholder-missions").exists, "plus d'état d'attente pour Mes missions")
        tabButton("tab-revenus", label: "Revenus").tap()
        require("Revenus affiche son état honnête") { self.visible(self.element("placeholder-revenus")) }
    }

    private func openExplorer() {
        tabButton("tab-explorer", label: "Explorer").tap()
        let count = element("missions-count")
        require("Explorer affiche 30 missions", timeout: 30) {
            self.containerVisible(self.element("missions-list")) && count.exists && count.label == "30 missions"
        }
        XCTAssertEqual(count.label, "30 missions")
        record("\(proofPrefix)-explorer")
    }

    private func openFirstMissionAndReturn() {
        let rows = elements(withPrefix: "mission-row-")
        require("Au moins une cellule mission est visible") { rows.count > 0 && self.visible(rows.firstMatch) }
        let row = rows.firstMatch
        let rowIdentifier = row.identifier
        row.tap()
        let title = element("mission-detail-title")
        require("Le détail de la mission est rendu") {
            self.containerVisible(self.element("mission-detail")) && self.visible(title) && !title.label.isEmpty
        }
        for identifier in ["mission-detail-etablissement", "mission-detail-periode", "mission-detail-remuneration", "mission-detail-creneaux"] {
            require("Le détail expose \(identifier)") { self.element(identifier).exists }
        }
        let remuneration = element("mission-detail-remuneration").label
        XCTAssertTrue(remuneration.contains("€") || remuneration.contains("Rétrocession") || remuneration.contains("Taux non renseigné"),
                      "La rémunération affichée est la valeur serveur formatée")
        XCTAssertTrue(element("mission-detail-creneau-1").exists, "Au moins un créneau est listé")
        record("\(proofPrefix)-mission-detail")

        let back = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(back) }
        back.tap()
        require("La liste est de retour après le détail") {
            self.containerVisible(self.element("missions-list")) && self.visible(self.element(rowIdentifier)) && !title.exists
        }
        XCTAssertEqual(element("missions-count").label, "30 missions", "Le compteur reste à 30 missions au retour")
        record("\(proofPrefix)-mission-retour")
    }

    private func assertNoNetworkRequest() {
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil affiche l'email de démonstration") {
            self.visible(self.element("profile-email")) && self.element("profile-email").label.contains(Self.demoEmail)
        }
        XCTAssertTrue(element("profile-role").label.contains("SOIGNANT"), "Le rôle affiché est celui renvoyé par le port de rôle")
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Aucune requête réseau ne doit partir en mode démonstration")
        record("\(proofPrefix)-profil")
    }

    private func signOut() {
        tap("logout-button")
        require("La déconnexion ramène à l'écran de connexion") { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(tabBarExists, "Aucune barre d'onglets après déconnexion")
        XCTAssertFalse(element("missions-list").exists, "Aucune liste de missions après déconnexion")
        XCTAssertFalse(element("login-error").exists, "Une déconnexion volontaire n'affiche aucun message d'erreur")
        record("\(proofPrefix)-deconnexion")
    }
}
