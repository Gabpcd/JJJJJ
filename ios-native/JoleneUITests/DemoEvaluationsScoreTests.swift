import XCTest

/// « Mes évaluations » et « Mon score » (L4-T9) en démonstration, sur iPhone, iPad portrait et iPad paysage. Les deux
/// écrans n'ont pas d'entrée dans le hub (comme sur le web : barre latérale, liens et notifications) ; ils sont ouverts
/// par leur lien, injecté au lancement par l'argument DEBUG `-JOLENE_OPEN_URL` et rejoué après la connexion.
///
/// - Évaluations (`demo-evaluations.json`) : statistiques affichées = celles de la fixture (4.4, 4, 25 %, 5.0), sans
///   changement quand un filtre réduit la liste (la moyenne des deux notes restantes vaudrait 4,75) ; signalement →
///   feuille → la carte relue porte « Déjà signalée ».
/// - Score (`demo-score.json`) : score et niveau servis, détail du calcul, un seul événement contestable ;
///   contestation (motif, explication, aucun justificatif) → l'événement relu est « Non contestable ».
/// - Aucune requête réseau (sentinelle).
///
/// Les règles (relecture qui confirme, refus verbatim, clé `events`, aucun défaut fabriqué, aucune moyenne recalculée)
/// sont prouvées par `EvaluationsModelTests`, `ScoreModelTests`, `EvaluationsScoreDecodingTests` ; le transport par
/// `SupabaseEvaluationsGatewayTests` et `SupabaseScoreGatewayTests` ; l'absence de toute lecture de la table des
/// notations par `EvaluationsSourceGuardTests`. Vérifié par la CI seulement.
final class DemoEvaluationsScoreTests: JoleneUITestCase {
    private enum Attendus {
        static let notation = "demo-notation-001"
        static let dejaSignalee = "demo-notation-004"
        static let contestable = "demo-evenement-001"
        static let traite = "demo-evenement-002"
        static let ferme = "demo-evenement-003"
    }

    func testEvaluationsStatistiquesDeLaFixturePuisSignalement() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/evaluations"])
        connexionDemo()
        let ecran = defilement("evaluations-screen")
        require("Les évaluations reçues sont lues", timeout: 30) {
            self.containerVisible(ecran) && self.element("evaluations-stats").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T9) : jamais un renvoi web")
        XCTAssertFalse(element("evaluations-erreur").exists)

        // Statistiques : valeurs de la fixture (du serveur), telles quelles.
        verifierStatistiques()
        XCTAssertEqual(element("evaluations-total").label, "4 évaluations")
        XCTAssertEqual(elements(withPrefix: "evaluation-note-demo-notation-").count, 4, "quatre notations publiées")
        XCTAssertTrue(element("evaluation-signalee-\(Attendus.dejaSignalee)").exists, "notation déjà signalée dans la fixture")
        XCTAssertFalse(element("evaluation-signaler-\(Attendus.dejaSignalee)").exists)
        record("\(proofPrefix)-evaluations-liste")

        // Filtre : la liste se réduit, les statistiques globales ne bougent pas (aucune moyenne recalculée).
        let troisMois = element("evaluations-periode-3M")
        scrollTo(troisMois, in: ecran)
        XCTAssertEqual(troisMois.label, "3 derniers mois")
        troisMois.tap()
        require("La page filtrée est relue") { self.element("evaluations-total").label == "2 évaluations" }
        XCTAssertEqual(elements(withPrefix: "evaluation-note-demo-notation-").count, 2)
        XCTAssertTrue(element("evaluations-periode-3M").isSelected)
        let moyenne = element("evaluations-stat-moyenne")
        scrollTo(moyenne, in: ecran, downward: false)
        verifierStatistiques()
        let toutes = element("evaluations-periode-TOUT")
        scrollTo(toutes, in: ecran)
        toutes.tap()
        require("Toutes les évaluations sont relues") { self.element("evaluations-total").label == "4 évaluations" }

