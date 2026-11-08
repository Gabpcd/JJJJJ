import XCTest

/// Push en démo, partie autorisation (lot 3, T4 ; blueprint §2.7) : aucune feuille système au login
/// (D1), carte « Autorisation du téléphone » de l'onglet Profil (`push-etat-appareil`, textes verbatim
/// de `PageParametresNotifications.tsx` l.341-352) selon `-JOLENE_PUSH_AUTORISATION`, bouton
/// `push-ouvrir-reglages`, puis déconnexion (désactivation du token démo avant la révocation). Aucune
/// requête réseau. Les taps de notification (`-JOLENE_SIMULER_PUSH`) sont ajoutés par T5.
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`).
final class DemoPushTests: JoleneUITestCase {
    static let titre = "Autorisation du téléphone"
    static let autorisees = "Les notifications sont autorisées sur cet appareil."
    static let aAutoriser = "Le canal est actif dans Jolene, mais le téléphone doit encore autoriser les notifications."
    static let bloquees = "Les notifications sont bloquées par le téléphone. Réactivez Jolene dans les réglages système."

    func testAppareilAutoriseTokenEnregistrePuisDeconnexion() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "accordee"])
        signInDemo()
        aucuneFeuilleSysteme()
        openProfile()
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Enregistrement du token démo : aucune requête réseau")
        let message = carteEtat()
        require("L'enregistrement démo est confirmé") { message.label == Self.autorisees }
        XCTAssertEqual(element("push-etat-appareil-title").label, Self.titre)
        let reglages = element("push-ouvrir-reglages")
        require("« Ouvrir les réglages » est atteignable") { self.visible(reglages) && reglages.isEnabled }
        record("\(proofPrefix)-push-autorise")

        let deconnexion = element("logout-button")
        scrollTo(deconnexion, in: element("profile-list"), downward: false)
        tap("logout-button")
        require("La déconnexion aboutit sans attendre", timeout: 10) { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(element("login-error").exists, "Aucun message d'erreur après une déconnexion volontaire")
        record("\(proofPrefix)-push-deconnexion")
    }

    func testAppareilNonDemandeAucunPromptAuLogin() throws {
        launchDemo() // défaut démo : autorisation jamais demandée
        signInDemo()
        aucuneFeuilleSysteme()
        openProfile()
        let message = carteEtat()
        require("L'état « à autoriser » est affiché") { message.label == Self.aAutoriser }
        aucuneFeuilleSysteme()
        record("\(proofPrefix)-push-non-demande")
    }

    func testAppareilRefuse() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "refusee"])
        signInDemo()
        openProfile()
        let message = carteEtat()
        require("L'état « bloquées » est affiché") { message.label == Self.bloquees }
        let reglages = element("push-ouvrir-reglages")
        require("« Ouvrir les réglages » est atteignable") { self.visible(reglages) && reglages.isEnabled }
        record("\(proofPrefix)-push-refuse")
    }

    // MARK: Étapes

    /// Jamais de demande d'autorisation au login (D1) : ni alerte de l'app ni alerte système.
    private func aucuneFeuilleSysteme() {
        XCTAssertEqual(app.alerts.count, 0, "Aucune alerte dans l'app")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "Aucune feuille système d'autorisation")
    }

    /// Amène la carte d'état dans la liste du profil et rend son message.
    private func carteEtat() -> XCUIElement {
        let list = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        let message = element("push-etat-appareil-message")
        scrollTo(message, in: list)
        require("La carte « Autorisation du téléphone » est affichée") { self.element("push-etat-appareil").exists }
        return message
    }

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

    private func openProfile() {
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil affiche l'email de démonstration") {
            self.visible(self.element("profile-email")) && self.element("profile-email").label.contains(Self.demoEmail)
        }
    }
}
