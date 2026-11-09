import XCTest

/// Complétion du profil soignant en démo (lot 3, T8) : lien de confirmation (`-JOLENE_OPEN_URL`) → aiguillage
/// d'onboarding → « Vos informations professionnelles » (`InscriptionSoignant.tsx` en mode parcours, textes verbatim)
/// → `register-soignant` simulée → espace soignant. Aucune requête réseau (`DemoInscriptionGateway`) : la sentinelle
/// `network-sentinel` du hub (« 0 requête ») est relue dès que l'espace est ouvert (revue B8 de T8, m7) — elle n'est
/// exposée que par le hub Profil, que les parcours restés hors de l'espace n'atteignent pas.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - un brouillon serveur repris (`JOLENE_DEMO_BROUILLON=complet`) remplit le formulaire ; la profession du parcours est
///   affichée en lecture seule ; les modes viennent du référentiel (IDE : salarié et libéral) ; « Oui » à la question
///   salarié(e) affiche l'avertissement d'exclusivité verbatim ; « Enregistrer mon profil » ouvre l'espace soignant,
///   jamais avant (D9) ;
/// - une saisie incomplète affiche la liste du web sans envoi ;
/// - un refus de `register-soignant` (`UNDERAGE`) affiche le message serveur verbatim, saisie conservée ;
/// - une finalisation en attente (503 `ACCOUNT_FINALIZATION_PENDING`) déconnecte et affiche le message serveur à la
///   connexion ;
/// - « Enregistrer et continuer plus tard » garde la saisie côté serveur : elle est retrouvée après déconnexion et
///   reconnexion du même compte (reprise après rechargement) ;
/// - un référentiel indisponible affiche les deux messages du web, garde le mode salarié et propose « Réessayer la
///   vérification » ;
/// - (revue B8 de T8, B1) un brouillon étudiant commencé sur le web (`JOLENE_DEMO_BROUILLON=etudiant`) ne propose que la
///   complétion web (« 🎓 Je suis étudiant(e) en santé ») : ni formulaire natif ni « Enregistrer mon profil » ; au retour
///   du renvoi web, le rôle est relu et l'écran reste la complétion web tant qu'aucun profil n'existe ;
/// - (revue B8 de T8, M1) un 409 `ACCOUNT_ALREADY_REGISTERED` (profil déjà créé) ouvre l'espace après relecture du rôle,
///   jamais l'impasse « Connectez-vous pour continuer » d'un utilisateur connecté.
/// Règles, refus et relectures sont prouvés au niveau 1 (`CompletionProfilModelTests`, `CompletionProfilRulesTests`,
/// `DemoInscriptionGatewayTests`, `SupabaseInscriptionGatewayTests`).
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) ; chaque contrôle est amené à
/// l'écran par un défilement borné (`scrollTo`) avant d'être exigé atteignable (PRINCIPES §6). Éclat CI
/// « lot3-inscription » (`ios-swift-ci.yml`).
final class DemoCompletionInscriptionTests: JoleneUITestCase {
    static let lienConfirmation = "https://jolene.app/inscription/confirmer?token_hash=demo&type=signup"
    static let variableBrouillon = "JOLENE_DEMO_BROUILLON"
    static let argumentRefus = "-JOLENE_DEMO_INSCRIPTION_REFUS"
    /// Compte démo ouvert par le lien de confirmation (`DemoInscriptionGateway.emailParDefaut`).
    static let emailNouveauCompte = "nouveau-soignant@example.invalid"
    /// Mot de passe fictif, accepté uniquement par le monde démo.
    static let motDePasse = "demonstration-8"

    /// Textes verbatim (`InscriptionSoignant.tsx`, `ChoixModesExercice.tsx`, `register-soignant/index.ts`).
    static let titre = "Vos informations professionnelles"
    static let professionIDE = "Infirmier(ère) Diplômé(e) d'État (IDE)"
    static let manques = "Vérifiez les informations suivantes : prénom, nom, téléphone valide, date de naissance (18 ans minimum), mode d’exercice."
    static let dateObligatoire = "La date de naissance est obligatoire"
    static let exclusivite = "ℹ️ Vous pourrez effectuer des missions sur Jolene en complément de votre activité salariée. Vérifiez que votre contrat de travail n'inclut pas de clause d'exclusivité."
    static let mineur = "Vous devez avoir au moins 18 ans pour vous inscrire."
    static let finalisationEnAttente = "Votre profil est enregistré. Reconnectez-vous pour reprendre votre espace."
    static let referentielIndisponible = "Le référentiel est momentanément indisponible. Vous pouvez poursuivre votre inscription ; le mode libéral pourra être activé après contrôle."
    static let modesIndisponibles = "Vérification temporairement indisponible. Le mode salarié reste accessible. Vos choix sont conservés ; l’ajout du libéral nécessite une vérification."
    static let etudiant = "🎓 Je suis étudiant(e) en santé"
    /// Complétion web du parcours étudiant (D11), URL remise au double démo du renvoi web.
    static let completionWeb = "https://jolene.app/inscription/completer"

