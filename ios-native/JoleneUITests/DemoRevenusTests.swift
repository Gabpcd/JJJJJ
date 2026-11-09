import XCTest

/// Onglet Revenus en démo (lot 3, T12, B9 ; `DECISIONS_LOT3.md`, section T12) sur iPhone, iPad portrait et iPad paysage
/// (`JOLENE_UI_ORIENTATION`, `proofPrefix`). Fixtures `demo-revenus.json`, `demo-escrow.json`,
/// `demo-missions-terminees.json` (horloge fixée au 02/11/2026). Lecture seule : aucun bouton de paiement.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - l'onglet natif remplace le placeholder du lot 0 (`placeholder-revenus` → `revenus-screen`, règle 8) : totaux
///   serveur (« Ce mois », « Total réglé », « Autres paiements en attente » et leur note, profil démo MIXTE), les sept
///   états du paiement rapide avec leurs libellés verbatim du web (tutoiement compris, HARD STOP n°4), les missions
///   terminées avec le montant de `montantFinanceAfficheMission` (net estimé « ~ », honoraires, brut indicatif, témoin
///   Rist à 280 €) et l'état de la dernière déclaration, notes « net estimé » verbatim ;
/// - le litige du paiement rapide ouvre le détail natif de la mission, empilé sur l'onglet Revenus ;
/// - « Factures », « Paie » et une ligne de mission (présences, lot 2) sont des renvois web canoniques (D4), présentés
///   par le double démo du présentateur `.safari` (aucune requête réseau) ;
/// - état d'erreur puis reprise (`JOLENE_FORCE_REVENUS_ECHEC=1`) ;
/// - lien universel `/soignant/mes-gains` (aperçu natif) et tap push `FACTURE_EMISE` (section factures : renvoi web, D4 ;
///   cas reporté de T5).
/// Les règles (décodage, montants, états, epoch, audit unique, pagination) sont prouvées au niveau 1 (`RevenusLectureTests`,
/// `RevenusPresentationTests`, `RevenusModelTests`, `SupabaseRevenusGatewayTests`).
final class DemoRevenusTests: JoleneUITestCase {
    private static let espace = "\u{00A0}"

    func testOngletRevenusAfficheTotauxPaiementsRapidesEtMissions() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirRevenus()
        XCTAssertFalse(element("placeholder-revenus").exists, "le placeholder du lot 0 est remplacé")
        XCTAssertFalse(element("revenus-error").exists)
        XCTAssertTrue(app.navigationBars["Revenus"].exists, "titre du web (`usePageTitle('Revenus')`)")
        XCTAssertEqual(element("revenus-sous-titre").label, "Vos gains, factures et documents de paie au même endroit")

        // Totaux serveur (`fn_mes_revenus_connect`), jamais recalculés.
        XCTAssertEqual(element("revenus-kpi-mois").label, "Ce mois, 195,00\(Self.espace)€")
        XCTAssertEqual(element("revenus-kpi-total").label, "Total réglé, 1\u{202F}425,60\(Self.espace)€")
        XCTAssertEqual(element("revenus-kpi-attente").label, "Autres paiements en attente, 780,00\(Self.espace)€")
        XCTAssertEqual(element("revenus-kpi-note").label,
                       "Ces montants incluent les transferts vers le solde Stripe et les règlements directs. Ils ne confirment pas à eux seuls une arrivée en banque.")
        record("\(proofPrefix)-revenus-haut")

