import XCTest

/// Préférences de notifications en démo (lot 3, T6) : Profil → « Réglages › Notifications »
/// (`profile-preferences-notifications`) → `prefs-screen`, port de `PageParametresNotifications.tsx`.
/// Recette dans l'interface (CLAUDE.md) : valeurs de `demo-preferences.json` affichées, canal global coupé →
/// cases grisées, carte « Autorisation du téléphone » dans les canaux globaux (hôte définitif, T4 → T6),
/// interrupteurs modifiés, « Enregistrer » → « Préférences enregistrées » (relu dans l'acteur démo), valeurs
/// relues en rouvrant l'écran, état d'erreur puis reprise (`JOLENE_FORCE_PREFERENCES_ECHEC`). Aucune
/// requête réseau. Écrit pour iPhone, iPad portrait et iPad paysage (`JOLENE_UI_ORIENTATION`).
///
/// Écart consigné (`DECISIONS_LOT3.md`, section T6) : l'entrée vit dans une section « Réglages » posée par T6
/// dans le hub Profil (fichier de T11), à la place de la carte provisoire de T4 ; l'Universal Link
/// `/soignant/parametres/notifications` ouvre le même écran (coordinateur des liens de L3-T3b,
/// `DemoLiensLot3Tests.testLienRecuAvantConnexionRejoueUneSeuleFoisApresReady`).
final class DemoPreferencesTests: JoleneUITestCase {
    func testPreferencesDemoModifieesEnregistreesPuisRelues() throws {
        launchDemo()
        connexionDemo()
        let ecran = prefsOuvrirDepuisLeProfil()

        // Valeurs de la fixture : e-mail, push et in-app actifs, SMS coupé (défaut serveur).
        XCTAssertEqual(prefsInterrupteur("prefs-canal-email"), true)
        XCTAssertEqual(prefsInterrupteur("prefs-canal-push"), true)
        XCTAssertEqual(prefsInterrupteur("prefs-canal-sms"), false)
        XCTAssertEqual(prefsInterrupteur("prefs-canal-inapp"), true)
        XCTAssertEqual(element("prefs-sms-alertes-avertissement").label,
                       "Le canal « SMS » est désactivé dans les canaux globaux ci-dessous : activez-le pour recevoir ces alertes.")
        XCTAssertFalse(element("prefs-sms-alertes").isEnabled, "alerte SMS grisée tant que le canal SMS est coupé")
        // Carte d'autorisation (T4) dans les canaux globaux : jamais demandée, canal push actif → l.349.
        let carte = element("push-etat-appareil-message")
        prefsDegager(carte, dans: ecran)
        XCTAssertEqual(carte.label, "Le canal est actif dans Jolene, mais le téléphone doit encore autoriser les notifications.")
        let caseSms = element("prefs-evt-CANDIDATURE_ACCEPTEE-SMS")
        prefsDegager(caseSms, dans: ecran)
        XCTAssertFalse(caseSms.isEnabled, "canal global coupé : case grisée (web l.406)")
        XCTAssertTrue(caseSms.label.contains("Canal SMS désactivé dans les canaux globaux"), "raison vocalisée : \(caseSms.label)")
        XCTAssertFalse(element("prefs-evt-SERIE_ONBOARDING-PUSH").exists, "« — » du web : aucun interrupteur hors canaux de l'événement")
        XCTAssertEqual(prefsInterrupteur("prefs-evt-LITIGE_RESOLU-PUSH"), false, "exception de la fixture")
        XCTAssertEqual(prefsInterrupteur("prefs-evt-CANDIDATURE_ACCEPTEE-EMAIL"), true, "aucune ligne = actif")
        record("\(proofPrefix)-prefs-initial")

        // Modifications : canal SMS activé (cases dégrisées), une case SMS coupée, une exception levée.
        prefsBasculer("prefs-canal-sms", dans: ecran)
        require("Le canal SMS est activé") { self.prefsInterrupteur("prefs-canal-sms") == true }
        require("La case SMS est dégrisée") { self.element("prefs-evt-CANDIDATURE_ACCEPTEE-SMS").isEnabled }
        XCTAssertFalse(element("prefs-sms-alertes-avertissement").exists, "avertissement retiré")
        prefsBasculer("prefs-evt-CANDIDATURE_ACCEPTEE-SMS", dans: ecran)
        require("La case SMS est coupée") { self.prefsInterrupteur("prefs-evt-CANDIDATURE_ACCEPTEE-SMS") == false }
        prefsBasculer("prefs-evt-LITIGE_RESOLU-PUSH", dans: ecran)
        require("L'exception est levée") { self.prefsInterrupteur("prefs-evt-LITIGE_RESOLU-PUSH") == true }
        prefsBasculer("prefs-sms-alertes", dans: ecran)
        require("L'alerte SMS est coupée") { self.prefsInterrupteur("prefs-sms-alertes") == false }

        tap("prefs-enregistrer")
        let enregistre = element("prefs-enregistre")
        require("« Préférences enregistrées » après relecture", timeout: 30) { enregistre.exists }
        XCTAssertTrue(enregistre.label.contains("Préférences enregistrées"), enregistre.label)
        XCTAssertFalse(element("prefs-enregistrement-erreur").exists)
        XCTAssertFalse(element("prefs-enregistrement-partiel").exists)
        record("\(proofPrefix)-prefs-enregistre")

        // Reprise : l'écran rouvert relit l'acteur démo (aucun brouillon local).
        prefsRetourAuProfil()
        let rouvert = prefsOuvrirDepuisLeProfil()
        XCTAssertEqual(prefsInterrupteur("prefs-canal-sms"), true, "canal SMS relu")
        XCTAssertEqual(prefsInterrupteur("prefs-sms-alertes"), false, "alerte SMS relue")
        XCTAssertEqual(prefsInterrupteur("prefs-evt-CANDIDATURE_ACCEPTEE-SMS"), false)
        XCTAssertEqual(prefsInterrupteur("prefs-evt-LITIGE_RESOLU-PUSH"), true)
        XCTAssertFalse(element("prefs-enregistre").exists, "aucune annonce reprise d'un écran précédent")
        prefsDegager(element("prefs-urgence"), dans: rouvert)
        XCTAssertTrue(element("prefs-urgence").label.contains("C'est une exigence de sécurité."), "texte verbatim web")
        record("\(proofPrefix)-prefs-relues")

        prefsRetourAuProfil()
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: element("profile-list"), downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "aucune requête réseau en démonstration")
    }

    /// État d'erreur puis reprise : `JOLENE_FORCE_PREFERENCES_ECHEC=1` (DEBUG, `AppContainer`) installe
    /// `DemoPreferencesEchecGateway`, dont la première lecture échoue comme un délai dépassé.
    func testPreferencesErreurPuisReprise() throws {
        launchDemo(environment: ["JOLENE_FORCE_PREFERENCES_ECHEC": "1"])
        connexionDemo()
        prefsOuvrirEntree()
        let erreur = element("prefs-error")
        require("L'écran affiche l'état d'erreur", timeout: 30) { self.containerVisible(erreur) }
        XCTAssertTrue(text("Impossible de charger vos préférences. Vos choix enregistrés sont conservés.").exists, "texte verbatim web (l.257)")
        XCTAssertFalse(element("prefs-canal-email").exists, "aucune préférence par défaut affichée")
        XCTAssertFalse(element("prefs-enregistrer").exists, "rien à enregistrer sans lecture")
        record("\(proofPrefix)-prefs-erreur")

        tap("prefs-retry")
        let email = element("prefs-canal-email")
        require("« Réessayer » relit les préférences démo", timeout: 30) { email.exists && !erreur.exists }
        XCTAssertEqual(prefsInterrupteur("prefs-canal-email"), true)
        XCTAssertEqual(prefsInterrupteur("prefs-evt-LITIGE_RESOLU-PUSH"), false)
        record("\(proofPrefix)-prefs-reprise")
    }

    // MARK: - Étapes

    private func connexionDemo() {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.containerVisible(scroll) }
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
        require("La session démo est prête", timeout: 30) { self.tabBarExists }
    }
}