    func testBrouillonReprisPuisProfilEnregistreOuvreLEspaceSoignant() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienConfirmation], environment: [Self.variableBrouillon: "complet"])
        let ecran = ouvrirCompletion()
        XCTAssertEqual(element("completion-titre").label, Self.titre)
        XCTAssertEqual(element("completion-prenom").value as? String, "Camille", "brouillon serveur repris")
        XCTAssertEqual(element("completion-nom").value as? String, "Démo")
        let profession = element("completion-profession")
        scrollTo(profession, in: ecran)
        XCTAssertTrue(profession.label.contains(Self.professionIDE), "profession du parcours en lecture seule : \(profession.label)")
        XCTAssertFalse(app.textFields.matching(identifier: "completion-profession").firstMatch.exists, "aucune saisie de profession")
        XCTAssertTrue(element("completion-date-naissance").exists, "date du brouillon affichée dans le sélecteur")
        let rpps = element("completion-rpps")
        scrollTo(rpps, in: ecran)
        XCTAssertTrue(rpps.exists, "IDE : RPPS optionnel proposé")

        let salarie = element("completion-mode-salarie")
        scrollTo(salarie, in: ecran)
        require("Le référentiel propose le libéral pour IDE") { self.element("completion-mode-liberal").exists }
        XCTAssertFalse(element("completion-modes-indisponible").exists)
        basculer(salarie)
        require("Le mode salarié est coché") { (salarie.value as? String) == "1" }

        let oui = element("completion-salarie-oui")
        scrollTo(oui, in: ecran)
        tap("completion-salarie-oui")
        let exclusivite = element("completion-exclusivite")
        require("L'avertissement d'exclusivité est affiché") { exclusivite.exists }
        XCTAssertEqual(exclusivite.label, Self.exclusivite, "texte verbatim (InscriptionSoignant.tsx l.84)")
        XCTAssertFalse(tabBarExists, "jamais l'espace soignant avant le profil complet (D9)")
        record("\(proofPrefix)-completion-formulaire")

        envoyer(ecran)
        require("Le profil enregistré ouvre l'espace soignant", timeout: 30) { self.tabBarExists }
        XCTAssertFalse(element("completion-screen").exists)
        record("\(proofPrefix)-completion-espace")
        sentinelleSansRequete("complétion démo jusqu'à l'espace : aucune requête réseau")
    }

    /// Revue B8 de T8, B1 : brouillon étudiant (« Je suis étudiant(e) » déclaré sur le web, puis « Enregistrer et continuer
    /// plus tard ») — la finalisation native est verrouillée (D11) : seul le renvoi vers la complétion web est proposé,
    /// aucun texte nouveau ; au retour, le rôle est relu et, sans profil créé, la complétion web reste proposée.
    func testBrouillonEtudiantNeProposeQueLaCompletionWebPuisRelitAuRetour() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienConfirmation], environment: [Self.variableBrouillon: "etudiant"])
        let ecran = ouvrirCompletion()
        XCTAssertEqual(element("completion-titre").label, Self.titre)
        let etudiant = element("completion-etudiant-web")
        scrollTo(etudiant, in: ecran)
        require("La complétion web de l'étudiant est proposée") { self.visible(etudiant) && etudiant.isEnabled }
        XCTAssertEqual(etudiant.label, Self.etudiant, "libellé verbatim (DeclarationEtudiant.tsx l.105)")
        XCTAssertFalse(element("completion-enregistrer").exists, "verrou D11 : jamais « Enregistrer mon profil » en natif")
        XCTAssertFalse(element("completion-prenom").exists, "aucun formulaire natif pour un parcours étudiant")
        XCTAssertFalse(element("completion-plus-tard").exists)
        XCTAssertFalse(tabBarExists)
        record("\(proofPrefix)-completion-etudiant")

        tap("completion-etudiant-web")
        let renvoi = element("renvoi-web-demo")
        require("Le renvoi web de la complétion est présenté", timeout: 15) { renvoi.exists }
        XCTAssertEqual(element("renvoi-web-url").label, Self.completionWeb, "page web de la complétion (parcours étudiant)")
        tap("renvoi-web-fermer")
        require("Retour : le rôle est relu, la complétion web reste proposée sans profil", timeout: 30) {
            !self.element("renvoi-web-demo").exists && self.containerVisible(self.element("completion-screen"))
                && self.element("completion-etudiant-web").exists
        }
        XCTAssertFalse(element("completion-enregistrer").exists)
        XCTAssertFalse(element("completion-erreur").exists, "retour sans complétion : aucun message")
        XCTAssertFalse(tabBarExists)
        record("\(proofPrefix)-completion-etudiant-retour")
    }

    /// Revue B8 de T8, M1 : 409 `ACCOUNT_ALREADY_REGISTERED` (profil déjà créé, par exemple après une issue inconnue) :
    /// issue inconnue relue — l'espace s'ouvre, le message « Connectez-vous pour continuer » n'est jamais affiché à un
    /// utilisateur connecté.
    func testCompteDejaFinaliseOuvreLEspaceApresRelectureDuRole() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienConfirmation, Self.argumentRefus, "ACCOUNT_ALREADY_REGISTERED"],
                   environment: [Self.variableBrouillon: "complet"])
        let ecran = ouvrirCompletion()
        cocherSalarie(ecran)
        envoyer(ecran)
        require("Le profil existant ouvre l'espace soignant", timeout: 30) { self.tabBarExists }
        XCTAssertFalse(element("completion-screen").exists)
        XCTAssertFalse(element("completion-erreur").exists, "jamais l'impasse « Connectez-vous pour continuer »")
        record("\(proofPrefix)-completion-compte-deja-finalise")
        sentinelleSansRequete("issue inconnue relue en démo : aucune requête réseau")
    }

    func testSaisieIncompleteAfficheLaListeDuWebSansEnvoi() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienConfirmation])
        let ecran = ouvrirCompletion()
        envoyer(ecran)
        let erreur = element("completion-erreur")
        require("La liste des informations à vérifier est affichée") { erreur.exists }
        XCTAssertTrue(erreur.label.hasSuffix(Self.manques), "texte du web (l.355-356) : \(erreur.label)")
        let date = element("completion-date-naissance-erreur")
        scrollTo(date, in: ecran, downward: false)
        XCTAssertEqual(date.label, Self.dateObligatoire)
        XCTAssertFalse(tabBarExists, "rien n'est envoyé")
        record("\(proofPrefix)-completion-saisie-incomplete")
    }

    func testRefusMineurAfficheLeMessageServeurVerbatim() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienConfirmation, Self.argumentRefus, "UNDERAGE"],
                   environment: [Self.variableBrouillon: "complet"])
        let ecran = ouvrirCompletion()
        cocherSalarie(ecran)
        envoyer(ecran)
        let erreur = element("completion-erreur")
        require("Le refus du serveur est affiché", timeout: 30) { erreur.exists }
        XCTAssertTrue(erreur.label.hasSuffix(Self.mineur), "message serveur verbatim : \(erreur.label)")
        XCTAssertFalse(tabBarExists, "aucun espace ouvert sur un refus")
        let prenom = element("completion-prenom")
        scrollTo(prenom, in: ecran, downward: false)
        XCTAssertEqual(prenom.value as? String, "Camille", "saisie conservée")
        record("\(proofPrefix)-completion-refus-mineur")
    }

    func testFinalisationEnAttenteDeconnecteEtAfficheLeMessageALaConnexion() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienConfirmation, Self.argumentRefus, "ACCOUNT_FINALIZATION_PENDING"],
                   environment: [Self.variableBrouillon: "complet"])
        let ecran = ouvrirCompletion()
        cocherSalarie(ecran)
        envoyer(ecran)
        let login = element("login-scroll")
        require("La déconnexion locale ramène à la connexion", timeout: 30) { self.visible(login) }
        let message = element("login-error")
        require("Le message du serveur est affiché à la connexion") { message.exists }
        XCTAssertEqual(message.label, Self.finalisationEnAttente, "message serveur verbatim (register-soignant l.367)")
        XCTAssertFalse(tabBarExists)
        record("\(proofPrefix)-completion-finalisation-en-attente")
    }

    func testEnregistrerPlusTardPuisReconnexionRetrouveLaSaisie() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienConfirmation])
        let ecran = ouvrirCompletion()
        let prenom = element("completion-prenom")
        focus(prenom, in: ecran)
        prenom.typeText("Lou")
        prenom.typeText("\n")
        let plusTard = element("completion-plus-tard")
        scrollTo(plusTard, in: ecran)
        tap("completion-plus-tard")
        require("Le parcours relu garde le prénom saisi", timeout: 30) {
            self.containerVisible(self.element("completion-screen")) && (self.element("completion-prenom").value as? String) == "Lou"
        }
        let deconnexion = element("logout-button")
        scrollTo(deconnexion, in: element("completion-screen"))
        tap("logout-button")
        connexion(email: Self.emailNouveauCompte)
        let reprise = element("completion-screen")
        require("La reconnexion ramène à la complétion", timeout: 30) { self.containerVisible(reprise) }
        XCTAssertEqual(element("completion-prenom").value as? String, "Lou", "brouillon serveur retrouvé après reconnexion")
        XCTAssertFalse(tabBarExists)
        record("\(proofPrefix)-completion-reprise")
    }

    func testReferentielIndisponibleGardeLeSalarieEtProposeDeReessayer() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Self.lienConfirmation, Self.argumentRefus, "TYPES_EXERCICE_INDISPONIBLE"])
        let ecran = ouvrirCompletion()
        let indisponible = element("completion-modes-indisponible")
        scrollTo(indisponible, in: ecran)
        require("L'indisponibilité du référentiel est signalée") { indisponible.exists }
        XCTAssertEqual(indisponible.label, Self.modesIndisponibles, "texte verbatim (ChoixModesExercice.tsx l.43)")
        XCTAssertTrue(element("completion-mode-salarie").exists, "le mode salarié reste accessible")
        XCTAssertFalse(element("completion-mode-liberal").exists, "le libéral ne s'ajoute jamais sans vérification")
        let reessayer = element("completion-modes-reessayer")
        scrollTo(reessayer, in: ecran)
        require("« Réessayer la vérification » est atteignable") { self.visible(reessayer) && reessayer.isEnabled }
        let referentiel = element("completion-referentiel-indisponible")
        scrollTo(referentiel, in: ecran)
        XCTAssertEqual(referentiel.label, Self.referentielIndisponible, "texte verbatim (InscriptionSoignant.tsx l.94)")
        record("\(proofPrefix)-completion-referentiel-indisponible")
    }

    // MARK: - Étapes

    /// Lien de confirmation reçu au lancement → aiguillage → complétion ; rend le conteneur défilant.
    @discardableResult
    private func ouvrirCompletion() -> XCUIElement {
        let ecran = element("completion-screen")
        require("Le lien confirmé ouvre la complétion du profil", timeout: 30) { self.containerVisible(ecran) }
        XCTAssertFalse(tabBarExists, "jamais l'espace soignant sans profil (D9)")
        return ecran
    }

    private func basculer(_ interrupteur: XCUIElement) {
        require("L'interrupteur \(interrupteur.identifier) est activable") { interrupteur.isEnabled }
        // Le commutateur est à droite de la ligne (`ToggleRow`).
        interrupteur.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func cocherSalarie(_ ecran: XCUIElement) {
        let salarie = element("completion-mode-salarie")
        scrollTo(salarie, in: ecran)
        basculer(salarie)
        require("Le mode salarié est coché") { (salarie.value as? String) == "1" }
    }

    private func envoyer(_ ecran: XCUIElement) {
        let bouton = element("completion-enregistrer")
        scrollTo(bouton, in: ecran)
        tap("completion-enregistrer")
    }

    /// Hub Profil ouvert, sentinelle relue (« 0 requête », revue B8 de T8, m7).
    private func sentinelleSansRequete(_ message: String) {
        tabButton("tab-profil", label: "Profil").tap()
        let hub = element("profile-list")
        require("Le hub Profil est affiché") { self.containerVisible(hub) }
        let sentinel = element("network-sentinel")
        scrollTo(sentinel, in: hub, downward: false)
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", message)
    }

    private func connexion(email adresse: String) {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché", timeout: 15) { self.containerVisible(scroll) }
        let email = element("login-email")
        focus(email, in: scroll)
        email.typeText(adresse)
        let password = element("login-password")
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.motDePasse)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) { scrollTo(submit, in: scroll) }
        submit.tap()
    }
}
