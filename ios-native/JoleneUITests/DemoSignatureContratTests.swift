import XCTest

/// Signature OTP d'un contrat en démonstration (lot 2, T9b ; `LOT2_PLAN.md` §3 T9b, décisions 18 et 20) : Profil ›
/// Mes contrats › `demo-contrat-001` (en attente de signatures, original contrôlé) → zone « Votre signature » native
/// (`SignatureOtpView`, session OTP de T8) : case de consentement, « Recevoir le code SMS pour signer », code envoyé au
/// numéro masqué démo, minuteur de 10 min (horloge démo fixée), code faux `111111` refusé avec les tentatives
/// restantes, code `000000` accepté puis relu (contrat, section Signatures et certificat), « déjà signé ». Textes
/// verbatim du web (`SignerContratOtp.tsx`, `TextesWeb.SignatureOtp`, `LibellesWeb.SignatureOtp`). Scénarios DEBUG
/// `-JOLENE_DEMO_SCENARIO otp-expire` (tout code refusé `OTP_EXPIRE`) et `compte-test` (compte TEST sans admission de
/// recette : renvoi web ; depuis la fusion du lot 3, le présentateur `.safari` du coordinateur des liens est injecté et
/// « ✍️ Signer le contrat » présente la page web du contrat). Aucune requête réseau (sentinelle), aucun SMS : la
/// signature est simulée par le monde démo.
///
/// Identifiants : `contrat-zone-signature`, `contrat-signature-otp`, `contrat-consentement`, `contrat-otp-envoyer`,
/// `contrat-otp-envoye`, `contrat-otp-destinataire`, `contrat-otp-sms-restants`, `contrat-otp-minuteur`,
/// `contract-otp`, `contrat-otp-tentatives`, `contrat-otp-erreur`, `contrat-otp-renvoyer`, `contrat-signer`,
/// `contrat-signe`, `contrat-renvoi-web` (+ `-message`, `-action`).
final class DemoSignatureContratTests: JoleneUITestCase {
    /// `TextesWeb.SignatureOtp.consentement` (`SignerContratOtp.tsx` l.276).
    static let consentement = "J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes."
    /// `TextesWeb.SignatureOtp.recevoirCode` (l.288).
    static let recevoirCode = "Recevoir le code SMS pour signer"
    /// `LibellesWeb.SignatureOtp.codeEnvoye` (l.151) avec le numéro masqué démo (`DemoContratsGateway.telephoneMasque`).
    static let codeEnvoye = "Code envoyé au +**********00. Valide 10 min."
    /// `TextesWeb.SignatureOtp.tentativesRestantes(n: 4)` (l.326).
    static let quatreTentatives = "Code incorrect. 4 tentatives restantes."
    /// `TextesWeb.SignatureOtp.otpIncorrect` (`MESSAGES_ERREUR`, l.40).
    static let codeIncorrect = "Code incorrect. Vérifiez votre SMS et réessayez."
    /// `TextesWeb.SignatureOtp.otpExpire` (`MESSAGES_ERREUR`, l.39).
    static let codeExpire = "Le code SMS a expiré (10 min). Demandez un nouveau code."
    /// `TextesWeb.SignatureOtp.contratSigne` (l.214) et `signeAvecSucces` (l.216).
    static let contratSigne = "Contrat signé ✅"
    static let signeAvecSucces = "Signé avec succès. Horodatage, IP et hash du document conservés (art. 1366-1367 Code civil)."
    /// `LibellesWeb.SignatureOtp.champCodeIndication` (`placeholder`, l.316).
    static let indicationCode = "123456"
    /// `MobileAccess.unsupportedRole` (lot 0), repris pour le renvoi web d'un compte TEST.
    static let espaceNonDisponible = "Cet espace n'est pas encore disponible dans l'application. Rendez-vous sur jolene.app."

