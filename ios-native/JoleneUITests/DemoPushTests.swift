import XCTest

/// Push en démo, partie autorisation (lot 3, T4 ; blueprint §2.7). Les taps de notification
/// (`-JOLENE_SIMULER_PUSH`) sont ajoutés par T5. Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - carte « Autorisation du téléphone » de l'onglet Profil (`push-etat-appareil`, textes verbatim de
///   `PageParametresNotifications.tsx` l.341-352) selon `-JOLENE_PUSH_AUTORISATION` : « autorisées » sans
///   bouton, « bloquées » avec « Ouvrir les réglages » (`push-ouvrir-reglages`), aucune carte quand
///   l'autorisation n'a jamais été demandée (le canal push de Jolene est inconnu du hub : le texte l.349
///   « Le canal est actif dans Jolene… » serait affirmé sans le savoir) ;
/// - aucune alerte de l'app au login (D1). En démo, l'autorisation est un double (`DemoPushPermission`) qui
///   ne sollicite jamais le système : l'absence de feuille SpringBoard ne garde que contre un câblage du
///   centre de notifications réel en démo. L'absence de demande implicite est prouvée au niveau 1
///   (`PushCoordinatorTests.testSansAutorisationAucunAppelNiDemande`,
///   `EtatNotificationsAppareilModelTests`) ;
/// - déconnexion : retour à l'écran de connexion sans attente ni message d'erreur. L'ordre « désactivation
///   du token → désinscription → oubli → révocation » n'est pas visible ici : il est prouvé au niveau 1
///   (`SessionStorePushTests`, `DemoPushGatewayTests`) et sur STAGING par T16 (`tokens_push` relu).
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) ; chaque contrôle
/// est amené à l'écran par un défilement borné (`scrollTo`) avant d'être exigé atteignable (PRINCIPES §6).
final class DemoPushTests: JoleneUITestCase {
    static let titre = "Autorisation du téléphone"
    static let autorisees = "Les notifications sont autorisées sur cet appareil."
    static let bloquees = "Les notifications sont bloquées par le téléphone. Réactivez Jolene dans les réglages système."
    /// Libellé d'action sans source web (`EtatNotificationsAppareil.ouvrirReglages`, épinglé au niveau 1).
    static let ouvrirReglages = "Ouvrir les réglages"

    func testAppareilAutoriseTokenEnregistrePuisDeconnexion() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "accordee"])
        signInDemo()
        aucuneAlerte()
        openProfile()
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Enregistrement du token démo : aucune requête réseau")
        let message = carteEtat()
        require("L'enregistrement démo est confirmé") { message.label == Self.autorisees }
        XCTAssertEqual(element("push-etat-appareil-title").label, Self.titre)
        XCTAssertFalse(element("push-ouvrir-reglages").exists,
                       "Autorisé et enregistré : « Ouvrir les réglages » est superflu, aucun bouton")
        record("\(proofPrefix)-push-autorise")

        let deconnexion = element("logout-button")
        scrollTo(deconnexion, in: element("profile-list"), downward: false)
        tap("logout-button")
        require("La déconnexion aboutit sans attendre", timeout: 10) { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(element("login-error").exists, "Aucun message d'erreur après une déconnexion volontaire")
        record("\(proofPrefix)-push-deconnexion")
    }

    func testAppareilNonDemandeAucunPromptNiCarte() throws {
        launchDemo() // défaut démo : autorisation jamais demandée
        signInDemo()
        aucuneAlerte()
        openProfile()
        let list = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        // La section Notifications se placerait juste avant la suppression de compte : la liste est amenée
        // jusqu'à la première ligne de cette section (défilement vers le bas : elle s'arrête en bas de l'écran),
        // si bien que l'emplacement de la carte est à l'écran et qu'une carte affichée y serait rendue.
        scrollTo(element("compte-suppression-info"), in: list)
        XCTAssertFalse(element("push-etat-appareil").exists,
                       "Jamais demandé, canal inconnu dans le hub : aucune carte, rien n'est affirmé")
        XCTAssertFalse(element("push-ouvrir-reglages").exists)
        aucuneAlerte()
        record("\(proofPrefix)-push-non-demande")
    }

    func testAppareilRefuse() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "refusee"])
        signInDemo()
        openProfile()
        let message = carteEtat()
        require("L'état « bloquées » est affiché") { message.label == Self.bloquees }
        let reglages = element("push-ouvrir-reglages")
        scrollTo(reglages, in: element("profile-list"))
        require("« Ouvrir les réglages » est atteignable") { self.visible(reglages) && reglages.isEnabled }
        XCTAssertEqual(reglages.label, Self.ouvrirReglages)
        record("\(proofPrefix)-push-refuse")
    }

    // MARK: Étapes

    /// Aucune alerte au login (D1) : ni alerte de l'app, ni feuille SpringBoard (garde de câblage en démo,
    /// voir l'en-tête : le double d'autorisation ne sollicite jamais le système).
    private func aucuneAlerte() {
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