/// Navigation et gestes de l'écran des préférences (lot 3, T6), partagés avec `DemoPushTests` (carte
/// d'autorisation, hôte définitif). Préfixe `prefs` : aucun conflit avec les étapes privées des autres
/// classes ; construits sur les helpers de `UITestSupport.swift` (`require`, `scrollTo`, `drag`).
extension JoleneUITestCase {
    /// Onglet Profil, puis l'entrée « Notifications » de la section « Réglages » (défilement borné).
    func prefsOuvrirEntree() {
        tabButton("tab-profil", label: "Profil").tap()
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let entree = element("profile-preferences-notifications")
        scrollTo(entree, in: liste)
        require("L'entrée Notifications est atteignable") { self.visible(entree) }
        XCTAssertTrue(entree.label.contains("Notifications"), entree.label)
        entree.tap()
    }

    /// Ouvre l'écran depuis le Profil et attend des préférences chargées.
    @discardableResult
    func prefsOuvrirDepuisLeProfil() -> XCUIElement {
        prefsOuvrirEntree()
        let ecran = element("prefs-screen")
        require("L'écran des préférences est chargé", timeout: 30) {
            self.containerVisible(ecran) && self.element("prefs-canal-email").exists
        }
        XCTAssertTrue(app.navigationBars["Préférences de notifications"].exists, "titre verbatim web")
        XCTAssertFalse(element("prefs-error").exists)
        return ecran
    }

