import XCTest

/// Liens universels en démo (lot 3, T3b, reliquat L1-T10 ; `DECISIONS_LOT3.md`, section T3b) sur iPhone, iPad portrait
/// et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`). Le lien est injecté au lancement par l'argument DEBUG
/// `-JOLENE_OPEN_URL <url>` (lien universel simulé à froid, mêmes refus qu'un lien réel), donc **avant** la connexion :
/// la démo s'ouvre sur l'écran de connexion.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - un lien de l'espace reçu avant la connexion n'ouvre rien sur l'écran de connexion (ni écran, ni renvoi web), puis
///   est rejoué une seule fois après `.ready` : centre de notifications natif (`/soignant/notifications`), édition du
///   profil (`/soignant/profil`), préférences de notifications (`/soignant/parametres/notifications`), chacun empilé
///   sur son onglet, retour à la racine de l'onglet par la barre de navigation ;
/// - une route sans écran natif livré (`/soignant/stripe-connect?success=true`, T14a) et une section de Revenus en
///   renvoi web (`/soignant/mes-gains?tab=factures`, D4) sont présentées **aussitôt**, sans session, par le
///   présentateur `.safari` (double démo `renvoi-web-demo`, URL canonique lue dans `renvoi-web-url`, aucune requête
///   réseau) ; après fermeture puis connexion, rien n'est rejoué ;
/// - (revue B8 de T3b, m8) détail de mission natif (`/soignant/missions/:id`, `LOT1_PLAN.md` §3 T10) ; absence
///   bornée (attente inversée) de toute présentation sur l'écran de connexion ;
/// - (revue B8 de T3b, m1) lien de réinitialisation `?code=` refusé par une alerte (option B), au lancement comme
///   pendant un renvoi affiché (lien remis par le double, `-JOLENE_OPEN_URL_SUIVANT`) : renvoi fermé d'abord, alerte
///   ensuite, jamais le code servi par Safari ;
/// - libellé DEBUG `deeplink-route` (démo) : route effectivement présentée par le coordinateur (apparition de la
///   feuille, exécution de la navigation par l'espace) ;
/// - aucune requête réseau (`network-sentinel`).
/// Les règles (classement de chaque route, option B du reset, dernier lien gagnant, lien contre tap, epoch, renvoi
/// jamais rejoué comme lien universel) sont prouvées au niveau 1 (`DeepLinkIntentTests`). Le lien universel réel
/// (AASA servie par le CDN d'Apple, tap depuis Mail) se prouve sur appareil (`RECETTE_DEVICE_LOT3.md`).
final class DemoLiensLot3Tests: JoleneUITestCase {
    func testLienNotificationsRecuAvantConnexionRejoueApresReady() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/notifications"])
        liensAucunePresentationSurLaConnexion()
        liensConnexionDemo()
        let centre = element("notifications-screen")
        require("Le centre de notifications natif est ouvert après `.ready`", timeout: 30) {
            self.containerVisible(centre) && self.element("notification-demo-notification-001").exists
        }
        XCTAssertFalse(element("notifications-error").exists)
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T5) : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "notifications")
        record("\(proofPrefix)-liens-notifications")
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Retour à la racine de l'Accueil") { self.containerVisible(self.element("accueil-screen")) && !centre.exists }
    }

    func testLienProfilOuvreLEditionNative() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/profil"])
        liensAucunePresentationSurLaConnexion()
        liensConnexionDemo()
        let ecran = element("profil-screen")
        require("L'édition native du profil est ouverte après `.ready`", timeout: 30) {
            self.containerVisible(ecran) && self.element("profil-nom-complet").exists
        }
        XCTAssertFalse(element("profil-erreur-chargement").exists)
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T9) : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "profil")
        record("\(proofPrefix)-liens-profil")
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Retour au hub, racine de l'onglet Profil") { self.containerVisible(self.element("profile-list")) && !ecran.exists }
    }

    /// Cas « lien reçu avant connexion → rejoué après `.ready` » détaillé : l'écran de connexion reste utilisable
    /// (saisie, bouton) sans qu'aucune présentation ne s'interpose ; le lien est rejoué une seule fois, puis la
    /// navigation reste libre (retour au hub, changement d'onglet sans nouveau rejeu).
    func testLienRecuAvantConnexionRejoueUneSeuleFoisApresReady() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://www.jolene.app/soignant/parametres/notifications?origine=mail"])
        liensAucunePresentationSurLaConnexion()
        record("\(proofPrefix)-liens-avant-connexion")
        liensConnexionDemo()
        let ecran = element("prefs-screen")
        require("Les préférences natives sont ouvertes après `.ready`", timeout: 30) {
            self.containerVisible(ecran) && self.element("prefs-canal-email").exists
        }
        XCTAssertTrue(app.navigationBars["Préférences de notifications"].exists, "titre verbatim web")
        XCTAssertEqual(element("deeplink-route").label, "parametresNotifications")
        record("\(proofPrefix)-liens-apres-ready")
        prefsRetourAuProfil()
        tabButton("tab-accueil", label: "Accueil").tap()
        require("L'Accueil est affiché") { self.containerVisible(self.element("accueil-screen")) }
        tabButton("tab-profil", label: "Profil").tap()
        require("Le hub est à sa racine : le lien n'est pas rejoué") {
            self.containerVisible(self.element("profile-list")) && !self.element("prefs-screen").exists
        }
        let sentinel = element("network-sentinel")
        scrollTo(sentinel, in: element("profile-list"), downward: false)
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "liens démo : aucune requête réseau")
    }

    /// Route sans écran natif livré (Stripe Connect, T14a) : renvoi web aussitôt, sans session (un renvoi n'a pas
    /// besoin de l'espace) ; jamais mémorisé, donc rien n'est rejoué après la connexion.
    func testRouteNonLivreeRenvoiWebAussitotSansSession() throws {
        let lien = "https://jolene.app/soignant/stripe-connect?success=true"
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", lien])
        liensRenvoiWebAffiche(lien)
        record("\(proofPrefix)-liens-renvoi-web")
        liensFermerRenvoiWeb()
        require("L'écran de connexion est de nouveau affiché") { self.containerVisible(self.element("login-scroll")) }
        XCTAssertEqual(element("deeplink-route").label, "safari \(lien)")
        liensConnexionDemo()
        require("L'Accueil est affiché, sans rejeu du lien", timeout: 30) { self.containerVisible(self.element("accueil-screen")) }
        XCTAssertFalse(element("renvoi-web-demo").exists, "renvoi déjà présenté : jamais rejoué après `.ready`")
        XCTAssertEqual(element("deeplink-route").label, "safari \(lien)", "aucune autre présentation")
    }

    /// Section de Revenus lue dans `?tab=` : factures en renvoi web assumé jusqu'au lot 4 (D4), URL canonique conservée.
    func testSectionFacturesDeRevenusEnRenvoiWeb() throws {
        let lien = "https://jolene.app/soignant/mes-gains?tab=factures"
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", lien])
        liensRenvoiWebAffiche(lien)
        XCTAssertFalse(element("placeholder-revenus").exists, "jamais l'onglet natif pour une section non portée")
        record("\(proofPrefix)-liens-revenus-factures")
        liensFermerRenvoiWeb()
        XCTAssertEqual(element("deeplink-route").label, "safari \(lien)")
    }

    /// `LOT1_PLAN.md` §3 T10 (revue B8 de T3b, m8) : lien universel vers le détail d'une mission, reçu avant la connexion,
    /// rejoué après `.ready` : détail natif empilé sur l'Accueil (jamais un renvoi web), retour à la racine de l'Accueil.
    func testLienDetailDeMissionOuvreLeDetailNatif() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/missions/demo-mission-002"])
        liensAucunePresentationSurLaConnexion()
        liensConnexionDemo()
        let titre = element("mission-detail-title")
        require("Le détail natif de la mission est ouvert après `.ready`", timeout: 30) {
            self.containerVisible(self.element("mission-detail")) && self.visible(titre)
        }
        XCTAssertEqual(titre.label, "Démonstration · Soins de suite 2")
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (lot 1) : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "missionDetail demo-mission-002")
        record("\(proofPrefix)-liens-detail-mission")
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Retour à la racine de l'Accueil") { self.containerVisible(self.element("accueil-screen")) && !titre.exists }
    }

    /// Option B (décision 7 du lot 1) : un lien de réinitialisation `?code=` reçu au lancement est refusé par une alerte
    /// au texte décidé, sans session ; jamais servi par Safari ni rejoué après la connexion.
    func testLienDeReinitialisationPkceRefuseParUneAlerte() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/reset-password?code=demo"])
        liensRefusAffichePuisFerme()
        record("\(proofPrefix)-liens-refus-reinitialisation")
        requireAbsence("Le code n'est jamais servi par Safari") { self.element("renvoi-web-demo").exists }
        XCTAssertFalse(element("deeplink-route").exists, "rien n'est présenté")
        liensConnexionDemo()
        require("L'Accueil est affiché", timeout: 30) { self.containerVisible(self.element("accueil-screen")) }
        XCTAssertEqual(app.alerts.count, 0, "le refus n'est jamais rejoué")
        XCTAssertFalse(element("deeplink-route").exists, "aucune navigation rejouée")
    }

    /// Revue B8 de T3b, m1 (second cas) : un lien `?code=` reçu **pendant** un renvoi affiché (bouton DEBUG du double,
    /// `-JOLENE_OPEN_URL_SUIVANT`) ferme d'abord le renvoi, puis présente l'alerte du refus une fois la feuille fermée ;
    /// jamais l'alerte sous la feuille, jamais le code servi par Safari.
    func testRenvoiAffichePuisLienDeReinitialisationAlerteApresLaFermeture() throws {
        let lien = "https://jolene.app/soignant/stripe-connect?success=true"
        let reinitialisation = "https://jolene.app/reset-password?code=demo"
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", lien, "-JOLENE_OPEN_URL_SUIVANT", reinitialisation])
        liensRenvoiWebAffiche(lien)
        let suivant = element("renvoi-web-lien-suivant")
        require("Le double du renvoi remet le lien suivant") { self.visible(suivant) && suivant.isEnabled }
        XCTAssertEqual(suivant.label, reinitialisation)
        record("\(proofPrefix)-liens-renvoi-avant-refus")
        suivant.tap()
        liensRefusAffichePuisFerme()
        XCTAssertFalse(element("renvoi-web-demo").exists, "le renvoi est fermé, le code n'est jamais servi par Safari")
        require("L'écran de connexion est de nouveau affiché") { self.containerVisible(self.element("login-scroll")) }
        XCTAssertEqual(element("deeplink-route").label, "safari \(lien)", "seul le renvoi a été présenté")
    }

    // MARK: Étapes

    /// Écran de connexion affiché, et rien de présenté par-dessus ni à sa place (lien de l'espace mémorisé). Revue B8 de
    /// T3b, m8 : absence bornée (attente inversée), jamais une lecture instantanée qu'une feuille encore en cours
    /// d'animation passerait.
    private func liensAucunePresentationSurLaConnexion() {
        require("L'écran de connexion est affiché") { self.containerVisible(self.element("login-scroll")) }
        requireAbsence("Rien n'est présenté avant `.ready` : ni renvoi web, ni route, ni espace, ni alerte") {
            self.element("renvoi-web-demo").exists || self.element("deeplink-route").exists || self.tabBarExists
                || self.app.alerts.count > 0
        }
        XCTAssertTrue(containerVisible(element("login-scroll")), "l'écran de connexion reste affiché")
    }

    /// Alerte du refus de réinitialisation (texte de la décision 7 du lot 1, `DeepLinkIntent.Textes`) affichée sans
    /// feuille par-dessus, puis fermée par « Fermer ».
    private func liensRefusAffichePuisFerme() {
        let alerte = app.alerts.firstMatch
        require("L'alerte du refus est présentée, sans feuille de renvoi", timeout: 30) {
            alerte.exists && !self.element("renvoi-web-demo").exists
        }
        XCTAssertTrue(alerte.staticTexts[Self.texteRefus].exists, "texte décidé (décision 7 du lot 1)")
        let fermer = alerte.buttons["Fermer"]
        require("« Fermer » est atteignable") { fermer.exists && fermer.isHittable }
        fermer.tap()
        require("L'alerte est fermée") { self.app.alerts.count == 0 }
    }

    /// `DeepLinkIntent.Textes.reinitialisationRefusee` (JoleneCore, épinglé par `DeepLinkIntentTests`).
    private static let texteRefus = "Ce lien ne permet pas de réinitialiser le mot de passe depuis l'application."

    private func liensConnexionDemo() {
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
        require("La session démo est prête : la barre d'onglets est affichée", timeout: 30) { self.tabBarExists }
    }
}

