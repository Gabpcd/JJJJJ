import XCTest

/// Push en démo (lot 3 ; blueprint §2.7) : autorisation (T4), taps de notification simulés
/// (`-JOLENE_SIMULER_PUSH`) et pré-prompt (`-JOLENE_SESSION_COUNT 2`) (T5). Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - carte « Autorisation du téléphone » de l'onglet Profil (`push-etat-appareil`, textes verbatim de
///   `PageParametresNotifications.tsx` l.341-352) selon `-JOLENE_PUSH_AUTORISATION` : « autorisées » sans
///   bouton, « bloquées » avec « Ouvrir les réglages » (`push-ouvrir-reglages`), aucune carte quand
///   l'autorisation n'a jamais été demandée (le canal push de Jolene est inconnu du hub : le texte l.349
///   « Le canal est actif dans Jolene… » serait affirmé sans le savoir) ;
/// - aucune alerte de l'app au login (D1). En démo, l'autorisation est un double (`DemoPushPermission`) qui
///   ne sollicite jamais le système : l'absence de feuille SpringBoard ne garde que contre un câblage du
///   centre de notifications réel en démo. L'absence de demande implicite est prouvée au niveau 1
///   (`PushCoordinatorTests.testSansAutorisationAucunAppelNiDemande`,
///   `EtatNotificationsAppareilModelTests`) ;
/// - déconnexion : retour à l'écran de connexion sans attente ni message d'erreur. L'ordre « désactivation
///   du token → désinscription → oubli → révocation » n'est pas visible ici : il est prouvé au niveau 1
///   (`SessionStorePushTests`, `DemoPushGatewayTests`) et sur STAGING par T16 (`tokens_push` relu).
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) ; chaque contrôle
/// est amené à l'écran par un défilement borné (`scrollTo`) avant d'être exigé atteignable (PRINCIPES §6).
final class DemoPushTests: JoleneUITestCase {
    static let titre = "Autorisation du téléphone"
    static let autorisees = "Les notifications sont autorisées sur cet appareil."
    static let bloquees = "Les notifications sont bloquées par le téléphone. Réactivez Jolene dans les réglages système."
    /// Libellé d'action sans source web (`EtatNotificationsAppareil.ouvrirReglages`, épinglé au niveau 1).
    static let ouvrirReglages = "Ouvrir les réglages"