        // Paiement rapide : sept états, libellés verbatim (PaiementsEscrowAVenir.tsx l.42-80).
        let escrow: [(String, String)] = [
            ("demo-escrow-001", "Paiement retardé, Cabinet fictif du Parc · nouvelle tentative le 04/11, 150,00\(Self.espace)€"),
            ("demo-assignee-002", "Paiement en litige, Établissement fictif des Lilas · voir le litige de la mission, 240,00\(Self.espace)€"),
            ("demo-escrow-003", "En attente de validation des heures, Établissement fictif République · l'établissement valide tes heures (automatique sous 72 h), 180,00\(Self.espace)€"),
            ("demo-escrow-004", "Versement en cours — estimé le 03/11, Cabinet fictif du Parc · ton virement est en route, 210,00\(Self.espace)€"),
            ("demo-escrow-005", "Réservé, Établissement fictif des Lilas · le montant de ta confirmation, mis de côté, 240,00\(Self.espace)€"),
            ("demo-escrow-006", "Versé le 30/10, Cabinet fictif du Parc, 195,00\(Self.espace)€"),
            ("demo-escrow-007", "Paiement annulé, Établissement fictif République · contacte le support si besoin, 120,00\(Self.espace)€"),
        ]
        for (id, label) in escrow {
            let ligne = element("revenus-escrow-\(id)")
            require("La ligne de paiement rapide \(id) est rendue") { ligne.exists }
            XCTAssertEqual(ligne.label, label, id)
        }
        for groupe in ["revenus-escrow-a-venir", "revenus-escrow-verses", "revenus-escrow-annules"] {
            XCTAssertTrue(element(groupe).exists, groupe)
        }

