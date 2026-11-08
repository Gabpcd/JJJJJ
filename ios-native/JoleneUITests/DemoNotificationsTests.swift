import XCTest

/// Centre de notifications démo (lot 3, T5) sur iPhone, iPad portrait et iPad paysage (`JOLENE_UI_ORIENTATION`,
/// `proofPrefix`) : `demo-notifications.json` servi par `DemoNotificationsGateway` (horloge démo
/// 2026-11-02T00:00:00Z), ouvert depuis le compteur de l'Accueil (« Voir », `accueil-notifications-action`).
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - liste et textes : sept lignes, deux non lues (pastille `notification-non-lue-<id>`), date relative comme
///   `formatDistanceToNow` (« il y a environ 2 heures »), « Voir » sur les seules destinations présentables ;
/// - tap sur une non lue : marquée lue (relue dans l'acteur démo) puis ouverture du détail de la mission ; au
///   retour, la pastille a disparu ; une non lue vers Mes missions bascule sur l'onglet ;
/// - lignes déjà lues vers un renvoi web (factures, Stripe, litiges) : depuis L3-T3b (présentateur `.safari` du
///   coordinateur des liens, injecté à la racine), chacune est un bouton avec « Voir » ; le litige ouvre sa page web
///   canonique (double démo `renvoi-web-demo`), puis le centre reste affiché à la fermeture ; ligne sans lien : ni
///   bouton ni « Voir » (jamais un bouton sans effet) ;
/// - (intégration du lot 3, T6) ligne déjà lue vers les préférences de notifications : un bouton avec « Voir », qui
///   ouvre l'écran natif des préférences (`prefs-screen`) sur l'onglet Profil, sans marquage (déjà lue) ;
/// - aucune requête réseau (`network-sentinel`).
/// Les règles (relecture, échec du marquage et sa réconciliation, annulation, lien invalide, epoch, échec du
/// tirer-pour-rafraîchir) sont prouvées au niveau 1 (`CentreNotificationsTests`, `DemoNotificationsGatewayTests`,
/// `SupabaseNotificationsGatewayTests`), comme la relecture du compteur de l'Accueil après une lecture
/// (`AccueilModelTests`, jeton de péremption) : le compteur démo est figé par `demo-dashboard.json`.
final class DemoNotificationsTests: JoleneUITestCase {
    func testCentreDepuisLAccueilMarquerLuePuisOuvrir() throws {
        launchDemo()
        connexionDemo()
        let accueil = element("accueil-screen")
        require("L'Accueil démo est chargé", timeout: 30) {
            self.containerVisible(accueil) && self.element("accueil-salutation").exists
        }
        let voir = element("accueil-notifications-action")
        degager(voir, dans: accueil)
        voir.tap()

        let centre = element("notifications-screen")
        let premiere = element("notification-demo-notification-001")
        require("Le centre de notifications natif est affiché", timeout: 30) {
            self.containerVisible(centre) && premiere.exists
        }
        XCTAssertFalse(element("notifications-error").exists)
        XCTAssertFalse(element("notifications-empty").exists)
        XCTAssertTrue(element("notification-non-lue-demo-notification-001").exists, "1re non lue")
        XCTAssertTrue(element("notification-non-lue-demo-notification-002").exists, "2e non lue")
        XCTAssertFalse(element("notification-non-lue-demo-notification-003").exists, "déjà lue")
        let libelle = premiere.label
        for fragment in ["Démonstration · Rappel de mission", "il y a environ 2 heures", "Voir"] {
            XCTAssertTrue(libelle.contains(fragment), "« \(fragment) » absent de « \(libelle) »")
        }
        XCTAssertEqual(premiere.elementType, .button, "non lue vers un écran natif : un bouton")
        record("\(proofPrefix)-notifications-liste")

        // Déjà lues, renvoi web (factures, Stripe, litiges) : le présentateur `.safari` du coordinateur des liens est
        // injecté (L3-T3b) : chaque ligne est un bouton avec « Voir ». Sans lien (007) : aucune action, donc aucun
        // bouton. Chaque ligne est d'abord amenée à l'écran et exigée rendue (la pile est paresseuse : une ligne non
        // rendue rendrait l'assertion négative vide, revue L3-T5 m7). La ligne 005 (préférences, écran natif depuis T6)
        // est vérifiée par `testLigneLueVersLesPreferencesOuvreLEcranNatif`.
        for id in ["003", "004", "006"] {
            let ligne = element("notification-demo-notification-\(id)")
            scrollTo(ligne, in: centre)
            require("La ligne \(id) est rendue") { ligne.exists }
            XCTAssertEqual(ligne.elementType, .button, "ligne \(id) : renvoi web présentable, un bouton")
            XCTAssertTrue(ligne.label.contains("Voir"), "ligne \(id) : « Voir » vers la page web, « \(ligne.label) »")
        }
        let sansLien = element("notification-demo-notification-007")
        scrollTo(sansLien, in: centre)
        require("La ligne 007 est rendue") { sansLien.exists }
        XCTAssertNotEqual(sansLien.elementType, .button, "ligne 007 : jamais un bouton sans effet")
        XCTAssertFalse(app.buttons.matching(identifier: "notification-demo-notification-007").firstMatch.exists,
                       "ligne 007 : jamais un bouton sans effet")
        XCTAssertFalse(sansLien.label.contains("Voir"), "ligne 007 : pas de « Voir » sans destination")

        // Déjà lue vers `/soignant/litiges` : page web canonique présentée (double démo), sans marquage ; le centre reste.
        let litige = element("notification-demo-notification-006")
        degager(litige, dans: centre)
        litige.tap()
        liensRenvoiWebAffiche("https://jolene.app/soignant/litiges")
        record("\(proofPrefix)-notifications-renvoi-web")
        liensFermerRenvoiWeb()
        require("Le centre reste affiché après le renvoi web") { self.containerVisible(centre) && litige.exists }

        // Non lue → marquée lue (relue) → détail de la mission démo (retour en haut de la liste d'abord).
        scrollTo(premiere, in: centre, downward: false)
        degager(premiere, dans: centre)
        premiere.tap()
        let titre = element("mission-detail-title")
        require("Le détail de la mission s'ouvre après le marquage", timeout: 30) {
            self.containerVisible(self.element("mission-detail")) && self.visible(titre)
        }
        XCTAssertEqual(titre.label, "Démonstration · Mission assignée 1")
        record("\(proofPrefix)-notifications-mission")
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Retour au centre, la notification est lue") {
            self.containerVisible(centre) && !self.element("notification-non-lue-demo-notification-001").exists
        }
        XCTAssertTrue(element("notification-non-lue-demo-notification-002").exists)