    func testAppareilAutoriseTokenEnregistrePuisDeconnexion() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "accordee"])
        signInDemo()
        aucuneAlerte()
        openProfile()
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Enregistrement du token démo : aucune requête réseau")
        let message = carteEtat()
        require("L'enregistrement démo est confirmé") { message.label == Self.autorisees }
        XCTAssertEqual(element("push-etat-appareil-title").label, Self.titre)
        XCTAssertFalse(element("push-ouvrir-reglages").exists,
                       "Autorisé et enregistré : « Ouvrir les réglages » est superflu, aucun bouton")
        record("\(proofPrefix)-push-autorise")

        let deconnexion = element("logout-button")
        scrollTo(deconnexion, in: element("profile-list"), downward: false)
        tap("logout-button")
        require("La déconnexion aboutit sans attendre", timeout: 10) { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(element("login-error").exists, "Aucun message d'erreur après une déconnexion volontaire")
        record("\(proofPrefix)-push-deconnexion")
    }

    func testAppareilNonDemandeAucunPromptNiCarte() throws {
        launchDemo() // défaut démo : autorisation jamais demandée
        signInDemo()
        aucuneAlerte()
        openProfile()
        let list = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        // La section Notifications se placerait juste avant la suppression de compte : la liste est amenée
        // jusqu'à la première ligne de cette section (défilement vers le bas : elle s'arrête en bas de l'écran),
        // si bien que l'emplacement de la carte est à l'écran et qu'une carte affichée y serait rendue.
        scrollTo(element("compte-suppression-info"), in: list)
        XCTAssertFalse(element("push-etat-appareil").exists,
                       "Jamais demandé, canal inconnu dans le hub : aucune carte, rien n'est affirmé")
        XCTAssertFalse(element("push-ouvrir-reglages").exists)
        aucuneAlerte()
        // T5 : 1re session démo (compteur en mémoire vive) : jamais de pré-prompt (D1).
        XCTAssertFalse(element("push-preprompt").exists, "1re session : aucun pré-prompt")
        record("\(proofPrefix)-push-non-demande")
    }

    func testAppareilRefuse() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "refusee"])
        signInDemo()
        openProfile()
        let message = carteEtat()
        require("L'état « bloquées » est affiché") { message.label == Self.bloquees }
        let reglages = element("push-ouvrir-reglages")
        scrollTo(reglages, in: element("profile-list"))
        require("« Ouvrir les réglages » est atteignable") { self.visible(reglages) && reglages.isEnabled }
        XCTAssertEqual(reglages.label, Self.ouvrirReglages)
        record("\(proofPrefix)-push-refuse")
    }

    // MARK: Taps (T5)

    // Tap à froid simulé (`-JOLENE_SIMULER_PUSH <TYPE>[:<valeur>][:<lien>]`, DEBUG démo) : mémorisé avant la session,
    // rejoué par le premier espace prêt après la connexion, rôle lu dans le snapshot (blueprint §2.5). Six types
    // ouvrent un écran natif ; un renvoi web (litige) est vérifié par la route présentée (`push-tap-cible`, DEBUG),
    // faute de présentateur `.safari` avant L1-T10. Les autres types (factures, paiements, préférences) sont
    // prouvés au niveau 1 (`PushTapIntentTests.testCiblesDesTypesPrincipaux`).

    func testTapRappelMissionOuvreLeDetail() throws {
        try tapOuvreLeDetail("RAPPEL_MISSION:demo-assignee-001", titre: "Démonstration · Mission assignée 1",
                             route: "missionDetail demo-assignee-001")
    }

    func testTapCandidatureAccepteeOuvreLeDetail() throws {
        try tapOuvreLeDetail("CANDIDATURE_ACCEPTEE:demo-mission-002", titre: "Démonstration · Soins de suite 2",
                             route: "missionDetail demo-mission-002")
    }

    func testTapMissionAssigneeOuvreLeDetail() throws {
        try tapOuvreLeDetail("MISSION_ASSIGNEE:demo-assignee-002", titre: "Démonstration · Mission assignée 2",
                             route: "missionDetail demo-assignee-002")
    }

    func testTapMissionAPourvoirSansIdOuvreExplorer() throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "MISSION_A_POURVOIR"])
        signInDemo()
        require("Explorer est ouvert (`/soignant/recherche-missions`)", timeout: 30) {
            self.containerVisible(self.element("missions-list"))
        }
        XCTAssertEqual(element("push-tap-cible").label, "explorer")
        record("\(proofPrefix)-push-tap-explorer")
    }

    func testTapMissionAnnuleeSansIdOuvreMesMissions() throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "MISSION_ANNULEE_ETAB"])
        signInDemo()
        require("L'onglet Mes missions est ouvert (`/soignant/missions`)", timeout: 30) {
            self.visible(self.element("placeholder-missions"))
        }
        XCTAssertEqual(element("push-tap-cible").label, "missions")
        record("\(proofPrefix)-push-tap-mes-missions")
    }

    func testTapLienExpliciteOuvreLeCentreDeNotifications() throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "SYSTEM::/soignant/notifications"])
        signInDemo()
        require("Le centre de notifications natif est ouvert", timeout: 30) {
            self.containerVisible(self.element("notifications-screen"))
                && self.element("notification-demo-notification-001").exists
        }
        XCTAssertEqual(element("push-tap-cible").label, "notifications")
        record("\(proofPrefix)-push-tap-centre")
    }

    func testTapLitigeVersLeWebSansEcranBloquant() throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "LITIGE_OUVERT"])
        signInDemo()
        let cible = element("push-tap-cible")
        require("Le tap est présenté (renvoi web)", timeout: 30) { cible.exists }
        XCTAssertEqual(cible.label, "safari https://jolene.app/soignant/litiges", "page web canonique, jamais un écran vide")
        XCTAssertTrue(containerVisible(element("accueil-screen")), "sans présentateur `.safari` (L1-T10), l'espace reste affiché")
        XCTAssertFalse(element("access-blocked").exists)
        XCTAssertFalse(element("env-blocked").exists)
        record("\(proofPrefix)-push-tap-web")
    }

    // MARK: Pré-prompt (T5)

    func testPrePromptDeuxiemeSessionPuisActiver() throws {
        launchDemo(extraArguments: ["-JOLENE_SESSION_COUNT", "2"]) // autorisation démo : jamais demandée
        signInDemo()
        aucuneAlerte()
        let carte = element("push-preprompt")
        require("Le pré-prompt apparaît (2e session, 5 s après l'ouverture de l'espace)", timeout: 20) { carte.exists }
        XCTAssertEqual(element("push-preprompt-title").label, "Recevoir les alertes missions ?")
        XCTAssertEqual(element("push-preprompt-message").label,
                       "Jolene vous envoie des notifications pour les nouvelles missions, les rappels de pointage et les mises à jour de vos contrats.")
        let activer = element("push-preprompt-activer")
        require("« Activer les notifications » est atteignable") { self.visible(activer) && activer.isEnabled }
        XCTAssertEqual(activer.label, "Activer les notifications")
        XCTAssertEqual(element("push-preprompt-plus-tard").label, "Plus tard")
        record("\(proofPrefix)-push-preprompt")

        activer.tap()
        let issue = element("push-preprompt-issue")
        require("L'activation aboutit : alertes push activées", timeout: 15) { issue.exists }
        XCTAssertTrue(issue.label.contains("Alertes push activées !"), "issue : « \(issue.label) »")
        XCTAssertFalse(carte.exists, "le pré-prompt se ferme avant la demande")
        aucuneAlerte()
        record("\(proofPrefix)-push-preprompt-active")
        // L'issue (toast) se ferme au tap ; sur iPad, elle recouvrirait la barre d'onglets haute.
        issue.tap()
        require("L'issue est effacée au tap") { !issue.exists }

        openProfile()
        let message = carteEtat()
        require("L'appareil est autorisé et enregistré") { message.label == Self.autorisees }
    }

    func testPrePromptPlusTard() throws {
        launchDemo(extraArguments: ["-JOLENE_SESSION_COUNT", "2"])
        signInDemo()
        let plusTard = element("push-preprompt-plus-tard")
        require("Le pré-prompt apparaît", timeout: 20) { self.visible(plusTard) }
        plusTard.tap()
        require("« Plus tard » ferme le pré-prompt") { !self.element("push-preprompt").exists }
        XCTAssertFalse(element("push-preprompt-issue").exists, "aucune demande, donc aucune issue")
        aucuneAlerte()
        openProfile()
        let list = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        scrollTo(element("compte-suppression-info"), in: list)
        XCTAssertFalse(element("push-etat-appareil").exists, "autorisation toujours jamais demandée : aucune carte")
        record("\(proofPrefix)-push-preprompt-plus-tard")
    }

    // MARK: Étapes

    /// Tap à froid vers le détail d'une mission démo : rejoué après la connexion, détail empilé sur l'Accueil.
    private func tapOuvreLeDetail(_ simulation: String, titre attendu: String, route: String) throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", simulation])
        signInDemo()
        let titre = element("mission-detail-title")
        require("Le tap ouvre le détail de la mission", timeout: 30) {
            self.containerVisible(self.element("mission-detail")) && self.visible(titre)
        }
        XCTAssertEqual(titre.label, attendu)
        XCTAssertEqual(element("push-tap-cible").label, route)
        aucuneAlerte()
        record("\(proofPrefix)-push-tap-\(route.replacingOccurrences(of: " ", with: "-"))")
        // Retour : la pile de l'Accueil reste cohérente (le détail était empilé sur sa racine).
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Retour à l'Accueil") { self.containerVisible(self.element("accueil-screen")) && !titre.exists }
    }

    /// Aucune alerte au login (D1) : ni alerte de l'app, ni feuille SpringBoard (garde de câblage en démo,
    /// voir l'en-tête : le double d'autorisation ne sollicite jamais le système).
    private func aucuneAlerte() {
        XCTAssertEqual(app.alerts.count, 0, "Aucune alerte dans l'app")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "Aucune feuille système d'autorisation")
    }

    /// Amène la carte d'état dans la liste du profil et rend son message.
    private func carteEtat() -> XCUIElement {
        let list = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        let message = element("push-etat-appareil-message")
        scrollTo(message, in: list)
        require("La carte « Autorisation du téléphone » est affichée") { self.element("push-etat-appareil").exists }
        return message
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

    private func openProfile() {
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil affiche l'email de démonstration") {
            self.visible(self.element("profile-email")) && self.element("profile-email").label.contains(Self.demoEmail)
        }
    }
}