    /// Retour au hub par le bouton retour de la barre de navigation.
    func prefsRetourAuProfil() {
        app.navigationBars.buttons.firstMatch.tap()
        require("Retour au profil") { self.containerVisible(self.element("profile-list")) && !self.element("prefs-screen").exists }
    }

    /// Valeur d'un interrupteur (`Toggle` SwiftUI : « 1 » / « 0 »), nil s'il est absent.
    func prefsInterrupteur(_ identifiant: String) -> Bool? {
        let cible = element(identifiant)
        guard cible.exists else { return nil }
        switch cible.value as? String {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }

    func prefsBasculer(_ identifiant: String, dans ecran: XCUIElement) {
        let cible = element(identifiant)
        prefsDegager(cible, dans: ecran)
        require("L'interrupteur \(identifiant) est activable") { cible.isEnabled }
        // Le commutateur est à droite de la ligne : un tap au centre peut tomber sur le libellé, qui bascule aussi.
        cible.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    /// Barre qui recouvre `cible` : navigation (haut), barre d'enregistrement de l'écran, ou onglets (bas, iPhone).
    func prefsBarreQuiRecouvre(_ cible: XCUIElement) -> PrefsBarre? {
        let navigation = app.navigationBars.firstMatch
        if navigation.exists, cible.frame.minY < navigation.frame.maxY { return .navigation }
        let action = element("prefs-barre-action")
        if action.exists, cible.identifier != "prefs-enregistrer", cible.frame.maxY > action.frame.minY { return .action }
        let onglets = app.tabBars.firstMatch
        if onglets.exists, cible.frame.maxY > onglets.frame.minY { return .onglets }
        return nil
    }

    /// Défilement borné jusqu'à la cible, puis dégagement des barres (glissements courts et bornés).
    func prefsDegager(_ cible: XCUIElement, dans ecran: XCUIElement) {
        scrollTo(cible, in: ecran)
        var essais = 0
        while essais < 8, let barre = prefsBarreQuiRecouvre(cible) {
            if barre == .navigation { drag(ecran, fromY: 0.4, toY: 0.6) } else { drag(ecran, fromY: 0.6, toY: 0.4) }
            essais += 1
        }
        require("La cible est atteignable hors des barres") { self.visible(cible) && self.prefsBarreQuiRecouvre(cible) == nil }
    }
}

/// Barres qui peuvent recouvrir un contrôle de l'écran des préférences.
enum PrefsBarre { case navigation, onglets, action }
