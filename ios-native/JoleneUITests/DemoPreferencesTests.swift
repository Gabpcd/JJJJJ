import XCTest

/// Préférences de notifications en démo (lot 3, T6) : Profil → « Réglages › Notifications » →
/// `prefs-screen`, port de `PageParametresNotifications.tsx`. Recette dans l'interface (CLAUDE.md) :
/// valeurs de `demo-preferences.json` affichées, canal global coupé → cases grisées, interrupteurs
/// modifiés, « Enregistrer » → « Préférences enregistrées » (relu dans l'acteur démo), valeurs
/// relues en rouvrant l'écran, état d'erreur puis reprise (`JOLENE_FORCE_PREFERENCES_ECHEC`). Aucune
/// requête réseau. Écrit pour iPhone, iPad portrait et iPad paysage (`JOLENE_UI_ORIENTATION`).
///
/// Écart consigné (notes de la tranche) : l'entrée vit dans une section « Réglages » ajoutée au hub
/// Profil, en attendant le hub de T11 et la route `.parametresNotifications` de T3 (Universal Link
/// `/soignant/parametres/notifications`, `DeepLinkCoordinator` du lot 1 T10, absents de la base).
final class DemoPreferencesTests: JoleneUITestCase {
    func testPreferencesDemoModifieesEnregistreesPuisRelues() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirPreferences()

        // Valeurs de la fixture : e-mail, push et in-app actifs, SMS coupé (défaut serveur).
        XCTAssertEqual(interrupteur("prefs-canal-email"), true)
        XCTAssertEqual(interrupteur("prefs-canal-push"), true)
        XCTAssertEqual(interrupteur("prefs-canal-sms"), false)
        XCTAssertEqual(interrupteur("prefs-canal-inapp"), true)
        XCTAssertEqual(element("prefs-sms-alertes-avertissement").label,
                       "Le canal « SMS » est désactivé dans les canaux globaux ci-dessous : activez-le pour recevoir ces alertes.")
        XCTAssertFalse(element("prefs-sms-alertes").isEnabled, "alerte SMS grisée tant que le canal SMS est coupé")
        let caseSms = element("prefs-evt-CANDIDATURE_ACCEPTEE-SMS")
        degager(caseSms, dans: ecran)
        XCTAssertFalse(caseSms.isEnabled, "canal global coupé : case grisée (web l.406)")
        XCTAssertTrue(caseSms.label.contains("Canal SMS désactivé dans les canaux globaux"), "raison vocalisée : \(caseSms.label)")
        XCTAssertFalse(element("prefs-evt-SERIE_ONBOARDING-PUSH").exists, "« — » du web : aucun interrupteur hors canaux de l'événement")
        XCTAssertEqual(interrupteur("prefs-evt-LITIGE_RESOLU-PUSH"), false, "exception de la fixture")
        XCTAssertEqual(interrupteur("prefs-evt-CANDIDATURE_ACCEPTEE-EMAIL"), true, "aucune ligne = actif")
        record("\(proofPrefix)-prefs-initial")

        // Modifications : canal SMS activé (cases dégrisées), une case SMS coupée, une exception levée.
        basculer("prefs-canal-sms", dans: ecran)
        require("Le canal SMS est activé") { self.interrupteur("prefs-canal-sms") == true }
        require("La case SMS est dégrisée") { self.element("prefs-evt-CANDIDATURE_ACCEPTEE-SMS").isEnabled }
        XCTAssertFalse(element("prefs-sms-alertes-avertissement").exists, "avertissement retiré")
        basculer("prefs-evt-CANDIDATURE_ACCEPTEE-SMS", dans: ecran)
        require("La case SMS est coupée") { self.interrupteur("prefs-evt-CANDIDATURE_ACCEPTEE-SMS") == false }
        basculer("prefs-evt-LITIGE_RESOLU-PUSH", dans: ecran)
        require("L'exception est levée") { self.interrupteur("prefs-evt-LITIGE_RESOLU-PUSH") == true }
        basculer("prefs-sms-alertes", dans: ecran)
        require("L'alerte SMS est coupée") { self.interrupteur("prefs-sms-alertes") == false }

        tap("prefs-enregistrer")
        let enregistre = element("prefs-enregistre")
        require("« Préférences enregistrées » après relecture", timeout: 30) { enregistre.exists }
        XCTAssertTrue(enregistre.label.contains("Préférences enregistrées"), enregistre.label)
        XCTAssertFalse(element("prefs-enregistrement-erreur").exists)
        XCTAssertFalse(element("prefs-enregistrement-partiel").exists)
        record("\(proofPrefix)-prefs-enregistre")

        // Reprise : l'écran rouvert relit l'acteur démo (aucun brouillon local).
        app.navigationBars.buttons.firstMatch.tap()
        require("Retour au profil") { self.containerVisible(self.element("profile-list")) && !self.element("prefs-screen").exists }
        let rouvert = ouvrirPreferences()
        XCTAssertEqual(interrupteur("prefs-canal-sms"), true, "canal SMS relu")
        XCTAssertEqual(interrupteur("prefs-sms-alertes"), false, "alerte SMS relue")
        XCTAssertEqual(interrupteur("prefs-evt-CANDIDATURE_ACCEPTEE-SMS"), false)
        XCTAssertEqual(interrupteur("prefs-evt-LITIGE_RESOLU-PUSH"), true)
        XCTAssertFalse(element("prefs-enregistre").exists, "aucune annonce reprise d'un écran précédent")
        degager(element("prefs-urgence"), dans: rouvert)
        XCTAssertTrue(element("prefs-urgence").label.contains("C'est une exigence de sécurité."), "texte verbatim web")
        record("\(proofPrefix)-prefs-relues")

