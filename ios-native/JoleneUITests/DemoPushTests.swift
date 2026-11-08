import XCTest

/// Push en démo (lot 3 ; blueprint §2.7) : autorisation (T4 ; carte déplacée par T6 dans les préférences de
/// notifications, son hôte définitif — une seule surface, `REVUES_LOT3.md`, section L3-T4), taps de notification
/// simulés (`-JOLENE_SIMULER_PUSH`) et pré-prompt (`-JOLENE_SESSION_COUNT 2`) (T5). Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - le hub Profil ne porte plus la carte (retirée par T6) mais l'entrée « Réglages › Notifications »
///   (`profile-preferences-notifications`) ;
/// - carte « Autorisation du téléphone » de l'écran des préférences (`push-etat-appareil`, textes verbatim de
///   `PageParametresNotifications.tsx` l.341-352, canal push lu des préférences) selon
///   `-JOLENE_PUSH_AUTORISATION` : « autorisées » sans bouton ; « bloquées » avec « Ouvrir les réglages »
///   (`push-ouvrir-reglages`) ; jamais demandée avec le canal push actif (fixture) : l.349 et « Activer sur
///   cet appareil » (`push-activer-appareil`, l.365), qui demande au tap seulement (D1) puis enregistre
///   l'appareil ; carte absente quand le canal push est coupé dans le brouillon (l.349 serait faux) ;
/// - aucune alerte de l'app au login ni à l'ouverture de l'écran (D1). En démo, l'autorisation est un double
///   (`DemoPushPermission`) qui ne sollicite jamais le système : l'absence de feuille SpringBoard ne garde que
///   contre un câblage du centre de notifications réel en démo. L'absence de demande implicite est prouvée au
///   niveau 1 (`PushCoordinatorTests.testSansAutorisationAucunAppelNiDemande`,
///   `EtatNotificationsAppareilModelTests`) ;
/// - déconnexion : retour à l'écran de connexion sans attente ni message d'erreur. L'ordre « désactivation
///   du token → désinscription → oubli → révocation » n'est pas visible ici : il est prouvé au niveau 1
///   (`SessionStorePushTests`, `DemoPushGatewayTests`) et sur STAGING par T16 (`tokens_push` relu).
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) ; chaque contrôle
/// est amené à l'écran par un défilement borné (`scrollTo`, `prefsDegager`) avant d'être exigé atteignable
/// (PRINCIPES §6). Navigation vers les préférences : helpers `prefs…` de `DemoPreferencesTests.swift`.
final class DemoPushTests: JoleneUITestCase {
    static let titre = "Autorisation du téléphone"
    static let autorisees = "Les notifications sont autorisées sur cet appareil."
    static let aAutoriser = "Le canal est actif dans Jolene, mais le téléphone doit encore autoriser les notifications."
    static let bloquees = "Les notifications sont bloquées par le téléphone. Réactivez Jolene dans les réglages système."
    /// Libellé d'action sans source web (`EtatNotificationsAppareil.ouvrirReglages`, épinglé au niveau 1).
    static let ouvrirReglages = "Ouvrir les réglages"
    /// `PageParametresNotifications.tsx` l.365 (`EtatNotificationsAppareil.activerSurAppareil`).
    static let activer = "Activer sur cet appareil"

