import XCTest

/// Récupération du mot de passe en démo (reste de L1-T10) sur iPhone, iPad portrait et iPad paysage. Le lien est
/// injecté au lancement par l'argument DEBUG `-JOLENE_OPEN_URL` (lien universel simulé à froid, mêmes refus qu'un lien
/// réel) ; la démo s'ouvre sur l'écran de connexion.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - « Mot de passe oublié ? » (`login-forgot`) ouvre la demande ; l'envoi affiche le texte web, identique que le compte
///   existe ou non, puis le délai de 60 s ;
/// - `/reset-password?token_hash=demo&type=recovery` ouvre l'écran natif (jamais un renvoi web), au-dessus de la
///   connexion ; tant que le nouveau mot de passe n'est pas enregistré, aucun espace n'est ouvert (quarantaine : pas
///   de barre d'onglets) ; refus du « serveur » démo affiché verbatim ; succès → connexion, sans session ouverte ;
/// - abandon (« Retour à la connexion ») → connexion, aucune session ; lien invalide → refus du web, jamais le
///   formulaire ;
/// - aucune requête réseau en démo (monde démo sans client). Aucun vrai e-mail, aucun vrai lien : le lien réel depuis
///   Mail (AASA, modèle d'e-mail `token_hash`) se prouve sur appareil (`RECETTE_DEVICE_LOT1.md`).
final class DemoReinitialisationTests: JoleneUITestCase {
    private static let lienDemo = "https://jolene.app/reset-password?token_hash=demo&type=recovery"
    private static let nouveau = ["Nouveau", "-mdp-", "2026"].joined()
    /// `DemoRecoveryGateway.nouveauRefuse` : refusé par la démo comme un mot de passe trop faible.
    private static let refuse = "motdepasse"

    func testMotDePasseOublieMemeReponseEtDelaiDeRenvoi() throws {
        launchDemo()
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.containerVisible(scroll) }
        let oublie = element("login-forgot")
        scrollTo(oublie, in: scroll)
        XCTAssertEqual(oublie.label, "Mot de passe oublié ?")
        oublie.tap()
        let feuille = element("reset-request-sheet")
        require("La demande de lien est affichée") { feuille.exists }
        let email = element("reset-request-email")
        focus(email, in: feuille)
        email.typeText("inconnue@example.test")
        let envoyer = element("reset-request-submit")
        require("« Envoyer le lien » est activé") { envoyer.isEnabled && envoyer.label == "Envoyer le lien" }
        envoyer.tap()
        let envoye = element("reset-request-envoye")
        require("Le texte web est affiché, sans dire si le compte existe") {
            envoye.exists && envoye.label == "Si un compte existe pour inconnue@example.test, le lien vient d’être envoyé. "
                + "Vérifiez aussi les courriers indésirables."
        }
        require("Le délai de renvoi est affiché") { envoyer.label.hasPrefix("Renvoyer dans ") && !envoyer.isEnabled }
        XCTAssertFalse(element("reset-request-erreur").exists)
        record("\(proofPrefix)-reinitialisation-demande")
        tap("reset-request-retour")
        require("Retour à la connexion") { !feuille.exists && self.containerVisible(scroll) }
        XCTAssertFalse(tabBarExists, "aucune session ouverte")
    }

    func testLienTokenHashEcranNatifEnQuarantainePuisConnexion() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienDemo])
        let ecran = element("reset-password-screen")
        let scroll = element("reset-scroll")
        let nouveau = element("reset-nouveau")
        require("L'écran natif de réinitialisation est affiché", timeout: 30) { ecran.exists && nouveau.exists }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré : jamais un renvoi web")
        XCTAssertFalse(tabBarExists, "quarantaine : la session de récupération n'ouvre aucun espace")
        let soumettre = element("reset-submit")
        XCTAssertFalse(soumettre.isEnabled)

        // Confirmation différente : message du web ; puis refus du « serveur » démo, affiché verbatim.
        focus(nouveau, in: scroll)
        nouveau.typeText(Self.refuse)
        let confirmation = element("reset-confirmation")
        focus(confirmation, in: scroll)
        confirmation.typeText("x")
        require("La non-correspondance est signalée") {
            self.element("reset-non-correspondance").label == "Les mots de passe ne correspondent pas"
        }
        confirmation.typeText(XCUIKeyboardKey.delete.rawValue)
        confirmation.typeText(Self.refuse)
        require("Le formulaire est valide") { soumettre.isEnabled }
        scrollTo(soumettre, in: scroll)
        soumettre.tap()
        let erreur = element("reset-erreur")
        require("Le refus est affiché verbatim") {
            erreur.exists && erreur.label.hasPrefix("Mot de passe trop faible.")
        }
        XCTAssertFalse(tabBarExists)

        // Champs vidés par le système à la refocalisation d'un champ sécurisé : nouvelle saisie complète.
        effacerEtSaisir(nouveau, Self.nouveau, dans: scroll)
        effacerEtSaisir(confirmation, Self.nouveau, dans: scroll)
        require("Le formulaire est valide") { soumettre.isEnabled }
        scrollTo(soumettre, in: scroll)
        soumettre.tap()
        let succes = element("reset-succes")
        require("Mot de passe modifié") { succes.exists && succes.label == "Mot de passe modifié" }
        XCTAssertFalse(tabBarExists, "toujours aucun espace avant la connexion")
        record("\(proofPrefix)-reinitialisation-succes")
        tap("reset-succes-connexion")
        let connexion = element("login-scroll")
        require("L'écran de connexion est affiché") { !ecran.exists && self.containerVisible(connexion) }
        XCTAssertFalse(tabBarExists, "connexion requise après la réinitialisation")
    }

    func testAbandonFermeEtRevientALaConnexion() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienDemo])
        let ecran = element("reset-password-screen")
        require("L'écran natif de réinitialisation est affiché", timeout: 30) { ecran.exists && self.element("reset-nouveau").exists }
        let annuler = element("reset-annuler")
        scrollTo(annuler, in: element("reset-scroll"))
        XCTAssertEqual(annuler.label, "Retour à la connexion")
        annuler.tap()
        require("Retour à la connexion") { !ecran.exists && self.containerVisible(self.element("login-scroll")) }
        XCTAssertFalse(tabBarExists, "abandon : aucune session ouverte")
    }

    func testLienInvalideDonneLeRefusDuWebJamaisLeFormulaire() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/reset-password?token_hash=perime&type=recovery"])
        let refus = element("reset-lien-invalide")
        require("Le refus est affiché", timeout: 30) { refus.exists && refus.label == "Lien invalide ou expiré" }
        XCTAssertFalse(element("reset-nouveau").exists, "jamais le formulaire")
        XCTAssertFalse(element("renvoi-web-demo").exists)
        record("\(proofPrefix)-reinitialisation-refus")
        tap("reset-retour-connexion")
        require("Retour à la connexion") {
            !self.element("reset-password-screen").exists && self.containerVisible(self.element("login-scroll"))
        }
        XCTAssertFalse(tabBarExists)
    }

    // MARK: - Étapes

    private func effacerEtSaisir(_ champ: XCUIElement, _ texte: String, dans conteneur: XCUIElement) {
        scrollTo(champ, in: conteneur, downward: false)
        focus(champ, in: conteneur)
        let existant = (champ.value as? String)?.count ?? 0
        if existant > 0 {
            champ.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existant + Self.refuse.count))
        }
        champ.typeText(texte)
    }
}