        // Non lue vers `/soignant/missions` → onglet Mes missions.
        let seconde = element("notification-demo-notification-002")
        degager(seconde, dans: centre)
        seconde.tap()
        require("L'onglet Mes missions est ouvert", timeout: 30) { self.visible(self.element("placeholder-missions")) }
        record("\(proofPrefix)-notifications-onglet")

        tabButton("tab-profil", label: "Profil").tap()
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "centre de notifications démo : aucune requête réseau")
    }

    /// Intégration du lot 3 (T5 × T6) : la ligne déjà lue vers `/soignant/parametres/notifications` a une cible native
    /// présentable depuis le centre (`CibleNotification.preferences`) : un bouton avec « Voir », qui bascule sur
    /// l'onglet Profil et y empile l'écran des préférences ; retour au hub par la barre de navigation.
    func testLigneLueVersLesPreferencesOuvreLEcranNatif() throws {
        launchDemo()
        connexionDemo()
        let accueil = element("accueil-screen")
        require("L'Accueil démo est chargé", timeout: 30) {
            self.containerVisible(accueil) && self.element("accueil-salutation").exists
        }
        let voir = element("accueil-notifications-action")
        degager(voir, dans: accueil)
        voir.tap()
        let centre = element("notifications-screen")
        require("Le centre de notifications natif est affiché", timeout: 30) {
            self.containerVisible(centre) && self.element("notification-demo-notification-001").exists
        }

        let ligne = element("notification-demo-notification-005")
        degager(ligne, dans: centre)
        require("La ligne des préférences est rendue") { ligne.exists }
        XCTAssertFalse(element("notification-non-lue-demo-notification-005").exists, "déjà lue")
        XCTAssertEqual(ligne.elementType, .button, "écran natif livré : la ligne est un bouton")
        for fragment in ["Démonstration · Préférences", "Voir"] {
            XCTAssertTrue(ligne.label.contains(fragment), "« \(fragment) » absent de « \(ligne.label) »")
        }
        record("\(proofPrefix)-notifications-ligne-preferences")

        ligne.tap()
        let ecran = element("prefs-screen")
        require("L'écran natif des préférences est ouvert sur l'onglet Profil", timeout: 30) {
            self.containerVisible(ecran) && self.element("prefs-canal-email").exists
        }
        XCTAssertTrue(app.navigationBars["Préférences de notifications"].exists, "titre verbatim web")
        XCTAssertFalse(element("prefs-error").exists)
        XCTAssertFalse(element("notifications-screen").exists, "le centre (onglet Accueil) n'est plus à l'écran")
        record("\(proofPrefix)-notifications-preferences")

        prefsRetourAuProfil()
        let sentinel = element("network-sentinel")
        scrollTo(sentinel, in: element("profile-list"), downward: false)
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "centre et préférences démo : aucune requête réseau")
    }

    // MARK: - Étapes

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

    /// Barre qui recouvre `cible` (barre de navigation, ou barre d'onglets basse sur iPhone).
    private func recouverte(_ cible: XCUIElement) -> (navigation: Bool, onglets: Bool) {
        let navigation = app.navigationBars.firstMatch
        let onglets = app.tabBars.firstMatch
        return (navigation.exists && cible.frame.minY < navigation.frame.maxY,
                onglets.exists && cible.frame.maxY > onglets.frame.minY)
    }

    /// Défilement borné jusqu'à la cible, puis dégagement des barres (glissements courts et bornés).
    private func degager(_ cible: XCUIElement, dans ecran: XCUIElement) {
        scrollTo(cible, in: ecran)
        var essais = 0
        while essais < 6 {
            let barres = recouverte(cible)
            if barres.onglets { drag(ecran, fromY: 0.6, toY: 0.4) } else if barres.navigation { drag(ecran, fromY: 0.4, toY: 0.6) } else { break }
            essais += 1
        }
        require("La cible est atteignable hors des barres") {
            let barres = self.recouverte(cible)
            return self.visible(cible) && !barres.navigation && !barres.onglets
        }
    }
}
