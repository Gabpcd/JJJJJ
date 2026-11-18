import XCTest

/// Coordonnées bancaires en démo (lot 3, T14b, B9 ; `DECISIONS_LOT3.md`, section T14b) sur iPhone, iPad portrait et
/// iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`). Serveur simulé `DemoIbanGateway` (RIB démo portant l'IBAN
/// d'exemple ISO 13616, titulaire = prénom et nom du profil fictif).
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - entrée du hub « Coordonnées bancaires » (`iban-ouvrir`) → écran `iban-screen` ;
/// - contrôle local du web : « IBAN invalide » sur une clé fausse, « IBAN valide » ensuite, bouton actif seulement alors ;
/// - enregistrement → « IBAN enregistré » après relecture, IBAN affiché masqué (quatre derniers caractères), champ vidé ;
/// - refus serveur `RIB_VERIFIE_REQUIS` (`JOLENE_DEMO_IBAN=rib-requis`) : message serveur verbatim sous « RIB vérifié
///   requis », action vers les documents, jamais « IBAN enregistré ».
/// Les règles (codes sans `error`, relecture probante, epoch, session) sont prouvées au niveau 1 (`IbanTests`,
/// `SupabaseIbanGatewayTests`).
final class DemoIbanTests: JoleneUITestCase {
    private static let ibanFaux = "FR7630006000011234567890188"

    func testEnregistrerRelitEtMasqueLIBAN() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirIban()
        let enregistrer = element("iban-enregistrer")
        XCTAssertFalse(enregistrer.isEnabled, "formulaire vide : bouton inactif (l.366)")

        saisir("iban-input", Self.ibanFaux, dans: ecran)
        require("Clé fausse : « IBAN invalide » (l.339)") { self.element("iban-invalide").exists }
        element("iban-input").typeText(XCUIKeyboardKey.delete.rawValue + "9")
        require("Clé juste : « IBAN valide » (l.344)") { self.element("iban-valide").exists && !self.element("iban-invalide").exists }
        saisir("iban-titulaire", "Camille Demo", dans: ecran)
        scrollTo(enregistrer, in: ecran)
        require("IBAN valide et titulaire : bouton actif") { enregistrer.isEnabled }
        XCTAssertEqual(enregistrer.label, "Enregistrer l'IBAN")
        record("\(proofPrefix)-iban-saisie")

        tap("iban-enregistrer")
        let succes = element("iban-succes")
        require("« IBAN enregistré » après relecture", timeout: 30) { succes.exists }
        XCTAssertTrue(succes.label.contains("IBAN enregistré"), succes.label)
        let actuel = element("iban-actuel")
        scrollTo(actuel, in: ecran, downward: false)
        XCTAssertTrue(actuel.label.contains("•••• •••• •••• •••• •••• 0189"), actuel.label)
        XCTAssertFalse(actuel.label.contains("30006000"), "jamais l'IBAN en clair")
        XCTAssertEqual(element("iban-actuel-titulaire").label, "Titulaire : Camille Démo")
        XCTAssertFalse(element("iban-erreur").exists)
        // Champ vide : XCUITest rend alors le texte indicatif (l.332), jamais l'IBAN saisi.
        let valeur = element("iban-input").value as? String ?? ""
        XCTAssertTrue(valeur.isEmpty || valeur == "FR76 3000 6000 0112 3456 7890 189", "champ IBAN vidé après l'envoi : \(valeur)")
        scrollTo(enregistrer, in: ecran)
        XCTAssertEqual(enregistrer.label, "Mettre à jour")
        XCTAssertFalse(enregistrer.isEnabled)
        record("\(proofPrefix)-iban-enregistre")
    }

    func testRefusRibRequisVerbatimJamaisUnSucces() throws {
        launchDemo(environment: ["JOLENE_DEMO_IBAN": "rib-requis"])
        connexionDemo()
        let ecran = ouvrirIban()
        saisir("iban-input", "FR7630006000011234567890189", dans: ecran)
        saisir("iban-titulaire", "Camille Demo", dans: ecran)
        let enregistrer = element("iban-enregistrer")
        scrollTo(enregistrer, in: ecran)
        require("Bouton actif") { enregistrer.isEnabled }
        tap("iban-enregistrer")
        let erreur = element("iban-erreur")
        require("Le refus du serveur est affiché", timeout: 30) { erreur.exists }
        XCTAssertTrue(erreur.label.contains("RIB vérifié requis"), erreur.label)
        XCTAssertTrue(erreur.label.contains("Téléversez puis faites vérifier le RIB correspondant."), erreur.label)
        XCTAssertTrue(element("iban-documents").exists, "« Téléverser mon RIB » (l.316)")
        XCTAssertFalse(element("iban-succes").exists, "jamais « IBAN enregistré » sur un refus")
        XCTAssertFalse(element("iban-actuel").exists)
        record("\(proofPrefix)-iban-rib-requis")
    }

    // MARK: - Parcours

    private func ouvrirIban() -> XCUIElement {
        tabButton("tab-profil", label: "Profil").tap()
        let liste = element("profile-list")
        require("Le hub est affiché") { self.containerVisible(liste) }
        let entree = element("iban-ouvrir")
        scrollTo(entree, in: liste)
        XCTAssertTrue(entree.label.contains("Coordonnées bancaires"), entree.label)
        tap("iban-ouvrir")
        let ecran = element("iban-screen")
        require("L'écran des coordonnées bancaires est chargé", timeout: 30) {
            self.containerVisible(ecran) && self.element("iban-input").exists
        }
        XCTAssertTrue(app.navigationBars["Coordonnées bancaires"].exists, "titre verbatim web (l.277)")
        return ecran
    }

    private func saisir(_ identifiant: String, _ texte: String, dans ecran: XCUIElement) {
        let champ = element(identifiant)
        scrollTo(champ, in: ecran)
        focus(champ, in: ecran)
        champ.typeText(texte)
    }

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
        toucherSeConnecter(submit, "La session démo est prête") { self.tabBarExists }
    }
}
