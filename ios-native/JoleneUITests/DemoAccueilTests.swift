import XCTest

/// Accueil démo (lot 1, T3) sur iPhone, iPad portrait et iPad paysage : tableau de bord servi
/// par `DemoDashboardGateway` (`demo-dashboard.json`, horloge fixée 2026-11-02T00:00:00Z). Les
/// valeurs attendues sont celles que `DemoDashboardTests` (JoleneCore) affirme sur le port : un
/// écart entre l'écran et le port fait échouer l'un des deux. Exclusions HARD STOP vérifiées
/// (`BandeauAlerte48h`, « cumul d'activité »), puis navigation vers le détail et vers Explorer ;
/// état d'erreur et reprise par « Réessayer » (`testAccueilErreurPuisReprise`).
final class DemoAccueilTests: JoleneUITestCase {
    private static let euro = "\u{00A0}€"

    func testAccueilDemo() throws {
        launchDemo()
        connexionDemo()

        let ecran = element("accueil-screen")
        let salutation = element("accueil-salutation")
        require("L'Accueil affiche le tableau de bord démo", timeout: 30) {
            self.containerVisible(ecran) && salutation.exists && !self.element("accueil-loading").exists
        }
        XCTAssertTrue(["Bonjour, Camille", "Bonsoir, Camille"].contains(salutation.label), "salutation : \(salutation.label)")
        XCTAssertEqual(element("accueil-accroche").label, "3 missions près de chez vous — vous pouvez déjà postuler.")
        XCTAssertFalse(element("accueil-error").exists, "aucune erreur en démo")
        XCTAssertFalse(element("accueil-oubli-pointage").exists, "aucun pointage oublié dans la démo")
        record("\(proofPrefix)-accueil-haut")

        // Mes prochaines missions : planning PREVISIONNEL vérifié, heure de Paris.
        verifier("accueil-prochaine-demo-assignee-001", dans: ecran, contient: [
            "Assignée", "Démonstration · Mission assignée 1", "Établissement fictif République · Paris", "jeudi 5 nov. · 08h00 → 16h00",
        ])
        verifier("accueil-prochaine-demo-assignee-002", dans: ecran, contient: [
            "Établissement fictif des Lilas · Les Lilas", "lundi 9 nov. · 08h00 → 16h00 · créneau 1/2",
        ])

        // Missions pour vous : les deux premières missions ouvertes, taux serveur.
        verifier("accueil-pour-toi-demo-mission-001", dans: ecran, contient: [
            "Urgente", "Démonstration · Médecine polyvalente 1", "mardi 3 nov. · 08h00 → 16h00", "23,00\(Self.euro)/h",
        ])
        verifier("accueil-pour-toi-demo-mission-002", dans: ecran, contient: ["mercredi 4 nov. · 08h00 → 16h00", "24,00\(Self.euro)/h"])
        XCTAssertFalse(element("accueil-pour-toi-demo-mission-003").exists, "le web n'affiche que les deux premières")

        // Mission proposée il y a 30 minutes : 1 h 30 de réponse.
        verifier("accueil-proposition-demo-proposition-001", dans: ecran, contient: [
            "Démonstration · Médecine polyvalente 11", "Expire dans 1h 30min", "13/11/2026 · 08:00–16:00", "Établissement fictif des Lilas",
        ])

        // Gains du mois relus mission par mission (décision 10), note « net estimé » verbatim.
        let gains = element("accueil-gains")
        scrollTo(gains, in: ecran)
        XCTAssertEqual(gains.label, "💰 Ce mois : 162,40\(Self.euro) net salarié estimé* sur 1 mission")
        let note = element("accueil-gains-note")
        scrollTo(note, in: ecran)
        XCTAssertTrue(note.label.hasPrefix("* Pour une mission salariée, le net est estimé"), "note : \(note.label)")
        let notifications = element("accueil-notifications")
        scrollTo(notifications, in: ecran)
        XCTAssertEqual(notifications.label, "2 notifications non lues")

        // HARD STOP n°4 : ni `BandeauAlerte48h` (web : « Plafond de 48h atteint… », « …plafond de 48h
        // cette semaine… », sans espace) ni encart « Cumul d'activité » (profil démo MIXTE). Recherche
        // sur tous les libellés, casse et accents ignorés. La démo planifie 8 h (le web n'afficherait
        // pas le bandeau, seuil 44 h) : la garde à 50 h planifiées est dans JoleneCore
        // (`AccueilAssemblageTests.testAucunTexteNeReprendLAlerte48hNiLeCumulDActivite`).
        for interdit in ["48h", "48 h", "plafond", "cumul d"] {
            XCTAssertFalse(libelleContenant(interdit).exists, "« \(interdit) » ne doit apparaître nulle part sur l'Accueil")
        }
        // Point d'extension calendrier (décision 18) : aucun bouton tant que T5 n'injecte pas
        // `ajoutCalendrierMission`. T5 remplace cette assertion par la présence du bouton et l'issue
        // `accueil-calendrier-issue` après un tap (LOT1_PLAN.md §3 T5, verrou de clôture T12).
        XCTAssertFalse(element("accueil-calendrier-demo-assignee-001").exists,
                       "bouton calendrier sans implémentation injectée : jamais un bouton sans effet (T5 le câble)")
        record("\(proofPrefix)-accueil-bas")

        ouvrirProchaineMissionPuisRevenir(ecran)
        ouvrirExplorerDepuisToutVoir(ecran)
    }

