import XCTest

/// Inscription soignant en démo (lot 3, T7) : écran de connexion → « Créer un compte soignant » → compte rapide
/// (`InscriptionRapide.tsx`, textes verbatim, consentement aux CGU et à la politique de confidentialité) → lien de
/// confirmation envoyé → « J’ai confirmé mon email » → aiguillage d'onboarding (parcours démarré par
/// `fn_demarrer_inscription` simulé) → complétion du profil (T8, `DemoCompletionInscriptionTests`). Aucune requête
/// réseau (`DemoInscriptionGateway`).
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - la saisie refusée affiche les quatre messages du web sous leurs champs, sans appel ;
/// - la création annonce le lien de confirmation (texte verbatim l.322-324) et le bouton devient
///   « J’ai confirmé mon email » ; la connexion qui suit ouvre l'aiguillage, jamais l'espace soignant sans profil ;
/// - un compte existant (`-JOLENE_DEMO_INSCRIPTION_REFUS USER_ALREADY_REGISTERED`) propose « Se connecter et
///   continuer » ; un refus captcha (`CAPTCHA_FAILED`) affiche le message générique du web et le renvoi vers
///   l'inscription web (D25), présenté par le présentateur `.safari` du coordinateur des liens (L3-T3b) ;
/// - « Se connecter » ramène à l'écran de connexion avec l'adresse saisie.
/// Les liens `/inscription/confirmer` et `/inscription/soignant` (`-JOLENE_OPEN_URL`, coordinateur des liens de
/// L3-T3b) sont prouvés par `DemoLiensLot3Tests` (intégration du lot 3), et au niveau 1 (`ConfirmationInscriptionModel`,
/// `DemoInscriptionGateway`, `SupabaseInscriptionGateway`, `DeepLinkIntentTests`).
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) ; chaque contrôle est
/// amené à l'écran par un défilement borné (`scrollTo`) avant d'être exigé atteignable (PRINCIPES §6).
final class DemoInscriptionTests: JoleneUITestCase {
    /// Textes verbatim (`InscriptionRapide.tsx`, `ConfirmationInscription.tsx`, `src/lib/erreurs.ts`).
    static let confirmationEnvoyee = "Un lien de confirmation vient de vous être envoyé. Ouvrez-le pour accéder à votre espace. Vous pouvez aussi revenir ici après confirmation."
    static let consentement = "J’accepte les CGU et la politique de confidentialité."
    static let compteExistant = "Ce compte existe déjà. Connectez-vous pour le reprendre."
    static let erreurInattendue = "Une erreur inattendue est survenue. Réessayez ou contactez le support."
    static let professionIDE = "Infirmier(ère) Diplômé(e) d'État (IDE)"
    static let nouvelEmail = "nouveau-soignant@example.invalid"
    /// Mot de passe fictif, accepté uniquement par le monde démo.
    static let nouveauMotDePasse = "demonstration-8"
    static let argumentRefus = "-JOLENE_DEMO_INSCRIPTION_REFUS"

    func testSaisieRefuseeAfficheLesMessagesDuWebSansAppel() throws {
        launchDemo()
        let scroll = ouvrirInscription()
        XCTAssertEqual(element("inscription-cgu-texte").label, Self.consentement, "consentement verbatim (l.264-284)")
        let submit = element("inscription-submit")
        scrollTo(submit, in: scroll)
        XCTAssertEqual(submit.label, "Créer mon compte")
        tap("inscription-submit")
        let attendus = [
            ("inscription-email-erreur", "Saisissez une adresse email valide."),
            ("inscription-password-erreur", "Choisissez un mot de passe de 8 caractères minimum."),
            ("inscription-profession-erreur", "Choisissez votre profession."),
            ("inscription-cgu-erreur", "Acceptez les conditions pour créer votre compte."),
        ]
        for (identifiant, texte) in attendus {
            let erreur = element(identifiant)
            require("Le message « \(texte) » est affiché") { erreur.exists }
            XCTAssertEqual(erreur.label, texte)
        }
        XCTAssertFalse(element("inscription-confirmation-envoyee").exists, "aucune création sans saisie valide")
        record("\(proofPrefix)-inscription-erreurs")
    }

    func testCreationPuisConfirmationOuvreLAiguillageEtLaCompletion() throws {
        launchDemo()
        let scroll = ouvrirInscription()
        remplir(scroll, email: Self.nouvelEmail)
        envoyer(scroll)
        let confirmation = element("inscription-confirmation-envoyee")
        require("Le lien de confirmation est annoncé", timeout: 30) { confirmation.exists }
        XCTAssertTrue(confirmation.label.hasSuffix(Self.confirmationEnvoyee), "texte verbatim : \(confirmation.label)")
        for champ in ["email", "password", "profession", "cgu"] {
            XCTAssertFalse(element("inscription-\(champ)-erreur").exists, "saisie acceptée : aucun message sous \(champ)")
        }
        let submit = element("inscription-submit")
        scrollTo(submit, in: scroll)
        require("Le bouton propose la connexion après confirmation") { submit.label == "J’ai confirmé mon email" }
        XCTAssertFalse(tabBarExists, "aucun espace avant la confirmation")
        record("\(proofPrefix)-inscription-confirmation")

        tap("inscription-submit")
        // T8 (règle 8) : l'écran bloquant provisoire `onboarding-completion` est remplacé par la complétion du profil.
        let completion = element("completion-screen")
        require("L'aiguillage ouvre la complétion du profil (parcours soignant démarré)", timeout: 30) {
            self.containerVisible(completion)
        }
        let profession = element("completion-profession")
        scrollTo(profession, in: completion)
        XCTAssertTrue(profession.label.contains(Self.professionIDE), "profession du formulaire, figée : \(profession.label)")
        XCTAssertFalse(tabBarExists, "jamais l'espace soignant sans profil (D9)")
        XCTAssertFalse(element("access-blocked").exists, "l'écran bloquant du lot 0 n'est plus affiché pour l'inscription")
        record("\(proofPrefix)-inscription-onboarding")

        let deconnexion = element("logout-button")
        scrollTo(deconnexion, in: completion)
        tap("logout-button")
        require("La déconnexion ramène à la connexion", timeout: 15) { self.visible(self.element("login-scroll")) }
    }