    func testSignatureOtpCodeFauxPuisCodeAccepteRelu() throws {
        launchDemo()
        signInDemo()
        openContrat("demo-contrat-001")
        let ecran = element("contrat-screen")

        // Avant tout envoi : case décochée, bouton désactivé, aucun champ de code.
        let envoyer = element("contrat-otp-envoyer")
        require("La zone de signature OTP est rendue") { envoyer.exists }
        scrollTo(envoyer, in: ecran)
        XCTAssertTrue(element("contrat-signature-otp").exists)
        XCTAssertEqual(envoyer.label, Self.recevoirCode, "libellé exact du web (l.288)")
        XCTAssertFalse(envoyer.isEnabled, "désactivé tant que la case n'est pas cochée (l.284)")
        let consentement = element("contrat-consentement")
        XCTAssertEqual(consentement.label, Self.consentement)
        XCTAssertFalse(consentement.isSelected)
        XCTAssertFalse(element("contract-otp").exists, "aucun champ de code avant l'envoi")
        XCTAssertFalse(element("contrat-renvoi-web").exists, "compte réel : signature native, aucun renvoi web")
        record("\(proofPrefix)-signature-avant-consentement")

        tap("contrat-consentement")
        require("La case est cochée et l'envoi activé") { consentement.isSelected && envoyer.isEnabled }
        tap("contrat-otp-envoyer")

        // Code envoyé : annonce, numéro masqué, un seul envoi décompté, minuteur de 10 min.
        let annonce = element("contrat-otp-envoye")
        require("L'envoi du code est annoncé") { annonce.exists }
        XCTAssertTrue(annonce.label.hasSuffix(Self.codeEnvoye), "format du web (l.151) : \(annonce.label)")
        XCTAssertEqual(element("contrat-otp-destinataire").label, "Code envoyé au +**********00")
        XCTAssertEqual(element("contrat-otp-sms-restants").label, "(2 envois restants)", "une seule requête d'envoi")
        XCTAssertEqual(element("contrat-otp-minuteur").label, "10:00", "minuteur dérivé de l'échéance, horloge démo fixée")
        XCTAssertFalse(element("contrat-otp-envoyer").exists, "« Recevoir le code » remplacé par le champ (l.280-292)")
        XCTAssertEqual(element("contrat-otp-renvoyer").label, "Renvoyer le code")
        let signer = element("contrat-signer")
        XCTAssertEqual(signer.label, "Signer")
        XCTAssertFalse(signer.isEnabled, "code incomplet : « Signer » désactivé (l.344)")
        XCTAssertEqual(element("contract-otp").placeholderValue, Self.indicationCode, "texte indicatif du web (l.316)")
        record("\(proofPrefix)-signature-code-envoye")

        // Code faux : refus du serveur démo et tentatives restantes.
        let champ = element("contract-otp")
        saisirCode("111111", dans: champ, ecran: ecran)
        scrollTo(signer, in: ecran)
        require("« Signer » est activé avec six chiffres") { signer.isEnabled }
        tap("contrat-signer")
        let tentatives = element("contrat-otp-tentatives")
        require("Le code faux est refusé avec les tentatives restantes") { tentatives.exists }
        XCTAssertEqual(tentatives.label, Self.quatreTentatives, "l.326")
        XCTAssertTrue(element("contrat-otp-erreur").label.hasSuffix(Self.codeIncorrect), "MESSAGES_ERREUR l.40")
        XCTAssertFalse(element("contrat-signe").exists)
        record("\(proofPrefix)-signature-code-faux")

        // Code accepté : confirmation affichée seulement après la relecture du contrat et du certificat.
        effacerCode(champ, ecran: ecran)
        saisirCode("000000", dans: champ, ecran: ecran)
        scrollTo(signer, in: ecran)
        require("« Signer » est activé") { signer.isEnabled }
        tap("contrat-signer")
        let signe = element("contrat-signe")
        require("La signature relue est confirmée") { signe.exists }
        XCTAssertTrue(signe.label.contains(Self.contratSigne), "l.214 : \(signe.label)")
        XCTAssertTrue(signe.label.contains(Self.signeAvecSucces), "l.216")
        XCTAssertFalse(element("contract-otp").exists, "plus de champ de code une fois signé")
        XCTAssertFalse(element("contrat-signer").exists)
        XCTAssertEqual(element("contrat-signatures-soignant").label, "Soignant(e) : ✅ Signé le 02/11/2026 à 01:00",
                       "section Signatures relue (horloge démo, heure de Paris)")
        XCTAssertEqual(element("contrat-signatures-etablissement").label, "Établissement : ⏳ En attente")
        let ligneCertificat = element("contrat-certificat-demo-signature-demo-contrat-001-soignant")
        require("Le certificat relu porte la signature") { ligneCertificat.exists }
        let dejaSigne = element("contrat-deja-signe")
        scrollTo(dejaSigne, in: ecran)
        XCTAssertEqual(dejaSigne.label, "✅ Vous avez déjà signé ce contrat", "état relu du serveur (l.819-823)")
        record("\(proofPrefix)-signature-relue")

        goBack()
        require("La liste des contrats est de retour") { self.containerVisible(self.element("contrats-liste")) }
        goBack()
        assertNoNetworkRequest()
    }

