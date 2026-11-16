import XCTest

/// Paiements déclarés en démo (lot 3, T13, B9 ; `DECISIONS_LOT3.md`, TJ7 et section T13) sur iPhone, iPad portrait et
/// iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`). Serveur simulé `DemoPaiementsGateway` (fixture
/// `demo-paiements-declares.json` : deux `DECLARE`, horloge fixée au 02/11/2026), le même que celui relu par l'onglet.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - la section « Paiements à confirmer » (`revenus-paiements-declares`) de l'onglet Revenus : en-tête verbatim du web
///   (vouvoyé : décision 9 du lot 1, TJ8), détail déplié (méthode, date, mission, taux, montant déclaré, pointages) ;
/// - « Confirmer la réception » → « Paiement confirmé ✅ » après relecture, carte retirée parce que le serveur ne la rend
///   plus, état de la mission relu (« Réception confirmée ») ;
/// - contestation sans motif impossible (« Envoyer la contestation » désactivé, motif blanc compris), puis envoyée avec un
///   motif → « Contestation envoyée », état de la mission relu (« Paiement contesté ») ;
/// - refus serveur verbatim (`JOLENE_DEMO_PAIEMENTS=refus`) : « Paiement déjà confirmé » (confirmé ailleurs, carte retirée
///   à la relecture), « Un litige de ce type est déjà ouvert pour cette mission. » (carte gardée), jamais un succès ;
/// - tap push `PAIEMENT_RECU` → onglet Revenus sur `revenus-paiements-declares` (correction 15 ; cas reporté de T5), et
///   sur iPhone l'onglet a défilé jusqu'à la section (en-tête de l'onglet hors du cadre utile, revue B8 n°1, m6).
/// Les règles (une mutation à la fois, double tap, relecture, 23505, délai dépassé, epoch, borne du motif) sont prouvées au
/// niveau 1 (`PaiementsDeclaresModelTests`, `PaiementsDeclaresTests`, `DemoPaiementsGatewayTests`,
/// `SupabasePaiementsGatewayTests`).
final class DemoPaiementsTests: JoleneUITestCase {
    private static let espace = "\u{00A0}"
    private static let premier = "demo-paiement-001"
    private static let second = "demo-paiement-004"

    func testConfirmerRelitCONFIRMEEtLaMissionSuit() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirRevenus()
        let entete = element("paiement-deplier-\(Self.premier)")
        scrollTo(entete, in: ecran)
        XCTAssertEqual(entete.label, "💰 Établissement fictif République déclare vous avoir payé 162,40\(Self.espace)€, "
                       + "Mission : Démonstration · Mission terminée 1, Touchez pour voir le détail · Confirmez ou contestez")
        XCTAssertTrue(element("paiement-declare-\(Self.second)").exists, "deux paiements déclarés")
        XCTAssertFalse(element("paiement-confirmer-\(Self.premier)").exists, "actions dans le détail déplié seulement")
        entete.tap()
        let confirmer = element("paiement-confirmer-\(Self.premier)")
        require("Le détail est déplié") { confirmer.exists }
        XCTAssertEqual(element("paiement-methode-\(Self.premier)").label, "Méthode : 🏦 Virement")
        XCTAssertEqual(element("paiement-date-\(Self.premier)").label, "Date : 1 nov. 2026")
        XCTAssertEqual(element("paiement-taux-\(Self.premier)").label, "Taux retenu : 26,00\(Self.espace)€/h")
        XCTAssertEqual(element("paiement-montant-declare-\(Self.premier)").label, "Montant déclaré : 162,40\(Self.espace)€")
        XCTAssertEqual(element("paiement-pointages-\(Self.premier)").label, "Pointages enregistrés · 2 segments")
        XCTAssertEqual(element("paiement-pointage-1-\(Self.premier)").label, "Pause précédente : 0h30")
        record("\(proofPrefix)-paiements-detail")