        // Missions terminées : montant (golden `mission-finance-display`) et état de la dernière déclaration.
        let montants: [(String, String, String)] = [
            ("demo-terminee-001", "environ 162,40\(Self.espace)€, Net salarié estimé", "Réception à confirmer"),
            ("demo-terminee-002", "256,00\(Self.espace)€, Honoraires prévisionnels du planning", "Paiement suivi dans Factures"),
            ("demo-terminee-003", "environ 240,00\(Self.espace)€, Rémunération brute indicative", "Régime à vérifier"),
            ("demo-terminee-004", "environ 170,50\(Self.espace)€, Net salarié estimé", "Réception confirmée"),
            ("demo-terminee-005", "280,00\(Self.espace)€, Honoraires prévisionnels du planning", "Paiement suivi dans Factures"),
        ]
        for (id, montant, etat) in montants {
            let ligne = element("revenus-mission-\(id)")
            require("La mission \(id) est rendue") { ligne.exists }
            XCTAssertTrue(element("revenus-mission-montant-\(id)").label.contains(montant),
                          "\(id) : \(element("revenus-mission-montant-\(id)").label)")
            XCTAssertEqual(element("revenus-mission-etat-\(id)").label, etat, id)
        }
        let note = element("revenus-note-net-estime")
        scrollTo(note, in: ecran)
        XCTAssertTrue(note.label.hasPrefix("* Pour une mission salariée, le net est estimé après cotisations sociales"))
        let bas = element("revenus-note-bas")
        scrollTo(bas, in: ecran)
        XCTAssertTrue(bas.label.hasPrefix("* Net salarié estimé après cotisations salariales (~22 %). * Honoraires libéraux hors charges URSSAF"),
                      bas.label)
        XCTAssertFalse(element("revenus-load-more").exists, "cinq missions : aucune page suivante")
        record("\(proofPrefix)-revenus-bas")
    }

    func testLigneEnLitigeOuvreLeDetailDeLaMission() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirRevenus()
        let litige = element("revenus-escrow-demo-assignee-002")
        scrollTo(litige, in: ecran)
        require("La ligne du litige est atteignable") { self.visible(litige) }
        litige.tap()
        let titre = element("mission-detail-title")
        require("Le détail natif de la mission est empilé sur Revenus", timeout: 30) {
            self.containerVisible(self.element("mission-detail")) && self.visible(titre)
        }
        XCTAssertEqual(titre.label, "Démonstration · Mission assignée 2")
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré : jamais un renvoi web")
        record("\(proofPrefix)-revenus-litige")
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Retour à la racine de l'onglet Revenus") { self.containerVisible(self.element("revenus-screen")) }
    }

    func testFacturesEtPaieSontDesRenvoisWeb() throws {
        launchDemo()
        connexionDemo()
        _ = ouvrirRevenus()
        let factures = element("revenus-factures-web")
        require("« Factures » est atteignable") { self.visible(factures) }
        XCTAssertEqual(factures.label, "Factures")
        factures.tap()
        liensRenvoiWebAffiche("https://jolene.app/soignant/mes-gains?tab=factures")
        record("\(proofPrefix)-revenus-factures")
        liensFermerRenvoiWeb()
        let paie = element("revenus-bulletins-web")
        require("« Paie » est atteignable") { self.visible(paie) }
        XCTAssertEqual(paie.label, "Paie")
        paie.tap()
        liensRenvoiWebAffiche("https://jolene.app/soignant/mes-gains?tab=bulletins")
        liensFermerRenvoiWeb()
        require("L'onglet Revenus est intact après les renvois") { self.containerVisible(self.element("revenus-screen")) }
        XCTAssertFalse(element("revenus-avances-web").exists, "avance de trésorerie : drapeau affacturage_actif non lu, défaut false (web l.848, l.897)")
    }

    func testMissionOuvreSesPresencesSurLeWeb() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirRevenus()
        let ligne = element("revenus-mission-demo-terminee-002")
        scrollTo(ligne, in: ecran)
        require("La ligne de mission est atteignable") { self.visible(ligne) }
        ligne.tap()
        liensRenvoiWebAffiche("https://jolene.app/soignant/presences/mission/demo-terminee-002")
        record("\(proofPrefix)-revenus-presences")
        liensFermerRenvoiWeb()
        require("L'onglet Revenus est intact") { self.containerVisible(self.element("revenus-screen")) }
    }

    func testErreurPuisReprise() throws {
        launchDemo(environment: ["JOLENE_FORCE_REVENUS_ECHEC": "1"])
        connexionDemo()
        tabButton("tab-revenus", label: "Revenus").tap()
        let erreur = element("revenus-error")
        require("L'erreur de chargement est affichée", timeout: 30) { erreur.exists }
        XCTAssertTrue(erreur.label.contains("Impossible de charger tous les revenus"), erreur.label)
        XCTAssertFalse(element("revenus-empty").exists, "jamais l'état vide sur une erreur")
        XCTAssertTrue(element("revenus-kpi-mois").exists, "sections indépendantes : les totaux restent lus")
        record("\(proofPrefix)-revenus-erreur")
        tap("revenus-retry")
        require("Les missions sont relues après « Réessayer »", timeout: 30) {
            self.element("revenus-mission-demo-terminee-001").exists && !self.element("revenus-error").exists
        }
    }

    func testLienUniverselMesGainsOuvreLOngletRevenus() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/mes-gains"])
        connexionDemo()
        require("L'onglet Revenus natif est ouvert après `.ready`", timeout: 30) {
            self.containerVisible(self.element("revenus-screen")) && self.element("revenus-mission-demo-terminee-001").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "aperçu natif livré : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "revenus(apercu)")
        record("\(proofPrefix)-revenus-lien")
    }

    /// Cas reporté de T5 (blueprint §3 T12) : `FACTURE_EMISE` mène à `/soignant/mes-gains?tab=factures`, section en renvoi
    /// web assumé (D4) ; la page canonique est présentée, jamais l'onglet natif à la place de la section.
    func testTapPushFactureEmiseOuvreLesFacturesSurLeWeb() throws {
        let page = "https://jolene.app/soignant/mes-gains?tab=factures"
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "FACTURE_EMISE"])
        connexionDemo()
        liensRenvoiWebAffiche(page)
        record("\(proofPrefix)-revenus-push-facture")
        liensFermerRenvoiWeb()
        XCTAssertEqual(element("deeplink-route").label, "safari \(page)")
    }

    // MARK: - Étapes

    @discardableResult
    private func ouvrirRevenus() -> XCUIElement {
        tabButton("tab-revenus", label: "Revenus").tap()
        let ecran = element("revenus-screen")
        require("L'onglet Revenus natif est affiché", timeout: 30) {
            self.containerVisible(ecran) && self.element("revenus-mission-demo-terminee-001").exists
        }
        return ecran
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
