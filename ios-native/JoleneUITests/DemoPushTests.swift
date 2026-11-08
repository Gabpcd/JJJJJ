import XCTest

/// Push en démo, partie autorisation (lot 3, T4 ; carte déplacée par T6 dans les préférences de notifications,
/// son hôte définitif — une seule surface, `REVUES_LOT3.md`, section L3-T4 ; blueprint §2.7). Les taps de
/// notification (`-JOLENE_SIMULER_PUSH`) sont ajoutés par T5. Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - le hub Profil ne porte plus la carte (retirée par T6) mais l'entrée « Réglages › Notifications »
///   (`profile-preferences-notifications`) ;
/// - carte « Autorisation du téléphone » de l'écran des préférences (`push-etat-appareil`, textes verbatim de
///   `PageParametresNotifications.tsx` l.341-352, canal push lu des préférences) selon
///   `-JOLENE_PUSH_AUTORISATION` : « autorisées » sans bouton ; « bloquées » avec « Ouvrir les réglages »
///   (`push-ouvrir-reglages`) ; jamais demandée avec le canal push actif (fixture) : l.349 et « Activer sur
///   cet appareil » (`push-activer-appareil`, l.365), qui demande au tap seulement (D1) puis enregistre
///   l'appareil ; carte absente quand le canal push est coupé dans le brouillon (l.349 serait faux) ;
/// - aucune alerte de l'app au login ni à l'ouverture de l'écran (D1). En démo, l'autorisation est un double
///   (`DemoPushPermission`) qui ne sollicite jamais le système : l'absence de feuille SpringBoard ne garde que
///   contre un câblage du centre de notifications réel en démo. L'absence de demande implicite est prouvée au
///   niveau 1 (`PushCoordinatorTests.testSansAutorisationAucunAppelNiDemande`,
///   `EtatNotificationsAppareilModelTests`) ;
/// - déconnexion : retour à l'écran de connexion sans attente ni message d'erreur. L'ordre « désactivation
///   du token → désinscription → oubli → révocation » n'est pas visible ici : il est prouvé au niveau 1
///   (`SessionStorePushTests`, `DemoPushGatewayTests`) et sur STAGING par T16 (`tokens_push` relu).
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) ; chaque contrôle
/// est amené à l'écran par un défilement borné (`scrollTo`, `prefsDegager`) avant d'être exigé atteignable
/// (PRINCIPES §6). Navigation vers les préférences : helpers `prefs…` de `DemoPreferencesTests.swift`.
final class DemoPushTests: JoleneUITestCase {
    static let titre = "Autorisation du téléphone"
    static let autorisees = "Les notifications sont autorisées sur cet appareil."
    static let aAutoriser = "Le canal est actif dans Jolene, mais le téléphone doit encore autoriser les notifications."
    static let bloquees = "Les notifications sont bloquées par le téléphone. Réactivez Jolene dans les réglages système."
    /// Libellé d'action sans source web (`EtatNotificationsAppareil.ouvrirReglages`, épinglé au niveau 1).
    static let ouvrirReglages = "Ouvrir les réglages"
    /// `PageParametresNotifications.tsx` l.365 (`EtatNotificationsAppareil.activerSurAppareil`).
    static let activer = "Activer sur cet appareil"