        scrollTo(confirmer, in: ecran)
        XCTAssertEqual(confirmer.label, "Confirmer la réception")
        confirmer.tap()
        let issue = element("paiement-confirme")
        require("« Paiement confirmé ✅ » après relecture du statut", timeout: 30) { issue.exists }
        XCTAssertTrue(issue.label.contains("Paiement confirmé ✅"), issue.label)
        require("La carte confirmée n'est plus rendue par le serveur") { !self.element("paiement-declare-\(Self.premier)").exists }
        XCTAssertTrue(element("paiement-declare-\(Self.second)").exists, "l'autre déclaration reste à confirmer")
        XCTAssertFalse(element("paiement-erreur").exists)
        record("\(proofPrefix)-paiements-confirme")
        let etat = element("revenus-mission-etat-demo-terminee-001")
        scrollTo(etat, in: ecran)
        require("L'état de la mission est relu après la confirmation", timeout: 30) { etat.label == "Réception confirmée" }
    }

    func testContestationSansMotifImpossiblePuisEnvoyee() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirRevenus()
        let envoyer = ouvrirContestation(Self.premier, ecran: ecran)
        XCTAssertEqual(envoyer.label, "Envoyer la contestation")
        XCTAssertFalse(envoyer.isEnabled, "sans motif : envoi impossible")
        let motif = element("paiement-motif")
        focus(motif, in: ecran)
        motif.typeText("   ")
        XCTAssertFalse(envoyer.isEnabled, "motif blanc : envoi impossible (`!motif.trim()`)")
        motif.typeText("Montant différent du virement reçu")
        fermerClavier(ecran)
        scrollTo(envoyer, in: ecran)
        require("Un motif saisi active l'envoi") { envoyer.isEnabled }
        record("\(proofPrefix)-paiements-motif")
        envoyer.tap()
        let issue = element("paiement-conteste")
        require("« Contestation envoyée » après relecture du statut", timeout: 30) { issue.exists }
        XCTAssertTrue(issue.label.contains("Contestation envoyée"), issue.label)
        require("La carte contestée n'est plus rendue par le serveur") { !self.element("paiement-declare-\(Self.premier)").exists }
        XCTAssertFalse(element("paiement-erreur").exists)
        let etat = element("revenus-mission-etat-demo-terminee-001")
        scrollTo(etat, in: ecran)
        require("L'état de la mission est relu après la contestation", timeout: 30) { etat.label == "Paiement contesté" }
        record("\(proofPrefix)-paiements-conteste")
    }

    func testRefusServeurVerbatimJamaisUnSucces() throws {
        launchDemo(environment: ["JOLENE_DEMO_PAIEMENTS": "refus"])
        connexionDemo()
        let ecran = ouvrirRevenus()
        // Confirmé ailleurs (web) : refus du serveur verbatim, carte retirée à la relecture, jamais « Paiement confirmé ».
        let entete = element("paiement-deplier-\(Self.premier)")
        scrollTo(entete, in: ecran)
        entete.tap()
        let confirmer = element("paiement-confirmer-\(Self.premier)")
        scrollTo(confirmer, in: ecran)
        confirmer.tap()
        let erreur = element("paiement-erreur")
        require("Le refus du serveur est affiché", timeout: 30) { erreur.exists }
        XCTAssertTrue(erreur.label.contains("Paiement déjà confirmé"), erreur.label)
        XCTAssertFalse(element("paiement-confirme").exists, "jamais un succès sur un refus")
        require("Confirmé ailleurs : la relecture ne rend plus la carte") { !self.element("paiement-declare-\(Self.premier)").exists }
        record("\(proofPrefix)-paiements-refus-confirmation")

        // Litige déjà ouvert sur la mission : refus verbatim, carte gardée, jamais « Contestation envoyée ».
        let envoyer = ouvrirContestation(Self.second, ecran: ecran)
        let motif = element("paiement-motif")
        focus(motif, in: ecran)
        motif.typeText("Montant erroné")
        fermerClavier(ecran)
        scrollTo(envoyer, in: ecran)
        require("Un motif saisi active l'envoi") { envoyer.isEnabled }
        envoyer.tap()
        require("Le refus LITIGE_DEJA_OUVERT est affiché", timeout: 30) {
            erreur.exists && erreur.label.contains("Un litige de ce type est déjà ouvert pour cette mission.")
        }
        XCTAssertFalse(element("paiement-conteste").exists, "jamais un succès sur un refus")
        XCTAssertTrue(element("paiement-declare-\(Self.second)").exists, "aucune écriture : la carte reste")
        record("\(proofPrefix)-paiements-refus-contestation")
    }

    /// Cas reporté de T5 (blueprint §3 T13) : `PAIEMENT_RECU` mène à `/soignant/mes-gains?tab=paiements` (correction 15),
    /// section native « Paiements à confirmer » de l'onglet Revenus, jamais un renvoi web.
    ///
    /// Revue B8 n°1, m6 : sur iPhone, la section est déjà près du haut de l'onglet ; la voir ne prouve pas que l'onglet a
    /// défilé jusqu'à elle (`RevenusScreen`, ancre `revenus-ancre-paiements-declares`). Le défilement est prouvé par
    /// l'en-tête de l'onglet (`revenus-sous-titre`, au-dessus de la section) sorti du cadre utile : entièrement au-dessus
    /// du bas des barres de navigation (ou du haut de l'écran sans barre). Sur iPad, où l'onglet peut tenir sans défiler,
    /// l'assertion reste la visibilité de la première carte.
    func testTapPushPaiementRecuOuvreLesPaiementsDeclares() throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "PAIEMENT_RECU"])
        connexionDemo()
        require("L'onglet Revenus s'ouvre sur les paiements à confirmer", timeout: 30) {
            self.element("revenus-paiements-declares").exists && self.visible(self.element("paiement-deplier-\(Self.premier)"))
        }
        if UIDevice.current.userInterfaceIdiom != .pad {
            let ecran = element("revenus-screen")
            let enTete = element("revenus-sous-titre")
            require("iPhone : l'onglet a défilé jusqu'à la section (en-tête de l'onglet hors du cadre utile)", timeout: 30) {
                guard enTete.exists, self.containerVisible(ecran) else { return false }
                let haut = self.basDesBarresDeNavigation(sur: ecran) ?? ecran.frame.minY
                return enTete.frame.maxY <= haut + 1
            }
            XCTAssertTrue(visible(element("paiement-deplier-\(Self.premier)")), "la section reste à l'écran après le défilement")
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "section native livrée : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "revenus(paiements)")
        record("\(proofPrefix)-paiements-push")
    }

    // MARK: - Étapes

    @discardableResult
    private func ouvrirRevenus() -> XCUIElement {
        tabButton("tab-revenus", label: "Revenus").tap()
        let ecran = element("revenus-screen")
        require("La section des paiements à confirmer est affichée", timeout: 30) {
            self.containerVisible(ecran) && self.element("revenus-paiements-declares").exists
                && self.element("revenus-mission-demo-terminee-001").exists
        }
        return ecran
    }

    /// Déplie la carte puis ouvre son formulaire de contestation ; rend « Envoyer la contestation ».
    private func ouvrirContestation(_ id: String, ecran: XCUIElement) -> XCUIElement {
        let entete = element("paiement-deplier-\(id)")
        scrollTo(entete, in: ecran)
        entete.tap()
        let contester = element("paiement-contester-\(id)")
        require("Le détail est déplié") { contester.exists }
        scrollTo(contester, in: ecran)
        XCTAssertEqual(contester.label, "Contester")
        contester.tap()
        let envoyer = element("paiement-contestation-envoyer")
        require("Le formulaire de contestation est ouvert") { envoyer.exists && self.element("paiement-motif").exists }
        // Le formulaire s'ouvre sous les actions, souvent hors écran : `focus` ne fait défiler que hors du clavier.
        scrollTo(element("paiement-motif"), in: ecran)
        return envoyer
    }

    /// Le défilement referme le clavier (`scrollDismissesKeyboard(.immediately)`), qui ne couvre jamais l'envoi.
    private func fermerClavier(_ ecran: XCUIElement) {
        guard app.keyboards.firstMatch.exists else { return }
        drag(ecran, fromY: 0.35, toY: 0.45)
        require("Le clavier est refermé") { !self.app.keyboards.firstMatch.exists }
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
        submit.tap()
        require("La session démo est prête", timeout: 30) { self.tabBarExists }
    }
}