        app.navigationBars.buttons.firstMatch.tap()
        require("Retour au profil") { self.containerVisible(self.element("profile-list")) }
        let sentinelle = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "aucune requête réseau en démonstration")
    }

    /// État d'erreur puis reprise : `JOLENE_FORCE_PREFERENCES_ECHEC=1` (DEBUG, `AppContainer`) installe
    /// `DemoPreferencesEchecGateway`, dont la première lecture échoue comme un délai dépassé.
    func testPreferencesErreurPuisReprise() throws {
        launchDemo(environment: ["JOLENE_FORCE_PREFERENCES_ECHEC": "1"])
        connexionDemo()
        ouvrirEntree()
        let erreur = element("prefs-error")
        require("L'écran affiche l'état d'erreur", timeout: 30) { self.containerVisible(erreur) }
        XCTAssertTrue(text("Impossible de charger vos préférences. Vos choix enregistrés sont conservés.").exists, "texte verbatim web (l.257)")
        XCTAssertFalse(element("prefs-canal-email").exists, "aucune préférence par défaut affichée")
        XCTAssertFalse(element("prefs-enregistrer").exists, "rien à enregistrer sans lecture")
        record("\(proofPrefix)-prefs-erreur")

        tap("prefs-retry")
        let email = element("prefs-canal-email")
        require("« Réessayer » relit les préférences démo", timeout: 30) { email.exists && !erreur.exists }
        XCTAssertEqual(interrupteur("prefs-canal-email"), true)
        XCTAssertEqual(interrupteur("prefs-evt-LITIGE_RESOLU-PUSH"), false)
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

    /// Onglet Profil, puis l'entrée « Notifications » de la section « Réglages » (défilement borné).
    private func ouvrirEntree() {
        tabButton("tab-profil", label: "Profil").tap()
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let entree = element("profile-preferences-notifications")
        var glissements = 0
        while !visible(entree) && glissements < 6 {
            drag(liste, fromY: 0.8, toY: 0.4)
            glissements += 1
        }
        require("L'entrée Notifications est atteignable") { self.visible(entree) }
        XCTAssertTrue(entree.label.contains("Notifications"), entree.label)
        entree.tap()
    }

    @discardableResult
    private func ouvrirPreferences() -> XCUIElement {
        ouvrirEntree()
        let ecran = element("prefs-screen")
        require("L'écran des préférences est chargé", timeout: 30) {
            self.containerVisible(ecran) && self.element("prefs-canal-email").exists
        }
        XCTAssertTrue(app.navigationBars["Préférences de notifications"].exists, "titre verbatim web")
        XCTAssertFalse(element("prefs-error").exists)
        return ecran
    }

    /// Valeur d'un interrupteur (`Toggle` SwiftUI : « 1 » / « 0 »), nil s'il est absent.
    private func interrupteur(_ identifiant: String) -> Bool? {
        let cible = element(identifiant)
        guard cible.exists else { return nil }
        switch cible.value as? String {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }

    private func basculer(_ identifiant: String, dans ecran: XCUIElement) {
        let cible = element(identifiant)
        degager(cible, dans: ecran)
        require("L'interrupteur \(identifiant) est activable") { cible.isEnabled }
        // Le commutateur est à droite de la ligne : un tap au centre peut tomber sur le libellé, qui bascule aussi.
        cible.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private enum Barre { case navigation, onglets, action }

    /// Barre qui recouvre `cible` : navigation (haut), onglets (bas, iPhone) ou barre d'enregistrement de l'écran.
    private func barreQuiRecouvre(_ cible: XCUIElement) -> Barre? {
        let navigation = app.navigationBars.firstMatch
        if navigation.exists, cible.frame.minY < navigation.frame.maxY { return .navigation }
        let action = element("prefs-barre-action")
        if action.exists, cible.identifier != "prefs-enregistrer", cible.frame.maxY > action.frame.minY { return .action }
        let onglets = app.tabBars.firstMatch
        if onglets.exists, cible.frame.maxY > onglets.frame.minY { return .onglets }
        return nil
    }

    /// Défilement borné jusqu'à la cible, puis dégagement des barres (glissements courts et bornés).
    private func degager(_ cible: XCUIElement, dans ecran: XCUIElement) {
        scrollTo(cible, in: ecran)
        var essais = 0
        while essais < 8, let barre = barreQuiRecouvre(cible) {
            if barre == .navigation { drag(ecran, fromY: 0.4, toY: 0.6) } else { drag(ecran, fromY: 0.6, toY: 0.4) }
            essais += 1
        }
        require("La cible est atteignable hors des barres") { self.visible(cible) && self.barreQuiRecouvre(cible) == nil }
    }
}