/// Renvoi web présenté par le coordinateur des liens (lot 3, T3b) : en démo, double du présentateur `.safari`
/// (`renvoi-web-demo`, aucune requête réseau) qui affiche l'URL ouverte (`renvoi-web-url`) et « Fermer »
/// (`renvoi-web-fermer`). Partagé avec `DemoPushTests`, `DemoNotificationsTests` et `DemoProfilTests` ; préfixe `liens`.
extension JoleneUITestCase {
    /// Attend la feuille du renvoi web et vérifie l'URL canonique servie.
    func liensRenvoiWebAffiche(_ url: String, timeout: TimeInterval = 30) {
        let feuille = element("renvoi-web-demo")
        let adresse = element("renvoi-web-url")
        require("Le renvoi web est présenté (double démo du présentateur `.safari`)", timeout: timeout) {
            self.containerVisible(feuille) && adresse.exists
        }
        XCTAssertEqual(adresse.label, url, "URL canonique servie par Safari, query et fragment conservés")
        XCTAssertEqual(app.alerts.count, 0)
    }

    /// Ferme la feuille du renvoi web par « Fermer ».
    func liensFermerRenvoiWeb() {
        let fermer = element("renvoi-web-fermer")
        require("« Fermer » est atteignable") { self.visible(fermer) && fermer.isEnabled }
        XCTAssertEqual(fermer.label, "Fermer")
        fermer.tap()
        require("La feuille du renvoi web est fermée") { !self.element("renvoi-web-demo").exists }
    }
}