    /// État d'erreur puis reprise (recette CLAUDE.md : états d'erreur dans l'interface) : surcharge
    /// DEBUG `JOLENE_FORCE_ACCUEIL_ECHEC` (`AppContainer`) → `DemoDashboardEchecGateway`, dont le
    /// premier chargement échoue comme un délai dépassé ; « Réessayer » relit le tableau de bord démo.
    func testAccueilErreurPuisReprise() throws {
        launchDemo(environment: ["JOLENE_FORCE_ACCUEIL_ECHEC": "1"])
        connexionDemo()

        let ecran = element("accueil-screen")
        let erreur = element("accueil-error")
        require("L'Accueil affiche l'état d'erreur", timeout: 30) { self.containerVisible(erreur) }
        XCTAssertTrue(text("Impossible de charger votre tableau de bord").exists, "titre de l'état d'erreur")
        XCTAssertTrue(text("Le service ne répond pas. Vérifiez votre connexion puis réessayez.").exists, "message de la panne simulée")
        XCTAssertFalse(element("accueil-session-expired").exists, "une panne n'est pas une session expirée")
        XCTAssertFalse(element("accueil-salutation").exists, "aucun tableau de bord fabriqué")
        record("\(proofPrefix)-accueil-erreur")

        let reessayer = element("accueil-retry")
        degager(reessayer, dans: ecran)
        reessayer.tap()
        let salutation = element("accueil-salutation")
        require("« Réessayer » relit le tableau de bord démo", timeout: 30) {
            salutation.exists && !erreur.exists && !self.element("accueil-loading").exists
        }
        XCTAssertTrue(["Bonjour, Camille", "Bonsoir, Camille"].contains(salutation.label), "salutation : \(salutation.label)")
        XCTAssertEqual(element("accueil-accroche").label, "3 missions près de chez vous — vous pouvez déjà postuler.")
        verifier("accueil-prochaine-demo-assignee-001", dans: ecran, contient: ["Démonstration · Mission assignée 1"])
        record("\(proofPrefix)-accueil-reprise")
    }

    // MARK: - Étapes

    /// Tout élément dont le libellé contient `fragment`, casse et accents ignorés.
    private func libelleContenant(_ fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[cd] %@", fragment)).firstMatch
    }

