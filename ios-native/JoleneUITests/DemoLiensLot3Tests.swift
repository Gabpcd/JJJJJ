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
/// - libellé DEBUG `deeplink-route` (démo) : route effectivement présentée par le coordinateur ;
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

    // MARK: Étapes

    /// Écran de connexion affiché, et rien de présenté par-dessus ni à sa place (lien de l'espace mémorisé).
    private func liensAucunePresentationSurLaConnexion() {
        require("L'écran de connexion est affiché") { self.containerVisible(self.element("login-scroll")) }
        XCTAssertFalse(element("renvoi-web-demo").exists, "un lien de l'espace n'est jamais servi par Safari")
        XCTAssertFalse(element("deeplink-route").exists, "rien n'est présenté avant `.ready`")
        XCTAssertFalse(tabBarExists, "aucun espace ouvert avant la connexion")
        XCTAssertEqual(app.alerts.count, 0)
    }

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