    func testAppareilAutoriseTokenEnregistrePuisDeconnexion() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "accordee"])
        signInDemo()
        aucuneAlerte()
        openProfile()
        aucuneCarteDansLeHub()
        let ecran = prefsOuvrirDepuisLeProfil()
        let message = carteEtat(dans: ecran)
        require("L'enregistrement démo est confirmé") { message.label == Self.autorisees }
        XCTAssertEqual(element("push-etat-appareil-title").label, Self.titre)
        XCTAssertFalse(element("push-ouvrir-reglages").exists,
                       "Autorisé et enregistré : « Ouvrir les réglages » est superflu, aucun bouton")
        XCTAssertFalse(element("push-activer-appareil").exists, "Autorisé et enregistré : rien à activer")
        record("\(proofPrefix)-push-autorise")

        prefsRetourAuProfil()
        let sentinel = element("network-sentinel")
        scrollTo(sentinel, in: element("profile-list"), downward: false)
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Enregistrement du token démo : aucune requête réseau")
        let deconnexion = element("logout-button")
        scrollTo(deconnexion, in: element("profile-list"), downward: false)
        tap("logout-button")
        require("La déconnexion aboutit sans attendre", timeout: 10) { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(element("login-error").exists, "Aucun message d'erreur après une déconnexion volontaire")
        record("\(proofPrefix)-push-deconnexion")
    }

    func testAppareilNonDemandeCarteEtActivationAuTap() throws {
        launchDemo() // défaut démo : autorisation jamais demandée
        signInDemo()
        let espaceOuvert = Date()
        aucuneAlerte()
        openProfile()
        aucuneCarteDansLeHub()
        // T5 : 1re session démo (compteur en mémoire vive) : jamais de pré-prompt (D1). L'absence n'est affirmée
        // qu'une fois le délai d'affichage écoulé (revue L3-T5, m7 : avant 5 s, elle ne prouverait rien), et avant
        // « Activer sur cet appareil » (une autorisation accordée exclurait le pré-prompt pour une autre raison).
        attendreLaFinDuDelaiDuPrePrompt(depuis: espaceOuvert)
        XCTAssertFalse(element("push-preprompt").exists, "1re session : aucun pré-prompt, délai écoulé")
        let ecran = prefsOuvrirDepuisLeProfil()
        aucuneAlerte() // ouverture de l'écran : aucune demande implicite (D1)
        let message = carteEtat(dans: ecran)
        require("Jamais demandé, canal push actif (fixture) : l.349") { message.label == Self.aAutoriser }
        let activer = element("push-activer-appareil")
        prefsDegager(activer, dans: ecran)
        XCTAssertEqual(activer.label, Self.activer)
        XCTAssertFalse(element("push-ouvrir-reglages").exists,
                       "Jamais demandé : Réglages n'a pas encore d'entrée Notifications pour l'app")
        record("\(proofPrefix)-push-non-demande")

        // Canal push coupé dans le brouillon : « Le canal est actif dans Jolene » serait faux, la carte disparaît.
        prefsBasculer("prefs-canal-push", dans: ecran)
        require("Canal push coupé : aucune carte") { !self.element("push-etat-appareil").exists }
        prefsBasculer("prefs-canal-push", dans: ecran)
        require("Canal push réactivé : la carte revient") { self.element("push-etat-appareil").exists }

        // Au tap seulement : demande (double démo, qui accorde) puis enregistrement de l'appareil.
        prefsDegager(activer, dans: ecran)
        activer.tap()
        require("Autorisation accordée et appareil enregistré", timeout: 20) {
            self.element("push-etat-appareil-message").label == Self.autorisees
        }
        XCTAssertFalse(element("push-activer-appareil").exists, "Tout est en ordre : plus aucun bouton")
        aucuneAlerte()
        record("\(proofPrefix)-push-active")
    }

    func testAppareilRefuse() throws {
        launchDemo(extraArguments: ["-JOLENE_PUSH_AUTORISATION", "refusee"])
        signInDemo()
        openProfile()
        let ecran = prefsOuvrirDepuisLeProfil()
        let message = carteEtat(dans: ecran)
        require("L'état « bloquées » est affiché") { message.label == Self.bloquees }
        let reglages = element("push-ouvrir-reglages")
        prefsDegager(reglages, dans: ecran)
        require("« Ouvrir les réglages » est atteignable") { self.visible(reglages) && reglages.isEnabled }
        XCTAssertEqual(reglages.label, Self.ouvrirReglages)
        XCTAssertFalse(element("push-activer-appareil").exists, "Refusé : une demande serait sans effet")
        record("\(proofPrefix)-push-refuse")
    }

    // MARK: Taps (T5)

    // Tap à froid simulé (`-JOLENE_SIMULER_PUSH <TYPE>[:<valeur>][:<lien>]`, DEBUG démo) : mémorisé avant la session,
    // rejoué par le premier espace prêt après la connexion, rôle lu dans le snapshot (blueprint §2.5). Six types
    // ouvrent un écran natif ; les renvois web (litige, contrat à signer) sont vérifiés par la route présentée
    // (`push-tap-cible`, DEBUG et démo seulement), faute de présentateur `.safari` avant L1-T10. Les préférences (T6)
    // et l'édition du profil (T9) ont leur cas de tap vers `prefs-screen` et `profil-screen` (blueprint §3 T5,
    // intégration du lot 3) ; factures et paiements sont prouvés au niveau 1
    // (`PushTapIntentTests.testCiblesDesTypesPrincipaux`) jusqu'à T12/T13.

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

    /// Blueprint §3 T5 (« l'écran final est vérifié par un cas de tap ajouté dans la tranche qui le livre ») :
    /// `/soignant/parametres/notifications` → écran natif des préférences (`prefs-screen`), empilé sur l'onglet Profil.
    func testTapLienExpliciteOuvreLesPreferences() throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "SYSTEM::/soignant/parametres/notifications"])
        signInDemo()
        let ecran = element("prefs-screen")
        require("L'écran natif des préférences est ouvert", timeout: 30) {
            self.containerVisible(ecran) && self.element("prefs-canal-email").exists
        }
        XCTAssertTrue(app.navigationBars["Préférences de notifications"].exists, "titre verbatim web")
        XCTAssertEqual(element("push-tap-cible").label, "parametresNotifications")
        aucuneAlerte()
        record("\(proofPrefix)-push-tap-preferences")
        prefsRetourAuProfil()
        let entree = element("profile-preferences-notifications")
        scrollTo(entree, in: element("profile-list"))
        require("Retour au hub, à la racine de l'onglet Profil") { entree.exists }
    }

    /// Blueprint §3 T5 (cas de tap de l'écran livré par T9) : `/soignant/profil` → édition native du profil
    /// (`profil-screen`), empilée sur l'onglet Profil.
    func testTapLienExpliciteOuvreLEditionDuProfil() throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "SYSTEM::/soignant/profil"])
        signInDemo()
        let ecran = element("profil-screen")
        require("L'édition native du profil est ouverte", timeout: 30) {
            self.containerVisible(ecran) && self.element("profil-nom-complet").exists
        }
        XCTAssertFalse(element("profil-erreur-chargement").exists)
        XCTAssertEqual(element("push-tap-cible").label, "profil")
        aucuneAlerte()
        record("\(proofPrefix)-push-tap-profil")
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Retour au hub, à la racine de l'onglet Profil") {
            self.containerVisible(self.element("profile-list")) && !ecran.exists
        }
    }

    /// Blueprint §3 T5 : `CONTRAT_A_SIGNER:contrat_id` → `/contrat/<id>` (renvoi web tant que l'écran du lot 2 n'est
    /// pas intégré, aucun présentateur `.safari` avant L1-T10) : route présentée vérifiée, l'espace reste affiché.
    func testTapContratASignerVersLeWebDuContrat() throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "CONTRAT_A_SIGNER:contrat_id=demo-contrat-001"])
        signInDemo()
        let cible = element("push-tap-cible")
        require("Le tap est présenté (renvoi web du contrat)", timeout: 30) { cible.exists }
        XCTAssertEqual(cible.label, "safari https://jolene.app/contrat/demo-contrat-001", "page web canonique du contrat")
        XCTAssertTrue(containerVisible(element("accueil-screen")), "sans présentateur `.safari` (L1-T10), l'espace reste affiché")
        XCTAssertFalse(element("access-blocked").exists)
        XCTAssertFalse(element("env-blocked").exists)
        aucuneAlerte()
        record("\(proofPrefix)-push-tap-contrat")
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
        let ecran = prefsOuvrirDepuisLeProfil()
        let message = carteEtat(dans: ecran)
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
        aucuneCarteDansLeHub()
        // Hôte de la carte depuis T6 : l'autorisation n'a toujours pas été demandée (canal push actif, fixture).
        let ecran = prefsOuvrirDepuisLeProfil()
        let message = carteEtat(dans: ecran)
        require("Autorisation toujours jamais demandée : l.349") { message.label == Self.aAutoriser }
        let activer = element("push-activer-appareil")
        prefsDegager(activer, dans: ecran)
        XCTAssertEqual(activer.label, Self.activer, "« Plus tard » : rien n'a été demandé, l'activation reste proposée")
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

    /// Délai d'affichage du pré-prompt après l'ouverture de l'espace (`PrePromptPush.delaiAffichage`, JoleneCore,
    /// web `DemandePermissionPush.tsx` l.79), plus une marge pour le rendu.
    static let delaiPrePrompt: TimeInterval = 5
    static let margePrePrompt: TimeInterval = 2

    /// Attend que le délai du pré-prompt soit écoulé depuis `debut` (attente inversée : aucune condition, durée
    /// bornée), pour qu'une absence affirmée ensuite ne soit pas vide.
    private func attendreLaFinDuDelaiDuPrePrompt(depuis debut: Date) {
        let reste = Self.delaiPrePrompt + Self.margePrePrompt - Date().timeIntervalSince(debut)
        guard reste > 0 else { return }
        let ecoule = XCTestExpectation(description: "délai du pré-prompt écoulé")
        ecoule.isInverted = true
        wait(for: [ecoule], timeout: reste)
    }

    /// Aucune alerte (D1) : ni alerte de l'app, ni feuille SpringBoard (garde de câblage en démo,
    /// voir l'en-tête : le double d'autorisation ne sollicite jamais le système).
    private func aucuneAlerte() {
        XCTAssertEqual(app.alerts.count, 0, "Aucune alerte dans l'app")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "Aucune feuille système d'autorisation")
    }

    /// Le hub ne porte plus la carte (une seule surface, T6) : la liste est amenée jusqu'à l'entrée « Réglages ›
    /// Notifications », posée à l'emplacement provisoire de T4 (entre « Application » et la suppression de
    /// compte), puis jusqu'à la suppression de compte (dernière section) ; aucune carte à l'un ni à l'autre.
    private func aucuneCarteDansLeHub() {
        let list = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        let entree = element("profile-preferences-notifications")
        scrollTo(entree, in: list)
        XCTAssertTrue(entree.label.contains("Notifications"), "Entrée « Notifications » du hub : \(entree.label)")
        XCTAssertFalse(element("push-etat-appareil").exists, "Carte retirée du hub : elle vit dans les préférences")
        scrollTo(element("compte-suppression-info"), in: list)
        XCTAssertFalse(element("push-etat-appareil").exists)
        XCTAssertFalse(element("push-ouvrir-reglages").exists)
    }

    /// Amène la carte d'état dans l'écran des préférences et rend son message.
    private func carteEtat(dans ecran: XCUIElement) -> XCUIElement {
        let message = element("push-etat-appareil-message")
        require("La carte « Autorisation du téléphone » est affichée") { self.element("push-etat-appareil").exists }
        prefsDegager(message, dans: ecran)
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