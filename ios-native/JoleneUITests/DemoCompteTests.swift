import XCTest

/// Suppression de compte en démo (lot 1, T8 ; Apple 5.1.1) : onglet Profil → texte RGPD du web
/// (tutoiement, HARD STOP n°4) → saisie stricte « SUPPRIMER » → `DemoAccountGateway` → écran
/// « Compte supprimé » (jamais « Votre session a expiré ») → connexion. Aucune requête réseau.
/// Identifiants : `compte-supprimer-ouvrir`, `compte-supprimer` (+ `-title`, `-message`, `-input`,
/// `-confirm`, `-cancel`, `-erreur`), `compte-supprime` (+ `-titre`, `-message`, `-continuer`).
final class DemoCompteTests: JoleneUITestCase {
    /// Textes verbatim de `SectionConfidentialite.tsx` (l.156, l.172) : l'écran les affiche tels quels.
    static let avertissementSection =
        "La suppression de ton compte est irréversible. Tes données seront anonymisées conformément au RGPD."
    static let avertissementConfirmation =
        "Cette action est irréversible. Tes données seront anonymisées conformément au RGPD."

    func testSuppressionDeCompteDemoJusquALEcranDeFinPuisConnexion() throws {
        launchDemo()
        signInDemo()
        openProfile()
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Aucune requête réseau en démonstration")

        openDeletion()
        let confirm = element("compte-supprimer-confirm")
        XCTAssertFalse(confirm.isEnabled, "Suppression impossible tant que SUPPRIMER n'est pas saisi")

        let input = element("compte-supprimer-input")
        focus(input, in: element("compte-supprimer"))
        input.typeText("SUPPRIME")
        require("La saisie incomplète est affichée") { (input.value as? String) == "SUPPRIME" }
        XCTAssertFalse(confirm.isEnabled, "Égalité stricte : « SUPPRIME » ne suffit pas")
        input.typeText("R")
        require("La phrase exacte active la suppression") { confirm.isEnabled }
        input.typeText("\n")
        if !visible(confirm) { scrollTo(confirm, in: element("compte-supprimer")) }
        record("\(proofPrefix)-compte-confirmation")

        tap("compte-supprimer-confirm")
        let fin = element("compte-supprime")
        require("L'écran « Compte supprimé » remplace l'espace connecté", timeout: 30) { self.containerVisible(fin) }
        XCTAssertEqual(element("compte-supprime-titre").label, "Compte supprimé")
        XCTAssertFalse(element("compte-supprime-message").label.isEmpty)
        XCTAssertFalse(tabBarExists, "Plus aucun onglet après la suppression")
        XCTAssertFalse(element("login-error").exists, "Jamais « Votre session a expiré » après une suppression")
        XCTAssertFalse(textContaining("session a expiré").exists)
        record("\(proofPrefix)-compte-supprime")

        tap("compte-supprime-continuer")
        require("La connexion est proposée après l'écran de fin") { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(element("login-error").exists, "Aucun message d'erreur à la connexion")
        XCTAssertFalse(element("compte-supprime").exists)
        record("\(proofPrefix)-compte-connexion")
    }

    func testAnnulerLaSuppressionRameneAuProfilSansRienSupprimer() throws {
        launchDemo()
        signInDemo()
        openProfile()
        openDeletion()

        tap("compte-supprimer-cancel")
        require("Le profil est de retour, la session intacte") {
            self.visible(self.element("profile-email")) && !self.element("compte-supprimer").exists
        }
        XCTAssertTrue(tabBarExists, "La session reste ouverte")
        XCTAssertTrue(element("profile-email").label.contains(Self.demoEmail))
        record("\(proofPrefix)-compte-annulation")
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

    private func openProfile() {
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil affiche l'email de démonstration") {
            self.visible(self.element("profile-email")) && self.element("profile-email").label.contains(Self.demoEmail)
        }
    }

    /// La section « Suppression de compte » est la dernière de la liste : la liste est amenée en bas
    /// (glissements bornés), le texte RGPD est vérifié mot pour mot, puis l'écran de confirmation s'ouvre.
    private func openDeletion() {
        let list = element("profile-list")
        let ouvrir = element("compte-supprimer-ouvrir")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        // Toujours deux glissements vers le bas : la dernière section remonte au-dessus de la barre
        // d'onglets (iPhone) même quand elle semblait déjà dans le cadre de la liste ; sans effet
        // quand tout le contenu tient à l'écran. Puis au plus quatre de plus tant qu'elle n'est pas atteignable.
        for _ in 0..<2 { drag(list, fromY: 0.8, toY: 0.3) }
        var glissements = 0
        while !visible(ouvrir) && glissements < 4 {
            drag(list, fromY: 0.8, toY: 0.3)
            glissements += 1
        }
        let avertissement = element("compte-suppression-info")
        require("Le texte RGPD de la section est affiché") { avertissement.exists }
        XCTAssertEqual(avertissement.label, Self.avertissementSection, "Texte RGPD verbatim web (tutoiement)")
        tap("compte-supprimer-ouvrir")

        let ecran = element("compte-supprimer")
        require("L'écran de confirmation est affiché") {
            self.containerVisible(ecran) && self.element("compte-supprimer-title").exists
        }
        XCTAssertEqual(element("compte-supprimer-title").label, "Supprimer mon compte")
        XCTAssertEqual(element("compte-supprimer-message").label, Self.avertissementConfirmation, "Texte RGPD verbatim web")
        XCTAssertTrue(textContaining("Tape SUPPRIMER pour confirmer.").exists, "Consigne verbatim web")
        XCTAssertTrue(element("compte-supprimer-confirm").exists)
        XCTAssertTrue(element("compte-supprimer-cancel").exists)
        record("\(proofPrefix)-compte-ecran")
    }
}