        // Signalement : la carte n'est « Déjà signalée » qu'après relecture.
        let signaler = element("evaluation-signaler-\(Attendus.notation)")
        scrollTo(signaler, in: ecran)
        XCTAssertEqual(signaler.label, "Signaler cette évaluation")
        signaler.tap()
        let feuille = element("evaluation-signalement")
        require("La feuille de signalement est ouverte") { self.containerVisible(feuille) }
        let envoyer = element("evaluation-signalement-envoyer")
        require("« Signaler » est rendu") { envoyer.exists }
        XCTAssertFalse(envoyer.isEnabled, "sans motif de dix caractères : envoi impossible")
        XCTAssertTrue(element("evaluation-signalement-explication").label
            .contains("Un administrateur Jolene examinera votre signalement"), "texte du web")
        XCTAssertTrue(element("evaluation-signalement-rappel").label.contains("Note moyenne : 5.0/5"))
        let motif = element("evaluation-signalement-motif")
        focus(motif, in: feuille)
        motif.typeText("Cette evaluation ne correspond pas a la mission.")
        fermerLePaveNumerique()
        require("Un motif saisi active l'envoi") { envoyer.isEnabled }
        record("\(proofPrefix)-evaluations-signalement")
        scrollTo(envoyer, in: feuille)
        envoyer.tap()
        require("La notation relue est signalée", timeout: 30) {
            !self.element("evaluation-signalement").exists && self.element("evaluation-signalee-\(Attendus.notation)").exists
        }
        XCTAssertEqual(element("evaluation-signalee-\(Attendus.notation)").label, "Déjà signalée")
        XCTAssertFalse(element("evaluation-signaler-\(Attendus.notation)").exists, "plus de signalement proposé")
        XCTAssertFalse(element("evaluations-action-erreur").exists, "aucune erreur en démonstration")
        let confirmation = element("evaluations-confirmation")
        scrollTo(confirmation, in: ecran, downward: false)
        XCTAssertTrue(confirmation.label.contains("Signalement transmis"), confirmation.label)
        verifierStatistiques()
        record("\(proofPrefix)-evaluations-signalee")
        verifierAucuneRequete(ecran: "evaluations-screen")
    }

    func testScoreContestationRendLEvenementNonContestable() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/score"])
        connexionDemo()
        let ecran = defilement("score-screen")
        require("Le score est lu", timeout: 30) { self.containerVisible(ecran) && self.element("score-valeur").exists }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T9) : jamais un renvoi web")
        XCTAssertFalse(element("score-erreur").exists)
        XCTAssertEqual(element("score-valeur").label, "73 / 100", "score servi (72,6), arrondi comme le web")
        XCTAssertTrue(element("score-niveau").label.contains("Or"), element("score-niveau").label)
        XCTAssertFalse(element("score-non-note").exists)
        record("\(proofPrefix)-score")

        // Détail du calcul : replié par défaut, composantes servies.
        XCTAssertFalse(element("score-breakdown").exists, "détail replié par défaut")
        let bascule = element("score-calcul-bascule")
        scrollTo(bascule, in: ecran)
        bascule.tap()
        require("Le détail du calcul est affiché") { self.element("score-breakdown").exists }
        XCTAssertTrue(element("score-composante-presentisme").exists)
        XCTAssertFalse(element("score-composante-reactivite").exists, "composante inactive : aucune valeur affichée")
        XCTAssertTrue(element("score-inactives").exists)
        scrollTo(bascule, in: ecran, downward: false)
        bascule.tap()
        require("Le détail est replié") { !self.element("score-breakdown").exists }

        // Événements : un seul contestable (valeur du serveur).
        let contester = element("score-contester-\(Attendus.contestable)")
        scrollTo(contester, in: ecran)
        XCTAssertTrue(contester.label.contains("Contester"), contester.label)
        XCTAssertEqual(elements(withPrefix: "score-contester-").count, 1, "un seul événement contestable")
        XCTAssertEqual(element("score-evenement-etat-\(Attendus.traite)").label, "Traitée")
        XCTAssertEqual(element("score-evenement-etat-\(Attendus.ferme)").label, "Non contestable")
        XCTAssertEqual(element("score-evenement-points-\(Attendus.contestable)").label, "-5 pts")
        record("\(proofPrefix)-score-evenements")
        contester.tap()

        let feuille = element("score-contestation")
        require("La feuille de contestation est ouverte") { self.containerVisible(feuille) }
        XCTAssertFalse(feuille.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "justificatif")).firstMatch.exists,
                       "aucun justificatif n'est demandé (D10)")
        let envoyer = element("score-contestation-envoyer")
        scrollTo(envoyer, in: feuille)
        envoyer.tap()
        let erreur = element("score-contestation-erreur")
        require("Sans motif, la contestation n'est pas envoyée") { erreur.exists }
        XCTAssertTrue(erreur.label.contains("Sélectionnez un motif."), erreur.label)
        let motif = element("score-contestation-motif-CONTEXTE_PARTICULIER")
        scrollTo(motif, in: feuille, downward: false)
        motif.tap()
        require("Le motif est choisi") { motif.isSelected }
        let texte = element("score-contestation-texte")
        scrollTo(texte, in: feuille)
        focus(texte, in: feuille)
        texte.typeText("Etablissement prevenu la veille par telephone.")
        fermerLePaveNumerique()
        record("\(proofPrefix)-score-contestation")
        scrollTo(envoyer, in: feuille)
        envoyer.tap()
        let etat = element("score-evenement-etat-\(Attendus.contestable)")
        require("L'événement relu n'est plus contestable", timeout: 30) {
            !self.element("score-contestation").exists && etat.exists
        }
        XCTAssertEqual(etat.label, "Non contestable")
        XCTAssertFalse(element("score-contester-\(Attendus.contestable)").exists, "plus de contestation proposée")
        XCTAssertEqual(elements(withPrefix: "score-contester-").count, 0)
        XCTAssertFalse(element("score-action-erreur").exists, "aucune erreur en démonstration")
        let confirmation = element("score-confirmation")
        scrollTo(confirmation, in: ecran, downward: false)
        XCTAssertTrue(confirmation.label.contains("Réclamation envoyée"), confirmation.label)
        record("\(proofPrefix)-score-conteste")
        verifierAucuneRequete(ecran: "score-screen")
    }

    // MARK: Étapes

    /// Statistiques de `demo-evaluations.json`, écrites comme le web (`toFixed(1)`, pourcentage tel que servi).
    private func verifierStatistiques(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(element("evaluations-stat-moyenne").label, "4.4", "note moyenne globale de la fixture", file: file, line: line)
        XCTAssertEqual(element("evaluations-stat-total").label, "4", "total de la fixture", file: file, line: line)
        XCTAssertEqual(element("evaluations-stat-pct5").label, "25%", "part de cinq étoiles de la fixture", file: file, line: line)
        XCTAssertEqual(element("evaluations-stat-evolution").label, "5.0", "note du dernier mois servi", file: file, line: line)
    }

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Profil remis à sa racine (l'écran y est empilé), puis sentinelle réseau.
    private func verifierAucuneRequete(ecran: String) {
        toucherOnglet("tab-profil", label: "Profil")
        if element(ecran).exists {
            let back = app.navigationBars.buttons.firstMatch
            require("Le bouton retour est disponible") { self.visible(back) }
            back.tap()
            require("L'écran \(ecran) est retiré") { !self.element(ecran).exists }
        }
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "évaluations et score n'émettent aucune requête en démonstration")
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
