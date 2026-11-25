import XCTest

/// Contrats et signature OTP de l'espace établissement en démo (lot 5, T10 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T10)
/// sur iPhone, iPad portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) : contrats dérivés des missions
/// démo M4 (signé) et M5 (à signer) de `demo-etab-contrats.json`, OTP démo (`000000`), aucune requête réseau. Vérifié par
/// la CI seulement (aucun simulateur en local), dans l'éclat « lot5-etablissement » de `ios-swift-ci.yml`.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - l'entrée « Contrats » de la barre de Missions ouvre la liste de l'établissement (`etab-contrats-screen`) ; la carte
///   du contrat à signer appelle « Signer le contrat » ; le contrat s'ouvre dans l'écran du lot 2 sous le contexte de
///   l'établissement (`contrat-detail`, jamais `contrat-screen`), avec le mode de signature du web verbatim ;
/// - consentement, envoi du code (numéro masqué seulement), code accepté, puis « Signé » relu (section Signatures de
///   l'établissement relue, horloge démo) ;
/// - un CDD à préparer est renvoyé au web (`contrat-preparer-web`), sans aucune signature native ;
/// - POINTAGE_ONLY : aucune entrée « Contrats » (permission `contrats` non servie).
/// Règles (requêtes, permission, triple contrôle, refus verbatim, relecture) prouvées au niveau 1
/// (`ContratModelEtablissementTests`, `DemoEtabContratsGatewayTests`, `SupabaseEtabContratsGatewayTests`).
final class DemoEtabContratsTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]
    private let aSigner = "demo-etab-contrat-m05"

    /// `TextesWeb.Contrat.otpLibelle` / `otpDescription` (`ContratMission.tsx` l.742, l.745), verbatim.
    static let modeOtpLibelle = "📱 Signature électronique OTP SMS"
    static let modeOtpDescription = "Code SMS à 6 chiffres + horodatage + hash document. Conforme art. 1366-1367 Code civil."

    func testContratDemoOtpPuisSigneRelu() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirContrats()
        let carte = element("etab-contrat-\(aSigner)")
        require("La carte du contrat à signer est rendue") { carte.exists }
        XCTAssertTrue(carte.label.contains("Signer le contrat"), carte.label)
        XCTAssertTrue(element("etab-contrat-demo-etab-contrat-m04").exists, "contrat signé de M4 listé")
        record("\(proofPrefix)-etab-contrats-liste")

        scrollTo(carte, in: element("etab-contrats-screen"))
        carte.tap()
        let ecran = element("contrat-detail")
        require("Le contrat s'ouvre dans l'écran du lot 2, contexte établissement", timeout: 30) { self.containerVisible(ecran) }
        XCTAssertFalse(element("contrat-screen").exists, "jamais l'écran du contrat soignant")

        let envoyer = element("contrat-otp-envoyer")
        require("La zone de signature OTP est rendue", timeout: 30) { envoyer.exists }
        scrollTo(envoyer, in: ecran)
        XCTAssertEqual(element("contrat-mode-otp-libelle").label, Self.modeOtpLibelle, "texte du web verbatim")
        XCTAssertEqual(element("contrat-mode-otp-description").label, Self.modeOtpDescription, "mention art. 1366-1367 verbatim")
        XCTAssertFalse(envoyer.isEnabled, "aucun envoi sans consentement")
        XCTAssertFalse(element("contract-otp").exists, "aucun champ de code avant l'envoi")
        record("\(proofPrefix)-etab-contrat-avant-envoi")

        tap("contrat-consentement")
        require("La case est cochée et l'envoi activé") { envoyer.isEnabled }
        tap("contrat-otp-envoyer")
        let destinataire = element("contrat-otp-destinataire")
        require("L'envoi du code est annoncé") { destinataire.exists }
        XCTAssertEqual(destinataire.label, "Code envoyé au +**********00", "numéro masqué seulement")
        record("\(proofPrefix)-etab-contrat-code-envoye")

        let champ = element("contract-otp")
        require("Le champ du code est rendu") { champ.exists }
        if !visible(champ) && !app.keyboards.firstMatch.exists { scrollTo(champ, in: ecran) }
        focus(champ, in: ecran)
        champ.typeText("000000")
        require("Le code saisi est affiché") { (champ.value as? String) == "000000" }
        fermerLePaveNumerique()
        let signer = element("contrat-signer")
        scrollTo(signer, in: ecran)
        require("« Signer » est activé") { signer.isEnabled }
        tap("contrat-signer")

        let signe = element("contrat-signe")
        require("La signature relue est confirmée", timeout: 30) { signe.exists }
        XCTAssertFalse(element("contract-otp").exists, "plus de champ de code une fois signé")
        XCTAssertEqual(element("contrat-signatures-etablissement").label, "Établissement : ✅ Signé le 02/11/2026 à 01:00",
                       "signature de l'établissement relue (horloge démo, heure de Paris)")
        XCTAssertFalse(element("contrat-mode-otp").exists, "mode de signature retiré après la signature")
        record("\(proofPrefix)-etab-contrat-signe")
    }

    func testCddAPreparerRenvoyeAuWeb() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_SCENARIO", "cdd-a-preparer"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirContrats()
        let carte = element("etab-contrat-\(aSigner)")
        require("La carte du contrat à préparer est rendue") { carte.exists }
        carte.tap()
        let ecran = element("contrat-detail")
        require("Le contrat est affiché", timeout: 30) { self.containerVisible(ecran) }
        let preparer = element("contrat-preparer-web")
        require("La préparation par l'employeur est renvoyée au web") { preparer.exists }
        XCTAssertFalse(element("contrat-otp-envoyer").exists, "aucune signature native d'un CDD sans original")
        XCTAssertFalse(element("contrat-zone-signature").exists)
        record("\(proofPrefix)-etab-contrat-cdd-a-preparer")
        scrollTo(preparer, in: ecran)
        tap("contrat-preparer-web")
        let renvoi = element("renvoi-web-demo")
        require("Le renvoi web est présenté") { self.containerVisible(renvoi) }
        XCTAssertEqual(element("renvoi-web-url").label, "https://jolene.app/contrat/\(aSigner)")
        tap("renvoi-web-fermer")
        require("Le renvoi web est fermé, le contrat reste affiché") { !renvoi.exists && self.containerVisible(ecran) }
    }

    func testPointageOnlySansEntreeContrats() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_ROLE_ETAB", "POINTAGE_ONLY"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        tabButton("tab-etab-missions", label: "Missions").tap()
        require("La liste des missions est relue") { self.containerVisible(self.element("etab-missions-screen")) }
        requireAbsence("Aucune entrée « Contrats » sans la permission contrats") { self.element("etab-missions-contrats").exists }
        record("\(proofPrefix)-etab-contrats-pointage-only")
    }

    // MARK: Étapes

    private func ouvrirContrats() {
        tabButton("tab-etab-missions", label: "Missions").tap()
        require("La liste des missions est relue") { self.containerVisible(self.element("etab-missions-screen")) }
        let entree = element("etab-missions-contrats")
        require("L'entrée « Contrats » est rendue") { entree.exists }
        entree.tap()
        require("La liste des contrats de l'établissement est affichée", timeout: 30) {
            self.containerVisible(self.element("etab-contrats-screen"))
        }
    }
}