    private func connexionDemo() {
        require("L'écran de connexion est affiché") { self.containerVisible(self.element("login-scroll")) }
        let scroll = element("login-scroll")
        let email = element("login-email")
        focus(email, in: scroll)
        email.typeText(Self.demoEmail)
        let password = element("login-password")
        // Retour sur l'email : `onSubmit` donne le focus au mot de passe (iPad paysage : un tap ne le prend pas).
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.demoPassword)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) {
            scrollTo(submit, in: scroll)
        }
        submit.tap()
        require("La session démo est prête", timeout: 30) { self.tabBarExists && self.containerVisible(self.element("accueil-screen")) }
    }

    /// Défilement borné jusqu'à la ligne, puis chaque fragment attendu dans son libellé accessible.
    private func verifier(_ identifiant: String, dans ecran: XCUIElement, contient fragments: [String],
                          file: StaticString = #filePath, line: UInt = #line) {
        let ligne = element(identifiant)
        scrollTo(ligne, in: ecran)
        for fragment in fragments {
            XCTAssertTrue(ligne.label.contains(fragment), "\(identifiant) : « \(fragment) » absent de « \(ligne.label) »",
                          file: file, line: line)
        }
    }

    private enum Barre { case navigation, onglets }

    /// Barre qui recouvre `cible`, le cas échéant : le cadre d'un `ScrollView` s'étend sous la barre
    /// de navigation et sous la barre d'onglets (iPhone), si bien que `scrollTo` peut s'arrêter sur
    /// une cible entièrement dans le conteneur mais masquée par une barre. Sur iPad (iPadOS 18 et
    /// suivants), la barre d'onglets est en haut, sans élément `TabBar` : seule la barre de
    /// navigation est alors contrôlée.
    private func barreQuiRecouvre(_ cible: XCUIElement) -> Barre? {
        let navigation = app.navigationBars.firstMatch
        if navigation.exists, cible.frame.minY < navigation.frame.maxY { return .navigation }
        let onglets = app.tabBars.firstMatch
        if onglets.exists, cible.frame.maxY > onglets.frame.minY { return .onglets }
        return nil
    }

    /// Avant un tap : défilement borné jusqu'à la cible, puis dégagement des barres (glissements
    /// courts et bornés, aucune attente arbitraire).
    private func degager(_ cible: XCUIElement, dans ecran: XCUIElement) {
        scrollTo(cible, in: ecran)
        var essais = 0
        while essais < 6, let barre = barreQuiRecouvre(cible) {
            // Cible sous la barre d'onglets : remonter le contenu ; sous la barre de navigation : le descendre.
            if barre == .onglets { drag(ecran, fromY: 0.6, toY: 0.4) } else { drag(ecran, fromY: 0.4, toY: 0.6) }
            essais += 1
        }
        require("La cible est atteignable hors des barres") { self.visible(cible) && self.barreQuiRecouvre(cible) == nil }
    }

    private func ouvrirProchaineMissionPuisRevenir(_ ecran: XCUIElement) {
        let ligne = element("accueil-prochaine-demo-assignee-001")
        degager(ligne, dans: ecran)
        ligne.tap()
        let titre = element("mission-detail-title")
        require("Le détail de la mission assignée est rendu") {
            self.containerVisible(self.element("mission-detail")) && self.visible(titre)
        }
        XCTAssertEqual(titre.label, "Démonstration · Mission assignée 1")
        XCTAssertTrue(element("mission-detail-creneau-1").exists, "le créneau planifié est listé")
        record("\(proofPrefix)-accueil-detail")

        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("L'Accueil est de retour après le détail") { self.containerVisible(ecran) && !titre.exists }
    }

    private func ouvrirExplorerDepuisToutVoir(_ ecran: XCUIElement) {
        let toutVoir = element("accueil-section-pour-toi-action")
        degager(toutVoir, dans: ecran)
        toutVoir.tap()
        let compteur = element("missions-count")
        require("« Tout voir » ouvre Explorer et ses 30 missions", timeout: 30) {
            self.containerVisible(self.element("missions-list")) && compteur.exists && compteur.label == "30 missions"
        }
        record("\(proofPrefix)-accueil-tout-voir")
    }
}
