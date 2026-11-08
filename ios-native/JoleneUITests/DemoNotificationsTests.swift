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
/// - lignes déjà lues vers un renvoi web (factures, Stripe, préférences, litiges) ou sans lien : chacune amenée à
///   l'écran et rendue, puis affirmée sans bouton ni « Voir » tant que le présentateur `.safari` (L1-T10) n'est pas
///   injecté (jamais un bouton sans effet) ;
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

        // Déjà lues, renvoi web sans présentateur `.safari` : aucune action possible, donc aucun bouton. Chaque ligne
        // est d'abord amenée à l'écran et exigée rendue (la pile est paresseuse : une ligne non rendue rendrait
        // l'assertion négative vide, revue L3-T5 m7), puis affirmée non bouton.
        for id in ["003", "004", "005", "006", "007"] {
            let ligne = element("notification-demo-notification-\(id)")
            scrollTo(ligne, in: centre)
            require("La ligne \(id) est rendue") { ligne.exists }
            XCTAssertNotEqual(ligne.elementType, .button, "ligne \(id) : jamais un bouton sans effet")
            XCTAssertFalse(app.buttons.matching(identifier: "notification-demo-notification-\(id)").firstMatch.exists,
                           "ligne \(id) : jamais un bouton sans effet")
            XCTAssertFalse(ligne.label.contains("Voir"), "ligne \(id) : pas de « Voir » sans destination présentable")
        }

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