    func testCodeExpireProposeUnNouveauCode() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SCENARIO", "otp-expire"])
        signInDemo()
        openContrat("demo-contrat-001")
        let ecran = element("contrat-screen")
        let consentement = element("contrat-consentement")
        require("La case de consentement est rendue") { consentement.exists }
        scrollTo(consentement, in: ecran)
        tap("contrat-consentement")
        // Le bouton d'envoi est sous la case : sur iPhone, il peut rester sous le bord de l'écran et la barre d'onglets
        // une fois la case amenée à l'écran (run 42568134868, iPhone : bouton à y = 839,7 pour un écran de 874 pt).
        // Il est amené à l'écran avant le toucher, comme dans `testSignatureOtpCodeFauxPuisCodeAccepteRelu`.
        scrollTo(element("contrat-otp-envoyer"), in: ecran)
        tap("contrat-otp-envoyer")
        require("Le code est envoyé") { self.element("contrat-otp-envoye").exists }
        saisirCode("000000", dans: element("contract-otp"), ecran: ecran)
        let signer = element("contrat-signer")
        scrollTo(signer, in: ecran)
        tap("contrat-signer")

        let erreur = element("contrat-otp-erreur")
        require("Le refus du serveur est affiché") { erreur.exists }
        XCTAssertTrue(erreur.label.hasSuffix(Self.codeExpire), "MESSAGES_ERREUR l.39 : \(erreur.label)")
        XCTAssertEqual(element("contrat-otp-minuteur").label, "Expiré", "l.305")
        let renvoyer = element("contrat-otp-renvoyer")
        XCTAssertEqual(renvoyer.label, "Recevoir un nouveau code", "l.339")
        XCTAssertTrue(renvoyer.isEnabled)
        XCTAssertFalse(signer.isEnabled, "code expiré : « Signer » désactivé (l.344)")
        XCTAssertFalse(element("contract-otp").isEnabled, "champ désactivé une fois expiré (l.317)")
        XCTAssertFalse(element("contrat-signe").exists)
        record("\(proofPrefix)-signature-code-expire")

        scrollTo(renvoyer, in: ecran)
        tap("contrat-otp-renvoyer")
        require("Un nouveau code est envoyé") { self.element("contrat-otp-sms-restants").label == "(1 envoi restant)" }
        XCTAssertEqual(element("contrat-otp-minuteur").label, "10:00")
        XCTAssertEqual(element("contrat-otp-renvoyer").label, "Renvoyer le code")
        XCTAssertTrue(element("contract-otp").isEnabled)
        record("\(proofPrefix)-signature-nouveau-code")