    func testAppareilAutoriseTokenEnregistrePuisDeconnexion() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "accordee"])
        signInDemo()
        aucuneAlerte()
        openProfile()
        aucuneCarteDansLeHub()
        let ecran = prefsOuvrirDepuisLeProfil()
        let message = carteEtat(dans: ecran)
        require("L'enregistrement démo est confirmé") { message.label == Self.autorisees }
        XCTAssertEqual(element("push-etat-appareil-title").label, Self.titre)
        XCTAssertFalse(element("push-ouvrir-reglages").exists,
                       "Autorisé et enregistré : « Ouvrir les réglages » est superflu, aucun bouton")
        XCTAssertFalse(element("push-activer-appareil").exists, "Autorisé et enregistré : rien à activer")
        record("\(proofPrefix)-push-autorise")

        prefsRetourAuProfil()
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Enregistrement du token démo : aucune requête réseau")
        let deconnexion = element("logout-button")
        scrollTo(deconnexion, in: element("profile-list"), downward: false)
        tap("logout-button")
        require("La déconnexion aboutit sans attendre", timeout: 10) { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(element("login-error").exists, "Aucun message d'erreur après une déconnexion volontaire")
        record("\(proofPrefix)-push-deconnexion")
    }

    func testAppareilNonDemandeCarteEtActivationAuTap() throws {
        launchDemo() // défaut démo : autorisation jamais demandée
        signInDemo()
        aucuneAlerte()
        openProfile()
        aucuneCarteDansLeHub()
        let ecran = prefsOuvrirDepuisLeProfil()
        aucuneAlerte() // ouverture de l'écran : aucune demande implicite (D1)
        let message = carteEtat(dans: ecran)
        require("Jamais demandé, canal push actif (fixture) : l.349") { message.label == Self.aAutoriser }
        let activer = element("push-activer-appareil")
        prefsDegager(activer, dans: ecran)
        XCTAssertEqual(activer.label, Self.activer)
        XCTAssertFalse(element("push-ouvrir-reglages").exists,
                       "Jamais demandé : Réglages n'a pas encore d'entrée Notifications pour l'app")
        record("\(proofPrefix)-push-non-demande")

        // Canal push coupé dans le brouillon : « Le canal est actif dans Jolene » serait faux, la carte disparaît.
        prefsBasculer("prefs-canal-push", dans: ecran)
        require("Canal push coupé : aucune carte") { !self.element("push-etat-appareil").exists }
        prefsBasculer("prefs-canal-push", dans: ecran)
        require("Canal push réactivé : la carte revient") { self.element("push-etat-appareil").exists }

        // Au tap seulement : demande (double démo, qui accorde) puis enregistrement de l'appareil.
        prefsDegager(activer, dans: ecran)
        activer.tap()
        require("Autorisation accordée et appareil enregistré", timeout: 20) {
            self.element("push-etat-appareil-message").label == Self.autorisees
        }
        XCTAssertFalse(element("push-activer-appareil").exists, "Tout est en ordre : plus aucun bouton")
        aucuneAlerte()
        record("\(proofPrefix)-push-active")
    }

    func testAppareilRefuse() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "refusee"])
        signInDemo()
        openProfile()
        let ecran = prefsOuvrirDepuisLeProfil()
        let message = carteEtat(dans: ecran)
        require("L'état « bloquées » est affiché") { message.label == Self.bloquees }
        let reglages = element("push-ouvrir-reglages")
        prefsDegager(reglages, dans: ecran)
        require("« Ouvrir les réglages » est atteignable") { self.visible(reglages) && reglages.isEnabled }
        XCTAssertEqual(reglages.label, Self.ouvrirReglages)
        XCTAssertFalse(element("push-activer-appareil").exists, "Refusé : une demande serait sans effet")
        record("\(proofPrefix)-push-refuse")
    }

    // MARK: Étapes

    /// Aucune alerte (D1) : ni alerte de l'app, ni feuille SpringBoard (garde de câblage en démo,
    /// voir l'en-tête : le double d'autorisation ne sollicite jamais le système).
    private func aucuneAlerte() {
        XCTAssertEqual(app.alerts.count, 0, "Aucune alerte dans l'app")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "Aucune feuille système d'autorisation")
    }

    /// Le hub ne porte plus la carte (une seule surface, T6) : la liste est amenée jusqu'à la suppression de
    /// compte (dernière section), si bien que l'emplacement provisoire de T4 est à l'écran ; seule l'entrée
    /// « Réglages › Notifications » y figure.
    private func aucuneCarteDansLeHub() {
        let list = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        scrollTo(element("compte-suppression-info"), in: list)
        XCTAssertFalse(element("push-etat-appareil").exists, "Carte retirée du hub : elle vit dans les préférences")
        XCTAssertFalse(element("push-ouvrir-reglages").exists)
        XCTAssertTrue(element("profile-preferences-notifications").exists, "Entrée « Notifications » du hub")
    }

    /// Amène la carte d'état dans l'écran des préférences et rend son message.
    private func carteEtat(dans ecran: XCUIElement) -> XCUIElement {
        let message = element("push-etat-appareil-message")
        require("La carte « Autorisation du téléphone » est affichée") { self.element("push-etat-appareil").exists }
        prefsDegager(message, dans: ecran)
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