    func testCompteExistantProposeDeSeConnecterEtContinuer() throws {
        launchDemo(extraArguments: [Self.argumentRefus, "USER_ALREADY_REGISTERED"])
        let scroll = ouvrirInscription()
        remplir(scroll, email: Self.nouvelEmail)
        envoyer(scroll)
        let erreur = element("inscription-erreur")
        require("Le compte existant est signalé", timeout: 30) { erreur.exists }
        XCTAssertTrue(erreur.label.hasSuffix(Self.compteExistant), "texte verbatim : \(erreur.label)")
        let submit = element("inscription-submit")
        scrollTo(submit, in: scroll)
        require("Le bouton propose la connexion") { submit.label == "Se connecter et continuer" }
        record("\(proofPrefix)-inscription-compte-existant")
        tap("inscription-submit")
        require("La connexion ouvre l'espace du compte existant", timeout: 30) { self.tabBarExists }
    }

    /// Intégration du lot 3 (règle 8) : le présentateur `.safari` est injecté depuis L3-T3b, le renvoi vers l'inscription
    /// web (D25) existe donc et ouvre sa page (double démo `renvoi-web-demo`, aucune requête réseau). Avant T3b, le
    /// test exigeait son absence (jamais un bouton sans effet).
    func testRefusCaptchaAfficheLeMessageGeneriqueEtLeRenvoiWeb() throws {
        launchDemo(extraArguments: [Self.argumentRefus, "CAPTCHA_FAILED"])
        let scroll = ouvrirInscription()
        remplir(scroll, email: Self.nouvelEmail)
        envoyer(scroll)
        let erreur = element("inscription-erreur")
        require("Le refus est affiché", timeout: 30) { erreur.exists }
        XCTAssertTrue(erreur.label.hasSuffix(Self.erreurInattendue), "message générique du web : \(erreur.label)")
        XCTAssertFalse(element("inscription-confirmation-envoyee").exists)
        XCTAssertEqual(element("inscription-submit").label, "Créer mon compte", "rien n'est supposé créé")
        let renvoi = element("inscription-renvoi-web")
        scrollTo(renvoi, in: scroll)
        XCTAssertEqual(renvoi.label, "Créer un compte soignant", "libellé verbatim (PageConnexion.tsx l.334)")
        record("\(proofPrefix)-inscription-captcha")
        tap("inscription-renvoi-web")
        liensRenvoiWebAffiche("https://jolene.app/inscription/soignant")
        liensFermerRenvoiWeb()
        require("Le formulaire reste affiché, refus compris") { self.containerVisible(scroll) && erreur.exists }
    }

    func testSeConnecterRameneALaConnexionAvecLAdresseSaisie() throws {
        launchDemo()
        let scroll = ouvrirInscription()
        let email = element("inscription-email")
        focus(email, in: scroll)
        email.typeText(Self.nouvelEmail)
        email.typeText("\n")
        let retour = element("inscription-se-connecter")
        scrollTo(retour, in: scroll)
        tap("inscription-se-connecter")
        let login = element("login-scroll")
        require("L'écran de connexion est de retour") { self.visible(login) }
        require("L'adresse saisie est reprise") { (self.element("login-email").value as? String) == Self.nouvelEmail }
        XCTAssertFalse(element("inscription-scroll").exists)
    }

    // MARK: - Étapes

    /// Connexion → « Créer un compte soignant » ; rend le conteneur défilant du formulaire.
    @discardableResult
    private func ouvrirInscription() -> XCUIElement {
        let login = element("login-scroll")
        require("L'écran de connexion est affiché") { self.visible(login) }
        let creer = element("login-create-account")
        scrollTo(creer, in: login)
        XCTAssertEqual(creer.label, "Créer un compte soignant", "libellé verbatim (PageConnexion.tsx l.334)")
        tap("login-create-account")
        let scroll = element("inscription-scroll")
        require("Le formulaire de création de compte est affiché") { self.containerVisible(scroll) }
        return scroll
    }

    /// Adresse, mot de passe, profession (menu), consentement.
    private func remplir(_ scroll: XCUIElement, email adresse: String) {
        let email = element("inscription-email")
        focus(email, in: scroll)
        email.typeText(adresse)
        let password = element("inscription-password")
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.nouveauMotDePasse)
        password.typeText("\n")
        require("Le clavier est fermé après le mot de passe") { !self.app.keyboards.firstMatch.exists }

        let profession = element("inscription-profession")
        scrollTo(profession, in: scroll)
        tap("inscription-profession")
        let option = app.buttons[Self.professionIDE].firstMatch
        require("La liste des professions est ouverte") { self.visible(option) }
        // Le choix est prouvé par l'envoi : aucune erreur de profession, lien de confirmation annoncé.
        option.tap()

        let cgu = element("inscription-cgu")
        scrollTo(cgu, in: scroll)
        XCTAssertEqual(cgu.label, Self.consentement, "case à cocher vocalisée avec la phrase verbatim")
        tap("inscription-cgu")
        require("Le consentement est coché") { cgu.isSelected }
    }

    private func envoyer(_ scroll: XCUIElement) {
        let submit = element("inscription-submit")
        scrollTo(submit, in: scroll)
        tap("inscription-submit")
    }
}