        // Revue fraîche de T9b (m9) : le scénario `otp-expire` est lui aussi prouvé sans réseau.
        goBack()
        require("La liste des contrats est de retour") { self.containerVisible(self.element("contrats-liste")) }
        goBack()
        assertNoNetworkRequest()
    }

    func testCompteTestSansAdmissionRenvoieVersLeWeb() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SCENARIO", "compte-test"])
        signInDemo()
        openContrat("demo-contrat-001")
        let ecran = element("contrat-screen")
        let message = element("contrat-renvoi-web-message")
        require("La zone de signature renvoie vers le web") { message.exists }
        scrollTo(message, in: ecran)
        XCTAssertTrue(element("contrat-renvoi-web").exists)
        XCTAssertTrue(message.label.hasSuffix(Self.espaceNonDisponible), "texte du lot 0 : \(message.label)")
        XCTAssertFalse(element("contrat-signature-otp").exists, "décision 18 : jamais d'OTP pour un compte TEST sans admission")
        XCTAssertFalse(element("contrat-consentement").exists)
        XCTAssertFalse(element("contrat-otp-envoyer").exists)
        XCTAssertFalse(element("contract-otp").exists)
        record("\(proofPrefix)-signature-compte-test")
        // Migré à la fusion des lots 2 et 3 (règle 8) : le présentateur `.safari` du coordinateur des liens (L3-T3b, qui
        // remplace L1-T10) est injecté ; « ✍️ Signer le contrat » est rendu et présente la page web du contrat
        // (`ContratPresentation.renvoiSignature`, double démo, aucune requête réseau), puis « Fermer » rend le contrat.
        // Avant la fusion, ce test exigeait son absence (jamais un bouton sans effet).
        let action = element("contrat-renvoi-web-action")
        require("Le renvoi web de la signature propose son bouton") { action.exists }
        scrollTo(action, in: ecran)
        XCTAssertEqual(action.label, "✍️ Signer le contrat", "libellé du web")
        tap("contrat-renvoi-web-action")
        liensRenvoiWebAffiche("https://jolene.app/contrat/demo-contrat-001")
        record("\(proofPrefix)-signature-compte-test-web")
        liensFermerRenvoiWeb()
        require("Le contrat est de retour, toujours sans OTP") {
            self.containerVisible(ecran) && self.element("contrat-renvoi-web").exists && !self.element("contrat-signature-otp").exists
        }

        goBack()
        require("La liste des contrats est de retour") { self.containerVisible(self.element("contrats-liste")) }
        goBack()
        assertNoNetworkRequest()
    }

    // MARK: Étapes

    /// Saisit le code dans le champ OTP UIKit (`OTPField`, `contract-otp`) après lui avoir donné le focus.
    private func saisirCode(_ code: String, dans champ: XCUIElement, ecran: XCUIElement) {
        require("Le champ du code est rendu") { champ.exists }
        // Le champ remplace le bouton d'envoi : il peut se trouver sous le bord de l'écran, que `focus` ne fait pas défiler.
        if !visible(champ) && !app.keyboards.firstMatch.exists { scrollTo(champ, in: ecran) }
        focus(champ, in: ecran)
        champ.typeText(code)
        require("Le code saisi est affiché") { (champ.value as? String) == code }
    }

    /// Efface le code saisi : curseur placé en fin de texte (le texte est centré, la touche à droite du champ place le
    /// curseur après le dernier chiffre), puis six effacements ; le champ ne garde aucun chiffre.
    private func effacerCode(_ champ: XCUIElement, ecran: XCUIElement) {
        focus(champ, in: ecran)
        champ.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        require("Le champ garde le focus clavier") { self.hasKeyboardFocus(champ) }
        champ.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        // Champ vide : XCUITest rend alors le texte indicatif (« 123456 », l.316) comme valeur.
        require("Le champ du code est vide") {
            let valeur = (champ.value as? String) ?? ""
            return valeur.isEmpty || valeur == champ.placeholderValue
        }
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

    /// Profil › Mon espace › Mes contrats (même chemin que `DemoContratsTests`), puis la carte du contrat.
    private func openContrat(_ id: String) {
        tabButton("tab-profil", label: "Profil").tap()
        require("La liste du profil est affichée") { self.containerVisible(self.element("profile-list")) }
        let entree = element("profil-contrats")
        if !visible(entree) { scrollTo(entree, in: element("profile-list")) }
        tap("profil-contrats")
        let liste = element("contrats-liste")
        require("La liste des contrats est affichée") { self.containerVisible(liste) }
        let carte = element("contrat-carte-\(id)")
        require("La carte \(id) est chargée") { carte.exists }
        if !visible(carte) { scrollTo(carte, in: liste) }
        tap("contrat-carte-\(id)")
        require("L'écran du contrat \(id) est affiché") { self.containerVisible(self.element("contrat-screen")) }
    }

    /// Bouton retour de la barre de navigation (même requête que `DemoContratsTests`).
    private func goBack() {
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est atteignable") { self.visible(retour) }
        retour.tap()
    }

    /// Sentinelle « 0 requête » du profil (DEBUG), au-dessus de « Mon espace » (même lecture que `DemoContratsTests`).
    private func assertNoNetworkRequest() {
        let list = element("profile-list")
        require("Le profil est de retour") { self.containerVisible(list) }
        let sentinel = element("network-sentinel")
        if !visible(sentinel) { scrollTo(sentinel, in: list, downward: false) }
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Aucune requête réseau en démonstration")
    }
}
